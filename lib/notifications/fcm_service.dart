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
import 'package:flutter/material.dart';
import 'in_app_notification.dart';
import 'notification_router.dart';
import 'notification_coordinator.dart';

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
      try {
        final settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await saveTokenForUser(currentUser.uid);
          }
        } else {
          debugPrint('FCM web permission status: ${settings.authorizationStatus}');
        }
      } catch (e) {
        debugPrint('FCM web permission request notice: $e');
      }

      // Refresh listener — keep Firestore in sync when browser rotates the token.
      _messaging.onTokenRefresh.listen((newToken) async {
        final user = fb_auth.FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await removeTokenFromAllExcept(newToken, user.uid);
            await _firestore.collection('users').doc(user.uid).set(
              {
                'fcmToken': newToken,
                'fcmTokens': FieldValue.arrayUnion([newToken]),
                'webTokens': FieldValue.arrayUnion([newToken]),
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

      // Note: Foreground messages are handled by NotificationCoordinator (WWReceiver / AWReceiver).
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
              'nativeTokens': FieldValue.arrayUnion([newToken]),
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

    // Setup local notifications channel
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            NotificationRouter.handlePayload(data);
          } catch (e) {
            debugPrint('[FCMService] Local notification payload parse error: $e');
          }
        }
      },
    );

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

    // Register tap listeners for notifications opened when app is in background or terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCMService] Notification opened app: ${message.data}');
      NotificationRouter.handleRemoteMessage(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('[FCMService] App launched from notification: ${message.data}');
        NotificationRouter.handleRemoteMessage(message);
      }
    });

    // Note: Foreground messages are handled by NotificationCoordinator (WAReceiver / AAReceiver).
  }

  // ─── Show local notification from FCM remote message (foreground only) ──────
  // Called ONLY when the app is in the FOREGROUND.
  // When the app is background/terminated, Android FCM plugin shows the system
  // tray notification automatically from the payload's `notification` block.
  // Showing a local notification here in that case would create a duplicate.
  // ignore: unused_element
  static Future<void> _showNotificationFromRemote(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'] ?? 'UniGrid';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    if (title.isEmpty && body.isEmpty) return;

    // Block self-notifications
    final currentUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    final senderUserId = message.data['senderUserId'] ?? '';
    if (senderUserId.isNotEmpty && senderUserId == currentUid) return;

    // Show system tray notification only for data-only messages
    // (messages WITH a `notification` block are already shown by FCM plugin
    // in background; in foreground they are suppressed by Android — safe to show).
    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'unigrid_notifications',
          'UniGrid Notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );

    // Always show the floating in-app glassmorphic banner in foreground
    InAppNotification.showGlobal(
      title: title,
      message: body,
      icon: Icons.notifications_active_rounded,
    );
  }

  // ─── Show Direct Device System Notification (Phone Tray) ───────────────────
  static Future<void> showLocalSystemNotification({
    required String title,
    required String body,
    int? id,
    Map<String, dynamic>? data,
  }) async {
    if (kIsWeb) return;
    try {
      final payloadData = Map<String, dynamic>.from(data ?? {'target': 'schedule', 'route': '/schedule'});
      payloadData['title'] ??= title;
      payloadData['body'] ??= body;

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
        payload: jsonEncode(payloadData),
      );
    } catch (e) {
      debugPrint('Error showing local system notification: $e');
    }
  }

  static String? _cachedToken;

  // ─── Save FCM Token to Firestore ──────────────────────────────────────────
  static Future<void> saveTokenForUser(String userId) async {
    try {
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey)
          : await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('FCM token is null or empty for user: $userId');
        return;
      }
      _cachedToken = token;

      // 1. Remove this token from any OTHER user account (cross-account cleanup)
      await removeTokenFromAllExcept(token, userId);

      // 2. Add to current user doc
      await _firestore.collection('users').doc(userId).set(
        {
          'fcmToken': token,
          'fcmTokens': FieldValue.arrayUnion([token]),
          if (kIsWeb)
            'webTokens': FieldValue.arrayUnion([token])
          else
            'nativeTokens': FieldValue.arrayUnion([token]),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('FCM token saved successfully for user: $userId');
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  /// Removes [token] from all user documents except [currentUserId]
  static Future<void> removeTokenFromAllExcept(String token, String currentUserId) async {
    try {
      final snap = await _firestore
          .collection('users')
          .where('fcmTokens', arrayContains: token)
          .get();
      for (final doc in snap.docs) {
        if (doc.id == currentUserId) continue;
        await doc.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
          'webTokens': FieldValue.arrayRemove([token]),
          'nativeTokens': FieldValue.arrayRemove([token]),
        });
        if (doc.data()['fcmToken'] == token) {
          await doc.reference.update({'fcmToken': FieldValue.delete()});
        }
        debugPrint('Cleaned up token from previous account: ${doc.id}');
      }
    } catch (e) {
      debugPrint('removeTokenFromAllExcept error: $e');
    }
  }

  /// Removes current device token on user logout
  static Future<void> removeCurrentTokenOnLogout(String userId) async {
    try {
      final token = _cachedToken ?? (kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey).catchError((_) => null)
          : await _messaging.getToken().catchError((_) => null));
      if (token != null && token.isNotEmpty) {
        await _firestore.collection('users').doc(userId).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
          'webTokens': FieldValue.arrayRemove([token]),
          'nativeTokens': FieldValue.arrayRemove([token]),
        });
        debugPrint('Removed FCM token on logout for user: $userId');
      }
    } catch (e) {
      debugPrint('removeCurrentTokenOnLogout error: $e');
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
      final origin = Uri.base.origin;
      if (origin.contains('unigrid.netlify.app')) {
        return '$origin/.netlify/functions/send-notification';
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
          'webTokens': FieldValue.arrayRemove([token]),
          'nativeTokens': FieldValue.arrayRemove([token]),
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
  // ignore: unused_element
  static Future<void> _sendFCMHttp({
    required List<String> tokens,
    required String title,
    required String body,
    required String senderUserId,
    String? messageId,
  }) async {
    if (tokens.isEmpty) return;

    // Deduplicate tokens set & remove current user device token
    String? currentToken;
    try {
      currentToken = kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey).timeout(const Duration(seconds: 2))
          : await _messaging.getToken().timeout(const Duration(seconds: 2));
    } catch (_) {}

    final Set<String> targetTokens = tokens.toSet();
    final String? selfToken = currentToken ?? _cachedToken;
    // Only filter out self-token if there are multiple tokens present.
    // If there is only 1 token (e.g. self-testing or single device), allow delivery.
    if (targetTokens.length > 1 && selfToken != null && selfToken.isNotEmpty) {
      targetTokens.remove(selfToken);
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
          'messageId': messageId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCMService] Sent notification via Netlify proxy to ${finalTokens.length} unique token(s)');
        try {
          final resData = jsonDecode(response.body);
          if (resData['deadTokens'] is List) {
            for (final deadToken in resData['deadTokens']) {
              if (deadToken is String && deadToken.isNotEmpty) {
                _removeStaleToken(deadToken);
              }
            }
          }
        } catch (_) {}
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
            // Native (Android/iOS) fallback — no webpush block, top-level notification
            body: jsonEncode({
              'message': {
                'token': token,
                'notification': {
                  'title': title,
                  'body': body,
                },
                'data': {
                  'title': title,
                  'body': body,
                  'senderUserId': senderUserId,
                  'messageId': messageId ?? 'unigrid-notification',
                },
                'android': {
                  'priority': 'high',
                  'notification': {
                    'title': title,
                    'body': body,
                    'sound': 'default',
                    'channel_id': 'unigrid_notifications',
                    'tag': messageId ?? 'unigrid-notification',
                    'icon': '@mipmap/ic_launcher',
                  },
                },
                'apns': {
                  'payload': {
                    'aps': {
                      'alert': {
                        'title': title,
                        'body': body,
                      },
                      'sound': 'default',
                    },
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
  // ─── Send to a Specific User (Private DM) ─────────────────────────────────
  static Future<void> sendPrivateNotification({
    required String recipientId,
    required String title,
    required String body,
    required String senderUserId,
    String? messageId,
    Map<String, String>? extraData,
  }) async {
    await NotificationCoordinator.sendPrivate(
      title: title,
      body: body,
      senderUserId: senderUserId,
      recipientId: recipientId,
      messageId: messageId,
      extraData: extraData,
    );
  }

  static Future<void> sendToDeptAndBatch({
    required String department,
    required String batch,
    required String title,
    required String body,
    required String senderUserId,
    bool adminsOnly = false,
    String? messageId,
    Map<String, String>? extraData,
  }) async {
    await NotificationCoordinator.sendBroadcast(
      title: title,
      body: body,
      senderUserId: senderUserId,
      department: department,
      batch: batch,
      adminsOnly: adminsOnly,
      messageId: messageId,
      extraData: extraData,
    );
  }

  // ─── Shortcut Helpers ─────────────────────────────────────────────────────
  // These helpers work on both web and native — they use Firestore + HTTP v1.
  static Future<void> notifyNewMessage({
    required String senderName,
    required String text,
    required String senderUserId,
    required String department,
    required String batch,
    String? messageId,
  }) async {
    final preview =
        text.characters.length > 80 ? '${text.characters.take(80)}...' : text;
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: senderName,
      body: preview,
      senderUserId: senderUserId,
      messageId: messageId,
      extraData: {
        'target': 'group_chat',
        'type': 'group_chat',
        'route': '/chat',
        'tabIndex': '3',
        'preferenceField': 'notifChat',
      },
    );
  }

  static Future<void> notifyNewAnnouncement({
    required String title,
    required String type,
    required String senderUserId,
    required String department,
    required String batch,
    String? messageId,
  }) async {
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: 'New ${type.isNotEmpty ? type : "Announcement"}',
      body: title,
      senderUserId: senderUserId,
      messageId: messageId,
      extraData: {
        'target': 'announcements',
        'type': 'announcement',
        'route': '/home',
        'tabIndex': '0',
        'preferenceField': 'notifAlerts',
      },
    );
  }

  static Future<void> notifyGeneralAnnouncement({
    required String title,
    required String content,
    required String senderUserId,
    String? messageId,
    String department = '',
    String batch = '',
    String target = '',
  }) async {
    String dept = department.trim();
    String bth = batch.trim();

    // Auto-resolve dept or batch if target string was passed instead
    if (dept.isEmpty && bth.isEmpty && target.isNotEmpty) {
      if (target.startsWith('Dept: ')) {
        dept = target.replaceFirst('Dept: ', '').trim();
      } else if (target.startsWith('Batch ')) {
        bth = target.replaceFirst('Batch ', '').trim();
      }
    }

    await sendToDeptAndBatch(
      department: dept,
      batch: bth,
      title: '📢 General Announcement',
      body: title.isNotEmpty ? title : content,
      senderUserId: senderUserId,
      messageId: messageId,
      extraData: {
        'target': 'general_announcement',
        'type': 'general_announcement',
        'route': '/home',
        'tabIndex': '0',
        'preferenceField': 'notifAlerts',
      },
    );
  }

  static Future<void> notifyNewMaterial({
    required String title,
    required String subject,
    required String senderUserId,
    required String department,
    required String batch,
    String? messageId,
  }) async {
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: 'New Material Uploaded',
      body: '$title${subject.isNotEmpty ? ' · $subject' : ''}',
      senderUserId: senderUserId,
      messageId: messageId,
      extraData: {
        'target': 'materials',
        'type': 'material',
        'route': '/materials',
        'tabIndex': '2',
        'preferenceField': 'notifAlerts',
      },
    );
  }

  static Future<void> notifyNewRegistration({
    required String studentName,
    required String studentId,
    required String department,
    required String batch,
    required String senderUserId,
    String? messageId,
  }) async {
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: 'New Registration Request 📝',
      body: '$studentName${studentId.isNotEmpty ? " (ID: $studentId)" : ""} requested registration in $department-Batch $batch. Waiting for CR approval.',
      senderUserId: senderUserId,
      adminsOnly: true,
      messageId: messageId,
      extraData: {
        'target': 'cr_panel',
        'type': 'registration_request',
        'route': '/cr_panel',
        'tabIndex': '4',
        'preferenceField': 'notifAlerts',
      },
    );
  }

  static Future<void> notifyAccountApproved({
    required String recipientUserId,
    required String department,
    required String batch,
    required String senderUserId,
    String? messageId,
  }) async {
    await sendPrivateNotification(
      recipientId: recipientUserId,
      title: 'Account Approved! 🎉',
      body: 'Your UniGrid registration for $department - Batch $batch has been approved by the CR. Welcome aboard!',
      senderUserId: senderUserId,
      messageId: messageId,
      extraData: {
        'target': 'home',
        'type': 'account_approved',
        'route': '/home',
        'tabIndex': '0',
        'preferenceField': 'notifAlerts',
      },
    );
  }
}
