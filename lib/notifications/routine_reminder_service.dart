import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/schedule_service.dart';
import 'in_app_notification.dart';
import 'fcm_service.dart';
import 'notification_router.dart';

import 'shared/sound_helper.dart';

/// Background service for scheduling and dispatching 10-minute class reminders.
/// Uses in-memory caching from shared ScheduleService to avoid duplicate Firestore queries.
class RoutineReminderService {
  static Timer? _reminderTimer;
  static final Set<String> _notifiedSlotsToday = {};

  static String? _lastSyncedUserId;
  static List<ClassSchedule> _cachedSchedule = [];

  /// Synchronizes class reminder notifications with current user preferences.
  /// Works across both Native Android/iOS devices and Web browsers while the tab/app is running.
  static Future<void> syncRoutineReminders(AppUser? user) async {
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

    // Ensure central schedule service is active for this scope
    ScheduleService.instance.syncScope(user.department, user.batch);

    // Read cached schedule from shared ScheduleService and listen to updates in-memory
    _cachedSchedule = ScheduleService.instance.classes;
    ScheduleService.instance.scheduleNotifier.addListener(_onScheduleUpdated);
    ScheduleService.instance.dayStatusesNotifier.addListener(_onScheduleUpdated);

    // Periodic timer checks local memory ONLY — zero Firestore reads per minute
    _reminderTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkUpcomingClassesFromCache();
    });
    debugPrint('[RoutineReminder] In-memory reminder timer active for user: ${user.email} (Web: $kIsWeb)');
  }

  static void _onScheduleUpdated() {
    _cachedSchedule = ScheduleService.instance.classes;
    _checkUpcomingClassesFromCache();
  }

  static void _checkUpcomingClassesFromCache() {
    if (_cachedSchedule.isEmpty) return;

    final now = DateTime.now();
    final todayDayName = DateFormat('EEEE').format(now); // e.g. "Monday"

    // 1. Check if the entire selected day is marked as Holiday, Boycott, or Auto Class
    final todayKey = '${now.year}_${now.month}_${now.day}';
    final dayStatuses = ScheduleService.instance.dayStatuses;
    String? todayDayStatus = dayStatuses[todayKey];

    if (todayDayStatus == null || todayDayStatus.isEmpty) {
      todayDayStatus = dayStatuses['${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}'] ??
          dayStatuses[DateFormat('yyyy-MM-dd').format(now)] ??
          dayStatuses[todayDayName.toLowerCase()];
    }

    final todayClasses = _cachedSchedule.where(
      (cls) => cls.dayOfWeek.toLowerCase() == todayDayName.toLowerCase(),
    ).toList();

    // Fallback: check if individual class items for today carry a day-wide override status
    if (todayDayStatus == null || todayDayStatus.isEmpty) {
      for (final c in todayClasses) {
        if (c.scheduledDate != null) {
          final sDate = c.scheduledDate!;
          if (sDate.year == now.year && sDate.month == now.month && sDate.day == now.day) {
            final st = c.status.trim().toLowerCase();
            if (st == 'auto' || st == 'boycott' || st == 'holiday') {
              todayDayStatus = st;
              break;
            }
          }
        }
      }
    }

    final normalizedDayStatus = (todayDayStatus ?? '').trim().toLowerCase();
    final bool isSpecialDay = normalizedDayStatus == 'holiday' ||
        normalizedDayStatus == 'boycott' ||
        normalizedDayStatus == 'auto' ||
        normalizedDayStatus == 'auto class' ||
        normalizedDayStatus == 'no class' ||
        normalizedDayStatus == 'no_class';

    // Strictly close/disable class start reminders on selected holiday / boycott / auto days
    if (isSpecialDay) {
      return;
    }

    for (final cls in todayClasses) {
      final clsStatus = cls.status.trim().toLowerCase();
      if (clsStatus == 'cancelled' ||
          clsStatus == 'no_class' ||
          clsStatus == 'no class' ||
          clsStatus == 'holiday' ||
          clsStatus == 'boycott' ||
          clsStatus == 'auto' ||
          clsStatus == 'auto class') {
        continue;
      }

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

          // 1. System/Browser notification + Sound chime
          if (kIsWeb) {
            playNotificationSound();
            showBrowserNotification(titleText, bodyText);
          } else {
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
          }

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
    ScheduleService.instance.scheduleNotifier.removeListener(_onScheduleUpdated);
    ScheduleService.instance.dayStatusesNotifier.removeListener(_onScheduleUpdated);
  }
}
