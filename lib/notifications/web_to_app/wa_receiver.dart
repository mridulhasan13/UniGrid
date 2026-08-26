import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../in_app_notification.dart';
import '../shared/duplicate_guard.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// WAReceiver  —  Web → App  (receiver side, runs on Android / iOS)
///
/// Handles FCM messages when the native app is in the FOREGROUND:
///   1. Guards against duplicates via DuplicateGuard
///   2. Shows a system-tray local notification WITH sound (default channel)
///   3. Shows the glassmorphic in-app banner on top
///
/// When the app is in BACKGROUND / TERMINATED, FCM automatically shows a
/// system-tray notification from the `notification` block in the payload
/// (sound included). No manual handling is needed for that case.
/// ─────────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../notification_router.dart';

class WAReceiver {
  WAReceiver._();

  static bool _initialized = false;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    // Initialise local notifications plugin (safe to call multiple times —
    // flutter_local_notifications is idempotent on re-init).
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            NotificationRouter.handlePayload(data);
          } catch (e) {
            debugPrint('[WAReceiver] Error parsing local notification payload: $e');
          }
        }
      },
    );

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final msgId = (message.data['messageId'] as String?) ??
          message.messageId ??
          'wa_${DateTime.now().millisecondsSinceEpoch}';

      // ── Duplicate guard ──────────────────────────────────────────────────
      if (DuplicateGuard.checkAndMark('native_$msgId')) return;

      // ── Self-notification guard ──────────────────────────────────────────
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final senderUid = (message.data['senderUserId'] as String?) ?? '';
      if (senderUid.isNotEmpty && senderUid == currentUid) return;

      // ── User notification preference check (Settings toggle) ─────────────
      try {
        final prefs = await SharedPreferences.getInstance();
        final prefField = (message.data['preferenceField'] as String?) ?? '';
        final target = (message.data['target'] ?? message.data['type'] ?? '').toString().toLowerCase();

        if (prefField == 'notifChat' || target.contains('chat') || target.contains('private')) {
          final notifChat = prefs.getBool('notif_chat') ?? true;
          if (!notifChat) {
            debugPrint('[WAReceiver] Suppressing foreground chat notification (notif_chat is OFF)');
            return;
          }
        }

        if (prefField == 'notifAlerts' || target.contains('announcement') || target.contains('material') || target.contains('notice')) {
          final notifAlerts = prefs.getBool('notif_alerts') ?? true;
          if (!notifAlerts) {
            debugPrint('[WAReceiver] Suppressing foreground alerts notification (notif_alerts is OFF)');
            return;
          }
        }

        // ── Target audience scope guard (safety net for targeted notices) ────
        final targetDept = (message.data['targetDept'] ?? message.data['department'] ?? '').toString().trim().toUpperCase();
        final targetBatch = (message.data['targetBatch'] ?? message.data['batch'] ?? '').toString().replaceAll('Batch', '').trim();
        final targetStr = (message.data['target'] ?? '').toString().trim();

        String resolvedDept = targetDept;
        String resolvedBatch = targetBatch;
        if (resolvedDept.isEmpty && resolvedBatch.isEmpty && targetStr.isNotEmpty) {
          if (targetStr.startsWith('Dept: ')) {
            resolvedDept = targetStr.replaceFirst('Dept: ', '').trim().toUpperCase();
          } else if (targetStr.startsWith('Batch ')) {
            resolvedBatch = targetStr.replaceFirst('Batch ', '').trim();
          }
        }

        if (resolvedDept.isNotEmpty || resolvedBatch.isNotEmpty) {
          final userDept = (prefs.getString('auth_session_department') ?? '').trim().toUpperCase();
          final userBatch = (prefs.getString('auth_session_batch') ?? '').trim();

          if (resolvedDept.isNotEmpty && userDept.isNotEmpty && userDept != resolvedDept) {
            debugPrint('[WAReceiver] Suppressing notice: device dept ($userDept) does not match target ($resolvedDept)');
            return;
          }
          if (resolvedBatch.isNotEmpty && userBatch.isNotEmpty && userBatch != resolvedBatch) {
            debugPrint('[WAReceiver] Suppressing notice: device batch ($userBatch) does not match target ($resolvedBatch)');
            return;
          }
        }
      } catch (e) {
        debugPrint('[WAReceiver] Error checking notification preferences: $e');
      }

      final title = message.notification?.title ??
          (message.data['title'] as String?) ??
          'UniGrid';
      final body = message.notification?.body ??
          (message.data['body'] as String?) ??
          '';
      if (title.isEmpty && body.isEmpty) return;

      final payloadMap = Map<String, dynamic>.from(message.data);
      payloadMap['title'] ??= title;
      payloadMap['body'] ??= body;

      // ── Resolve Category Group & Tag for Stacking (like WhatsApp/Messenger) ─
      final bool isChat = target.contains('chat') ||
          target.contains('private') ||
          prefField == 'notifChat';
      final bool isRoutine = target.contains('schedule') ||
          target.contains('routine') ||
          target.contains('reminder');

      final String groupKey = isChat
          ? 'com.unigrid.CHATS'
          : (isRoutine ? 'com.unigrid.ROUTINE' : 'com.unigrid.ALERTS');
      final String categoryTag = isChat
          ? 'unigrid_chats'
          : (isRoutine ? 'unigrid_routine' : 'unigrid_alerts');
      final int notifId = isChat
          ? 1001
          : (isRoutine ? 3001 : 2001);

      // ── System tray notification (stacked by category with sound) ────────
      await _local.show(
        notifId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'unigrid_notifications', // same channel as FCMService
            'UniGrid Notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true, // ← default device sound
            enableVibration: true,
            tag: categoryTag, // Stacks notifications into single category box
            groupKey: groupKey,
            autoCancel: true,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: isChat
                  ? 'UniGrid Chat'
                  : (isRoutine ? 'UniGrid Routine' : 'UniGrid Notice'),
            ),
          ),
        ),
        payload: jsonEncode(payloadMap),
      );

      // ── In-app banner (cleanly replaces any active banner) ───────────────
      InAppNotification.showGlobal(
        title: title,
        message: body,
        icon: Icons.notifications_active_rounded,
        onTap: () {
          NotificationRouter.handlePayload(payloadMap);
        },
      );
    });

    debugPrint('[WAReceiver] ✓ Initialized — listening for foreground native pushes');
  }
}
