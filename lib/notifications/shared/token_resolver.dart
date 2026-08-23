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
  static Future<List<String>> getWebTokensForUser(String uid, {String? requiredPreferenceField}) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (requiredPreferenceField != null && data != null && data[requiredPreferenceField] == false) {
      debugPrint('[TokenResolver] Suppressed web token for user $uid ($requiredPreferenceField is disabled)');
      return [];
    }
    return _extractCategory(data, 'webTokens');
  }

  /// All native (Android/iOS) tokens for a single user.
  static Future<List<String>> getNativeTokensForUser(String uid, {String? requiredPreferenceField}) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (requiredPreferenceField != null && data != null && data[requiredPreferenceField] == false) {
      debugPrint('[TokenResolver] Suppressed native token for user $uid ($requiredPreferenceField is disabled)');
      return [];
    }
    return _extractCategory(data, 'nativeTokens');
  }

  /// All tokens (web + native) for a single user.
  static Future<List<String>> getAllTokensForUser(String uid, {String? requiredPreferenceField}) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    if (requiredPreferenceField != null && data != null && data[requiredPreferenceField] == false) {
      return [];
    }
    final Set<String> all = {};
    all.addAll(_extractCategory(data, 'webTokens'));
    all.addAll(_extractCategory(data, 'nativeTokens'));
    return all.toList();
  }

  // ─── Dept + Batch group lookups ───────────────────────────────────────────

  /// Web tokens for every member of a dept+batch group.
  static Future<List<String>> getWebTokensForGroup({
    required String department,
    required String batch,
    bool adminsOnly = false,
    String? excludeUserId,
    String? requiredPreferenceField,
  }) async {
    return _queryGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: excludeUserId,
      categoryField: 'webTokens',
      requiredPreferenceField: requiredPreferenceField,
    );
  }

  /// Native tokens for every member of a dept+batch group.
  static Future<List<String>> getNativeTokensForGroup({
    required String department,
    required String batch,
    bool adminsOnly = false,
    String? excludeUserId,
    String? requiredPreferenceField,
  }) async {
    return _queryGroup(
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      excludeUserId: excludeUserId,
      categoryField: 'nativeTokens',
      requiredPreferenceField: requiredPreferenceField,
    );
  }

  static bool isWebToken(String token) {
    if (token.trim().isEmpty) return false;
    return true; // Any valid token retrieved from webTokens array
  }


  // ─── Internals ────────────────────────────────────────────────────────────

  static List<String> _extractCategory(
    Map<String, dynamic>? data,
    String categoryField,
  ) {
    if (data == null) return [];
    final Set<String> tokens = {};

    // 1. Primary: check explicit category array (webTokens or nativeTokens)
    if (data[categoryField] is List) {
      for (final t in data[categoryField] as List) {
        if (t is String && t.trim().isNotEmpty) {
          tokens.add(t.trim());
        }
      }
    }

    // 2. Secondary fallback: check general fcmTokens & fcmToken ONLY if explicit category fields do not exist on doc
    if (tokens.isEmpty &&
        !data.containsKey('webTokens') &&
        !data.containsKey('nativeTokens')) {
      if (data['fcmTokens'] is List) {
        for (final t in data['fcmTokens'] as List) {
          if (t is String && t.trim().isNotEmpty) {
            tokens.add(t.trim());
          }
        }
      }
      final single = data['fcmToken'];
      if (single is String && single.trim().isNotEmpty) {
        tokens.add(single.trim());
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
    String? requiredPreferenceField,
  }) async {
    try {
      final snap = await _db.collection('users').get();

      final Set<String> tokens = {};
      final cleanDept = department.trim().toUpperCase();
      final cleanBatch = batch.replaceAll('Batch', '').trim();

      for (final doc in snap.docs) {
        if (excludeUserId != null && doc.id == excludeUserId) continue;
        final data = doc.data();

        // 1. Department filter (case-insensitive)
        if (cleanDept.isNotEmpty) {
          final userDept =
              (data['department'] ?? '').toString().trim().toUpperCase();
          if (userDept != cleanDept) continue;
        }

        // 2. Batch filter (type-safe, handles int or string)
        if (cleanBatch.isNotEmpty) {
          final userBatch = (data['batch'] ?? '')
              .toString()
              .replaceAll('Batch', '')
              .trim();
          if (userBatch != cleanBatch) continue;
        }

        // ── Respect user's notification preference from settings ─────────────
        if (requiredPreferenceField != null &&
            data[requiredPreferenceField] == false) {
          continue; // User has toggled OFF this notification category in Settings
        }

        if (adminsOnly && data['isCR'] != true && data['isAdmin'] != true) {
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
