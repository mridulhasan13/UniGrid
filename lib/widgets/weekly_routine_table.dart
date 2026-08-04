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
import '../widgets/unigrid_loader.dart';
import '../notifications/in_app_notification.dart';
import '../screens/schedule_builder_screen.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';

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
  final weekKey = '${user.department}_${user.batch}_${sundayDate.year}_${sundayDate.month}_${sundayDate.day}';
  if (_autoPopulatedWeeks.contains(weekKey)) return;
  _autoPopulatedWeeks.add(weekKey);

  final defaultPath = deptBatchCol(user.department, user.batch, 'default_schedule');
  final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');

  try {
    final defaultSnap = await FirebaseFirestore.instance.collection(defaultPath).get();
    if (defaultSnap.docs.isEmpty) return;

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
    final schedulePath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'schedule')
        : 'schedule';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(schedulePath).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error loading schedule: ${snapshot.error}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
            child: UniGridLoader(
              title: 'Loading Routine',
              subtitle: 'Rendering weekly class grid...',
              showBackground: false,
            ),
          );
        }

        final rawClasses = (snapshot.data?.docs ?? [])
            .map((doc) => ClassSchedule.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .where((cls) {
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

        if (rawClasses.isEmpty && user != null && user.hasDeptScope) {
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
                        return Expanded(
                          child: Padding(
                            padding:
                                EdgeInsets.only(bottom: idx == 4 ? 0.0 : 4.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.15),
                                    AppColors.secondary.withOpacity(0.04)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                    color: AppColors.primary.withOpacity(0.2)),
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
                                          color: AppColors.textPrimary,
                                          letterSpacing: 0.2),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formattedDate,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 6.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary.withOpacity(0.7),
                                          letterSpacing: 0.1),
                                    ),
                                  ],
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
                            context, [colFlex[1], colFlex[2]], 0, classes, sundayDate),
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
                            classes, sundayDate),
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
                            classes, sundayDate),
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
                  height: 358,
                  width: isMobile ? 920 : double.infinity,
                  child: tableGridContent,
                ),
              ),
            ],
          ),
        );

        final Widget tableCard = ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: useBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: cardContainer,
                )
              : cardContainer,
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
                  maxScale: 2.5,
                  constrained: !isMobile, // Allows panning horizontally & vertically to scroll when not constrained
                  boundaryMargin: const EdgeInsets.all(100), // Gives scroll limits buffer
                  child: SizedBox(
                    width: isMobile ? 920 : null,
                    height: isMobile ? 416 : null,
                    child: tableCard,
                  ),
                ),
              ),
            ),
          ],
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

  Widget _buildPeriodGroupColumn(BuildContext context, List<int> flexWeights,
      int groupIdx, List<ClassSchedule> allClasses, DateTime sundayDate) {
    int columnSumFlex = flexWeights.reduce((a, b) => a + b);
    return Expanded(
      flex: columnSumFlex,
      child: Column(
        children: List.generate(ScheduleConstants.days.length, (rowIdx) {
          final day = ScheduleConstants.days[rowIdx];
          final dayDate = _getDateTimeForDay(sundayDate, day);
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
    } else if (status == 'no class') {
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);
    final isCR = user != null && (user.isCR || user.isAdmin || isRootAdmin);

    final double roomFontSize = stackedCount >= 3 ? 5.0 : (isCompact ? 5.5 : 6.5);
    final double titleFontSize = stackedCount >= 3 ? 6.2 : (isCompact ? 7.0 : 8.0);
    final double verticalPadding = stackedCount >= 3 ? 0.5 : (isCompact ? 1.0 : 3.0);

    return GestureDetector(
      onTap: isCR ? () => _showStatusUpdateDialog(context, cls, user) : null,
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
            Text(
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
            Text(
              status == 'no class'
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

  void _showStatusUpdateDialog(BuildContext context, ClassSchedule cls, AppUser? user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundTop,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).padding.bottom + 48,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update Status: ${cls.subject}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.schedule, color: Colors.blueAccent),
                  title:
                      Text('Upcoming', style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    _updateStatus(context, ctx, cls, 'upcoming');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text('Completed',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    _updateStatus(context, ctx, cls, 'completed');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.redAccent),
                  title: Text('Cancelled',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    _updateStatus(context, ctx, cls, 'cancelled');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.yellowAccent),
                  title:
                      Text('No Class', style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    _updateStatus(context, ctx, cls, 'no class');
                  },
                ),
                Divider(color: AppColors.glassCardBorder),
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.amberAccent),
                  title: Text('Edit Class Details',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                         builder: (context) => ScheduleBuilderScreen(
                          classToEdit: cls,
                          customSlots: customSlots,
                          user: user,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Delete Class (Free Slot)',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    _deleteClass(context, ctx, cls);
                  },
                ),
              ],
            ),
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
      context: sheetContext,
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
