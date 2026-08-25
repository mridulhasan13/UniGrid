import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/dept_scope.dart';
import 'in_app_notification.dart';
import 'fcm_service.dart';
import 'notification_router.dart';

/// Background service for scheduling and dispatching 10-minute class reminders.
/// Uses in-memory caching and real-time subscription to avoid continuous Firestore polling.
class RoutineReminderService {
  static Timer? _reminderTimer;
  static StreamSubscription<QuerySnapshot>? _scheduleSubscription;
  static final Set<String> _notifiedSlotsToday = {};

  static String? _lastSyncedUserId;
  static List<ClassSchedule> _cachedSchedule = [];

  /// Synchronizes class reminder notifications with current user preferences.
  /// No-op on web — timers and local notifications are not supported on the web platform.
  static Future<void> syncRoutineReminders(AppUser? user) async {
    if (kIsWeb) return;
    if (user == null || !user.hasDeptScope) {
      stop();
      _lastSyncedUserId = null;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notif_routine') ?? true;
    if (!enabled) {
      stop();
      _lastSyncedUserId = null;
      debugPrint('[RoutineReminder] Disabled by user settings.');
      return;
    }

    if (_lastSyncedUserId == user.id &&
        _reminderTimer != null &&
        _reminderTimer!.isActive) {
      return;
    }

    stop();
    _lastSyncedUserId = user.id;

    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');

    // Subscribe to schedule updates in real-time (reads once upon connection & on real schedule changes)
    _scheduleSubscription = FirebaseFirestore.instance
        .collection(schedulePath)
        .snapshots()
        .listen(
      (snapshot) {
        _cachedSchedule = snapshot.docs
            .map((doc) => ClassSchedule.fromMap(doc.data(), doc.id))
            .toList();
        // Check immediately when schedule loads or updates
        _checkUpcomingClassesFromCache();
      },
      onError: (e) {
        debugPrint('[RoutineReminder] Schedule stream error: $e');
      },
    );

    // Periodic timer checks local memory ONLY — zero Firestore reads per minute
    _reminderTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkUpcomingClassesFromCache();
    });
    debugPrint('[RoutineReminder] In-memory reminder timer active for user: ${user.email}');
  }

  static void _checkUpcomingClassesFromCache() {
    if (_cachedSchedule.isEmpty) return;

    final now = DateTime.now();
    final todayDayName = DateFormat('EEEE').format(now); // e.g. "Monday"

    final todayClasses = _cachedSchedule.where(
      (cls) => cls.dayOfWeek.toLowerCase() == todayDayName.toLowerCase(),
    );

    for (final cls in todayClasses) {
      if (cls.status == 'cancelled') continue;

      final startTime = _getStartTimeForClass(cls, now);
      if (startTime == null) continue;

      final difference = startTime.difference(now);
      final classKey =
          '${cls.id}_${now.year}_${now.month}_${now.day}_${cls.startSlot}';

      // Check if class starts within 10 minutes (between 0 and 10 minutes)
      if (difference.inSeconds > 0 && difference.inSeconds <= 600) {
        if (!_notifiedSlotsToday.contains(classKey)) {
          _notifiedSlotsToday.add(classKey);
          final minutesLeft = (difference.inSeconds / 60).ceil();
          final titleText = 'Class Reminder: ${cls.subject}';
          final bodyText =
              'Starts in $minutesLeft mins at ${cls.room}${cls.teacher.isNotEmpty ? " · ${cls.teacher}" : ""}';

          // 1. Direct System Notification to Phone (Tray / Lock Screen / Sound / Vibration)
          FCMService.showLocalSystemNotification(
            title: titleText,
            body: bodyText,
            data: {
              'target': 'schedule',
              'type': 'routine_reminder',
              'route': '/schedule',
              'tabIndex': '1',
            },
          );

          // 2. In-App Glassmorphic Overlay Banner (if app is open)
          try {
            InAppNotification.showGlobal(
              title: titleText,
              message: bodyText,
              icon: Icons.schedule_rounded,
              accentColor: const Color(0xFF3B82F6),
              onTap: () {
                NotificationRouter.handlePayload({
                  'target': 'schedule',
                  'type': 'routine_reminder',
                  'route': '/schedule',
                  'tabIndex': '1',
                });
              },
            );
          } catch (e) {
            debugPrint('[RoutineReminder] Could not show in-app banner: $e');
          }
        }
      }
    }
  }

  static DateTime? _getStartTimeForClass(ClassSchedule cls, DateTime date) {
    final slotTimes = {
      1: const TimeOfDay(hour: 8, minute: 0),
      2: const TimeOfDay(hour: 8, minute: 50),
      3: const TimeOfDay(hour: 9, minute: 50),
      4: const TimeOfDay(hour: 10, minute: 40),
      5: const TimeOfDay(hour: 11, minute: 30),
      6: const TimeOfDay(hour: 12, minute: 20),
      7: const TimeOfDay(hour: 13, minute: 50),
      8: const TimeOfDay(hour: 14, minute: 40),
      9: const TimeOfDay(hour: 15, minute: 30),
      10: const TimeOfDay(hour: 16, minute: 20),
    };

    final tod = slotTimes[cls.startSlot];
    if (tod == null) return null;

    return DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
  }

  static void stop() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
    _scheduleSubscription?.cancel();
    _scheduleSubscription = null;
  }
}
