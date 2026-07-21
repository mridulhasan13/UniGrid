import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/dept_scope.dart';
import '../widgets/in_app_notification.dart';
import 'fcm_service.dart';

/// Background service for scheduling and dispatching 10-minute class reminders.
class RoutineReminderService {
  static Timer? _reminderTimer;
  static final Set<String> _notifiedSlotsToday = {};

  static String? _lastSyncedUserId;

  /// Synchronizes class reminder notifications with current user preferences.
  static Future<void> syncRoutineReminders(AppUser? user) async {
    if (user == null || !user.hasDeptScope) {
      _reminderTimer?.cancel();
      _reminderTimer = null;
      _lastSyncedUserId = null;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notif_routine') ?? true;
    if (!enabled) {
      _reminderTimer?.cancel();
      _reminderTimer = null;
      _lastSyncedUserId = null;
      debugPrint('[RoutineReminder] Disabled by user settings.');
      return;
    }

    if (_lastSyncedUserId == user.id &&
        _reminderTimer != null &&
        _reminderTimer!.isActive) {
      return;
    }

    _reminderTimer?.cancel();
    _lastSyncedUserId = user.id;

    // Check for upcoming classes immediately and every 60 seconds
    _checkUpcomingClasses(user);
    _reminderTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkUpcomingClasses(user);
    });
    debugPrint('[RoutineReminder] Timer active for user: ${user.email}');
  }

  static Future<void> _checkUpcomingClasses(AppUser user) async {
    final now = DateTime.now();
    final todayDayName = DateFormat('EEEE').format(now); // e.g. "Monday"

    try {
      final schedulePath =
          deptBatchCol(user.department, user.batch, 'schedule');
      final query = await FirebaseFirestore.instance
          .collection(schedulePath)
          .where('dayOfWeek', isEqualTo: todayDayName)
          .get();

      final todayClasses = query.docs
          .map((doc) =>
              ClassSchedule.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

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
            );

            // 2. In-App Glassmorphic Overlay Banner (if app is open)
            InAppNotification.showGlobal(
              title: titleText,
              message: bodyText,
              icon: Icons.schedule_rounded,
              accentColor: const Color(0xFF3B82F6),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[RoutineReminder] Error checking schedule: $e');
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
  }
}
