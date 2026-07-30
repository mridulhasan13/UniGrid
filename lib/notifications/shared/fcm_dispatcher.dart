import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ─────────────────────────────────────────────────────────────────────────────
/// FcmDispatcher
///
/// Single-responsibility HTTP sender.  Takes a list of FCM tokens + payload,
/// POSTs to the Netlify proxy (which auto-builds the correct per-platform
/// FCM payload), and cleans up dead tokens from Firestore.
///
/// • Web tokens → Netlify builds webpush payload (shown once by Service Worker)
/// • Native tokens → Netlify builds notification+android+apns payload
///
/// Fallback: if Netlify is unreachable on native, nothing fails — the error is
/// logged and the send is skipped (native apps also have FCMService as backup).
/// ─────────────────────────────────────────────────────────────────────────────
class FcmDispatcher {
  FcmDispatcher._();

  static const String _webVapidKey =
      'BNR1QB2c8bLrptm_9N8Zus_K4h4W7J7XFPj0tLTlB_195BQmphwUtImtcskWrbr1QfwnH4PCVoPvfywDcr5ajE8';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String get _netlifyUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.contains('unigrid.netlify.app')) {
        return '$origin/.netlify/functions/send-notification';
      }
    }
    return 'https://unigrid.netlify.app/.netlify/functions/send-notification';
  }

  // ─── Main dispatch ────────────────────────────────────────────────────────

  /// Sends [title]+[body] to every token in [tokens].
  /// Automatically filters out the sender's own device token.
  static Future<void> dispatch({
    required List<String> tokens,
    required String title,
    required String body,
    required String senderUserId,
    required String messageId,
  }) async {
    if (tokens.isEmpty) return;

    final Set<String> targets = tokens.toSet();

    // Remove sender's own current token so they don't notify themselves
    try {
      final String? selfToken = kIsWeb
          ? await FirebaseMessaging.instance
              .getToken(vapidKey: _webVapidKey)
              .timeout(const Duration(seconds: 2))
          : await FirebaseMessaging.instance
              .getToken()
              .timeout(const Duration(seconds: 2));
      if (selfToken != null && selfToken.isNotEmpty && targets.length > 1) {
        targets.remove(selfToken);
      }
    } catch (_) {}

    if (targets.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(_netlifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tokens': targets.toList(),
          'title': title,
          'bodyText': body,
          'senderUserId': senderUserId,
          'messageId': messageId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint(
          '[FcmDispatcher] ✓ Sent "$title" to ${targets.length} token(s)',
        );
        _handleDeadTokens(response.body);
      } else {
        debugPrint(
          '[FcmDispatcher] Netlify returned ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[FcmDispatcher] Dispatch error: $e');
    }
  }

  // ─── Dead-token cleanup ───────────────────────────────────────────────────

  static void _handleDeadTokens(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      if (data['deadTokens'] is! List) return;
      for (final dead in data['deadTokens'] as List) {
        if (dead is String && dead.isNotEmpty) _removeToken(dead);
      }
    } catch (_) {}
  }

  static void _removeToken(String token) {
    _db
        .collection('users')
        .where('fcmTokens', arrayContains: token)
        .get()
        .then((snap) {
      for (final doc in snap.docs) {
        doc.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
        if (doc.data()['fcmToken'] == token) {
          doc.reference.update({'fcmToken': FieldValue.delete()});
        }
        debugPrint('[FcmDispatcher] Removed dead token from ${doc.id}');
      }
    }).catchError((Object e) {
      debugPrint('[FcmDispatcher] Token cleanup error: $e');
    });
  }
}
