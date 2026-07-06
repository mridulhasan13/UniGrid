import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'onesignal_service.dart';

// ─── Top-level background handler (runs even when app is KILLED) ─────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase AUTOMATICALLY displays the notification when the payload contains a 'notification' block
  // (which our HTTP v1 push does).
  // If we show a local notification here, the user gets double notifications!
  debugPrint('Handling a background message: ${message.messageId}');
}

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Initialize ───────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    if (kIsWeb) return;

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

    // Save FCM Token immediately if user is already logged in (handles permission grant delay)
    final currentUser = fb_auth.FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await saveTokenForUser(currentUser.uid);
    }

    // Subscribe to global topic for serverless automated broadcasts
    try {
      await _messaging.subscribeToTopic('all_users');
      debugPrint('✅ Subscribed to global all_users topic');
    } catch (e) {
      debugPrint('⚠️ Topic subscription failed: $e');
    }

    // Request battery optimization exclusion (keeps Firestore streams alive
    // when phone is locked — same as WhatsApp/Telegram do)
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
        debugPrint('✅ Battery optimization exclusion requested');
      } else {
        debugPrint('✅ Already excluded from battery optimization');
      }
    } catch (e) {
      debugPrint('⚠️ Battery optimization request failed: $e');
    }
  }

  // ─── Show local notification from FCM remote message ─────────────────────
  static Future<void> _showNotificationFromRemote(RemoteMessage message) async {
    final senderUserId = message.data['senderUserId'];
    final currentUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;

    if (senderUserId != null && senderUserId == currentUid) {
      return;
    }

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ??
          message.data['title'] ??
          'UniGrid Notification',
      message.notification?.body ?? message.data['body'] ?? '',
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
  }

  // ─── Save FCM Token to Firestore ──────────────────────────────────────────
  static Future<void> saveTokenForUser(String userId) async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('⚠️ FCM token is null for user: $userId (perhaps permission not granted yet)');
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

  // ─── Send Private Notification to a Specific User ─────────────────────────
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
      if (!recipientDoc.exists) {
        debugPrint('Recipient user document not found: $recipientId');
        return;
      }

      final token = recipientDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) {
        debugPrint('No FCM token found for recipient: $recipientId');
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

  // ─── Direct FCM Push via Googleapis ───────────────────────────────────────
  static Future<String> _getAccessToken() async {
    final jsonString =
        await rootBundle.loadString('assets/service_account.json');
    final accountCredentials =
        auth.ServiceAccountCredentials.fromJson(jsonString);
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final client =
        await auth.clientViaServiceAccount(accountCredentials, scopes);
    final accessToken = client.credentials.accessToken.data;
    client.close();
    return accessToken;
  }

  static Future<void> _sendFCMHttp({
    required List<String> tokens,
    required String title,
    required String body,
    required String senderUserId,
  }) async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      final projectId = jsonMap['project_id'];

      final accessToken = await _getAccessToken();
      final endpoint =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      for (final token in tokens) {
        final response = await http.post(
          Uri.parse(endpoint),
          headers: <String, String>{
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
          debugPrint('✅ Sent direct FCM to $token');
        } else {
          debugPrint('❌ Failed direct FCM to $token: ${response.body}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error sending direct FCM: $e');
    }
  }

  // ─── Send to Specific Dept & Batch Users ──────────────────────────────────
  static Future<void> sendToDeptAndBatch({
    required String department,
    required String batch,
    required String title,
    required String body,
    required String senderUserId,
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
          .map((doc) => doc.data()['fcmToken'] as String?)
          .whereType<String>()
          .where((t) => t.isNotEmpty && t != currentToken)
          .toList();

      if (tokens.isEmpty) {
        debugPrint('No tokens to notify for dept $department, batch $batch');
        return;
      }

      await _sendFCMHttp(
        tokens: tokens,
        title: title,
        body: body,
        senderUserId: senderUserId,
      );
      debugPrint(
          '✅ Notification requests sent directly to FCM for ${tokens.length} users in $department - $batch');
    } catch (e) {
      debugPrint('❌ sendToDeptAndBatch error: $e');
    }
  }

  // ─── Shortcut helpers ─────────────────────────────────────────────────────
  static Future<void> notifyNewMessage({
    required String senderName,
    required String text,
    required String senderUserId,
    required String department,
    required String batch,
  }) async {
    if (kIsWeb) {
      await OneSignalService.notifyNewMessage(
        senderName: senderName,
        text: text,
        department: department,
        batch: batch,
      );
      return;
    }
    final preview = text.length > 80 ? '${text.substring(0, 80)}...' : text;
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: '💬 $senderName',
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
    if (kIsWeb) {
      await OneSignalService.notifyNewAnnouncement(
        title: title,
        type: type,
        department: department,
        batch: batch,
      );
      return;
    }
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: '📢 New ${type.isNotEmpty ? type : "Announcement"}',
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
    if (kIsWeb) {
      await OneSignalService.notifyNewMaterial(
        title: title,
        subject: subject,
        department: department,
        batch: batch,
      );
      return;
    }
    await sendToDeptAndBatch(
      department: department,
      batch: batch,
      title: '📚 New Material Uploaded',
      body: '$title${subject.isNotEmpty ? ' · $subject' : ''}',
      senderUserId: senderUserId,
    );
  }
}
