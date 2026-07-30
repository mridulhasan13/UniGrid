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
    );

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final msgId = message.messageId ??
          (message.data['messageId'] as String?) ??
          'wa_${DateTime.now().millisecondsSinceEpoch}';

      // ── Duplicate guard ──────────────────────────────────────────────────
      if (DuplicateGuard.checkAndMark('native_$msgId')) return;

      // ── Self-notification guard ──────────────────────────────────────────
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final senderUid = (message.data['senderUserId'] as String?) ?? '';
      if (senderUid.isNotEmpty && senderUid == currentUid) return;

      final title = message.notification?.title ??
          (message.data['title'] as String?) ??
          'UniGrid';
      final body = message.notification?.body ??
          (message.data['body'] as String?) ??
          '';
      if (title.isEmpty && body.isEmpty) return;

      // ── System tray notification (with sound) ────────────────────────────
      await _local.show(
        msgId.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'unigrid_notifications',       // same channel as FCMService
            'UniGrid Notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,               // ← default device sound
            enableVibration: true,
            tag: msgId,                    // prevents OS-level duplicate
          ),
        ),
      );

      // ── In-app banner ────────────────────────────────────────────────────
      InAppNotification.showGlobal(
        title: title,
        message: body,
        icon: Icons.notifications_active_rounded,
      );
    });

    debugPrint('[WAReceiver] ✓ Initialized — listening for foreground native pushes');
  }
}
