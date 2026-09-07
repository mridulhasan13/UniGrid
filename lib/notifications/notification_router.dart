import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';
import '../screens/main_screen.dart';
import '../screens/private_chat_screen.dart';
import 'in_app_notification.dart';
import 'web_to_app/wa_receiver.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NotificationRouter
///
/// Handles deep-linking and directs the user to the exact screen or tab
/// when a notification (push, local system tray, or in-app overlay) is tapped.
/// Instantly routes with zero blocking roundtrips.
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationRouter {
  NotificationRouter._();

  static String? activeChatId;
  static Map<String, dynamic>? _pendingPayload;
  static Timer? _drainTimer;
  static int _drainAttempts = 0;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Wipes all notifications from the Android / iOS notification bar
  static Future<void> clearAllNotifications() async {
    if (kIsWeb) return;
    try {
      WAReceiver.clearHistory();
      _localNotifications.cancelAll().catchError((_) {});
    } catch (_) {}
  }

  /// Handles incoming FCM RemoteMessage when notification was clicked
  static void handleRemoteMessage(RemoteMessage message) {
    debugPrint('[NotificationRouter] Received RemoteMessage data: ${message.data}');
    clearAllNotifications();
    final data = Map<String, dynamic>.from(message.data);
    if (message.notification != null) {
      data['title'] ??= message.notification!.title;
      data['body'] ??= message.notification!.body;
    }
    handlePayload(data);
  }

  /// Start auto-drain polling to ensure pending notification is processed as soon
  /// as navigator and auth session become ready.
  static void _startAutoDrain() {
    _drainTimer?.cancel();
    _drainAttempts = 0;
    _drainTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      _drainAttempts++;
      if (_pendingPayload == null || _drainAttempts > 25) {
        timer.cancel();
        _drainTimer = null;
        return;
      }
      final nav = globalNavigatorKey.currentState;
      final user = FirebaseAuth.instance.currentUser;
      if (nav != null && user != null) {
        timer.cancel();
        _drainTimer = null;
        processPendingNotification();
      }
    });
  }

  /// Process any saved payload after the user is authenticated and MainScreen is mounted
  static void processPendingNotification() {
    if (_pendingPayload != null) {
      final payload = _pendingPayload!;
      _pendingPayload = null;
      debugPrint('[NotificationRouter] Processing pending payload: $payload');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handlePayload(payload);
      });
    }
  }

  /// Central routing handler: inspects target / type / route / sender details
  /// and opens the exact corresponding section instantaneously (0ms delay).
  static Future<void> handlePayload(Map<String, dynamic> data) async {
    if (data.isEmpty) return;

    // Immediately wipe notifications from the status bar
    clearAllNotifications();
    InAppNotification.dismiss();

    final navState = globalNavigatorKey.currentState;
    final currentUser = FirebaseAuth.instance.currentUser;

    if (navState == null || currentUser == null) {
      debugPrint('[NotificationRouter] App/User session not ready yet — caching payload for auto-drain.');
      _pendingPayload = data;
      _startAutoDrain();
      return;
    }

    final categoryTag = (data['categoryTag'] ?? '').toString().toLowerCase();
    final prefField = (data['preferenceField'] ?? '').toString();
    final target = (data['target'] ?? data['type'] ?? data['route'] ?? categoryTag ?? prefField ?? '').toString().toLowerCase();
    debugPrint('[NotificationRouter] Routing instantly to target: "$target" (categoryTag: "$categoryTag", prefField: "$prefField")');

    try {
      // 1. Private Chat / Direct Message
      if (target.contains('private') || target.contains('pm_')) {
        final senderUserId = (data['senderUserId'] ?? data['recipientId'] ?? data['userId'] ?? '').toString();
        if (senderUserId.isNotEmpty) {
          // Clear active notification thread for this specific user
          WAReceiver.clearHistory(senderUserId).catchError((_) {});

          // Pop any open modals/dialogs to reach base
          try {
            navState.popUntil((route) => route.isFirst);
          } catch (_) {}

          // Instant navigation: construct AppUser immediately from payload without waiting for Firestore get()
          final targetUser = AppUser(
            id: senderUserId,
            name: (data['senderName'] ?? data['title'] ?? 'Student').toString(),
            email: (data['senderEmail'] ?? '').toString(),
            photoUrl: (data['senderPhoto'] ?? data['authorPhoto'] ?? '').toString(),
            department: (data['department'] ?? '').toString(),
            batch: (data['batch'] ?? '').toString(),
            studentId: (data['studentId'] ?? '').toString(),
            phoneNumber: '',
            isApproved: true,
            isAdmin: false,
            isCR: false,
          );

          navState.push(
            MaterialPageRoute(
              builder: (_) => PrivateChatScreen(recipient: targetUser),
            ),
          );
          return;
        }
      }

      // 2. Group Chat (Department Room)
      if (target.contains('chat') || target.contains('group') || categoryTag == 'unigrid_chats' || prefField == 'notifChat') {
        WAReceiver.clearHistory('batch_chat').catchError((_) {});
        try {
          navState.popUntil((route) => route.isFirst);
        } catch (_) {}
        MainScreen.switchTab(3); // Tab 3: Chat
        return;
      }

      // 3. Class Schedule / Timetable / Routine Reminders
      if (target.contains('schedule') || target.contains('routine') || target.contains('reminder') || categoryTag == 'unigrid_routine') {
        try {
          navState.popUntil((route) => route.isFirst);
        } catch (_) {}
        MainScreen.switchTab(1); // Tab 1: Schedule
        return;
      }

      // 4. Study Materials
      if (target.contains('material')) {
        try {
          navState.popUntil((route) => route.isFirst);
        } catch (_) {}
        MainScreen.switchTab(2); // Tab 2: Materials
        return;
      }

      // 5. CR Panel / Pending Approvals / Registration Requests
      if (target.contains('cr_panel') || target.contains('registration') || target.contains('approval')) {
        try {
          navState.popUntil((route) => route.isFirst);
        } catch (_) {}
        MainScreen.switchTab(4); // Tab 4: CR Panel
        return;
      }

      // 6. Announcements / Notices / General Campus Broadcasts / Home
      if (target.contains('announcement') || target.contains('notice') || target.contains('home') || categoryTag == 'unigrid_alerts' || prefField == 'notifAlerts') {
        try {
          navState.popUntil((route) => route.isFirst);
        } catch (_) {}
        MainScreen.switchTab(0); // Tab 0: Home
        return;
      }

      // 7. Tab index fallback if explicitly specified
      if (data['tabIndex'] != null) {
        final idx = int.tryParse(data['tabIndex'].toString());
        if (idx != null) {
          try {
            navState.popUntil((route) => route.isFirst);
          } catch (_) {}
          MainScreen.switchTab(idx);
          return;
        }
      }

      // Default fallback
      try {
        navState.popUntil((route) => route.isFirst);
      } catch (_) {}
      MainScreen.switchTab(0);
    } catch (e, st) {
      debugPrint('[NotificationRouter] Navigation error: $e\n$st');
    }
  }
}

