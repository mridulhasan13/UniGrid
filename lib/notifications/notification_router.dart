import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';
import '../screens/main_screen.dart';
import '../screens/private_chat_screen.dart';
import 'in_app_notification.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// NotificationRouter
///
/// Handles deep-linking and directs the user to the exact screen or tab
/// when a notification (push, local system tray, or in-app overlay) is tapped.
/// Automatically wipes all notifications from the status bar on tap.
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationRouter {
  NotificationRouter._();

  static Map<String, dynamic>? _pendingPayload;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Wipes all notifications from the Android / iOS notification bar
  static Future<void> clearAllNotifications() async {
    if (kIsWeb) return;
    try {
      await _localNotifications.cancelAll();
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
  /// and opens the exact corresponding section.
  static Future<void> handlePayload(Map<String, dynamic> data) async {
    if (data.isEmpty) return;

    // Immediately wipe notifications from the status bar (like Messenger/WhatsApp)
    clearAllNotifications();
    InAppNotification.dismiss();

    final target = (data['target'] ?? data['type'] ?? data['route'] ?? '').toString().toLowerCase();
    debugPrint('[NotificationRouter] Routing to target: "$target"');

    final navState = globalNavigatorKey.currentState;
    if (navState == null || FirebaseAuth.instance.currentUser == null) {
      debugPrint('[NotificationRouter] App/User session not ready yet — caching payload for deferred navigation.');
      _pendingPayload = data;
      return;
    }

    try {
      // 1. Private Chat / Direct Message
      if (target.contains('private') || target.contains('pm_')) {
        final senderUserId = (data['senderUserId'] ?? data['recipientId'] ?? data['userId'] ?? '').toString();
        if (senderUserId.isNotEmpty) {
          // Pop any open modals/screens to reach base
          navState.popUntil((route) => route.isFirst);

          AppUser? targetUser;
          try {
            final doc = await FirebaseFirestore.instance.collection('users').doc(senderUserId).get();
            if (doc.exists && doc.data() != null) {
              targetUser = AppUser.fromMap(doc.data()!, doc.id);
            }
          } catch (e) {
            debugPrint('[NotificationRouter] Error fetching sender user: $e');
          }

          targetUser ??= AppUser(
            id: senderUserId,
            name: data['senderName'] ?? data['title'] ?? 'Student',
            email: '',
            photoUrl: data['senderPhoto'] ?? '',
            department: '',
            batch: '',
            studentId: '',
            phoneNumber: '',
            isApproved: true,
            isAdmin: false,
            isCR: false,
          );

          navState.push(
            MaterialPageRoute(
              builder: (_) => PrivateChatScreen(recipient: targetUser!),
            ),
          );
          return;
        }
      }

      // 2. Group Chat (Department Room)
      if (target.contains('chat') || target.contains('group')) {
        navState.popUntil((route) => route.isFirst);
        MainScreen.switchTab(3); // Tab 3: Chat
        return;
      }

      // 3. Class Schedule / Timetable / Routine Reminders
      if (target.contains('schedule') || target.contains('routine') || target.contains('reminder')) {
        navState.popUntil((route) => route.isFirst);
        MainScreen.switchTab(1); // Tab 1: Schedule
        return;
      }

      // 4. Study Materials
      if (target.contains('material')) {
        navState.popUntil((route) => route.isFirst);
        MainScreen.switchTab(2); // Tab 2: Materials
        return;
      }

      // 5. CR Panel / Pending Approvals / Registration Requests
      if (target.contains('cr_panel') || target.contains('registration') || target.contains('approval')) {
        navState.popUntil((route) => route.isFirst);
        MainScreen.switchTab(4); // Tab 4: CR Panel
        return;
      }

      // 6. Announcements / Notices / General Campus Broadcasts / Home
      if (target.contains('announcement') || target.contains('notice') || target.contains('home')) {
        navState.popUntil((route) => route.isFirst);
        MainScreen.switchTab(0); // Tab 0: Home
        return;
      }

      // 7. Tab index fallback if explicitly specified
      if (data['tabIndex'] != null) {
        final idx = int.tryParse(data['tabIndex'].toString());
        if (idx != null) {
          navState.popUntil((route) => route.isFirst);
          MainScreen.switchTab(idx);
          return;
        }
      }

      // Default fallback
      navState.popUntil((route) => route.isFirst);
      MainScreen.switchTab(0);
    } catch (e, st) {
      debugPrint('[NotificationRouter] Navigation error: $e\n$st');
    }
  }
}
