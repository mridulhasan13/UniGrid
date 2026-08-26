import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class _CachedGroupEntry {
  final List<String> tokens;
  final DateTime timestamp;

  _CachedGroupEntry(this.tokens) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 30);
}

class _CachedUserEntry {
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  _CachedUserEntry(this.data) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 30);
}

class _CachedGroupUsersEntry {
  final List<Map<String, dynamic>> userDocs;
  final DateTime timestamp;

  _CachedGroupUsersEntry(this.userDocs) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 30);
}

/// ─────────────────────────────────────────────────────────────────────────────
/// TokenResolver
///
/// Reads categorized FCM tokens from Firestore:
///   • `webTokens`   — explicit array saved when a Web user logs in
///   • `nativeTokens` — explicit array saved when an Android/iOS user logs in
///
/// Falls back to `fcmTokens` if explicit category fields are empty.
/// Uses in-memory caching to eliminate redundant reads during active sessions.
/// ─────────────────────────────────────────────────────────────────────────────
class TokenResolver {
  TokenResolver._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final Map<String, _CachedGroupEntry> _groupCache = {};
  static final Map<String, _CachedUserEntry> _userCache = {};
  static final Map<String, _CachedGroupUsersEntry> _groupUsersCache = {};

  static Future<Map<String, dynamic>?> _getUserData(String uid) async {
    final cached = _userCache[uid];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      _userCache[uid] = _CachedUserEntry(data);
      return data;
    } catch (e) {
      debugPrint('[TokenResolver] Error reading user $uid: $e');
      return null;
    }
  }

  // ─── Per-user lookups ──────────────────────────────────────────────────────

  /// All web (browser) tokens for a single user.
  static Future<List<String>> getWebTokensForUser(String uid, {String? requiredPreferenceField}) async {
    final data = await _getUserData(uid);
    if (requiredPreferenceField != null && data != null && data[requiredPreferenceField] == false) {
      debugPrint('[TokenResolver] Suppressed web token for user $uid ($requiredPreferenceField is disabled)');
      return [];
    }
    return _extractCategory(data, 'webTokens');
  }

  /// All native (Android/iOS) tokens for a single user.
  static Future<List<String>> getNativeTokensForUser(String uid, {String? requiredPreferenceField}) async {
    final data = await _getUserData(uid);
    if (requiredPreferenceField != null && data != null && data[requiredPreferenceField] == false) {
      debugPrint('[TokenResolver] Suppressed native token for user $uid ($requiredPreferenceField is disabled)');
      return [];
    }
    return _extractCategory(data, 'nativeTokens');
  }

  /// All tokens (web + native) for a single user.
  static Future<List<String>> getAllTokensForUser(String uid, {String? requiredPreferenceField}) async {
    final data = await _getUserData(uid);
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

  static Future<List<Map<String, dynamic>>> _getGroupUsers(String cleanDept) async {
    final cached = _groupUsersCache[cleanDept];
    if (cached != null && !cached.isExpired) {
      return cached.userDocs;
    }
    try {
      Query<Map<String, dynamic>> query = _db.collection('users');
      if (cleanDept.isNotEmpty) {
        query = query.where('department', isEqualTo: cleanDept);
      }
      var snap = await query.get();
      if (snap.docs.isEmpty && cleanDept.isNotEmpty) {
        snap = await _db.collection('users').get();
      }
      final docs = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      _groupUsersCache[cleanDept] = _CachedGroupUsersEntry(docs);
      return docs;
    } catch (e) {
      debugPrint('[TokenResolver] Error fetching group users: $e');
      return [];
    }
  }

  static Future<List<String>> _queryGroup({
    required String department,
    required String batch,
    required bool adminsOnly,
    required String categoryField,
    String? excludeUserId,
    String? requiredPreferenceField,
  }) async {
    final cacheKey =
        '${department}_${batch}_${adminsOnly}_${categoryField}_${excludeUserId ?? ""}_${requiredPreferenceField ?? ""}';
    final cached = _groupCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.tokens;
    }

    try {
      final cleanDept = department.trim().toUpperCase();
      final cleanBatch = batch.replaceAll('Batch', '').trim();

      final userDocs = await _getGroupUsers(cleanDept);
      final Set<String> tokens = {};

      for (final data in userDocs) {
        final String docId = (data['id'] ?? '').toString();
        if (excludeUserId != null && docId == excludeUserId) continue;

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

      final result = tokens.toList();
      _groupCache[cacheKey] = _CachedGroupEntry(result);
      return result;
    } catch (e) {
      debugPrint('[TokenResolver] Error querying group ($categoryField): $e');
      return [];
    }
  }
}
