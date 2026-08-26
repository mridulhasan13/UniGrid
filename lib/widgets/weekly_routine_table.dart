import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../utils/schedule_constants.dart';
import '../widgets/linkified_text.dart';
import '../widgets/unigrid_loader.dart';
import '../notifications/in_app_notification.dart';
import '../screens/schedule_builder_screen.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/schedule_service.dart';

final Set<String> _autoPopulatedWeeks = {};

DateTime _getDateTimeForDayHelper(DateTime sundayDate, String dayName) {
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
  final target = sundayDate.add(Duration(days: daysOffset));
  return DateTime(target.year, target.month, target.day);
}

Future<void> _checkAndAutoPopulateWeek({
  required AppUser user,
  required DateTime sundayDate,
}) async {
  if (!user.isCR && !user.isAdmin) return;

  final weekKey = '${user.department}_${user.batch}_${sundayDate.year}_${sundayDate.month}_${sundayDate.day}';
  if (_autoPopulatedWeeks.contains(weekKey)) return;
  _autoPopulatedWeeks.add(weekKey);

  final defaultPath = deptBatchCol(user.department, user.batch, 'default_schedule');
  final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');

  try {
    final defaultSnap = await FirebaseFirestore.instance.collection(defaultPath).get();
    if (defaultSnap.docs.isEmpty) return;

    // Guard against race with _checkAndAutoResetStatuses in schedule_screen:
    // if that function already wrote classes for this week, skip to avoid duplicates.
    final normSun = DateTime(sundayDate.year, sundayDate.month, sundayDate.day);
    final normSat = DateTime(sundayDate.year, sundayDate.month, sundayDate.day + 6, 23, 59, 59);
    final existingCheck = await FirebaseFirestore.instance
        .collection(schedulePath)
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(normSun))
        .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(normSat))
        .limit(1)
        .get();
    if (existingCheck.docs.isNotEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (var doc in defaultSnap.docs) {
      final data = doc.data();
      final dayStr = (data['dayOfWeek'] ?? '').toString().trim();
      final dayDate = _getDateTimeForDayHelper(sundayDate, dayStr);
      final newRef = FirebaseFirestore.instance.collection(schedulePath).doc();

      batch.set(newRef, {
        'subject': data['subject'] ?? '',
        'subname': data['subname'] ?? '',
        'room': data['room'] ?? '',
        'teacher': data['teacher'] ?? '',
        'time': data['time'] ?? '',
        'dayOfWeek': dayStr,
        'startSlot': data['startSlot'] ?? 1,
        'span': data['span'] ?? 1,
        'group': data['group'] ?? '',
        'status': 'upcoming',
        'scheduledDate': Timestamp.fromDate(dayDate),
        'lastUpdatedDate': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  } catch (e) {
    debugPrint('Auto populate error: $e');
  }
}

class WeeklyRoutineTable extends StatelessWidget {
  final Map<String, dynamic>? customSlots;
  final String university;
  final String levelTerm;
  final VoidCallback? onDateTap;
  final DateTime? selectedDate;

  const WeeklyRoutineTable({
    super.key,
    this.customSlots,
    required this.university,
    required this.levelTerm,
    this.onDateTap,
    this.selectedDate,
  });

  // Base layout grid widths: Days column + 10 structural class blocks + 2 vertical break gutters
  static const List<int> colFlex = [
    60,
    45,
    45,
    20,
    45,
    45,
    45,
    45,
    24,
    45,
    45,
    45,
    45
  ];

  DateTime _getSundayOfWeek(DateTime date) {
    if (date.weekday == DateTime.friday) {
      return date.add(const Duration(days: 2));
    } else if (date.weekday == DateTime.saturday) {
      return date.add(const Duration(days: 1));
    } else {
      final daysBack = date.weekday == DateTime.sunday ? 0 : date.weekday;
      return date.subtract(Duration(days: daysBack));
    }
  }

  String _getDateForDay(DateTime sundayDate, String dayName) {
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
    return DateFormat('d MMM').format(targetDate);
  }

  DateTime _getDateTimeForDay(DateTime sundayDate, String dayName) {
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

  @override
  Widget build(BuildContext context) {
    final sundayDate = _getSundayOfWeek(selectedDate ?? DateTime.now());
    final double screenWidth = MediaQuery.of(context).size.width;
    // Mobile/narrow check: screens narrower than 920px are scaled/scrollable using InteractiveViewer
    final bool isMobile = screenWidth < 920;
    final user = Provider.of<AppUser?>(context);
    
    if (user != null && user.hasDeptScope) {
      ScheduleService.instance.syncScope(user.department, user.batch);
    }

    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: ScheduleService.instance.dayStatusesNotifier,
      builder: (context, dayStatusesMap, _) {
        return ValueListenableBuilder<List<ClassSchedule>>(
          valueListenable: ScheduleService.instance.scheduleNotifier,
          builder: (context, rawClassesList, _) {
            final isInitialLoading = ScheduleService.instance.isLoadingNotifier.value && rawClassesList.isEmpty;
            if (isInitialLoading) {
              return const Center(
                child: UniGridLoader(
                  title: 'Loading Routine',
                  subtitle: 'Rendering weekly class grid...',
                  showBackground: false,
                ),
              );
            }

            final rawClasses = rawClassesList.where((cls) {
              if (cls.scheduledDate != null) {
                final clsDate = cls.scheduledDate!;
                final saturdayDate = sundayDate.add(const Duration(days: 6));
                
                final normalizedCls = DateTime(clsDate.year, clsDate.month, clsDate.day);
                final normalizedSun = DateTime(sundayDate.year, sundayDate.month, sundayDate.day);
                final normalizedSat = DateTime(saturdayDate.year, saturdayDate.month, saturdayDate.day);
                
                return (normalizedCls.isAtSameMomentAs(normalizedSun) || normalizedCls.isAfter(normalizedSun)) &&
                       (normalizedCls.isAtSameMomentAs(normalizedSat) || normalizedCls.isBefore(normalizedSat));
              }
              return true;
            })
            .toList();

        final isCR = user != null && (user.isCR || user.isAdmin);

        if (rawClasses.isEmpty && user != null && user.hasDeptScope && isCR) {
          final weekKey = '${user.department}_${user.batch}_${sundayDate.year}_${sundayDate.month}_${sundayDate.day}';
          if (!_autoPopulatedWeeks.contains(weekKey)) {
            _autoPopulatedWeeks.add(weekKey);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkAndAutoPopulateWeek(user: user, sundayDate: sundayDate);
            });
          }
        }

        // De-duplicate classes to prevent "barcode" layout if database has duplicate records
        final Map<String, ClassSchedule> uniqueClasses = {};
        for (var cls in rawClasses) {
          final key =
              '${cls.dayOfWeek}_${cls.startSlot}_${cls.subject.trim()}_${cls.group.trim()}_${cls.teacher.trim()}_${cls.room.trim()}';
          uniqueClasses[key] = cls;
        }
        final classes = uniqueClasses.values.toList();

        final slotsList = ScheduleConstants.getTimeSlots(customSlots);

        // Find Tea Break in slotsList (the first break at slot == 0)
        final teaBreakData = slotsList.firstWhere(
          (s) =>
              s['slot'] == 0 &&
              (s['time'].toString().toLowerCase().contains('tea') ||
                  s['time'].toString().toLowerCase().contains('break_tea')),
          orElse: () => {'time': 'Tea Break\n9:40 - 9:50'},
        );
        final String teaBreakText = teaBreakData['time'] as String;

        // Find Lunch Break in slotsList (the second break at slot == 0)
        final lunchBreakData = slotsList.firstWhere(
          (s) =>
              s['slot'] == 0 &&
              (s['time'].toString().toLowerCase().contains('lunch') ||
                  s['time'].toString().toLowerCase().contains('break_lunch')),
          orElse: () => {'time': 'Lunch & Prayer Break\n1:10 - 2:00'},
        );
        final String lunchBreakText = lunchBreakData['time'] as String;

        final cleanTeaText = teaBreakText.split('\n')[0].toUpperCase();
        final cleanLunchText = lunchBreakText.split('\n')[0].toUpperCase();

        final Widget tableGridContent = Column(
          children: [
            // Time Slot Row with strict fixed height to prevent vertical fractional overflow
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  Expanded(flex: colFlex[0], child: const SizedBox.shrink()),
                  Expanded(
                      flex: colFlex[1],
                      child: _buildTimeHeader(slotsList, 1, '8:00-8:50')),
                  Expanded(
                      flex: colFlex[2],
                      child: _buildTimeHeader(slotsList, 2, '8:50-9:40')),
                  Expanded(
                      flex: colFlex[3],
                      child: _buildBreakHeader(slotsList, 'Tea')),
                  Expanded(
                      flex: colFlex[4],
                      child: _buildTimeHeader(slotsList, 3, '9:50-10:40')),
                  Expanded(
                      flex: colFlex[5],
                      child: _buildTimeHeader(slotsList, 4, '10:40-11:30')),
                  Expanded(
                      flex: colFlex[6],
                      child: _buildTimeHeader(slotsList, 5, '11:30-12:20')),
                  Expanded(
                      flex: colFlex[7],
                      child: _buildTimeHeader(slotsList, 6, '12:20-13:10')),
                  Expanded(
                      flex: colFlex[8],
                      child: _buildBreakHeader(slotsList, 'Lunch')),
                  Expanded(
                      flex: colFlex[9],
                      child: _buildTimeHeader(slotsList, 7, '2:00-2:50')),
                  Expanded(
                      flex: colFlex[10],
                      child: _buildTimeHeader(slotsList, 8, '2:50-3:40')),
                  Expanded(
                      flex: colFlex[11],
                      child: _buildTimeHeader(slotsList, 9, '3:40-4:30')),
                  Expanded(
                      flex: colFlex[12],
                      child: _buildTimeHeader(slotsList, 10, '4:30-5:20')),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Main Dynamic Grid Segment Area wrapping expanded rows
            Expanded(
              child: Row(
                children: [
                  // Day Segment Indicators Column
                  Expanded(
                    flex: colFlex[0],
                    child: Column(
                      children:
                          ScheduleConstants.days.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final day = entry.value;
                        final formattedDate = _getDateForDay(sundayDate, day);
                        final dayDate = _getDateTimeForDay(sundayDate, day);
                        final dayKey = '${dayDate.year}_${dayDate.month}_${dayDate.day}';

                        String? activeStatus = dayStatusesMap[dayKey];
                        if (activeStatus == null || activeStatus.isEmpty) {
                          for (var c in rawClasses) {
                            if (c.dayOfWeek == day && c.scheduledDate != null) {
                              final sDate = c.scheduledDate!;
                              if (sDate.year == dayDate.year &&
                                  sDate.month == dayDate.month &&
                                  sDate.day == dayDate.day) {
                                final st = c.status.trim().toLowerCase();
                                if (st == 'auto' || st == 'boycott' || st == 'holiday') {
                                  activeStatus = st;
                                  break;
                                }
                              }
                            }
                          }
                        }

                        final bool isAuto = activeStatus == 'auto';
                        final bool isBoycott = activeStatus == 'boycott';
                        final bool isHoliday = activeStatus == 'holiday';

                        Color borderColor = AppColors.primary.withOpacity(0.2);
                        List<Color> bgColors = [
                          AppColors.primary.withOpacity(0.15),
                          AppColors.secondary.withOpacity(0.04)
                        ];

                        if (isAuto) {
                          borderColor = Colors.cyanAccent.withOpacity(0.7);
                          bgColors = [
                            Colors.cyan.withOpacity(0.35),
                            Colors.cyan.withOpacity(0.12)
                          ];
                        } else if (isBoycott) {
                          borderColor = Colors.redAccent.withOpacity(0.7);
                          bgColors = [
                            Colors.red.withOpacity(0.35),
                            Colors.red.withOpacity(0.12)
                          ];
                        }

                        return Expanded(
                          child: Padding(
                            padding:
                                EdgeInsets.only(bottom: idx == 4 ? 0.0 : 4.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  _showDayStatusDialog(context, user, day, dayDate, activeStatus);
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: bgColors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(
                                        color: borderColor,
                                        width: (isAuto || isBoycott) ? 1.5 : 1.0),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          day.toUpperCase(),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.bold,
                                              color: isAuto
                                                  ? Colors.cyanAccent
                                                  : (isBoycott
                                                      ? Colors.redAccent
                                                      : AppColors.textPrimary),
                                              letterSpacing: 0.2),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          formattedDate,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 6.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary
                                                  .withOpacity(0.7),
                                              letterSpacing: 0.1),
                                        ),
                                        if (isAuto || isBoycott) ...[
                                          const SizedBox(height: 1),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 3, vertical: 0.5),
                                            decoration: BoxDecoration(
                                              color: isAuto
                                                  ? Colors.cyanAccent
                                                  : Colors.redAccent,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                            child: Text(
                                              isAuto ? 'AUTO' : 'BOYCOTT',
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 5.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Timetable Core Content Grid Blocks
                  Expanded(
                    flex: colFlex.reduce((a, b) => a + b) - colFlex[0],
                    child: Row(
                      children: [
                        // Periods 1 & 2 Block
                        _buildPeriodGroupColumn(
                            context, [colFlex[1], colFlex[2]], 0, classes, sundayDate, dayStatusesMap),
                        const SizedBox(width: 4),
                        // Tea Break Box
                        Expanded(
                            flex: colFlex[3],
                            child: MiniRotatedBreak(text: cleanTeaText)),
                        const SizedBox(width: 4),
                        // Periods 3, 4, 5, 6 Block
                        _buildPeriodGroupColumn(
                            context,
                            [colFlex[4], colFlex[5], colFlex[6], colFlex[7]],
                            1,
                            classes, sundayDate, dayStatusesMap),
                        const SizedBox(width: 4),
                        // Lunch Break Box
                        Expanded(
                            flex: colFlex[8],
                            child: MiniRotatedBreak(text: cleanLunchText)),
                        const SizedBox(width: 4),
                        // Periods 7, 8, 9, 10 Block
                        _buildPeriodGroupColumn(
                            context,
                            [colFlex[9], colFlex[10], colFlex[11], colFlex[12]],
                            2,
                            classes, sundayDate, dayStatusesMap),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        );

        final bool useBlur = !kIsWeb;

        final Widget cardContainer = Container(
          width: isMobile ? 920 : double.infinity,
          decoration: BoxDecoration(
            color: AppColors.glassCardColor.withOpacity(useBlur ? 0.75 : 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeaderBar(
                university: university,
                levelTerm: levelTerm,
                onDateTap: onDateTap,
              ),
              const SizedBox(height: 6),
              Flexible(
                fit: FlexFit.loose,
                child: SizedBox(
                  height: 384,
                  width: isMobile ? 920 : double.infinity,
                  child: tableGridContent,
                ),
              ),
            ],
          ),
        );

        final Widget tableCard = RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: useBlur
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: cardContainer,
                  )
                : cardContainer,
          ),
        );

        return Stack(
          children: [
            // Ambient Glossy Green Radial Glow Background
            Center(
              child: Container(
                width: 600,
                height: 450,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.12),
                      AppColors.primary.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),

            // Glassmorphic Scrollable Frame Container
            Center(
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: InteractiveViewer(
                  minScale: 0.3,
                  maxScale: 5.0,
                  scaleFactor: 800.0,
                  trackpadScrollCausesScale: true,
                  clipBehavior: Clip.hardEdge,
                  constrained: !isMobile, // Allows panning horizontally & vertically to scroll when not constrained
                  boundaryMargin: const EdgeInsets.all(300), // Gives scroll limits buffer
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: isMobile ? 920 : null,
                      height: isMobile ? 448 : null,
                      child: tableCard,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  },
);
}

  Widget _buildTimeHeader(
      List<Map<String, dynamic>> slotsList, int slotNum, String defaultRange) {
    final slotData = slotsList.firstWhere(
      (s) => s['slot'] == slotNum,
      orElse: () => {'time': defaultRange},
    );
    final String range = slotData['time'] as String;
    String displayRange = range;
    if (displayRange.contains('\n')) {
      displayRange = displayRange.split('\n').last.trim();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.2),
            width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$slotNum',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            displayRange.replaceAll(' - ', '-'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 7.5,
              color: AppColors.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakHeader(
      List<Map<String, dynamic>> slotsList, String breakName) {
    final breakData = slotsList.firstWhere(
      (s) =>
          s['slot'] == 0 &&
          s['time'].toString().toLowerCase().contains(breakName.toLowerCase()),
      orElse: () => {'time': breakName},
    );
    final String timeStr = breakData['time'] as String;
    String name = timeStr.split('\n')[0].trim();
    if (name.toLowerCase().contains('tea')) {
      name = 'Tea';
    } else if (name.toLowerCase().contains('lunch')) {
      name = 'Lunch';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: AppColors.secondary.withOpacity(0.2),
            width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      alignment: Alignment.center,
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          color: AppColors.secondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildPeriodGroupColumn(
      BuildContext context,
      List<int> flexWeights,
      int groupIdx,
      List<ClassSchedule> allClasses,
      DateTime sundayDate,
      Map<String, String> dayStatusesMap) {
    int columnSumFlex = flexWeights.reduce((a, b) => a + b);
    return Expanded(
      flex: columnSumFlex,
      child: Column(
        children: List.generate(ScheduleConstants.days.length, (rowIdx) {
          final day = ScheduleConstants.days[rowIdx];
          final dayDate = _getDateTimeForDay(sundayDate, day);
          final dayKey = '${dayDate.year}_${dayDate.month}_${dayDate.day}';

          final dayClasses = allClasses.where((c) {
            if (c.dayOfWeek != day) return false;
            if (c.scheduledDate != null) {
              final sDate = c.scheduledDate!;
              return sDate.year == dayDate.year &&
                  sDate.month == dayDate.month &&
                  sDate.day == dayDate.day;
            }
            return true;
          }).toList();

          String? overrideStatus = dayStatusesMap[dayKey];
          if (overrideStatus == null || overrideStatus.isEmpty) {
            for (var c in dayClasses) {
              final st = c.status.trim().toLowerCase();
              if (st == 'auto' || st == 'boycott' || st == 'holiday') {
                overrideStatus = st;
                break;
              }
            }
          }

          if (overrideStatus == 'auto' || overrideStatus == 'boycott' || overrideStatus == 'holiday') {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: rowIdx == 4 ? 0.0 : 4.0),
                child: _buildDayOverrideCard(overrideStatus!, groupIdx),
              ),
            );
          }

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: rowIdx == 4 ? 0.0 : 4.0),
              child: Row(
                children:
                    _getDynamicRowData(context, day, groupIdx, dayClasses),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayOverrideCard(String status, int groupIdx) {
    final bool isAuto = status == 'auto';
    final bool isHoliday = status == 'holiday';
    final Color themeColor = isAuto
        ? Colors.cyanAccent
        : (isHoliday ? Colors.orangeAccent : Colors.redAccent);
    final String displayText = isAuto
        ? 'AUTO'
        : (isHoliday ? 'HOLIDAY' : 'BOYCOTT');
    final List<Color> bgGradient = isAuto
        ? [
            const Color(0xFF003840).withOpacity(0.9),
            const Color(0xFF001F24).withOpacity(0.9),
          ]
        : (isHoliday
            ? [
                const Color(0xFF402200).withOpacity(0.9),
                const Color(0xFF241300).withOpacity(0.9),
              ]
            : [
                const Color(0xFF40000D).withOpacity(0.9),
                const Color(0xFF240005).withOpacity(0.9),
              ]);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: themeColor.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: themeColor.withOpacity(0.15),
            blurRadius: 6,
          ),
        ],
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: themeColor,
          fontWeight: FontWeight.bold,
          fontSize: 10.5,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Future<void> _showDayStatusDialog(
    BuildContext context,
    AppUser? user,
    String day,
    DateTime dayDate,
    String? currentStatus,
  ) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);
    final isCR = user != null && (user.isCR || user.isAdmin || isRootAdmin);
    final formattedDate = DateFormat('EEEE, d MMMM').format(dayDate);

    if (!isCR) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundTop,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            day,
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(
            currentStatus == 'auto' || currentStatus == 'boycott' || currentStatus == 'holiday'
                ? 'This day is marked as ${currentStatus!.toUpperCase()} by the CR.\nAll classes for this day are uncounted.'
                : 'Only Class Representatives (CRs) can set Auto, Boycott, or Holiday status for schedule days.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassCardBorder),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedDate,
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              'Set Day Status (Classes will be uncounted)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDayOptionButton(
              context: ctx,
              title: 'Auto Class',
              subtitle: 'Mark entire day as Auto. All classes uncounted.',
              icon: Icons.smart_button_rounded,
              color: Colors.cyanAccent,
              isSelected: currentStatus == 'auto',
              onTap: () {
                Navigator.pop(ctx);
                _updateDayStatus(context, user, day, dayDate, 'auto');
              },
            ),
            const SizedBox(height: 10),
            _buildDayOptionButton(
              context: ctx,
              title: 'Boycott Day',
              subtitle: 'Mark entire day as Boycott. All classes uncounted.',
              icon: Icons.block_rounded,
              color: Colors.redAccent,
              isSelected: currentStatus == 'boycott',
              onTap: () {
                Navigator.pop(ctx);
                _updateDayStatus(context, user, day, dayDate, 'boycott');
              },
            ),
            const SizedBox(height: 10),
            _buildDayOptionButton(
              context: ctx,
              title: 'Holiday',
              subtitle: 'Mark entire day as Holiday. All classes uncounted.',
              icon: Icons.beach_access_rounded,
              color: Colors.orangeAccent,
              isSelected: currentStatus == 'holiday',
              onTap: () {
                Navigator.pop(ctx);
                _updateDayStatus(context, user, day, dayDate, 'holiday');
              },
            ),
            if (currentStatus == 'auto' || currentStatus == 'boycott' || currentStatus == 'holiday') ...[
              const SizedBox(height: 12),
              Divider(color: AppColors.glassCardBorder),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _updateDayStatus(context, user, day, dayDate, 'normal');
                },
                icon: const Icon(Icons.refresh_rounded, color: Colors.amberAccent, size: 16),
                label: const Text(
                  'Restore Normal Routine',
                  style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildDayOptionButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(isSelected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(isSelected ? 0.8 : 0.3),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.6), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateDayStatus(
    BuildContext context,
    AppUser? user,
    String day,
    DateTime dayDate,
    String newStatus,
  ) async {
    if (user == null || !user.hasDeptScope) return;

    final metaPath = deptBatchCol(user.department, user.batch, 'routine_metadata');
    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');
    final docKey = '${dayDate.year}_${dayDate.month}_${dayDate.day}';

    try {
      final dayStatusRef = FirebaseFirestore.instance.collection(metaPath).doc('day_statuses');
      if (newStatus == 'normal') {
        await dayStatusRef.set({
          docKey: FieldValue.delete(),
        }, SetOptions(merge: true));
      } else {
        await dayStatusRef.set({
          docKey: newStatus,
        }, SetOptions(merge: true));
      }

      final scheduleDocs = await FirebaseFirestore.instance
          .collection(schedulePath)
          .where('dayOfWeek', isEqualTo: day)
          .get();

      if (scheduleDocs.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in scheduleDocs.docs) {
          final data = doc.data();
          DateTime? clsDate;
          if (data['scheduledDate'] != null) {
            if (data['scheduledDate'] is Timestamp) {
              clsDate = (data['scheduledDate'] as Timestamp).toDate();
            } else if (data['scheduledDate'] is String) {
              clsDate = DateTime.tryParse(data['scheduledDate']);
            }
          }

          bool isTargetDay = clsDate == null ||
              (clsDate.year == dayDate.year &&
               clsDate.month == dayDate.month &&
               clsDate.day == dayDate.day);

          if (isTargetDay) {
            batch.update(doc.reference, {
              'status': newStatus == 'normal' ? 'upcoming' : newStatus,
              'lastUpdatedDate': FieldValue.serverTimestamp(),
            });
          }
        }
        await batch.commit();
      }

      if (context.mounted) {
        final String label = newStatus == 'auto'
            ? 'Auto Day'
            : (newStatus == 'boycott'
                ? 'Boycott Day'
                : (newStatus == 'holiday' ? 'Holiday' : 'Normal Routine'));
        InAppNotification.show(
          context,
          title: '$day Status Updated',
          message: '$day is now set to "$label". Classes are ${newStatus == 'normal' ? 'restored' : 'uncounted'}.',
          accentColor: newStatus == 'auto'
              ? Colors.cyanAccent
              : (newStatus == 'boycott'
                  ? Colors.redAccent
                  : (newStatus == 'holiday' ? Colors.orangeAccent : Colors.greenAccent)),
          icon: newStatus == 'auto'
              ? Icons.smart_button_rounded
              : (newStatus == 'boycott'
                  ? Icons.block_rounded
                  : (newStatus == 'holiday' ? Icons.beach_access_rounded : Icons.check_circle_outline_rounded)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        InAppNotification.show(
          context,
          title: 'Update Failed',
          message: 'Failed to update day status: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  List<Widget> _getDynamicRowData(BuildContext context, String day,
      int groupIdx, List<ClassSchedule> dayClasses) {
    final List<int> slots =
        groupIdx == 0 ? [1, 2] : (groupIdx == 1 ? [3, 4, 5, 6] : [7, 8, 9, 10]);

    List<Widget> children = [];
    final slotsList = ScheduleConstants.getTimeSlots(customSlots);
    int i = 0;
    while (i < slots.length) {
      final slotNum = slots[i];

      // Check if this slot is configured as a Break for this day
      final slotData = slotsList.firstWhere(
        (s) => s['slot'] == slotNum,
        orElse: () => {'type': 'Class', 'breakDays': 'All Days'},
      );
      final slotType = slotData['type'] ?? 'Class';
      final breakDaysStr = slotData['breakDays'] ?? 'All Days';
      final isBreakForDay = slotType == 'Break' &&
          (breakDaysStr == 'All Days' || breakDaysStr == day);

      if (isBreakForDay) {
        children.add(
          const Expanded(
            flex: 45,
            child: MiniRotatedBreak(text: 'BREAK'),
          ),
        );
        if (i < slots.length - 1) {
          children.add(const SizedBox(width: 4));
        }
        i++;
        continue;
      }

      // Find classes starting at this slot
      final classesAtSlot =
          dayClasses.where((c) => c.startSlot == slotNum).toList();

      if (classesAtSlot.isNotEmpty) {
        final span = classesAtSlot.first.span;
        final maxAllowedSpan = slots.length - i;
        final actualSpan = span.clamp(1, maxAllowedSpan);

        children.add(
          Expanded(
            flex: actualSpan * 45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: classesAtSlot.asMap().entries.map((entry) {
                final idx = entry.key;
                final cls = entry.value;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: idx == classesAtSlot.length - 1
                            ? 0
                            : (classesAtSlot.length >= 3 ? 2 : 4)),
                    child: _buildDynamicClassBox(context, cls,
                        isCompact: classesAtSlot.length > 1,
                        stackedCount: classesAtSlot.length),
                  ),
                );
              }).toList(),
            ),
          ),
        );
        if (i < slots.length - 1) {
          children.add(const SizedBox(width: 4));
        }
        i += actualSpan;
      } else {
        children.add(
          const Expanded(
            flex: 45,
            child: BlankItem(),
          ),
        );
        if (i < slots.length - 1) {
          children.add(const SizedBox(width: 4));
        }
        i++;
      }
    }
    return children;
  }

  Widget _buildDynamicClassBox(BuildContext context, ClassSchedule cls,
      {bool isCompact = false, int stackedCount = 1}) {
    final bool isLab = cls.subject.toLowerCase().contains('lab') ||
        cls.subject.toLowerCase().contains('practical') ||
        cls.span > 1;

    final String status = cls.status.toLowerCase();
    final Color baseColor = isLab ? AppColors.secondary : AppColors.primary;

    final Color mainThemeColor;
    final List<Color> gradientColors;

    if (status == 'completed') {
      mainThemeColor = const Color(0xFF00E676); // Green
      gradientColors = [
        const Color(0xFF00E676).withOpacity(0.15),
        const Color(0xFF003010).withOpacity(0.25),
      ];
    } else if (status == 'cancelled') {
      mainThemeColor = const Color(0xFFFF1744); // Red
      gradientColors = [
        const Color(0xFFFF1744).withOpacity(0.15),
        const Color(0xFF400010).withOpacity(0.25),
      ];
    } else if (status == 'upcoming') {
      mainThemeColor = const Color(0xFF2196F3); // Blue
      gradientColors = [
        const Color(0xFF2196F3).withOpacity(0.15),
        const Color(0xFF0D47A1).withOpacity(0.25),
      ];
    } else if (status == 'no class' || status == 'no_class') {
      // Both underscore and space variants are treated as 'No Class'
      mainThemeColor = const Color(0xFFFFD600); // Vibrant Yellow
      gradientColors = [
        const Color(0xFFFFD600).withOpacity(0.15),
        const Color(0xFF423A00).withOpacity(0.25),
      ];
    } else {
      mainThemeColor = baseColor;
      gradientColors = [
        baseColor.withOpacity(0.15),
        Colors.black.withOpacity(0.35),
      ];
    }

    final user = Provider.of<AppUser?>(context);

    final double roomFontSize = stackedCount >= 3 ? 5.0 : (isCompact ? 5.5 : 6.5);
    final double titleFontSize = stackedCount >= 3 ? 6.2 : (isCompact ? 7.0 : 8.0);
    final double verticalPadding = stackedCount >= 3 ? 0.5 : (isCompact ? 1.0 : 3.0);

    return GestureDetector(
      onTap: () => _showClassDetailsSheet(context, cls, user),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: mainThemeColor.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: verticalPadding),
        alignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinkifiedText(
              cls.teacher.isEmpty ? cls.room : '${cls.room}  •  ${cls.teacher}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: roomFontSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            if (stackedCount < 3) SizedBox(height: isCompact ? 1 : 2),
            LinkifiedText(
              (status == 'no class' || status == 'no_class')
                  ? 'NO CLASS'
                  : (status == 'cancelled'
                      ? 'CANCELLED'
                      : (cls.group.isEmpty
                          ? cls.subject
                          : '${cls.subject} (${cls.group})')),
              textAlign: TextAlign.center,
              maxLines: isCompact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: titleFontSize,
                fontWeight: FontWeight.bold,
                color: mainThemeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _lookupTeacherAndCourse(
      ClassSchedule cls, AppUser? user) async {
    if (user == null || !user.hasDeptScope) return null;

    final List<String> candidateInitials = [];
    if (cls.teacher.trim().isNotEmpty) {
      candidateInitials.add(cls.teacher.trim().toLowerCase());
    }

    // Extract potential teacher short code from subject like "YE 211-0723: YM - A"
    final subject = cls.subject.trim();
    if (subject.contains(':')) {
      final afterColon = subject.split(':')[1].trim();
      final parts = afterColon.split(RegExp(r'[\s\-_]+'));
      for (final p in parts) {
        if (p.isNotEmpty && p.length <= 5) {
          candidateInitials.add(p.toLowerCase());
        }
      }
    }

    try {
      final List<String> searchPaths = [
        'depts/${user.department}/courses',
        deptBatchCol(user.department, user.batch, 'courses'),
        'courses',
      ];

      for (final path in searchPaths) {
        try {
          final snap = await FirebaseFirestore.instance.collection(path).get();
          for (final doc in snap.docs) {
            final data = doc.data();
            final cCode = (data['courseCode'] ?? '').toString().trim();
            final tShort = (data['teacherShort'] ?? '').toString().trim();
            final tName = (data['teacherName'] ?? '').toString().trim();
            final cName = (data['courseName'] ?? '').toString().trim();

            final bool matchesInitial = tShort.isNotEmpty &&
                candidateInitials.contains(tShort.toLowerCase());
            final bool matchesCode = cCode.isNotEmpty &&
                (subject.toLowerCase().contains(cCode.toLowerCase()) ||
                    cCode.toLowerCase().contains(subject.split(':')[0].trim().toLowerCase()));

            if (matchesInitial || matchesCode) {
              return {
                'courseCode': cCode,
                'courseName': cName,
                'teacherName': tName,
                'teacherShort': tShort.isNotEmpty
                    ? tShort
                    : (candidateInitials.isNotEmpty
                        ? candidateInitials.first.toUpperCase()
                        : ''),
                'totalCredit': data['totalCredit'],
                'levelTerm': data['levelTerm'],
              };
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error looking up course/teacher: $e');
    }
    return null;
  }

  void _showClassDetailsSheet(
      BuildContext context, ClassSchedule cls, AppUser? user) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);
    final isCR = user != null && (user.isCR || user.isAdmin || isRootAdmin);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _lookupTeacherAndCourse(cls, user),
              builder: (context, snapshot) {
                final courseInfo = snapshot.data;
                final String resolvedCourseName = (cls.subname.isNotEmpty
                        ? cls.subname
                        : (courseInfo?['courseName'] ?? ''))
                    .toString()
                    .trim();
                final String resolvedTeacherName =
                    (courseInfo?['teacherName'] ?? '').toString().trim();

                // Extract short tag
                String teacherShort = cls.teacher.isNotEmpty
                    ? cls.teacher
                    : (courseInfo?['teacherShort'] ?? '');

                if (teacherShort.isEmpty && cls.subject.contains(':')) {
                  final afterColon = cls.subject.split(':')[1].trim();
                  final parts = afterColon.split(RegExp(r'[\s\-_]+'));
                  if (parts.isNotEmpty && parts.first.length <= 5) {
                    teacherShort = parts.first;
                  }
                }

                // Display teacher as "Full Name (Short)"
                final String teacherDisplayTitle;
                if (resolvedTeacherName.isNotEmpty) {
                  if (teacherShort.isNotEmpty &&
                      !resolvedTeacherName.contains('($teacherShort)')) {
                    teacherDisplayTitle =
                        '$resolvedTeacherName ($teacherShort)';
                  } else {
                    teacherDisplayTitle = resolvedTeacherName;
                  }
                } else if (teacherShort.isNotEmpty) {
                  teacherDisplayTitle = 'Teacher ($teacherShort)';
                } else {
                  teacherDisplayTitle = 'Faculty Member';
                }

                // Clean avatar initial (strip Dr., Prof., etc.)
                String extractCleanAvatarInitial(String short, String fullName) {
                  String clean = short.trim();
                  clean = clean.replaceAll(
                      RegExp(r'^(Dr\.|Prof\.|Engr\.|Mr\.|Mrs\.|Ms\.)\s*',
                          caseSensitive: false),
                      '');
                  clean = clean.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

                  if (clean.isNotEmpty) {
                    if (clean.length > 3) {
                      return clean.substring(0, 3).toUpperCase();
                    }
                    return clean.toUpperCase();
                  }

                  if (fullName.trim().isNotEmpty) {
                    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) {
                      final low = p.toLowerCase();
                      return low != 'dr.' &&
                          low != 'dr' &&
                          low != 'prof.' &&
                          low != 'prof' &&
                          low != 'engr.' &&
                          low != 'engr' &&
                          low != 'mr.' &&
                          low != 'mr';
                    }).toList();
                    if (parts.length >= 2) {
                      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
                    } else if (parts.isNotEmpty) {
                      return parts[0][0].toUpperCase();
                    }
                  }
                  return 'T';
                }

                final String avatarInitial =
                    extractCleanAvatarInitial(teacherShort, resolvedTeacherName);

                Color statusColor;
                IconData statusIcon;
                String statusText = cls.status.toUpperCase();

                switch (cls.status.toLowerCase()) {
                  case 'completed':
                    statusColor = Colors.greenAccent;
                    statusIcon = Icons.check_circle_rounded;
                    break;
                  case 'cancelled':
                    statusColor = Colors.redAccent;
                    statusIcon = Icons.cancel_rounded;
                    break;
                  case 'no class':
                  case 'no_class':
                    statusColor = Colors.amberAccent;
                    statusIcon = Icons.block_rounded;
                    statusText = 'NO CLASS';
                    break;
                  case 'upcoming':
                    statusColor = Colors.blueAccent;
                    statusIcon = Icons.schedule_rounded;
                    break;
                  default:
                    statusColor = AppColors.primary;
                    statusIcon = Icons.event_available_rounded;
                    statusText = 'NORMAL';
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundTop.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25),
                            width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row with Icon, Title, Status, and Close button
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.school_rounded,
                                      color: AppColors.primary, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cls.subject,
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (resolvedCourseName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          resolvedCourseName,
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => Navigator.pop(ctx),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.textPrimary
                                          .withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.close_rounded,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Status Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: statusColor.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon,
                                      color: statusColor, size: 12),
                                  const SizedBox(width: 5),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Class Details Grid
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.glassCardColor.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppColors.textPrimary
                                        .withOpacity(0.08)),
                              ),
                              child: Column(
                                children: [
                                  _buildDetailRow(
                                    Icons.meeting_room_rounded,
                                    'Room',
                                    cls.room.isNotEmpty
                                        ? cls.room
                                        : 'Not specified',
                                    Colors.cyanAccent,
                                  ),
                                  const Divider(
                                      color: Colors.white10, height: 16),
                                  _buildDetailRow(
                                    Icons.access_time_rounded,
                                    'Time & Slot',
                                    '${cls.time} (Slot ${cls.startSlot}${cls.span > 1 ? " - ${cls.startSlot + cls.span - 1}" : ""})',
                                    Colors.amberAccent,
                                  ),
                                  const Divider(
                                      color: Colors.white10, height: 16),
                                  _buildDetailRow(
                                    Icons.calendar_today_rounded,
                                    'Day',
                                    cls.dayOfWeek,
                                    Colors.purpleAccent,
                                  ),
                                  if (cls.group.isNotEmpty) ...[
                                    const Divider(
                                        color: Colors.white10, height: 16),
                                    _buildDetailRow(
                                      Icons.group_rounded,
                                      'Section / Group',
                                      cls.group,
                                      Colors.blueAccent,
                                    ),
                                  ],
                                  if (courseInfo?['totalCredit'] != null) ...[
                                    const Divider(
                                        color: Colors.white10, height: 16),
                                    _buildDetailRow(
                                      Icons.star_outline_rounded,
                                      'Credits',
                                      '${courseInfo!['totalCredit']} Credits',
                                      Colors.greenAccent,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Teacher Details Card
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppColors.secondary
                                        .withOpacity(0.25)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor:
                                        AppColors.secondary.withOpacity(0.2),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          avatarInitial,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: AppColors.secondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: avatarInitial.length <= 2
                                                ? 14
                                                : 11.5,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          teacherDisplayTitle,
                                          style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          teacherShort.isNotEmpty
                                              ? 'Initial: $teacherShort • Department of ${user?.department ?? ""}'
                                              : 'Department of ${user?.department ?? ""}',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // CR Controls Section
                            if (isCR) ...[
                              const SizedBox(height: 20),
                              Center(
                                child: Text(
                                  'CR Controls (Change Class Status)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  runAlignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _buildStatusActionChip(
                                      label: 'Upcoming',
                                      color: Colors.lightBlueAccent,
                                      icon: Icons.schedule_rounded,
                                      onTap: () => _updateStatus(
                                          context, ctx, cls, 'upcoming'),
                                    ),
                                    _buildStatusActionChip(
                                      label: 'Completed',
                                      color: const Color(0xFF00E676),
                                      icon: Icons.check_circle_rounded,
                                      onTap: () => _updateStatus(
                                          context, ctx, cls, 'completed'),
                                    ),
                                    _buildStatusActionChip(
                                      label: 'Cancelled',
                                      color: const Color(0xFFFF5252),
                                      icon: Icons.cancel_rounded,
                                      onTap: () => _updateStatus(
                                          context, ctx, cls, 'cancelled'),
                                    ),
                                    _buildStatusActionChip(
                                      label: 'No Class',
                                      color: const Color(0xFFFFD700),
                                      icon: Icons.block_rounded,
                                      onTap: () => _updateStatus(
                                          context, ctx, cls, 'no class'),
                                    ),
                                    _buildStatusActionChip(
                                      label: 'Edit',
                                      color: const Color(0xFFE040FB),
                                      icon: Icons.edit_rounded,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ScheduleBuilderScreen(
                                              classToEdit: cls,
                                              customSlots: customSlots,
                                              user: user,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    _buildStatusActionChip(
                                      label: 'Delete Slot',
                                      color: const Color(0xFFFF3D00),
                                      icon: Icons.delete_forever_rounded,
                                      onTap: () =>
                                          _deleteClass(context, ctx, cls),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5)),
      ],
    );
  }

  Widget _buildStatusActionChip({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8.5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.85), width: 1.3),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 10,
                spreadRadius: 0.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 15.5),
              const SizedBox(width: 6.5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameScheduledDate(dynamic rawDate, DateTime? targetDate) {
    if (rawDate == null && targetDate == null) return true;
    if (rawDate == null || targetDate == null) return false;
    DateTime? d;
    if (rawDate is Timestamp) {
      d = rawDate.toDate();
    } else if (rawDate is String) {
      d = DateTime.tryParse(rawDate);
    }
    if (d == null) return false;
    return d.year == targetDate.year &&
        d.month == targetDate.month &&
        d.day == targetDate.day;
  }

  Future<void> _updateStatus(
      BuildContext parentContext, BuildContext sheetContext, ClassSchedule cls, String status) async {
    if (sheetContext.mounted) {
      Navigator.pop(sheetContext); // close bottom sheet
    }
    final user = Provider.of<AppUser?>(parentContext, listen: false);
    final schedulePath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'schedule')
        : 'schedule';

    try {
      final collectionRef = FirebaseFirestore.instance.collection(schedulePath);

      // Batch update target doc AND any duplicates matching the same day, startSlot, subject, group, and scheduledDate
      final query = await collectionRef
          .where('dayOfWeek', isEqualTo: cls.dayOfWeek)
          .where('startSlot', isEqualTo: cls.startSlot)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool foundTarget = false;

      for (var doc in query.docs) {
        final data = doc.data();
        final String subj = (data['subject'] ?? '').toString().trim();
        final String grp = (data['group'] ?? '').toString().trim();
        final bool dateMatches = _isSameScheduledDate(data['scheduledDate'], cls.scheduledDate);

        if (doc.id == cls.id || (dateMatches && subj == cls.subject.trim() && grp == cls.group.trim())) {
          batch.update(doc.reference, {
            'status': status,
            'lastUpdatedDate': FieldValue.serverTimestamp(),
          });
          foundTarget = true;
        }
      }

      if (!foundTarget) {
        batch.update(collectionRef.doc(cls.id), {
          'status': status,
          'lastUpdatedDate': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (parentContext.mounted) {
        final String statusLabel = status == 'no class'
            ? 'No Class'
            : status.substring(0, 1).toUpperCase() + status.substring(1);
        final Color accentColor = status == 'cancelled'
            ? Colors.redAccent
            : (status == 'completed'
                ? Colors.green
                : (status == 'no class' ? Colors.amberAccent : Colors.blueAccent));

        InAppNotification.show(
          parentContext,
          title: 'Status Updated',
          message: '${cls.subject} status set to $statusLabel.',
          accentColor: accentColor,
          icon: Icons.published_with_changes_rounded,
        );
      }
    } catch (e) {
      debugPrint('Failed to update class status: $e');
      if (parentContext.mounted) {
        InAppNotification.show(
          parentContext,
          title: 'Update Failed',
          message: 'Failed to update status: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _deleteClass(
      BuildContext parentContext, BuildContext sheetContext, ClassSchedule cls) async {
    final user = Provider.of<AppUser?>(parentContext, listen: false);
    final confirm = await showDialog<bool>(
      context: parentContext,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.glassCardBorder)),
        title: Text(
          'Delete Class Schedule?',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete this class from the routine? This slot will become an empty "No Class" space.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext); // Close the bottom sheet safely
      }

      final schedulePath = user != null && user.hasDeptScope
          ? deptBatchCol(user.department, user.batch, 'schedule')
          : 'schedule';

      try {
        final collectionRef =
            FirebaseFirestore.instance.collection(schedulePath);

        // Batch delete target doc AND any duplicates matching the same day, startSlot, subject, group, and scheduledDate
        final query = await collectionRef
            .where('dayOfWeek', isEqualTo: cls.dayOfWeek)
            .where('startSlot', isEqualTo: cls.startSlot)
            .get();

        final batch = FirebaseFirestore.instance.batch();
        bool foundTarget = false;

        for (var doc in query.docs) {
          final data = doc.data();
          final String subj = (data['subject'] ?? '').toString().trim();
          final String grp = (data['group'] ?? '').toString().trim();
          final bool dateMatches =
              _isSameScheduledDate(data['scheduledDate'], cls.scheduledDate);

          if (doc.id == cls.id ||
              (dateMatches &&
                  subj == cls.subject.trim() &&
                  grp == cls.group.trim())) {
            batch.delete(doc.reference);
            foundTarget = true;
          }
        }

        if (!foundTarget) {
          batch.delete(collectionRef.doc(cls.id));
        }

        await batch.commit();

        if (parentContext.mounted) {
          InAppNotification.show(
            parentContext,
            title: 'Class Deleted',
            message: 'Class schedule removed successfully.',
            accentColor: Colors.redAccent,
            icon: Icons.delete_forever_rounded,
          );
        }
      } catch (e) {
        debugPrint('Failed to delete class schedule: $e');
        if (parentContext.mounted) {
          InAppNotification.show(
            parentContext,
            title: 'Delete Failed',
            message: 'Failed to delete class: $e',
            accentColor: Colors.redAccent,
            icon: Icons.error_outline_rounded,
          );
        }
      }
    }
  }
}

// --- Header Section ---
class HeaderBar extends StatelessWidget {
  final String university;
  final String levelTerm;
  final VoidCallback? onDateTap;

  const HeaderBar({
    super.key,
    required this.university,
    required this.levelTerm,
    this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    // Tuesday-15 Jan 2026 format (using EEEE-d MMM yyyy format)
    final formattedDate =
        '(${DateFormat('EEEE-d MMM yyyy').format(DateTime.now())})';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                children: [
                  TextSpan(text: '${university.toUpperCase()} :: '),
                  TextSpan(
                    text: levelTerm.toUpperCase(),
                    style: TextStyle(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDateTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.25),
                  width: 1),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formattedDate,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Micro UI Elements Components ---

class MiniRotatedBreak extends StatelessWidget {
  final String text;
  const MiniRotatedBreak({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.03),
        border: Border.all(
            color: AppColors.secondary.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
      alignment: Alignment.center,
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            text,
            style: TextStyle(
                fontSize: 6.5,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
                letterSpacing: 1.2),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class BlankItem extends StatelessWidget {
  const BlankItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withOpacity(0.005),
        border: Border.all(color: AppColors.textPrimary.withOpacity(0.02)),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
