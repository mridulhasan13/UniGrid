import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, compute;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img;
import 'supabase_config.dart';

/// Fast format-specific decoder using magic numbers to bypass auto-detector overhead
img.Image? _decodeImageFromBytes(Uint8List bytes) {
  if (bytes.length < 4) return img.decodeImage(bytes);

  // Check JPEG magic number: FF D8
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return img.decodeJpg(bytes);
  }

  // Check PNG magic number: 89 50 4E 47
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return img.decodePng(bytes);
  }

  // Check GIF magic number: 47 49 46 38 ('GIF8')
  if (bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return img.decodeGif(bytes);
  }

  return img.decodeImage(bytes);
}

/// Compress image inside a background isolate to keep UI smooth and make uploads faster.
/// Runs on a separate thread via compute() so the main UI thread is never blocked.
Uint8List _compressImageForStorage(Uint8List bytes) {
  try {
    final image = _decodeImageFromBytes(bytes);
    if (image == null) return bytes;

    // Skip compression if already reasonably small in dimensions and file size
    if (image.width <= 1280 && image.height <= 1280 && bytes.length < 400 * 1024) {
      return bytes;
    }

    // Limit maximum dimension to 1280px for standard materials / announcements
    img.Image resized;
    if (image.width > image.height) {
      resized = image.width > 1280
          ? img.copyResize(image, width: 1280, interpolation: img.Interpolation.nearest)
          : image;
    } else {
      resized = image.height > 1280
          ? img.copyResize(image, height: 1280, interpolation: img.Interpolation.nearest)
          : image;
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
  } catch (e) {
    debugPrint('[ImageCompressor] Error compressing image on isolate: $e');
    return bytes;
  }
}

/// Supabase Storage Service
/// Handles uploading files/images to Supabase Storage and returns permanent public URLs.
/// File URLs are stored in Firestore, so files are accessible across all platforms.
///
/// Folders used:
///   - auth_service.dart          → folder: 'avatars'
///   - general_announcements_... → folder: 'announcements'
///   - cr_panel_screen.dart      → folder: 'announcements'
///   - materials_screen.dart     → folder: 'materials'
///   - course_registry_screen.dart → folder: 'ct_marks'
class SupabaseStorageService {
  static SupabaseStorageClient get _storage => Supabase.instance.client.storage;

  /// Uploads [bytes] to Supabase Storage bucket [SupabaseConfig.bucket]
  /// under [folder]/timestamp_[fileName] and returns the permanent public URL.
  static Future<String> uploadFile({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  }) async {
    final lowerName = fileName.toLowerCase();
    final isImage = lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif');

    Uint8List uploadBytes = bytes;

    // Compress images on background isolate before uploading
    if (isImage) {
      debugPrint('[SupabaseUpload] Compressing image on background isolate: $fileName');
      try {
        final startLen = bytes.length;
        uploadBytes = await compute(_compressImageForStorage, bytes);
        final endLen = uploadBytes.length;
        debugPrint('[SupabaseUpload] Compressed image from $startLen to $endLen bytes');
      } catch (e) {
        debugPrint('[SupabaseUpload] Compression failed, using raw bytes: $e');
      }
    }

    // Always use a unique timestamped path to prevent collisions and allow immutability
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final storagePath = '$folder/$uniqueName';
    final mimeType = _getMimeType(fileName);

    debugPrint('[SupabaseUpload] Uploading to: ${SupabaseConfig.bucket}/$storagePath');
    debugPrint('[SupabaseUpload] File size: ${uploadBytes.length} bytes | MIME: $mimeType');

    try {
      await _storage.from(SupabaseConfig.bucket).uploadBinary(
        storagePath,
        uploadBytes,
        fileOptions: FileOptions(
          contentType: mimeType,
          upsert: false, // Never overwrite — immutable uploads only
        ),
      );

      // Get the permanent public URL (no expiry since bucket is public)
      final publicUrl = _storage
          .from(SupabaseConfig.bucket)
          .getPublicUrl(storagePath);

      debugPrint('[SupabaseUpload] Public URL: $publicUrl');

      // Update real-time storage metrics in Firestore
      try {
        final Map<String, dynamic> metricUpdate = {
          'totalBytes': FieldValue.increment(uploadBytes.length),
          'lastUploadTime': FieldValue.serverTimestamp(),
        };
        if (folder.contains('announcement')) {
          metricUpdate['announcementsBytes'] = FieldValue.increment(uploadBytes.length);
        } else if (folder.contains('material')) {
          metricUpdate['materialsBytes'] = FieldValue.increment(uploadBytes.length);
        } else if (folder.contains('avatar')) {
          metricUpdate['avatarsBytes'] = FieldValue.increment(uploadBytes.length);
        }
        FirebaseFirestore.instance
            .collection('app_config')
            .doc('storage_metrics')
            .set(metricUpdate, SetOptions(merge: true))
            .catchError((_) {});
      } catch (_) {}

      // Trigger keep-alive heartbeat for all previous projects in background
      SupabaseConfig.triggerHeartbeatIfNeeded().catchError((_) {});
      return publicUrl;
    } on StorageException catch (e) {
      debugPrint('[SupabaseUpload] StorageException: ${e.message} | statusCode: ${e.statusCode}');
      rethrow;
    } catch (e) {
      debugPrint('[SupabaseUpload] Unexpected error: $e');
      rethrow;
    }
  }

  /// Deletes a file from Supabase Storage given its full public URL.
  /// Extracts the storage path from the URL automatically.
  /// Call this when a material or announcement with a file is deleted from Firestore.
  static Future<void> deleteFileByUrl(String publicUrl) async {
    try {
      // Extract the storage path from the public URL
      // URL format: https://<project>.supabase.co/storage/v1/object/public/unigrid-files/<path>
      final uri = Uri.parse(publicUrl);
      final segments = uri.pathSegments;
      // Find "unigrid-files" in the path and take everything after it
      final bucketIndex = segments.indexOf(SupabaseConfig.bucket);
      if (bucketIndex == -1) {
        debugPrint('[SupabaseUpload] Could not extract path from URL: $publicUrl');
        return;
      }
      final storagePath = segments.sublist(bucketIndex + 1).join('/');

      debugPrint('[SupabaseUpload] Deleting: $storagePath');
      await _storage.from(SupabaseConfig.bucket).remove([storagePath]);
      debugPrint('[SupabaseUpload] Deleted: $storagePath');

      // Decrement storage metrics in Firestore
      try {
        final Map<String, dynamic> metricUpdate = {
          'lastUploadTime': FieldValue.serverTimestamp(),
        };
        if (storagePath.contains('announcement')) {
          metricUpdate['announcementsBytes'] = FieldValue.increment(-1500000);
          metricUpdate['totalBytes'] = FieldValue.increment(-1500000);
        } else if (storagePath.contains('material')) {
          metricUpdate['materialsBytes'] = FieldValue.increment(-2000000);
          metricUpdate['totalBytes'] = FieldValue.increment(-2000000);
        } else if (storagePath.contains('avatar')) {
          metricUpdate['avatarsBytes'] = FieldValue.increment(-500000);
          metricUpdate['totalBytes'] = FieldValue.increment(-500000);
        }
        FirebaseFirestore.instance
            .collection('app_config')
            .doc('storage_metrics')
            .set(metricUpdate, SetOptions(merge: true))
            .catchError((_) {});
      } catch (_) {}
    } catch (e) {
      // Non-fatal: log and continue. The Firestore doc deletion is more important.
      debugPrint('[SupabaseUpload] Delete failed (non-fatal): $e');
    }
  }

  static String _getMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'zip':
        return 'application/zip';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// Fetches live file metrics directly from Supabase Storage buckets
  static Future<Map<String, double>> fetchLiveStorageBreakdown() async {
    double materialsBytes = 0;
    double announcementsBytes = 0;
    double avatarsBytes = 0;
    double chatBytes = 0;
    double marksheetsBytes = 0;
    double otherBytes = 0;

    Future<void> scanPath(String path, String category) async {
      try {
        final items = await _storage.from(SupabaseConfig.bucket).list(path: path);
        for (final item in items) {
          final size = (item.metadata?['size'] as num?)?.toDouble() ??
              (item.metadata?['contentLength'] as num?)?.toDouble() ??
              0.0;
          if (size > 0) {
            if (category == 'materials' || path.startsWith('materials')) {
              materialsBytes += size;
            } else if (category == 'announcements' || path.startsWith('announcements')) {
              announcementsBytes += size;
            } else if (category == 'avatars' || path.startsWith('avatars') || path.startsWith('profile_photos')) {
              avatarsBytes += size;
            } else if (category == 'chat' || path.startsWith('chat_images')) {
              chatBytes += size;
            } else if (category == 'ct_marksheets' || path.startsWith('ct_marksheets')) {
              marksheetsBytes += size;
            } else {
              otherBytes += size;
            }
          } else if (item.id == null || item.id!.isEmpty) {
            // It's a folder: traverse it
            final nextSub = path.isEmpty ? item.name : '$path/${item.name}';
            await scanPath(nextSub, category);
          }
        }
      } catch (e) {
        debugPrint('[SupabaseStorage] Scan path error for $path: $e');
      }
    }

    try {
      await Future.wait([
        scanPath('materials', 'materials'),
        scanPath('announcements', 'announcements'),
        scanPath('profile_photos', 'avatars'),
        scanPath('avatars', 'avatars'),
        scanPath('chat_images', 'chat'),
        scanPath('ct_marksheets', 'ct_marksheets'),
      ]);
    } catch (e) {
      debugPrint('[SupabaseStorage] fetchLiveStorageBreakdown error: $e');
    }

    final totalLiveBytes = materialsBytes + announcementsBytes + avatarsBytes + chatBytes + marksheetsBytes + otherBytes;

    return {
      'materialsMB': materialsBytes / (1024 * 1024),
      'announcementsMB': announcementsBytes / (1024 * 1024),
      'avatarsMB': avatarsBytes / (1024 * 1024),
      'chatMB': chatBytes / (1024 * 1024),
      'marksheetsMB': marksheetsBytes / (1024 * 1024),
      'otherMB': otherBytes / (1024 * 1024),
      'totalLiveStorageMB': totalLiveBytes / (1024 * 1024),
    };
  }
}
