import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// ─────────────────────────────────────────────────────────────────────────────
/// TokenResolver
///
/// Reads categorized FCM tokens from Firestore:
///   • `webTokens`   — explicit array saved when a Web user logs in
///   • `nativeTokens` — explicit array saved when an Android/iOS user logs in
///
/// Falls back to `fcmTokens` if explicit category fields are empty.
/// ─────────────────────────────────────────────────────────────────────────────
class TokenResolver {
  TokenResolver._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Per-user lookups ──────────────────────────────────────────────────────

  /// All web (browser) tokens for a single user.
  static Future<List<String>> getWebTokensForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return _extractCategory(doc.data(), 'webTokens');
  }

  /// All native (Android/iOS) tokens for a single user.
  static Future<List<String>> getNativeTokensForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return _extractCategory(doc.data(), 'nativeTokens');
  }

  /// All tokens (web + native) for a single user.
  static Future<List<String>> getAllTokensForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final Set<String> all = {};
    all.addAll(_extractCategory(doc.data(), 'webTokens'));
    all.addAll(_extractCategory(doc.data(), 'nativeTokens'));
    return all.toList();
  }

  // ─── Dept + Batch group lookups ───────────────────────────────────────────

  /// Web tokens for every member of a dept+batch group.
  static Future<List<String>> getWebTokensForGroup({
    required String department,
    required String batch,
    bool adminsOnly = false,
    String? excludeUserId,
  }) async {
    return _queryGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: excludeUserId,
      categoryField: 'webTokens',
    );
  }

  /// Native tokens for every member of a dept+batch group.
  static Future<List<String>> getNativeTokensForGroup({
    required String department,
    required String batch,
    bool adminsOnly = false,
    String? excludeUserId,
  }) async {
    return _queryGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: excludeUserId,
      categoryField: 'nativeTokens',
    );
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  static List<String> _extractCategory(
    Map<String, dynamic>? data,
    String categoryField,
  ) {
    if (data == null) return [];
    final Set<String> tokens = {};
    final bool isWebCategory = categoryField == 'webTokens';

    // 1. Primary: check explicit category array
    if (data[categoryField] is List) {
      for (final t in data[categoryField] as List) {
        if (t is String && t.isNotEmpty) {
          if (isWebCategory ? !t.contains(':APA91b') : t.contains(':APA91b')) {
            tokens.add(t);
          }
        }
      }
    }

    // 2. Fallback: if category array is empty, check legacy fcmTokens/fcmToken
    if (tokens.isEmpty) {
      if (data['fcmTokens'] is List) {
        for (final t in data['fcmTokens'] as List) {
          if (t is String && t.isNotEmpty) {
            if (isWebCategory ? !t.contains(':APA91b') : t.contains(':APA91b')) {
              tokens.add(t);
            }
          }
        }
      }
      final single = data['fcmToken'];
      if (single is String && single.isNotEmpty) {
        if (isWebCategory ? !single.contains(':APA91b') : single.contains(':APA91b')) {
          tokens.add(single);
        }
      }
    }

    return tokens.toList();
  }

  static Future<List<String>> _queryGroup({
    required String department,
    required String batch,
    required bool adminsOnly,
    required String categoryField,
    String? excludeUserId,
  }) async {
    try {
      final snap = await _db
          .collection('users')
          .where('department', isEqualTo: department)
          .where('batch', isEqualTo: batch)
          .get();

      final Set<String> tokens = {};
      for (final doc in snap.docs) {
        if (excludeUserId != null && doc.id == excludeUserId) continue;
        final data = doc.data();
        if (adminsOnly &&
            data['isCR'] != true &&
            data['isAdmin'] != true) {
          continue;
        }
        tokens.addAll(_extractCategory(data, categoryField));
      }
      return tokens.toList();
    } catch (e) {
      debugPrint('[TokenResolver] Error querying group ($categoryField): $e');
      return [];
    }
  }
}
