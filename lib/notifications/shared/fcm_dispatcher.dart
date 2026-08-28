import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

/// ─────────────────────────────────────────────────────────────────────────────
/// FcmDispatcher
///
/// Single-responsibility HTTP sender.  Takes a list of FCM tokens + payload,
/// POSTs to the Netlify proxy first, and if that fails on native platforms,
/// falls back to a direct FCM HTTP v1 call using the bundled service account.
///
/// Delivery strategy (2-step):
///   Step 1 — Netlify serverless proxy (free tier, 125k/mo)
///   Step 2 — Direct FCM HTTP v1 via service account (native only, fallback)
///
/// • Web tokens → Netlify builds webpush payload (shown once by Service Worker)
/// • Native tokens → Netlify or direct FCM builds notification+android+apns payload
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
    String targetPlatform = 'web',
    Map<String, String>? extraData,
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

    if (targets.isEmpty) {
      debugPrint('[FcmDispatcher] Targets empty (self-token removed or no active tokens)');
      return;
    }

    final List<String> finalTokens = targets.toList();

    // ── Step 1: Netlify free serverless proxy ────────────────────────────────
    bool netlifySucceeded = false;
    try {
      final response = await http.post(
        Uri.parse(_netlifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tokens': finalTokens,
          'title': title,
          'bodyText': body,
          'senderUserId': senderUserId,
          'messageId': messageId,
          'targetPlatform': targetPlatform,
          'extraData': extraData ?? {},
          ...?extraData,
        }),
      );

      if (response.statusCode == 200 && !response.body.trim().toLowerCase().startsWith('<!doctype')) {
        debugPrint(
          '[FcmDispatcher] ✓ Sent "$title" to ${finalTokens.length} token(s) via Netlify',
        );
        _handleDeadTokens(response.body);
        netlifySucceeded = true;
      } else {
        debugPrint(
          '[FcmDispatcher] Netlify returned status ${response.statusCode} (HTML/Non-JSON response)',
        );
      }
    } catch (e) {
      debugPrint('[FcmDispatcher] Netlify unavailable ($e) — trying native fallback');
    }

    // ── Step 2: Native fallback — direct FCM HTTP v1 via service account ─────
    // Only runs on Android/iOS when Netlify failed; rootBundle is unavailable on web.
    if (!netlifySucceeded && !kIsWeb) {
      await _sendDirectNative(
        tokens: finalTokens,
        title: title,
        body: body,
        senderUserId: senderUserId,
        messageId: messageId,
        extraData: extraData,
      );
    }
  }

  // ─── Direct FCM HTTP v1 (native fallback) ────────────────────────────────

  static Future<void> _sendDirectNative({
    required List<String> tokens,
    required String title,
    required String body,
    required String senderUserId,
    required String messageId,
    Map<String, String>? extraData,
  }) async {
    try {
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      final projectId = jsonMap['project_id'] as String?;
      if (projectId == null || projectId.isEmpty) {
        debugPrint('[FcmDispatcher] service_account.json missing project_id');
        return;
      }

      final accessToken = await _getAccessToken(jsonString);
      final endpoint =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      final target = (extraData?['target'] ?? extraData?['type'] ?? '').toString().toLowerCase();
      final bool isChat = target.contains('chat') || target.contains('private');
      final bool isRoutine = target.contains('schedule') || target.contains('routine');
      final String categoryTag = isChat
          ? 'unigrid_chats'
          : (isRoutine ? 'unigrid_routine' : 'unigrid_alerts');

      final Map<String, String> dataPayload = {
        'title': title,
        'body': body,
        'senderUserId': senderUserId,
        'messageId': messageId,
        'categoryTag': categoryTag,
        ...?extraData,
      };

      for (final token in tokens.toSet()) {
        try {
          final response = await http.post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'message': {
                'token': token,
                'notification': {'title': title, 'body': body},
                'data': dataPayload,
                'android': {
                  'priority': 'high',
                  'notification': {
                    'title': title,
                    'body': body,
                    'sound': 'default',
                    'channel_id': 'unigrid_notifications',
                    'tag': messageId,
                    'icon': '@mipmap/ic_launcher',
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                  },
                },
                'apns': {
                  'payload': {
                    'aps': {
                      'alert': {'title': title, 'body': body},
                      'sound': 'default',
                    },
                  },
                },
              },
            }),
          );

          if (response.statusCode == 200) {
            debugPrint('[FcmDispatcher] ✓ Direct FCM fallback OK: ${token.substring(0, 15)}...');
          } else if (response.statusCode == 404 ||
              response.body.contains('UNREGISTERED') ||
              response.body.contains('NOT_FOUND')) {
            debugPrint('[FcmDispatcher] Dead token (direct fallback), removing...');
            _removeToken(token);
          } else {
            debugPrint('[FcmDispatcher] Direct FCM failed: ${response.statusCode} ${response.body}');
          }
        } catch (e) {
          debugPrint('[FcmDispatcher] Direct FCM send error for token: $e');
        }
      }
    } catch (e) {
      debugPrint('[FcmDispatcher] _sendDirectNative error: $e');
    }
  }

  // ─── OAuth2 access token from service account JSON ───────────────────────

  static Future<String> _getAccessToken(String serviceAccountJson) async {
    final accountCredentials =
        auth.ServiceAccountCredentials.fromJson(serviceAccountJson);
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client = await auth.clientViaServiceAccount(accountCredentials, scopes);
    final accessToken = client.credentials.accessToken.data;
    client.close();
    return accessToken;
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
