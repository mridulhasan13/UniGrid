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

/// Top-level background message handler — must be a top-level function.
/// Called by Firebase when a notification arrives while the app is terminated or in background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Nothing to do here — Android shows the notification automatically from the FCM payload.
  debugPrint('📬 Background FCM message received: ${message.messageId}');
}

class FCMService {
  static bool _initialized = false;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // ─── Initialize FCM ───────────────────────────────────────────────────────
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;
    _initialized = true;

    // Register token refresh listener immediately
    _messaging.onTokenRefresh.listen((newToken) async {
      final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await _firestore.collection('users').doc(currentUser.uid).set(
            {'fcmToken': newToken, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
          debugPrint('🔄 FCM token refreshed and saved for user: ${currentUser.uid}');
        } catch (e) {
          debugPrint('❌ FCM token refresh save error: $e');
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
      debugPrint('✅ Subscribed to global all_users topic');
    } catch (e) {
      debugPrint('⚠️ Topic subscription failed: $e');
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
      debugPrint('⚠️ Battery optimization exclusion failed: $e');
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
  }

  // ─── Save FCM Token to Firestore ──────────────────────────────────────────
  static Future<void> saveTokenForUser(String userId) async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('⚠️ FCM token is null for user: $userId');
        return;
      }
      await _firestore.collection('users').doc(userId).set(
        {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      debugPrint('✅ FCM token saved for user: $userId');
    } catch (e) {
      debugPrint('❌ FCM token save error: $e');
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

  // ─── Send FCM HTTP v1 to a list of tokens ────────────────────────────────
  static Future<void> _sendFCMHttp({
    required List<String> tokens,
    required String title,
    required String body,
    required String senderUserId,
  }) async {
    try {
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      final projectId = jsonMap['project_id'] as String;
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
            },
          }),
        );
        if (response.statusCode == 200) {
          debugPrint('✅ FCM sent to token');
        } else if (response.statusCode == 404) {
          // Token is stale (user reinstalled app or cleared data) — clean it up
          debugPrint('🗑️ Stale FCM token detected, removing from Firestore...');
          try {
            final staleQuery = await _firestore
                .collection('users')
                .where('fcmToken', isEqualTo: token)
                .limit(1)
                .get();
            for (final doc in staleQuery.docs) {
              await doc.reference.update({
                'fcmToken': FieldValue.delete(),
                'fcmUpdatedAt': FieldValue.delete(),
              });
              debugPrint('🗑️ Removed stale token for user: ${doc.id}');
            }
          } catch (e) {
            debugPrint('⚠️ Could not clean stale token: $e');
          }
        } else {
          debugPrint('❌ FCM failed: ${response.statusCode} ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending FCM: $e');
    }
  }

  // ─── Send to a Specific User (Private DM) ─────────────────────────────────
  static Future<void> sendPrivateNotification({
    required String recipientId,
    required String title,
    required String body,
    required String senderUserId,
  }) async {
    if (kIsWeb) return;
    try {
      final recipientDoc =
          await _firestore.collection('users').doc(recipientId).get();
      if (!recipientDoc.exists) return;
      final token = recipientDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) {
        debugPrint('No FCM token for recipient: $recipientId');
        return;
      }
      await _sendFCMHttp(
        tokens: [token],
        title: title,
        body: body,
        senderUserId: senderUserId,
      );
    } catch (e) {
      debugPrint('❌ sendPrivateNotification error: $e');
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
    if (kIsWeb) return;
    try {
      final currentToken = await _messaging.getToken();
      final usersSnap = await _firestore
          .collection('users')
          .where('department', isEqualTo: department)
          .where('batch', isEqualTo: batch)
          .get();

      final tokens = usersSnap.docs
          .where((doc) => doc.id != senderUserId)
          .where((doc) {
            if (!adminsOnly) return true;
            final data = doc.data();
            final isCR = data['isCR'] == true;
            final isAdmin = data['isAdmin'] == true;
            return isCR || isAdmin;
          })
          .map((doc) => doc.data()['fcmToken'] as String?)
          .whereType<String>()
          .where((t) => t.isNotEmpty && t != currentToken)
          .toSet()
          .toList();

      if (tokens.isEmpty) {
        debugPrint('No tokens to notify for $department - $batch');
        return;
      }

      await _sendFCMHttp(
        tokens: tokens,
        title: title,
        body: body,
        senderUserId: senderUserId,
      );
      debugPrint('✅ Notified ${tokens.length} users in $department - $batch');
    } catch (e) {
      debugPrint('❌ sendToDeptAndBatch error: $e');
    }
  }

  // ─── Shortcut Helpers ─────────────────────────────────────────────────────
  static Future<void> notifyNewMessage({
    required String senderName,
    required String text,
    required String senderUserId,
    required String department,
    required String batch,
  }) async {
    if (kIsWeb) return;
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
    if (kIsWeb) return;
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
    if (kIsWeb) return;
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: 'New Material Uploaded',
      body: '$title${subject.isNotEmpty ? ' · $subject' : ''}',
      senderUserId: senderUserId,
    );
  }
}
