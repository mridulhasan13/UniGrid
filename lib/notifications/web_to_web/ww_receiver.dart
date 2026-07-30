import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart' show Icons;
import '../in_app_notification.dart';
import '../shared/duplicate_guard.dart';
import '../shared/sound_helper.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// WWReceiver  —  Web → Web  (receiver side, runs in the browser)
///
/// Listens to FirebaseMessaging.onMessage for foreground web pushes and:
///   1. Guards against duplicates via DuplicateGuard
///   2. Plays a synthesised ding-dong via Web Audio API
///   3. Shows the glassmorphic in-app banner
///
/// Background (app not focused): handled entirely by the Service Worker
///   (firebase-messaging-sw.js → onBackgroundMessage → showNotification).
///   The OS plays the system notification sound automatically in that case.
/// ─────────────────────────────────────────────────────────────────────────────
class WWReceiver {
  WWReceiver._();

  static bool _initialized = false;

  static void init() {
    if (!kIsWeb || _initialized) return;
    _initialized = true;

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final msgId = message.messageId ??
          (message.data['messageId'] as String?) ??
          'ww_${DateTime.now().millisecondsSinceEpoch}';

      // ── Duplicate guard ──────────────────────────────────────────────────
      if (DuplicateGuard.checkAndMark('ww_$msgId')) return;

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

      // ── Sound (Web Audio API ding-dong) ──────────────────────────────────
      playNotificationSound();

      // ── In-app banner ────────────────────────────────────────────────────
      InAppNotification.showGlobal(
        title: title,
        message: body,
        icon: Icons.notifications_active_rounded,
      );
    });

    debugPrint('[WWReceiver] ✓ Initialized — listening for foreground web pushes');
  }
}
