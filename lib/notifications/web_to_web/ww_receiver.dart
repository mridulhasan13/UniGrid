import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/constants.dart';
import '../in_app_notification.dart';
import '../notification_router.dart';
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

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final msgId = (message.data['messageId'] as String?) ??
          message.messageId ??
          'ww_${DateTime.now().millisecondsSinceEpoch}';

      // ── Duplicate guard ──────────────────────────────────────────────────
      if (DuplicateGuard.checkAndMark(msgId)) return;

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
            debugPrint('[WWReceiver] Suppressing web chat notification (notif_chat is OFF)');
            return;
          }
        }

        if (prefField == 'notifAlerts' || target.contains('announcement') || target.contains('material') || target.contains('notice')) {
          final notifAlerts = prefs.getBool('notif_alerts') ?? true;
          if (!notifAlerts) {
            debugPrint('[WWReceiver] Suppressing web alerts notification (notif_alerts is OFF)');
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
            debugPrint('[WWReceiver] Suppressing notice: web dept ($userDept) does not match target ($resolvedDept)');
            return;
          }
          if (resolvedBatch.isNotEmpty && userBatch.isNotEmpty && userBatch != resolvedBatch) {
            debugPrint('[WWReceiver] Suppressing notice: web batch ($userBatch) does not match target ($resolvedBatch)');
            return;
          }
        }
      } catch (e) {
        debugPrint('[WWReceiver] Error checking notification preferences: $e');
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

      // ── Resolve Category Group for In-App Banner ─────────────────────────
      final categoryTag = (message.data['categoryTag'] ?? '').toString().toLowerCase();
      final type = (message.data['type'] ?? '').toString().toLowerCase();
      final route = (message.data['route'] ?? '').toString().toLowerCase();
      final target = (message.data['target'] ?? message.data['type'] ?? '').toString().toLowerCase();
      final prefField = (message.data['preferenceField'] ?? '').toString();

      final bool isPrivate = target.contains('private') || type.contains('private') || route.contains('private');
      final bool isChat = isPrivate ||
          target.contains('chat') ||
          type.contains('chat') ||
          categoryTag.contains('chat') ||
          route.contains('chat') ||
          prefField == 'notifChat';

      final bool isRoutine = target.contains('schedule') ||
          target.contains('routine') ||
          target.contains('reminder') ||
          type.contains('schedule') ||
          type.contains('routine') ||
          categoryTag.contains('routine') ||
          route.contains('schedule');

      final bool isMaterial = target.contains('material') ||
          type.contains('material') ||
          categoryTag.contains('material') ||
          route.contains('material');

      final IconData notifIcon = isPrivate
          ? Icons.person_rounded
          : (isChat
              ? Icons.chat_bubble_rounded
              : (isRoutine
                  ? Icons.calendar_today_rounded
                  : (isMaterial ? Icons.folder_rounded : Icons.campaign_rounded)));

      final Color notifAccentColor = isPrivate
          ? Colors.deepPurpleAccent
          : (isChat
              ? AppColors.primary
              : (isRoutine
                  ? Colors.blueAccent
                  : (isMaterial ? AppColors.primary : Colors.amberAccent)));

      // ── Sound (Web Audio API ding-dong) ──────────────────────────────────
      playNotificationSound();

      // ── In-app banner ────────────────────────────────────────────────────
      InAppNotification.showGlobal(
        title: title,
        message: body,
        icon: notifIcon,
        accentColor: notifAccentColor,
        photoUrl: (message.data['authorPhoto'] ?? message.data['photoUrl'] ?? message.data['senderPhoto']) as String?,
        onTap: () {
          NotificationRouter.handlePayload(payloadMap);
        },
      );
    });

    debugPrint('[WWReceiver] ✓ Initialized — listening for foreground web pushes');
  }
}
