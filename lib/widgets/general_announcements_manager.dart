import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/supabase_storage_service.dart';
import '../utils/constants.dart';
import '../widgets/glass_card.dart';
import '../widgets/linkified_text.dart';
import '../widgets/unigrid_loader.dart';
import '../notifications/fcm_service.dart';
import '../notifications/in_app_notification.dart';
import '../screens/file_viewer_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// GeneralAnnouncementService
/// ─────────────────────────────────────────────────────────────────────────────
class GeneralAnnouncementService {
  GeneralAnnouncementService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'general_announcements';

  /// Stream of unseen general announcement count for a specific [userId].
  static Stream<int> unseenCountStream(String userId) {
    if (userId.isEmpty) return Stream.value(0);
    return _db
        .collection(_collection)
        .snapshots()
        .map((snap) {
      int unseen = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final List seenBy = data['seenBy'] is List ? (data['seenBy'] as List) : [];
        if (!seenBy.contains(userId)) {
          unseen++;
        }
      }
      return unseen;
    });
  }

  /// Mark a specific general announcement doc as seen by [userId].
  static Future<void> markAsSeen(String docId, String userId) async {
    if (docId.isEmpty || userId.isEmpty) return;
    try {
      await _db.collection(_collection).doc(docId).set({
        'seenBy': FieldValue.arrayUnion([userId]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[GeneralAnnouncementService] Error marking as seen: $e');
    }
  }

  /// Post a new General Announcement (Root Admin only) and dispatch FCM push to all users.
  static Future<void> postGeneralAnnouncement({
    required String title,
    required String content,
    required String details,
    required String type,
    required String postedBy,
    required String postedByUserId,
    PlatformFile? file,
  }) async {
    final Map<String, dynamic> docData = {
      'title': title,
      'content': content,
      'type': type.isNotEmpty ? type : 'General',
      'timestamp': FieldValue.serverTimestamp(),
      'postedBy': postedBy,
      'postedByUserId': postedByUserId,
      'seenBy': [postedByUserId],
    };

    if (details.isNotEmpty) {
      docData['details'] = details;
    }
    if (file != null && file.name.isNotEmpty) {
      docData['fileName'] = file.name;
    }

    // 1. Post document to global Firestore collection
    final docRef = await _db.collection(_collection).add(docData);

    // 2. Dispatch FCM global notification to all users across app
    try {
      FCMService.notifyGeneralAnnouncement(
        title: title,
        content: content,
        senderUserId: postedByUserId,
        messageId: docRef.id,
      );
    } catch (e) {
      debugPrint('[GeneralAnnouncementService] FCM notification error: $e');
    }

    // 3. Background file upload (if attached)
    if (file != null) {
      try {
        Uint8List? fileBytes = file.bytes;
        if ((fileBytes == null || fileBytes.isEmpty) && file.path != null) {
          if (!kIsWeb) {
            fileBytes = await File(file.path!).readAsBytes();
          }
        }

        if (fileBytes != null) {
          final fileUrl = await SupabaseStorageService.uploadFile(
            bytes: fileBytes,
            fileName: file.name,
            folder: 'announcements',
          );

          await docRef.update({'fileUrl': fileUrl});
        }
      } catch (e) {
        debugPrint('[GeneralAnnouncementService] Background file upload error: $e');
      }
    }
  }

  /// Delete a general announcement (Root Admin only).
  static Future<void> deleteAnnouncement(String docId) async {
    try {
      final snap = await _db.collection(_collection).doc(docId).get();
      final data = snap.data();
      final fileUrl = (data?['fileUrl'] ?? '').toString();
      if (fileUrl.isNotEmpty) {
        await SupabaseStorageService.deleteFileByUrl(fileUrl);
      }
    } catch (_) {}
    await _db.collection(_collection).doc(docId).delete();
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// GeneralNotificationBell
/// Top-right icon button that replaces the logout icon on HomeScreen.
/// Shows a live unseen badge count. Tapping opens GeneralAnnouncementsSheet.
/// ─────────────────────────────────────────────────────────────────────────────
class GeneralNotificationBell extends StatelessWidget {
  final AppUser? user;
  const GeneralNotificationBell({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final userId = user?.id ?? '';

    return StreamBuilder<int>(
      stream: GeneralAnnouncementService.unseenCountStream(userId),
      builder: (context, snapshot) {
        final unseenCount = snapshot.data ?? 0;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                unseenCount > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_outlined,
                color: unseenCount > 0
                    ? Colors.amberAccent
                    : AppColors.textSecondary,
                size: 24,
              ),
              tooltip: 'General Announcements',
              onPressed: () {
                if (user != null) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => GeneralAnnouncementsSheet(user: user!),
                  );
                }
              },
            ),

            // Unseen badge counter
            if (unseenCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent,
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unseenCount > 99 ? '99+' : '$unseenCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// GeneralAnnouncementsSheet
/// Modal bottom sheet displaying all General Announcements.
/// ─────────────────────────────────────────────────────────────────────────────
class GeneralAnnouncementsSheet extends StatelessWidget {
  final AppUser user;
  const GeneralAnnouncementsSheet({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = authService.isRootAdmin(authService.currentAuthEmail) ||
        authService.isRootAdmin(user.email) ||
        user.isAdmin ||
        user.isCR;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: AppColors.backgroundTop.withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.12)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.amberAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'General Announcements',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'University-wide official notices from Root Admin',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.textPrimary.withOpacity(0.1)),

              // Stream of General Announcements
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('general_announcements')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading announcements: ${snapshot.error}',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const UniGridLoader(
                        title: 'Loading',
                        subtitle: 'Fetching general notices...',
                        showBackground: false,
                      );
                    }

                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_paused_rounded,
                              size: 48,
                              color: AppColors.textPrimary.withOpacity(0.25),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No general announcements yet.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Map & Sort by timestamp descending
                    final items = docs.map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      DateTime dt = DateTime.now();
                      if (data['timestamp'] is Timestamp) {
                        dt = (data['timestamp'] as Timestamp).toDate();
                      }
                      final List seenBy =
                          data['seenBy'] is List ? (data['seenBy'] as List) : [];
                      final bool isSeen = seenBy.contains(user.id);

                      return {
                        'id': d.id,
                        'title': data['title'] ?? '',
                        'content': data['content'] ?? '',
                        'type': data['type'] ?? 'General',
                        'timestamp': dt,
                        'postedBy': data['postedBy'] ?? 'Root Admin',
                        'fileUrl': data['fileUrl'],
                        'fileName': data['fileName'],
                        'details': data['details'],
                        'isSeen': isSeen,
                      };
                    }).toList()
                      ..sort((a, b) => (b['timestamp'] as DateTime)
                          .compareTo(a['timestamp'] as DateTime));

                    // Schedule mark-as-seen post-frame to prevent infinite build/stream loops
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      for (final item in items) {
                        final bool isSeen = item['isSeen'] as bool;
                        final String id = item['id'] as String;
                        if (!isSeen) {
                          GeneralAnnouncementService.markAsSeen(id, user.id);
                        }
                      }
                    });

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _GeneralCard(
                          item: item,
                          isRootAdmin: isRootAdmin,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneralCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isRootAdmin;

  const _GeneralCard({
    required this.item,
    required this.isRootAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final String type = item['type'] as String;
    final DateTime dt = item['timestamp'] as DateTime;
    final String dateStr = DateFormat('MMM dd, hh:mm a').format(dt);
    final String? fileUrl = item['fileUrl'] as String?;
    final String? fileName = item['fileName'] as String?;
    final String? details = item['details'] as String?;

    Color badgeColor = Colors.amberAccent;
    if (type == 'Urgent') badgeColor = Colors.redAccent;
    if (type == 'System Alert') badgeColor = Colors.purpleAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Badge & Actions
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign, color: badgeColor, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        type.toUpperCase(),
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['postedBy'] as String,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (isRootAdmin) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent, size: 20),
                    tooltip: 'Delete Announcement',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.backgroundTop,
                          title: const Text('Delete General Announcement'),
                          content: const Text(
                              'Are you sure you want to delete this global notice?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete',
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await GeneralAnnouncementService.deleteAnnouncement(
                            item['id'] as String);
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Title
            if ((item['title'] as String).isNotEmpty)
              Text(
                item['title'] as String,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if ((item['title'] as String).isNotEmpty)
              const SizedBox(height: 6),

            // Content
            LinkifiedText(
              item['content'] as String,
              style: TextStyle(
                color: AppColors.textPrimary.withOpacity(0.9),
                fontSize: 14,
                height: 1.4,
              ),
              selectable: true,
            ),

            // Details line (if present)
            if (details != null && details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Text(
                  details,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            // Attachment button (if present)
            if (fileUrl != null && fileUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FileViewerScreen(
                        fileUrl: fileUrl,
                        fileName: fileName ?? 'Attachment',
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.glassCardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.glassCardBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file_rounded,
                          color: AppColors.secondary, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName ?? 'View Attached Document',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                dateStr,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// GeneralAnnouncementComposer
/// Dispatch UI added to MasterPanelScreen for Root Admins to send global notices.
/// ─────────────────────────────────────────────────────────────────────────────
class GeneralAnnouncementComposer extends StatefulWidget {
  const GeneralAnnouncementComposer({super.key});

  @override
  State<GeneralAnnouncementComposer> createState() =>
      _GeneralAnnouncementComposerState();
}

class _GeneralAnnouncementComposerState
    extends State<GeneralAnnouncementComposer> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _detailsController = TextEditingController();
  String _type = 'General';
  PlatformFile? _attachedFile;
  bool _isPosting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: kIsWeb,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _attachedFile = result.files.first;
      });
    }
  }

  Future<void> _dispatchGeneralAnnouncement() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    final details = _detailsController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      InAppNotification.show(
        context,
        title: 'Input Missing',
        message: 'Please enter a title or announcement content.',
        accentColor: Colors.redAccent,
      );
      return;
    }

    final user = Provider.of<AppUser?>(context, listen: false);
    if (user == null) return;

    setState(() => _isPosting = true);

    final postedBy =
        user.name.isNotEmpty ? '${user.name} (Root Admin)' : 'Root Admin';

    try {
      await GeneralAnnouncementService.postGeneralAnnouncement(
        title: title,
        content: content,
        details: details,
        type: _type,
        postedBy: postedBy,
        postedByUserId: user.id,
        file: _attachedFile,
      );

      _titleController.clear();
      _contentController.clear();
      _detailsController.clear();
      setState(() {
        _attachedFile = null;
        _isPosting = false;
      });

      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Global Announcement Dispatched',
          message: 'General Announcement sent to all users across the app!',
          accentColor: Colors.green,
          icon: Icons.campaign_rounded,
        );
      }
    } catch (e) {
      setState(() => _isPosting = false);
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Dispatch Error',
          message: 'Failed to post general announcement: $e',
          accentColor: Colors.redAccent,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width <= 600;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.campaign_rounded,
                    color: Colors.amberAccent, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GENERAL ANNOUNCEMENT',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Broadcast to EVERY user across all departments & batches',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Title
          TextField(
            controller: _titleController,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Announcement Title',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.glassCardBorder),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Content
          TextField(
            controller: _contentController,
            maxLines: 4,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Announcement Message',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.glassCardBorder),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Details & Category Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _detailsController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Details (e.g. Venue: Main Hall)',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.glassCardBorder),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassCardBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _type,
                    dropdownColor: AppColors.backgroundTop,
                    style: TextStyle(color: AppColors.textPrimary),
                    items: const [
                      DropdownMenuItem(
                          value: 'General', child: Text('General')),
                      DropdownMenuItem(
                          value: 'Urgent', child: Text('Urgent')),
                      DropdownMenuItem(
                          value: 'System Alert', child: Text('System Alert')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _type = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Attachment & Submit Row (Responsive for Mobile & Desktop)
          if (isMobile) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.attach_file_rounded, size: 18),
                    label: Text(
                      _attachedFile == null
                          ? 'Attach File'
                          : _attachedFile!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.glassCardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (_attachedFile != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.redAccent, size: 18),
                    onPressed: () => setState(() => _attachedFile = null),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isPosting ? null : _dispatchGeneralAnnouncement,
                icon: _isPosting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: AppColors.onPrimary, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_isPosting ? 'Dispatching...' : 'Dispatch Global'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(
                    _attachedFile == null
                        ? 'Attach File'
                        : _attachedFile!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.glassCardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_attachedFile != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.redAccent, size: 18),
                    onPressed: () => setState(() => _attachedFile = null),
                  ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isPosting ? null : _dispatchGeneralAnnouncement,
                  icon: _isPosting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: AppColors.onPrimary, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_isPosting ? 'Dispatching...' : 'Dispatch Global'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
