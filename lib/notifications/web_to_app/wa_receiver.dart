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
import '../shared/notif_thread_store.dart';

class WAReceiver {
  WAReceiver._();

  static bool _initialized = false;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static final List<String> _recentAlertLines = [];

  /// Clears recent lines buffer when user opens chats / clears notifications
  static Future<void> clearHistory([String? specificThreadKey]) async {
    if (specificThreadKey != null && specificThreadKey.isNotEmpty) {
      await NotifThreadStore.clearThread(specificThreadKey);
      try {
        if (specificThreadKey == 'batch_chat' || specificThreadKey == 'chat') {
          await _local.cancel(1001, tag: 'unigrid_batch_chat');
        } else if (specificThreadKey == 'unigrid_routine' || specificThreadKey == 'routine') {
          await _local.cancel(3000, tag: 'unigrid_routine');
        } else if (specificThreadKey == 'unigrid_materials' || specificThreadKey == 'materials') {
          await _local.cancel(4000, tag: 'unigrid_materials');
        } else if (specificThreadKey == 'unigrid_alerts' || specificThreadKey == 'alerts') {
          await _local.cancel(2000, tag: 'unigrid_alerts');
        } else {
          final dmId = 10000 + (specificThreadKey.hashCode.abs() % 90000);
          await _local.cancel(dmId, tag: 'unigrid_dm_$specificThreadKey');
        }
      } catch (_) {}
    } else {
      _recentAlertLines.clear();
      await NotifThreadStore.clearAll();
      try {
        await _local.cancelAll();
      } catch (_) {}
    }
  }

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

      final prefField = (message.data['preferenceField'] as String?) ?? '';
      final target = (message.data['target'] ?? message.data['type'] ?? '').toString().toLowerCase();

      // ── User notification preference check (Settings toggle) ─────────────
      try {
        final prefs = await SharedPreferences.getInstance();

        if (prefField == 'notifChat' || target.contains('chat') || target.contains('private')) {
          final notifChat = prefs.getBool('notif_chat') ?? true;
          if (!notifChat) {
            debugPrint('[WAReceiver] Suppressing foreground chat notification (notif_chat is OFF)');
            return;
          }
        }

        if (prefField == 'notifRoutine' || target.contains('schedule') || target.contains('routine') || target.contains('reminder')) {
          final notifRoutine = prefs.getBool('notif_routine') ?? true;
          if (!notifRoutine) {
            debugPrint('[WAReceiver] Suppressing foreground routine notification (notif_routine is OFF)');
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

      // ── Resolve Category Group for Bundling (Messenger/WhatsApp Style) ────
      final categoryTag = (message.data['categoryTag'] ?? '').toString().toLowerCase();
      final type = (message.data['type'] ?? '').toString().toLowerCase();
      final route = (message.data['route'] ?? '').toString().toLowerCase();

      final bool isChat = target.contains('chat') ||
          target.contains('private') ||
          type.contains('chat') ||
          type.contains('private') ||
          categoryTag.contains('chat') ||
          route.contains('chat') ||
          route.contains('private') ||
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

      if (isChat) {
        // Suppress notification if user is actively in this chat screen right now
        final currentActive = NotificationRouter.activeChatId;
        if (currentActive != null) {
          final bool isPrivateCheck = target.contains('private') || type.contains('private') || route.contains('private');
          final senderUserId = (message.data['senderUserId'] ?? message.data['userId'] ?? message.data['authorId'] ?? '').toString();
          if (isPrivateCheck && (senderUid == currentActive || senderUserId == currentActive)) {
            debugPrint('[WAReceiver] Suppressing notification — active private chat is open');
            return;
          }
          if (!isPrivateCheck && currentActive == 'group_chat') {
            debugPrint('[WAReceiver] Suppressing notification — active group chat is open');
            return;
          }
        }

        // Resolve conversation thread key (group chat vs 1-on-1 private chat)
        final bool isPrivate = target.contains('private') || type.contains('private') || route.contains('private');
        final String threadKey = isPrivate
            ? (senderUid.isNotEmpty ? senderUid : 'dm_chat')
            : ((message.data['chatId'] as String?) ?? 'batch_chat');
        final String conversationTitle = isPrivate
            ? (title.isNotEmpty ? title : 'Student')
            : ((message.data['groupTitle'] as String?) ?? 'Department Chat');
        final String lineText = isPrivate
            ? body
            : (title.isNotEmpty ? '$title: $body' : body);
        final String androidTag = isPrivate
            ? 'unigrid_dm_$threadKey'
            : 'unigrid_batch_chat';
        final int conversationNotifId = isPrivate ? (10000 + (threadKey.hashCode.abs() % 90000)) : 1001;

        // Sync with active status bar notifications: if user dismissed/swiped previous notification, start fresh
        await NotifThreadStore.syncWithActiveNotifications(
          localNotif: _local,
          threadKey: threadKey,
          notifId: conversationNotifId,
          tag: androidTag,
        );

        // 1. Stack message lines under this sender/chat in persistent store (WhatsApp Style)
        final stackedLines = await NotifThreadStore.addMessage(
          threadKey: threadKey,
          senderName: conversationTitle,
          messageText: lineText,
        );

        final finalChatTitle = stackedLines.length > 1
            ? '$conversationTitle (${stackedLines.length} messages)'
            : conversationTitle;

        // 2. Post / Update conversation notification for THIS specific person/chat
        await _local.show(
          conversationNotifId,
          finalChatTitle,
          stackedLines.last,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'unigrid_notifications',
              'UniGrid Notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              tag: androidTag,
              groupKey: 'com.unigrid.CHATS',
              autoCancel: true,
              styleInformation: InboxStyleInformation(
                stackedLines,
                contentTitle: finalChatTitle,
                summaryText: '${stackedLines.length} message${stackedLines.length > 1 ? "s" : ""}',
              ),
            ),
          ),
          payload: jsonEncode(payloadMap),
        );
      } else if (isRoutine) {
        final line = title.isNotEmpty ? '$title: $body' : body;
        await NotifThreadStore.syncWithActiveNotifications(
          localNotif: _local,
          threadKey: 'unigrid_routine',
          notifId: 3000,
          tag: 'unigrid_routine',
        );
        final stackedLines = await NotifThreadStore.addMessage(
          threadKey: 'unigrid_routine',
          senderName: '📅 Routine Reminders',
          messageText: line,
        );
        final finalTitle = stackedLines.length > 1
            ? '📅 Routine (${stackedLines.length} updates)'
            : (title.isNotEmpty ? title : '📅 Routine');

        await _local.show(
          3000,
          finalTitle,
          stackedLines.last,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'unigrid_notifications',
              'UniGrid Notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              tag: 'unigrid_routine',
              groupKey: 'com.unigrid.ROUTINE',
              autoCancel: true,
              styleInformation: InboxStyleInformation(
                stackedLines,
                contentTitle: finalTitle,
                summaryText: '${stackedLines.length} reminder${stackedLines.length > 1 ? "s" : ""}',
              ),
            ),
          ),
          payload: jsonEncode(payloadMap),
        );
      } else if (isMaterial) {
        final line = title.isNotEmpty && title != 'UniGrid' ? '$title: $body' : body;
        await NotifThreadStore.syncWithActiveNotifications(
          localNotif: _local,
          threadKey: 'unigrid_materials',
          notifId: 4000,
          tag: 'unigrid_materials',
        );
        final stackedLines = await NotifThreadStore.addMessage(
          threadKey: 'unigrid_materials',
          senderName: '📁 Study Materials',
          messageText: line,
        );
        final finalTitle = stackedLines.length > 1
            ? '📁 Study Materials (${stackedLines.length} files)'
            : (title.isNotEmpty ? title : '📁 Study Materials');

        await _local.show(
          4000,
          finalTitle,
          stackedLines.last,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'unigrid_notifications',
              'UniGrid Notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              tag: 'unigrid_materials',
              groupKey: 'com.unigrid.MATERIALS',
              autoCancel: true,
              styleInformation: InboxStyleInformation(
                stackedLines,
                contentTitle: finalTitle,
                summaryText: '${stackedLines.length} file${stackedLines.length > 1 ? "s" : ""}',
              ),
            ),
          ),
          payload: jsonEncode(payloadMap),
        );
      } else {
        // Notices / Announcements / General Notices -> ONE single stacked partition
        final line = title.isNotEmpty && title != 'UniGrid' ? '$title: $body' : body;
        await NotifThreadStore.syncWithActiveNotifications(
          localNotif: _local,
          threadKey: 'unigrid_alerts',
          notifId: 2000,
          tag: 'unigrid_alerts',
        );
        final stackedLines = await NotifThreadStore.addMessage(
          threadKey: 'unigrid_alerts',
          senderName: '📢 Announcements',
          messageText: line,
        );
        final finalTitle = stackedLines.length > 1
            ? '📢 Announcements (${stackedLines.length} updates)'
            : (title.isNotEmpty ? title : '📢 Announcements');

        await _local.show(
          2000,
          finalTitle,
          stackedLines.last,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'unigrid_notifications',
              'UniGrid Notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              tag: 'unigrid_alerts',
              groupKey: 'com.unigrid.ALERTS',
              autoCancel: true,
              styleInformation: InboxStyleInformation(
                stackedLines,
                contentTitle: finalTitle,
                summaryText: '${stackedLines.length} update${stackedLines.length > 1 ? "s" : ""}',
              ),
            ),
          ),
          payload: jsonEncode(payloadMap),
        );
      }

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

