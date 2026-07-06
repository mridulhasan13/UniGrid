class ScheduleConstants {
  static const List<String> days = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday'
  ];

  // Time slots matching BUTEX routine structure
  static List<Map<String, dynamic>> getTimeSlots(
      Map<String, dynamic>? customSlots) {
    final List<Map<String, dynamic>> slots = [
      {
        'slot': 1,
        'time': '8:00 - 8:50',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 2,
        'time': '8:50 - 9:40',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 0,
        'time': 'Tea Break\n9:40 - 9:50',
        'isBreak': true,
        'type': 'Break',
        'breakDays': 'All Days'
      },
      {
        'slot': 3,
        'time': '9:50 - 10:40',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 4,
        'time': '10:40 - 11:30',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 5,
        'time': '11:30 - 12:20',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 6,
        'time': '12:20 - 13:10',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 0,
        'time': 'Lunch & Prayer Break\n1:10 - 2:00',
        'isBreak': true,
        'type': 'Break',
        'breakDays': 'All Days'
      },
      {
        'slot': 7,
        'time': '2:00 - 2:50',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 8,
        'time': '2:50 - 3:40',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 9,
        'time': '3:40 - 4:30',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
      {
        'slot': 10,
        'time': '4:30 - 5:20',
        'isBreak': false,
        'type': 'Class',
        'breakDays': 'All Days'
      },
    ];

    if (customSlots != null && customSlots.isNotEmpty) {
      for (var slot in slots) {
        final slotNum = slot['slot'] as int;
        final isDefaultBreak = slot['isBreak'] as bool;
        final String key = slotNum == 0
            ? (slot['time'].toString().contains('Tea') ||
                    slot['time'].toString().contains('tea')
                ? 'break_tea'
                : 'break_lunch')
            : 'slot_$slotNum';

        if (customSlots.containsKey(key)) {
          final dynamic val = customSlots[key];
          if (val is Map) {
            slot['time'] = val['time'] ?? slot['time'];
            slot['type'] = val['type'] ?? (isDefaultBreak ? 'Break' : 'Class');
            slot['breakDays'] = val['breakDays'] ?? 'All Days';
            // Sync isBreak flag with selected type
            slot['isBreak'] = (slot['type'] == 'Break');
          } else if (val is String) {
            slot['time'] = val;
          }
        }
      }
    }
    return slots;
  }

  static String getTimeForSlot(
      int startSlot, int span, Map<String, dynamic>? customSlots) {
    final slots = getTimeSlots(customSlots);
    if (span <= 1) {
      final slotData = slots.firstWhere((s) => s['slot'] == startSlot,
          orElse: () => {'time': ''});
      return slotData['time'];
    } else {
      final startData = slots.firstWhere((s) => s['slot'] == startSlot,
          orElse: () => {'time': ''});
      final endData = slots.firstWhere((s) => s['slot'] == startSlot + span - 1,
          orElse: () => {'time': ''});

      if (startData['time'].toString().isEmpty ||
          endData['time'].toString().isEmpty) return '';

      String startTime = startData['time'].split('-')[0].trim();
      String endTime = endData['time'].split('-')[1].trim();

      if (startTime.contains('\n'))
        startTime = startTime.split('\n').last.trim();
      if (endTime.contains('\n')) endTime = endTime.split('\n').last.trim();

      return '$startTime - $endTime';
    }
  }
}
