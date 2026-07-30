import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// ─────────────────────────────────────────────────────────────────────────────
/// TokenResolver
///
/// Reads FCM tokens from Firestore and splits them into:
///   • Web tokens   — browser Push subscriptions (no ':APA91b' in string)
///   • Native tokens — Android / iOS FCM registrations (contain ':APA91b')
///
/// This mirrors the same detection logic used in the Netlify function
/// `netlify/functions/send-notification.js → isWebToken()`.
/// ─────────────────────────────────────────────────────────────────────────────
class TokenResolver {
  TokenResolver._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Token classification ──────────────────────────────────────────────────
  static bool isWebToken(String token) => !token.contains(':APA91b');
  static bool isNativeToken(String token) => token.contains(':APA91b');

  // ─── Per-user lookups ──────────────────────────────────────────────────────

  /// All web (browser) tokens for a single user.
  static Future<List<String>> getWebTokensForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return _extract(doc.data(), isWebToken);
  }

  /// All native (Android/iOS) tokens for a single user.
  static Future<List<String>> getNativeTokensForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return _extract(doc.data(), isNativeToken);
  }

  /// All tokens (web + native) for a single user.
  static Future<List<String>> getAllTokensForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return _extract(doc.data(), (_) => true);
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
      filter: isWebToken,
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
      filter: isNativeToken,
    );
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  static List<String> _extract(
    Map<String, dynamic>? data,
    bool Function(String) filter,
  ) {
    if (data == null) return [];
    final Set<String> tokens = {};

    if (data['fcmTokens'] is List) {
      for (final t in data['fcmTokens'] as List) {
        if (t is String && t.isNotEmpty && filter(t)) tokens.add(t);
      }
    }
    final single = data['fcmToken'];
    if (single is String && single.isNotEmpty && filter(single)) {
      tokens.add(single);
    }

    return tokens.toList();
  }

  static Future<List<String>> _queryGroup({
    required String department,
    required String batch,
    required bool adminsOnly,
    required bool Function(String) filter,
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
        tokens.addAll(_extract(data, filter));
      }
      return tokens.toList();
    } catch (e) {
      debugPrint('[TokenResolver] Error querying group: $e');
      return [];
    }
  }
}
