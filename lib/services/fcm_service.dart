import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart' show Icons;
import '../widgets/in_app_notification.dart';

// ─── Web Push VAPID Key ──────────────────────────────────────────────────────
// Generate this in Firebase Console → Project Settings → Cloud Messaging
// → Web Push certificates → Generate key pair.
// Replace the placeholder below with your actual VAPID key.
const String _webVapidKey =
    'BNR1QB2c8bLrptm_9N8Zus_K4h4W7J7XFPj0tLTlB_195BQmphwUtImtcskWrbr1QfwnH4PCVoPvfywDcr5ajE8';

/// Top-level background message handler — must be a top-level function.
/// Called by Firebase when a notification arrives while the app is terminated or in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do here — Android shows the notification automatically from the FCM payload.
  debugPrint('Background FCM message received: ${message.messageId}');
}

class FCMService {
  static bool _initialized = false;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // ─── Initialize FCM ───────────────────────────────────────────────────────
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      // ── Web-specific init ────────────────────────────────────────────────
      // Request permission from the browser.
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint('FCM web: notification permission denied');
        return;
      }

      // Save token for any already-logged-in user.
      final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await saveTokenForUser(currentUser.uid);
      }

      // Refresh listener — keep Firestore in sync when browser rotates the token.
      _messaging.onTokenRefresh.listen((newToken) async {
        final user = fb_auth.FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await _firestore.collection('users').doc(user.uid).set(
              {
                'fcmToken': newToken,
                'fcmTokens': FieldValue.arrayUnion([newToken]),
                'fcmUpdatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            debugPrint('FCM web token refreshed for user: ${user.uid}');
          } catch (e) {
            debugPrint('FCM web token refresh save error: $e');
          }
        }
      });

      // Foreground messages on web — show the in-app banner (no local notifications API on web).
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        final currentUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
        final senderUserId = message.data['senderUserId'] ?? '';
        if (senderUserId.isNotEmpty && senderUserId == currentUid) return;

        InAppNotification.showGlobal(
          title: notification.title ?? 'UniGrid',
          message: notification.body ?? '',
          icon: Icons.notifications_active_rounded,
        );
      });

      debugPrint('FCM web initialized successfully');
      return;
    }

    // ── Native (Android / iOS) init ──────────────────────────────────────────

    // Register token refresh listener immediately
    _messaging.onTokenRefresh.listen((newToken) async {
      final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await _firestore.collection('users').doc(currentUser.uid).set(
            {
              'fcmToken': newToken,
              'fcmTokens': FieldValue.arrayUnion([newToken]),
              'fcmUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          debugPrint('FCM token refreshed and saved for user: ${currentUser.uid}');
        } catch (e) {
          debugPrint('FCM token refresh save error: $e');
        }
      }
    });

    // Explicitly request notification permissions via permission_handler on Android
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }

    // Request push notification permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // Save FCM Token immediately if user is already logged in
    final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await saveTokenForUser(currentUser.uid);
    }

    // Subscribe to global topic
    try {
      await _messaging.subscribeToTopic('all_users');
      debugPrint('Subscribed to global all_users topic');
    } catch (e) {
      debugPrint('Topic subscription failed: $e');
    }

    // Request battery optimization exclusion
    await _requestBatteryOptimizationExclusion();

    // Setup local notifications channel
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // Create high-importance notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'unigrid_notifications',
      'UniGrid Notifications',
      description: 'Push notifications for UniGrid App',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Handle messages when app is in FOREGROUND
    FirebaseMessaging.onMessage.listen(_showNotificationFromRemote);
  }

  // ─── Request Battery Optimization Exclusion ───────────────────────────────
  static Future<void> _requestBatteryOptimizationExclusion() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('Battery optimization exclusion failed: $e');
    }
  }

  // ─── Show local notification from FCM remote message ─────────────────────
  static Future<void> _showNotificationFromRemote(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // Block self-notifications
    final currentUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    final senderUserId = message.data['senderUserId'] ?? '';
    if (senderUserId.isNotEmpty && senderUserId == currentUid) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'unigrid_notifications',
          'UniGrid Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          ticker: notification.body,
          subText: 'UniGrid',
          styleInformation: BigTextStyleInformation(
            notification.body ?? '',
            contentTitle: notification.title,
          ),
        ),
      ),
    );

    // Show floating in-app glassmorphic notification banner
    InAppNotification.showGlobal(
      title: notification.title ?? 'Notification',
      message: notification.body ?? '',
      icon: Icons.notifications_active_rounded,
    );
  }

  // ─── Show Direct Device System Notification (Phone Tray) ───────────────────
  static Future<void> showLocalSystemNotification({
    required String title,
    required String body,
    int? id,
  }) async {
    if (kIsWeb) return;
    try {
      await _localNotifications.show(
        id ?? title.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'unigrid_notifications',
            'UniGrid Notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            ticker: body,
            subText: 'Class Reminder',
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error showing local system notification: $e');
    }
  }

  // ─── Save FCM Token to Firestore ──────────────────────────────────────────
  static Future<void> saveTokenForUser(String userId) async {
    try {
      // On web, a VAPID key is required to get the push subscription token.
      // On native platforms, getToken() works without any arguments.
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey)
          : await _messaging.getToken();
      if (token == null) {
        debugPrint('FCM token is null for user: $userId');
        return;
      }
      await _firestore.collection('users').doc(userId).set(
        {
          'fcmToken': token,
          'fcmTokens': FieldValue.arrayUnion([token]),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      print('\n====================================================');
      print('🔥 FCM TOKEN (User: $userId, Web: $kIsWeb):');
      print(token);
      print('====================================================\n');
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  // ─── Get OAuth2 Access Token from Service Account ─────────────────────────
  static Future<String> _getAccessToken() async {
    final jsonString = await rootBundle.loadString('assets/service_account.json');
    final accountCredentials = auth.ServiceAccountCredentials.fromJson(jsonString);
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client = await auth.clientViaServiceAccount(accountCredentials, scopes);
    final accessToken = client.credentials.accessToken.data;
    client.close();
    return accessToken;
  }

  // ─── Netlify Free Serverless Endpoint ──────────────────────────────────
  static String get _netlifyFunctionUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.contains('unigrid.netlify.app')) {
        return '/.netlify/functions/send-notification';
      }
    }
    return 'https://unigrid.netlify.app/.netlify/functions/send-notification';
  }

  static Future<void> _removeStaleToken(String token) async {
    try {
      final staleQuery = await _firestore
          .collection('users')
          .where('fcmTokens', arrayContains: token)
          .get();
      for (final doc in staleQuery.docs) {
        await doc.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
        if (doc.data()['fcmToken'] == token) {
          await doc.reference.update({'fcmToken': FieldValue.delete()});
        }
        debugPrint('Removed dead FCM token from user: ${doc.id}');
      }
    } catch (e) {
      debugPrint('Could not clean stale token: $e');
    }
  }

  // ─── Send FCM to a list of target FCM tokens ─────────────────────────────
  // Free notification delivery across ALL platforms:
  // - Web to App
  // - App to Web
  // - App to App
  // - Web to Web
  static Future<void> _sendFCMHttp({
    required List<String> tokens,
    required String title,
    required String body,
    required String senderUserId,
  }) async {
    if (tokens.isEmpty) return;

    // Deduplicate tokens set & remove current user device token
    final currentToken = kIsWeb
        ? await _messaging.getToken(vapidKey: _webVapidKey)
        : await _messaging.getToken();
    final Set<String> targetTokens = tokens.toSet();
    if (currentToken != null) {
      targetTokens.remove(currentToken);
    }
    if (targetTokens.isEmpty) return;

    final List<String> finalTokens = targetTokens.toList();

    // 1. First, attempt delivery via Netlify free serverless proxy (125k/mo free)
    try {
      final netlifyUri = Uri.parse(_netlifyFunctionUrl);
      final response = await http.post(
        netlifyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tokens': finalTokens,
          'title': title,
          'bodyText': body,
          'senderUserId': senderUserId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCMService] Sent notification via Netlify proxy to ${finalTokens.length} unique token(s)');
        return;
      } else {
        debugPrint('[FCMService] Netlify function returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[FCMService] Netlify proxy unavailable/failed ($e) — checking native fallback');
    }

    // 2. Fallback for Native platforms (Android/iOS): Direct FCM HTTP v1 via Service Account
    if (!kIsWeb) {
      try {
        final jsonString = await rootBundle.loadString('assets/service_account.json');
        final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
        final projectId = jsonMap['project_id'] as String?;
        if (projectId == null || projectId.isEmpty) return;

        final accessToken = await _getAccessToken();
        final endpoint =
            'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

        for (final token in tokens) {
          final response = await http.post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'message': {
                'token': token,
                'notification': {
                  'title': title,
                  'body': body,
                },
                'data': {
                  'senderUserId': senderUserId,
                },
                'android': {
                  'priority': 'high',
                  'notification': {
                    'sound': 'default',
                    'channel_id': 'unigrid_notifications',
                  },
                },
                'apns': {
                  'payload': {
                    'aps': {
                      'sound': 'default',
                    },
                  },
                },
                'webpush': {
                  'notification': {
                    'title': title,
                    'body': body,
                    'icon': '/icons/Icon-192.png',
                    'requireInteraction': false,
                  },
                  'fcm_options': {
                    'link': '/',
                  },
                },
              },
            }),
          );

          if (response.statusCode == 200) {
            debugPrint('FCM sent directly to token: ${token.substring(0, 15)}...');
          } else if (response.statusCode == 404) {
            debugPrint('Stale FCM token detected, removing from Firestore...');
            await _removeStaleToken(token);
          } else {
            debugPrint('FCM direct failed: ${response.statusCode} ${response.body}');
          }
        }
      } catch (e) {
        debugPrint('Error sending FCM direct native: $e');
      }
    }
  }

  // ─── Send to a Specific User (Private DM) ─────────────────────────────────
  static Future<void> sendPrivateNotification({
    required String recipientId,
    required String title,
    required String body,
    required String senderUserId,
  }) async {
    try {
      final recipientDoc =
          await _firestore.collection('users').doc(recipientId).get();
      if (!recipientDoc.exists) return;
      final data = recipientDoc.data();
      if (data == null) return;

      final Set<String> tokens = {};
      if (data['fcmTokens'] is List) {
        for (final t in data['fcmTokens']) {
          if (t is String && t.isNotEmpty) tokens.add(t);
        }
      }
      if (tokens.isEmpty && data['fcmToken'] is String && (data['fcmToken'] as String).isNotEmpty) {
        tokens.add(data['fcmToken'] as String);
      }

      if (tokens.isEmpty) {
        debugPrint('No FCM tokens for recipient: $recipientId');
        return;
      }
      await _sendFCMHttp(
        tokens: tokens.toList(),
        title: title,
        body: body,
        senderUserId: senderUserId,
      );
    } catch (e) {
      debugPrint('sendPrivateNotification error: $e');
    }
  }

  static Future<void> sendToDeptAndBatch({
    required String department,
    required String batch,
    required String title,
    required String body,
    required String senderUserId,
    bool adminsOnly = false,
  }) async {
    try {
      final currentToken = kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey)
          : await _messaging.getToken();
      final usersSnap = await _firestore
          .collection('users')
          .where('department', isEqualTo: department)
          .where('batch', isEqualTo: batch)
          .get();

      final Set<String> tokens = {};
      for (final doc in usersSnap.docs) {
        if (doc.id == senderUserId) continue;
        final data = doc.data();
        if (adminsOnly) {
          final isCR = data['isCR'] == true;
          final isAdmin = data['isAdmin'] == true;
          if (!isCR && !isAdmin) continue;
        }

        if (data['fcmTokens'] is List) {
          for (final t in data['fcmTokens']) {
            if (t is String && t.isNotEmpty && t != currentToken) {
              tokens.add(t);
            }
          }
        }
        if (data['fcmToken'] is String && (data['fcmToken'] as String).isNotEmpty) {
          final t = data['fcmToken'] as String;
          if (t != currentToken) tokens.add(t);
        }
      }

      if (tokens.isEmpty) {
        debugPrint('No tokens to notify for $department - $batch');
        return;
      }

      await _sendFCMHttp(
        tokens: tokens.toList(),
        title: title,
        body: body,
        senderUserId: senderUserId,
      );
      debugPrint('Notified ${tokens.length} target tokens in $department - $batch');
    } catch (e) {
      debugPrint('sendToDeptAndBatch error: $e');
    }
  }

  // ─── Shortcut Helpers ─────────────────────────────────────────────────────
  // These helpers work on both web and native — they use Firestore + HTTP v1.
  static Future<void> notifyNewMessage({
    required String senderName,
    required String text,
    required String senderUserId,
    required String department,
    required String batch,
  }) async {
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: senderName,
      body: preview,
      senderUserId: senderUserId,
    );
  }

  static Future<void> notifyNewAnnouncement({
    required String title,
    required String type,
    required String senderUserId,
    required String department,
    required String batch,
  }) async {
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: 'New ${type.isNotEmpty ? type : "Announcement"}',
      body: title,
      senderUserId: senderUserId,
    );
  }

  static Future<void> notifyNewMaterial({
    required String title,
    required String subject,
    required String senderUserId,
    required String department,
    required String batch,
  }) async {
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: 'New Material Uploaded',
      body: '$title${subject.isNotEmpty ? ' · $subject' : ''}',
      senderUserId: senderUserId,
    );
  }
}
