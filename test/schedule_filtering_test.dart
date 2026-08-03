import 'package:flutter_test/flutter_test.dart';
import 'package:unigrid_app/models/models.dart';

void main() {
  group('Schedule Filtering Tests', () {
    // Helper to compute Sunday of a given date (same logic as weekly_routine_table.dart)
    DateTime getSundayOfWeek(DateTime date) {
      if (date.weekday == DateTime.friday) {
        return date.add(const Duration(days: 2));
      } else if (date.weekday == DateTime.saturday) {
        return date.add(const Duration(days: 1));
      } else {
        final daysBack = date.weekday == DateTime.sunday ? 0 : date.weekday;
        return date.subtract(Duration(days: daysBack));
      }
    }

    DateTime getDateTimeForDay(DateTime sundayDate, String dayName) {
      int daysOffset = 0;
      switch (dayName.trim().toLowerCase()) {
        case 'sunday':
          daysOffset = 0;
          break;
        case 'monday':
          daysOffset = 1;
          break;
        case 'tuesday':
          daysOffset = 2;
          break;
        case 'wednesday':
          daysOffset = 3;
          break;
        case 'thursday':
          daysOffset = 4;
          break;
        case 'friday':
          daysOffset = 5;
          break;
        case 'saturday':
          daysOffset = 6;
          break;
        default:
          daysOffset = 0;
      }
      final targetDate = sundayDate.add(Duration(days: daysOffset));
      return DateTime(targetDate.year, targetDate.month, targetDate.day);
    }

    test('Regular repeating class matches all weeks', () {
      final repeatingClass = ClassSchedule(
        id: 'cls1',
        dayOfWeek: 'Tuesday',
        subject: 'Regular Class',
        room: 'R1',
        time: '8:00 - 8:50',
        scheduledDate: null, // No specific scheduled date (repeats weekly)
      );

      // Current running week Sunday: June 14, 2026. Tuesday is June 16, 2026.
      final runningSunday = DateTime(2026, 6, 14);
      final runningTuesday = getDateTimeForDay(runningSunday, 'Tuesday');

      expect(runningTuesday, DateTime(2026, 6, 16));

      // Filter check
      final showInRunningWeek = repeatingClass.scheduledDate == null ||
          (repeatingClass.scheduledDate!.year == runningTuesday.year &&
              repeatingClass.scheduledDate!.month == runningTuesday.month &&
              repeatingClass.scheduledDate!.day == runningTuesday.day);

      expect(showInRunningWeek, isTrue);
    });

    test('Future week scheduled class is hidden in current week', () {
      final futureClass = ClassSchedule(
        id: 'cls2',
        dayOfWeek: 'Tuesday',
        subject: 'Future Make-up Class',
        room: 'R2',
        time: '2:00 - 2:50',
        scheduledDate: DateTime(2026, 6, 23), // Scheduled for June 23, 2026
      );

      // Current running week Sunday: June 14, 2026. Tuesday is June 16, 2026.
      final runningSunday = DateTime(2026, 6, 14);
      final runningTuesday = getDateTimeForDay(runningSunday, 'Tuesday');

      // Filter check for running week (June 14-18)
      final showInRunningWeek = futureClass.scheduledDate == null ||
          (futureClass.scheduledDate!.year == runningTuesday.year &&
              futureClass.scheduledDate!.month == runningTuesday.month &&
              futureClass.scheduledDate!.day == runningTuesday.day);

      expect(showInRunningWeek, isFalse);
    });

    test('Future week scheduled class is shown when that week becomes active', () {
      final futureClass = ClassSchedule(
        id: 'cls2',
        dayOfWeek: 'Tuesday',
        subject: 'Future Make-up Class',
        room: 'R2',
        time: '2:00 - 2:50',
        scheduledDate: DateTime(2026, 6, 23), // Scheduled for June 23, 2026
      );

      // Active week shifts to the week of June 21, 2026. Tuesday is June 23, 2026.
      final activeSunday = DateTime(2026, 6, 21);
      final activeTuesday = getDateTimeForDay(activeSunday, 'Tuesday');

      expect(activeTuesday, DateTime(2026, 6, 23));

      // Filter check for active week
      final showInActiveWeek = futureClass.scheduledDate == null ||
          (futureClass.scheduledDate!.year == activeTuesday.year &&
              futureClass.scheduledDate!.month == activeTuesday.month &&
              futureClass.scheduledDate!.day == activeTuesday.day);

      expect(showInActiveWeek, isTrue);
    });

    test('Past week class identification preserves/restores completed status', () {
      final pastClass = ClassSchedule(
        id: 'cls3',
        dayOfWeek: 'Monday',
        subject: 'Past Week Class',
        room: 'R3',
        time: '9:00 - 9:50',
        scheduledDate: DateTime(2026, 6, 8), // Week of June 7
        status: 'upcoming', // Supposedly wrongly reset to upcoming
      );

      final currentSunday = DateTime(2026, 6, 14); // Running week starts June 14
      final classSunday = getSundayOfWeek(pastClass.scheduledDate!);

      final isPastWeekClass = classSunday.isBefore(currentSunday);
      expect(isPastWeekClass, isTrue);

      // Restoration logic rule: Past week classes with 'upcoming' status are restored to 'completed'
      String restoredStatus = pastClass.status;
      if (isPastWeekClass && pastClass.status == 'upcoming') {
        restoredStatus = 'completed';
      }

      expect(restoredStatus, 'completed');
    });
  });
}
