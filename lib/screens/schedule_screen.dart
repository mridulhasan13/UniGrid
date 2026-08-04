import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/weekly_routine_table.dart';
import '../utils/schedule_constants.dart';
import 'schedule_builder_screen.dart';
import 'course_registry_screen.dart';
import '../widgets/glass_card.dart';
import '../widgets/floating_app_bar.dart';
import '../services/auth_service.dart';
import '../notifications/in_app_notification.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  bool _isCalendarExpanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-reset is now triggered on build once we have user context
  }

  DateTime _normalizeStartOfWeek(DateTime date) {
    final sunday = _getSundayOfWeek(date);
    return DateTime(sunday.year, sunday.month, sunday.day);
  }

  // Auto-reset logic: If the last update was in a previous week, reset current/repeating statuses to 'upcoming',
  // and restore past week classes back to 'completed'.
  Future<void> _checkAndAutoResetStatuses(AppUser? user) async {
    if (user == null || !user.hasDeptScope) return;
    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');
    final metaPath = deptBatchCol(user.department, user.batch, 'routine_metadata');
    try {
      final infoDocRef = FirebaseFirestore.instance.collection(metaPath).doc('info');
      final infoDoc = await infoDocRef.get();

      DateTime? lastReset;
      if (infoDoc.exists) {
        final data = infoDoc.data();
        if (data != null && data['lastResetDate'] != null) {
          lastReset = (data['lastResetDate'] as Timestamp).toDate();
        }
      }

      final now = DateTime.now();
      final currentStartOfWeek = _normalizeStartOfWeek(now);
      final lastResetStartOfWeek =
          lastReset != null ? _normalizeStartOfWeek(lastReset) : null;

      final bool isNewWeek = lastResetStartOfWeek == null ||
          currentStartOfWeek.isAfter(lastResetStartOfWeek);

      if (isNewWeek || lastReset == null) {
        final allDocs = await FirebaseFirestore.instance.collection(schedulePath).get();
        final batch = FirebaseFirestore.instance.batch();
        bool needsCommit = false;

        final defaultPath = deptBatchCol(user.department, user.batch, 'default_schedule');
        final defaultSnap = await FirebaseFirestore.instance.collection(defaultPath).get();

        if (defaultSnap.docs.isNotEmpty) {
          bool currentWeekHasClasses = false;
          final normSun = DateTime(currentStartOfWeek.year, currentStartOfWeek.month, currentStartOfWeek.day);
          final normSat = DateTime(currentStartOfWeek.year, currentStartOfWeek.month, currentStartOfWeek.day + 6, 23, 59, 59);

          for (var doc in allDocs.docs) {
            final data = doc.data();
            if (data['scheduledDate'] != null) {
              DateTime? clsDate;
              if (data['scheduledDate'] is Timestamp) {
                clsDate = (data['scheduledDate'] as Timestamp).toDate();
              } else if (data['scheduledDate'] is String) {
                clsDate = DateTime.tryParse(data['scheduledDate']);
              }
              if (clsDate != null) {
                final normCls = DateTime(clsDate.year, clsDate.month, clsDate.day);
                if ((normCls.isAtSameMomentAs(normSun) || normCls.isAfter(normSun)) &&
                    (normCls.isAtSameMomentAs(normSat) || normCls.isBefore(normSat))) {
                  currentWeekHasClasses = true;
                  break;
                }
              }
            }
          }

          if (!currentWeekHasClasses) {
            for (var doc in defaultSnap.docs) {
              final data = doc.data();
              final dayStr = (data['dayOfWeek'] ?? '').toString().trim();
              final dayDate = _getDateTimeForDay(currentStartOfWeek, dayStr);
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
          }
        }

        batch.set(infoDocRef, {
          'lastResetDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await batch.commit();
        debugPrint('Schedule master routine populated for new week.');
      }
    } catch (e) {
      debugPrint('Auto-reset check failed: $e');
    }
  }

  Future<void> _showEditMetadataDialog(BuildContext context, AppUser? user,
      String currentUni, String currentLevelTerm) async {
    final metaPath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'routine_metadata')
        : 'routine_metadata';
    final uniController = TextEditingController(text: currentUni);
    final levelTermController = TextEditingController(text: currentLevelTerm);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        title: Text('Edit Routine Details',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You cannot change the date, but you can edit the university name and level/term below.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: uniController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'University Name',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.3))),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: levelTermController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Level & Term',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.textSecondary.withOpacity(0.3))),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection(metaPath)
                  .doc('info')
                  .set({
                'university': uniController.text.trim(),
                'levelTerm': levelTermController.text.trim(),
              }, SetOptions(merge: true));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child:
                const Text('Save', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditSlotsDialog(BuildContext context, AppUser? user,
      Map<String, dynamic>? currentSlots) async {
    final metaPath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'routine_metadata')
        : 'routine_metadata';
    final List<Map<String, dynamic>> defaultSlots =
        ScheduleConstants.getTimeSlots(currentSlots);
    final Map<String, TextEditingController> controllers = {};
    final Map<String, String> slotTypes = {};
    final Map<String, String> breakDays = {};

    for (var slot in defaultSlots) {
      final slotNum = slot['slot'] as int;
      final isDefaultBreak = slotNum == 0;
      final String key = slotNum == 0
          ? (slot['time'].toString().contains('Tea') ||
                  slot['time'].toString().contains('tea')
              ? 'break_tea'
              : 'break_lunch')
          : 'slot_$slotNum';

      controllers[key] = TextEditingController(text: slot['time']);
      slotTypes[key] = slot['type'] ?? (isDefaultBreak ? 'Break' : 'Class');
      breakDays[key] = slot['breakDays'] ?? 'All Days';
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: AppColors.glassCardColor.withOpacity(0.88),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.glassCardBorder,
                  width: 1.5,
                ),
                boxShadow: AppStyles.emeraldGlow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.edit_calendar_rounded,
                                  color: AppColors.secondary, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Edit Time Slots',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Configure timing, type, and breaks',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: Icon(Icons.close_rounded,
                                  color: AppColors.textSecondary),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(color: AppColors.glassCardBorder, height: 1),
                        const SizedBox(height: 16),

                        // Scrollable content
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: defaultSlots.map((slot) {
                                final slotNum = slot['slot'] as int;
                                final String key = slotNum == 0
                                    ? (slot['time'].toString().contains('Tea') ||
                                            slot['time'].toString().contains('tea')
                                        ? 'break_tea'
                                        : 'break_lunch')
                                    : 'slot_$slotNum';

                                final String label = slotNum == 0
                                    ? (slot['time'].toString().contains('Tea') ||
                                            slot['time'].toString().contains('tea')
                                        ? 'Tea Break Time'
                                        : 'Lunch Break Time')
                                    : 'Slot $slotNum Time';

                                final currentType = slotTypes[key]!;
                                String currentBreakDays = breakDays[key]!;
                                if (!['All Days', ...ScheduleConstants.days]
                                    .contains(currentBreakDays)) {
                                  currentBreakDays = 'All Days';
                                }

                                final isTeaBreak = label.contains('Tea');
                                final isLunchBreak = label.contains('Lunch');

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.textPrimary.withOpacity(0.015),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: AppColors.glassCardBorder
                                            .withOpacity(0.4)),
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextField(
                                        controller: controllers[key],
                                        style: TextStyle(
                                            color: AppColors.textPrimary, fontSize: 13.5),
                                        decoration: InputDecoration(
                                          labelText: label,
                                          labelStyle: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12),
                                          prefixIcon: Icon(
                                            isTeaBreak
                                                ? Icons.coffee_rounded
                                                : isLunchBreak
                                                    ? Icons.restaurant_rounded
                                                    : Icons.access_time_rounded,
                                            color: AppColors.primary,
                                            size: 18,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color:
                                                    AppColors.glassCardBorder),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: AppColors
                                                    .glassCardBorder
                                                    .withOpacity(0.4)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: AppColors.secondary,
                                                width: 1.5),
                                          ),
                                          filled: true,
                                          fillColor:
                                              AppColors.textPrimary.withOpacity(0.01),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: DropdownButtonFormField<
                                                String>(
                                              value: currentType,
                                              decoration: InputDecoration(
                                                labelText: 'Type',
                                                labelStyle: TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 11),
                                                border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12)),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                      color: AppColors
                                                          .glassCardBorder
                                                          .withOpacity(0.4)),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                      color:
                                                          AppColors.secondary,
                                                      width: 1.5),
                                                ),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                              ),
                                              dropdownColor:
                                                  AppColors.backgroundTop,
                                              items: ['Class', 'Break']
                                                  .map((type) {
                                                return DropdownMenuItem(
                                                  value: type,
                                                  child: Text(type,
                                                      style: TextStyle(
                                                          color: AppColors.textPrimary,
                                                          fontSize: 13)),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                setDialogState(() {
                                                  slotTypes[key] = val!;
                                                });
                                              },
                                            ),
                                          ),
                                          if (currentType == 'Break') ...[
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: DropdownButtonFormField<
                                                  String>(
                                                value: currentBreakDays,
                                                decoration: InputDecoration(
                                                  labelText: 'Days as Break',
                                                  labelStyle: TextStyle(
                                                      color: AppColors.textSecondary,
                                                      fontSize: 11),
                                                  border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12)),
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide: BorderSide(
                                                        color: AppColors
                                                            .glassCardBorder
                                                            .withOpacity(0.4)),
                                                  ),
                                                  focusedBorder:
                                                      OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    borderSide: BorderSide(
                                                        color:
                                                            AppColors.secondary,
                                                        width: 1.5),
                                                  ),
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 8),
                                                ),
                                                dropdownColor:
                                                    AppColors.backgroundTop,
                                                items: [
                                                  'All Days',
                                                  ...ScheduleConstants.days
                                                ].map((day) {
                                                  return DropdownMenuItem(
                                                    value: day,
                                                    child: Text(day,
                                                        style: TextStyle(
                                                            color: AppColors.textPrimary,
                                                            fontSize: 12)),
                                                  );
                                                }).toList(),
                                                onChanged: (val) {
                                                  setDialogState(() {
                                                    breakDays[key] = val!;
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(color: AppColors.glassCardBorder, height: 1),
                        const SizedBox(height: 16),

                        // Action Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Cancel',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5)),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.secondary
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () async {
                                  final Map<String, dynamic> updatedSlots = {};
                                  controllers.forEach((key, controller) {
                                    updatedSlots[key] = {
                                      'time': controller.text.trim(),
                                      'type': slotTypes[key],
                                      'breakDays': breakDays[key],
                                    };
                                  });

                                  await FirebaseFirestore.instance
                                      .collection(metaPath)
                                      .doc('slots')
                                      .set(updatedSlots, SetOptions(merge: true));

                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.save_rounded,
                                        color: AppColors.onPrimary, size: 16),
                                    SizedBox(width: 6),
                                    Text(
                                      'Save Slots',
                                      style: TextStyle(
                                          color: AppColors.onPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        ),
      );
  }

  Future<void> _showResetConfirmationDialog(
      BuildContext context, AppUser? user) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final schedulePath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'schedule')
        : 'schedule';
    final metaPath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'routine_metadata')
        : 'routine_metadata';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        title: const Text('Reset Routine Data',
            style: TextStyle(
                color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you absolutely sure you want to reset all schedule routine data?\n\n'
          'This action will:\n'
          '• Delete ALL added classes in the routine.\n'
          '• Reset all custom time slots and break definitions back to BUTEX defaults.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog

              try {
                // 1. Delete all documents in the schedule collection
                final allDocs = await FirebaseFirestore.instance
                    .collection(schedulePath)
                    .get();
                final batch = FirebaseFirestore.instance.batch();
                for (var doc in allDocs.docs) {
                  batch.delete(doc.reference);
                }
                await batch.commit();

                // 2. Reset routine_metadata documents
                await FirebaseFirestore.instance
                    .collection(metaPath)
                    .doc('slots')
                    .delete();

                await FirebaseFirestore.instance
                    .collection(metaPath)
                    .doc('info')
                    .set({
                  'university': 'Bangladesh University of Textiles',
                  'levelTerm': 'Level-1 Term-2',
                });

                InAppNotification.show(
                  context,
                  title: 'Routine Reset',
                  message: 'Routine successfully reset to factory defaults!',
                  accentColor: Colors.green,
                  icon: Icons.restart_alt_rounded,
                );
              } catch (e) {
                InAppNotification.show(
                  context,
                  title: 'Reset Failed',
                  message: 'Failed to reset: $e',
                  accentColor: Colors.redAccent,
                  icon: Icons.error_outline_rounded,
                );
              }
            },
            child: const Text('Reset',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }



  Future<void> _saveAsDefaultRoutine(BuildContext context, AppUser? user) async {
    if (user == null || !user.hasDeptScope) return;
    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');
    final defaultPath = deptBatchCol(user.department, user.batch, 'default_schedule');

    try {
      final activeDocs = await FirebaseFirestore.instance.collection(schedulePath).get();
      if (activeDocs.docs.isEmpty) {
        if (context.mounted) {
          InAppNotification.show(
            context,
            title: 'No Routine to Save',
            message: 'Your active schedule is currently empty.',
            accentColor: Colors.amberAccent,
            icon: Icons.warning_amber_rounded,
          );
        }
        return;
      }

      final sundayDate = _getSundayOfWeek(_selectedDate);
      final saturdayDate = sundayDate.add(const Duration(days: 6));
      final normSun = DateTime(sundayDate.year, sundayDate.month, sundayDate.day);
      final normSat = DateTime(saturdayDate.year, saturdayDate.month, saturdayDate.day);

      // Filter classes for active week and de-duplicate unique slots
      final Map<String, Map<String, dynamic>> uniqueActiveWeekDocs = {};

      for (var doc in activeDocs.docs) {
        final data = doc.data();
        DateTime? clsDate;
        if (data['scheduledDate'] != null) {
          if (data['scheduledDate'] is Timestamp) {
            clsDate = (data['scheduledDate'] as Timestamp).toDate();
          } else if (data['scheduledDate'] is String) {
            clsDate = DateTime.tryParse(data['scheduledDate']);
          }
        }

        bool isCurrentWeek = true;
        if (clsDate != null) {
          final normCls = DateTime(clsDate.year, clsDate.month, clsDate.day);
          isCurrentWeek = (normCls.isAtSameMomentAs(normSun) || normCls.isAfter(normSun)) &&
                          (normCls.isAtSameMomentAs(normSat) || normCls.isBefore(normSat));
        }

        if (isCurrentWeek) {
          final dayOfWeek = (data['dayOfWeek'] ?? '').toString().trim();
          final startSlot = data['startSlot'] ?? 1;
          final subject = (data['subject'] ?? '').toString().trim();
          final group = (data['group'] ?? '').toString().trim();
          final teacher = (data['teacher'] ?? '').toString().trim();
          final room = (data['room'] ?? '').toString().trim();

          final key = '${dayOfWeek}_${startSlot}_${subject}_${group}_${teacher}_${room}';
          uniqueActiveWeekDocs[key] = data;
        }
      }

      if (uniqueActiveWeekDocs.isEmpty) {
        if (context.mounted) {
          InAppNotification.show(
            context,
            title: 'No Routine for Active Week',
            message: 'No class entries found for the selected week.',
            accentColor: Colors.amberAccent,
            icon: Icons.info_outline_rounded,
          );
        }
        return;
      }

      final currentDefaultDocs = await FirebaseFirestore.instance.collection(defaultPath).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in currentDefaultDocs.docs) {
        batch.delete(doc.reference);
      }

      for (var data in uniqueActiveWeekDocs.values) {
        final newRef = FirebaseFirestore.instance.collection(defaultPath).doc();
        batch.set(newRef, {
          'subject': data['subject'] ?? '',
          'subname': data['subname'] ?? '',
          'room': data['room'] ?? '',
          'teacher': data['teacher'] ?? '',
          'time': data['time'] ?? '',
          'dayOfWeek': data['dayOfWeek'] ?? '',
          'startSlot': data['startSlot'] ?? 1,
          'span': data['span'] ?? 1,
          'group': data['group'] ?? '',
          'status': 'upcoming',
          'lastUpdatedDate': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (context.mounted) {
        InAppNotification.show(
          context,
          title: 'Default Routine Saved',
          message: 'Saved ${uniqueActiveWeekDocs.length} unique class slot(s) for the active week as your Default Routine template!',
          accentColor: Colors.greenAccent,
          icon: Icons.bookmark_added_rounded,
        );
      }
    } catch (e) {
      if (context.mounted) {
        InAppNotification.show(
          context,
          title: 'Save Failed',
          message: 'Failed to save default routine: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _showApplyDefaultRoutineDialog(BuildContext context, AppUser? user) async {
    if (user == null || !user.hasDeptScope) return;
    final defaultPath = deptBatchCol(user.department, user.batch, 'default_schedule');
    final initialDay = _getDayOfWeekName(_selectedDate);

    try {
      final defaultDocs = await FirebaseFirestore.instance.collection(defaultPath).get();
      if (defaultDocs.docs.isEmpty) {
        if (context.mounted) {
          InAppNotification.show(
            context,
            title: 'No Default Routine',
            message: 'No saved default routine found. Set up your routine and click "Save as Default Routine" first.',
            accentColor: Colors.amberAccent,
            icon: Icons.info_outline_rounded,
          );
        }
        return;
      }

      final daysList = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      String chosenDay = daysList.contains(initialDay) ? initialDay : 'Sunday';

      if (!context.mounted) return;

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            final int dayItemCount = defaultDocs.docs
                .where((d) => (d.data()['dayOfWeek'] ?? '').toString().trim().toLowerCase() == chosenDay.toLowerCase())
                .length;

            return AlertDialog(
              backgroundColor: AppColors.backgroundTop,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.glassCardBorder),
              ),
              title: Row(
                children: [
                  Icon(Icons.published_with_changes_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Apply Default Routine',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose a day or apply the template to the entire week:',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'SELECT TARGET DAY',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.glassCardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.glassCardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: chosenDay,
                          isExpanded: true,
                          dropdownColor: AppColors.backgroundTop,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                          items: daysList.map((day) {
                            final count = defaultDocs.docs
                                .where((d) => (d.data()['dayOfWeek'] ?? '').toString().trim().toLowerCase() == day.toLowerCase())
                                .length;
                            return DropdownMenuItem<String>(
                              value: day,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(day),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$count slot(s)',
                                      style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                chosenDay = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.today_rounded, color: Colors.blueAccent, size: 20),
                        ),
                        title: Text('Apply for $chosenDay only',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Replaces $chosenDay\'s active classes ($dayItemCount slot(s) in template)',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _applyDefaultRoutine(context, user, targetDay: chosenDay);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00E676).withOpacity(0.18)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF00E676), size: 20),
                        ),
                        title: Text('Apply Entire Default Week',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Replaces active routine for ALL days (${defaultDocs.docs.length} total slot(s))',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _applyDefaultRoutine(context, user, targetDay: null);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (context.mounted) {
        InAppNotification.show(
          context,
          title: 'Load Failed',
          message: 'Failed to load default routine: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
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
    final target = sundayDate.add(Duration(days: daysOffset));
    return DateTime(target.year, target.month, target.day);
  }

  Future<void> _applyDefaultRoutine(BuildContext context, AppUser user, {String? targetDay}) async {
    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');
    final defaultPath = deptBatchCol(user.department, user.batch, 'default_schedule');

    try {
      final defaultSnap = await FirebaseFirestore.instance.collection(defaultPath).get();
      final activeSnap = await FirebaseFirestore.instance.collection(schedulePath).get();

      final sundayDate = _getSundayOfWeek(_selectedDate);
      final normSun = DateTime(sundayDate.year, sundayDate.month, sundayDate.day);
      final normSat = DateTime(sundayDate.year, sundayDate.month, sundayDate.day + 6, 23, 59, 59);

      final batch = FirebaseFirestore.instance.batch();

      if (targetDay != null && targetDay.isNotEmpty) {
        final targetDayLower = targetDay.trim().toLowerCase();
        final targetDate = _getDateTimeForDay(sundayDate, targetDay);

        for (var doc in activeSnap.docs) {
          final data = doc.data();
          DateTime? clsDate;
          if (data['scheduledDate'] != null) {
            if (data['scheduledDate'] is Timestamp) {
              clsDate = (data['scheduledDate'] as Timestamp).toDate();
            } else if (data['scheduledDate'] is String) {
              clsDate = DateTime.tryParse(data['scheduledDate']);
            }
          }

          final day = (data['dayOfWeek'] ?? '').toString().trim().toLowerCase();
          bool isSameTargetDay = day == targetDayLower;
          bool isInTargetWeek = clsDate == null ||
              (clsDate.isAfter(normSun.subtract(const Duration(seconds: 1))) &&
               clsDate.isBefore(normSat.add(const Duration(seconds: 1))));

          if (isSameTargetDay && isInTargetWeek) {
            batch.delete(doc.reference);
          }
        }

        for (var doc in defaultSnap.docs) {
          final data = doc.data();
          final day = (data['dayOfWeek'] ?? '').toString().trim().toLowerCase();
          if (day == targetDayLower) {
            final newRef = FirebaseFirestore.instance.collection(schedulePath).doc();
            batch.set(newRef, {
              'subject': data['subject'] ?? '',
              'subname': data['subname'] ?? '',
              'room': data['room'] ?? '',
              'teacher': data['teacher'] ?? '',
              'time': data['time'] ?? '',
              'dayOfWeek': data['dayOfWeek'] ?? targetDay,
              'startSlot': data['startSlot'] ?? 1,
              'span': data['span'] ?? 1,
              'group': data['group'] ?? '',
              'status': 'upcoming',
              'scheduledDate': Timestamp.fromDate(targetDate),
              'lastUpdatedDate': FieldValue.serverTimestamp(),
            });
          }
        }

        await batch.commit();

        if (context.mounted) {
          InAppNotification.show(
            context,
            title: 'Day Routine Applied',
            message: 'Applied default routine for $targetDay (${DateFormat('d MMM').format(targetDate)})!',
            accentColor: Colors.blueAccent,
            icon: Icons.today_rounded,
          );
        }
      } else {
        for (var doc in activeSnap.docs) {
          final data = doc.data();
          DateTime? clsDate;
          if (data['scheduledDate'] != null) {
            if (data['scheduledDate'] is Timestamp) {
              clsDate = (data['scheduledDate'] as Timestamp).toDate();
            } else if (data['scheduledDate'] is String) {
              clsDate = DateTime.tryParse(data['scheduledDate']);
            }
          }

          bool isInActiveWeek = clsDate == null ||
              (clsDate.isAfter(normSun.subtract(const Duration(seconds: 1))) &&
               clsDate.isBefore(normSat.add(const Duration(seconds: 1))));

          if (isInActiveWeek) {
            batch.delete(doc.reference);
          }
        }

        for (var doc in defaultSnap.docs) {
          final data = doc.data();
          final dayStr = (data['dayOfWeek'] ?? '').toString().trim();
          final dayDate = _getDateTimeForDay(sundayDate, dayStr);
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

        if (context.mounted) {
          InAppNotification.show(
            context,
            title: 'Week Routine Applied',
            message: 'Applied default routine for week of ${DateFormat('d MMM').format(sundayDate)}!',
            accentColor: Colors.greenAccent,
            icon: Icons.published_with_changes_rounded,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        InAppNotification.show(
          context,
          title: 'Apply Failed',
          message: 'Failed to apply default routine: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  PopupMenuItem<String> _buildDynamicMenuItem({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    Color? accentColor,
    bool isDestructive = false,
  }) {
    final effectiveColor = isDestructive
        ? const Color(0xFFFF453A)
        : (accentColor ?? AppColors.primary);

    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDestructive
              ? const Color(0xFFFF453A).withOpacity(0.08)
              : effectiveColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDestructive
                ? const Color(0xFFFF453A).withOpacity(0.28)
                : effectiveColor.withOpacity(0.18),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: effectiveColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: effectiveColor.withOpacity(0.12),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(icon, color: effectiveColor, size: 15),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDestructive
                          ? const Color(0xFFFF453A)
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.75),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: effectiveColor.withOpacity(0.4),
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);
    final isCR = user != null && (user.isCR || user.isAdmin || isRootAdmin);

    // Run auto-reset once per build session when user is available
    if (user != null && user.hasDeptScope) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoResetStatuses(user);
      });
    }

    // If no dept scope, show setup needed
    if (user != null && !user.hasDeptScope) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  height: 48,
                ),
                const SizedBox(height: 16),
                const Text('Department not set',
                    style: AppStyles.heading2, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Please complete your profile to view your schedule.',
                    style: AppStyles.caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final metaPath = user != null
        ? deptBatchCol(user.department, user.batch, 'routine_metadata')
        : 'routine_metadata';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(metaPath)
          .doc('info')
          .snapshots(),
      builder: (context, metaSnapshot) {
        String university = 'Bangladesh University of Textiles';
        String levelTerm = 'Level-1 Term-2';

        if (metaSnapshot.hasData && metaSnapshot.data!.exists) {
          final data = metaSnapshot.data!.data() as Map<String, dynamic>;
          university = data['university'] ?? university;
          levelTerm = data['levelTerm'] ?? levelTerm;
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection(metaPath)
              .doc('slots')
              .snapshots(),
          builder: (context, slotsSnapshot) {
            final customSlots =
                slotsSnapshot.hasData && slotsSnapshot.data!.exists
                    ? slotsSnapshot.data!.data() as Map<String, dynamic>
                    : null;

            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: null,
              body: Container(
                decoration: BoxDecoration(
                  gradient: AppGradients.mainBackground,
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FloatingAppBar(
                        title: 'Weekly Routine',
                        actions: [
                          IconButton(
                            icon: Icon(Icons.menu_book, color: AppColors.textSecondary),
                            tooltip: 'Course & Teacher Registry',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CourseRegistryScreen(),
                                ),
                              );
                            },
                          ),
                          if (isCR)
                            PopupMenuButton<String>(
                              tooltip: 'Routine Options',
                              elevation: 16,
                              shadowColor: AppColors.primary.withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color: AppColors.primary.withOpacity(0.35),
                                    width: 1.5),
                              ),
                              color: AppColors.backgroundTop.withOpacity(0.96),
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: AppColors.primary.withOpacity(0.35)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.2),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.tune_rounded,
                                    color: AppColors.primary, size: 18),
                              ),
                              onSelected: (value) {
                                if (value == 'edit_meta') {
                                  _showEditMetadataDialog(
                                      context, user, university, levelTerm);
                                } else if (value == 'edit_slots') {
                                  _showEditSlotsDialog(context, user, customSlots);
                                } else if (value == 'add_class') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ScheduleBuilderScreen(
                                        customSlots: customSlots,
                                        initialDayOfWeek:
                                            _getDayOfWeekName(_selectedDate),
                                        user: user,
                                        selectedDate: _selectedDate,
                                      ),
                                    ),
                                  );
                                } else if (value == 'save_default') {
                                  _saveAsDefaultRoutine(context, user);
                                } else if (value == 'apply_default') {
                                  _showApplyDefaultRoutineDialog(context, user);
                                } else if (value == 'copy_prev_week') {
                                  _copyFromPreviousWeek(context, user);
                                } else if (value == 'clear_data') {
                                  _showResetConfirmationDialog(context, user);
                                }
                              },
                              itemBuilder: (context) => [
                                _buildDynamicMenuItem(
                                  value: 'edit_meta',
                                  title: 'Edit Routine Details',
                                  subtitle: 'University & Level/Term metadata',
                                  icon: Icons.edit_note_rounded,
                                ),
                                _buildDynamicMenuItem(
                                  value: 'edit_slots',
                                  title: 'Edit Time Slots',
                                  subtitle: 'Durations, breaks & custom slots',
                                  icon: Icons.schedule_rounded,
                                ),
                                _buildDynamicMenuItem(
                                  value: 'add_class',
                                  title: 'Add New Class',
                                  subtitle: 'Schedule a new class slot',
                                  icon: Icons.add_circle_outline_rounded,
                                ),
                                _buildDynamicMenuItem(
                                  value: 'save_default',
                                  title: 'Save as Default Routine',
                                  subtitle: 'Save active schedule as master template',
                                  icon: Icons.bookmark_added_rounded,
                                ),
                                _buildDynamicMenuItem(
                                  value: 'apply_default',
                                  title: 'Apply Default Routine...',
                                  subtitle: 'Restore template for day or full week',
                                  icon: Icons.published_with_changes_rounded,
                                ),
                                _buildDynamicMenuItem(
                                  value: 'copy_prev_week',
                                  title: 'Copy from Previous Week',
                                  subtitle: 'Duplicate last week\'s schedule',
                                  icon: Icons.content_copy_rounded,
                                ),
                                _buildDynamicMenuItem(
                                  value: 'clear_data',
                                  title: 'Reset Routine Data',
                                  subtitle: 'Wipe all routine schedule entries',
                                  icon: Icons.delete_forever_rounded,
                                  isDestructive: true,
                                ),
                              ],
                            ),
                        ],
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double availableHeight = constraints.maxHeight;
                            final double calendarHeight = _isCalendarExpanded ? 340 : 54;
                            final double tableHeight = (availableHeight - calendarHeight - 8 - 80).clamp(425.0, 1000.0);

                            return SingleChildScrollView(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: 16.0,
                                  right: 16.0,
                                  top: 8.0,
                                  bottom: MediaQuery.of(context).padding.bottom + 80,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildDateCalendarCard(user, customSlots),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: tableHeight,
                                      child: WeeklyRoutineTable(
                                        customSlots: customSlots,
                                        university: university,
                                        levelTerm: levelTerm,
                                        selectedDate: _selectedDate,
                                        onDateTap: () {
                                          setState(() {
                                            _isCalendarExpanded = !_isCalendarExpanded;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  },
);
},
);
}

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

  Future<void> _copyFromPreviousWeek(BuildContext context, AppUser? user) async {
    if (user == null || !user.hasDeptScope) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');

    // Calculate dates and normalize to midnight
    final rawSunday = _getSundayOfWeek(_selectedDate);
    final targetSunday = DateTime(rawSunday.year, rawSunday.month, rawSunday.day);
    final targetSaturday = targetSunday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final prevSunday = targetSunday.subtract(const Duration(days: 7));
    final prevSaturday = prevSunday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final String prevWeekStr = DateFormat('d MMM').format(prevSunday) + ' - ' + DateFormat('d MMM').format(prevSaturday);
    final String currentWeekStr = DateFormat('d MMM').format(targetSunday) + ' - ' + DateFormat('d MMM').format(targetSaturday);

    // 1. Confirm with the user
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        title: const Text('Copy Previous Week\'s Schedule',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Do you want to copy all scheduled classes from the previous week ($prevWeekStr) '
          'to the selected week ($currentWeekStr)?\n\n'
          'Warning: This will overwrite/replace any classes already scheduled for the selected week.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copy Schedule', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.backgroundTop,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Copying schedule...', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            ],
          ),
        ),
      ),
    );

    try {
      // 2. Fetch classes from the previous week
      final prevQuery = await FirebaseFirestore.instance
          .collection(schedulePath)
          .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(prevSunday))
          .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(prevSaturday))
          .get();

      if (prevQuery.docs.isEmpty) {
        // Close loading dialog
        if (context.mounted) Navigator.pop(context);
        
        InAppNotification.show(
          context,
          title: 'No Classes Found',
          message: 'No classes found in the previous week ($prevWeekStr) to copy.',
          accentColor: Colors.amber,
          icon: Icons.calendar_today_rounded,
        );
        return;
      }

      // 3. Fetch and delete classes from the current week
      final currentQuery = await FirebaseFirestore.instance
          .collection(schedulePath)
          .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(targetSunday))
          .where('scheduledDate', isLessThanOrEqualTo: Timestamp.fromDate(targetSaturday))
          .get();

      final batch = FirebaseFirestore.instance.batch();

      // Delete existing classes in target week to prevent duplicates
      for (var doc in currentQuery.docs) {
        batch.delete(doc.reference);
      }

      // Copy previous week's classes to current week
      for (var doc in prevQuery.docs) {
        final data = doc.data();
        
        // Update the scheduledDate to be 7 days forward
        if (data['scheduledDate'] != null) {
          final oldDate = (data['scheduledDate'] as Timestamp).toDate();
          final newDate = oldDate.add(const Duration(days: 7));
          data['scheduledDate'] = Timestamp.fromDate(newDate);
        }

        // Set status to upcoming for the new week
        data['status'] = 'upcoming';
        data['lastUpdatedDate'] = FieldValue.serverTimestamp();

        // Add to batch (generate a new document ID)
        final newDocRef = FirebaseFirestore.instance.collection(schedulePath).doc();
        batch.set(newDocRef, data);
      }

      await batch.commit();

      // Close loading dialog
      if (context.mounted) Navigator.pop(context);

      InAppNotification.show(
        context,
        title: 'Schedule Copied',
        message: 'Successfully copied ${prevQuery.docs.length} classes to the selected week!',
        accentColor: Colors.green,
        icon: Icons.content_copy_rounded,
      );
    } catch (e) {
      // Close loading dialog
      if (context.mounted) Navigator.pop(context);

      InAppNotification.show(
        context,
        title: 'Copy Failed',
        message: 'Failed to copy schedule: $e',
        accentColor: Colors.redAccent,
        icon: Icons.error_outline_rounded,
      );
    }
  }

  String _getDayOfWeekName(DateTime date) {
    switch (date.weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  int _getDaysInMonth(int year, int month) {
    if (month == 2) {
      final bool isLeap =
          (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return isLeap ? 29 : 28;
    }
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month - 1];
  }

  Widget _buildDateCalendarCard(
      AppUser? user, Map<String, dynamic>? customSlots) {
    final String monthName = DateFormat('MMMM yyyy').format(_focusedMonth);
    final String selectedDateStr =
        DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);

    if (!_isCalendarExpanded) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _isCalendarExpanded = true;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassCardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    '($monthName)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'Tap to open calendar',
                    style: TextStyle(
                      color: AppColors.textPrimary.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary, size: 18),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassCardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Universal Calendar',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.keyboard_arrow_up_rounded,
                    color: AppColors.primary, size: 20),
                onPressed: () {
                  setState(() {
                    _isCalendarExpanded = false;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.chevron_left,
                    color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  setState(() {
                    _focusedMonth =
                        DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                  });
                },
              ),
              Text(
                monthName,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20),
                onPressed: () {
                  setState(() {
                    _focusedMonth =
                        DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children:
                        ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map((d) {
                      return SizedBox(
                        width: 28,
                        child: Text(
                          d,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.primary.withOpacity(0.7),
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                  _buildCalendarDays(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: AppColors.textPrimary.withOpacity(0.08)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  selectedDateStr,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: [
                  if (user != null && user.isCR) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ScheduleBuilderScreen(
                              customSlots: customSlots,
                              initialDayOfWeek:
                                  _getDayOfWeekName(_selectedDate),
                              user: user,
                              selectedDate: _selectedDate,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.blueAccent.withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                color: Colors.blueAccent, size: 10),
                            SizedBox(width: 2),
                            Text(
                              'Schedule Class',
                              style: TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Text(
                      _getDayOfWeekName(_selectedDate).toUpperCase(),
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDateClassesList(user, customSlots),
        ],
      ),
    );
  }

  Widget _buildCalendarDays() {
    final DateTime firstDay =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final int offset = firstDay.weekday == 7 ? 0 : firstDay.weekday;
    final int totalDays =
        _getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    final int totalItems = offset + totalDays;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.0,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < offset) {
          return const SizedBox.shrink();
        }

        final int day = index - offset + 1;
        final DateTime date =
            DateTime(_focusedMonth.year, _focusedMonth.month, day);
        final DateTime now = DateTime.now();
        final bool isToday = date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
        final bool isSelected = date.year == _selectedDate.year &&
            date.month == _selectedDate.month &&
            date.day == _selectedDate.day;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = date;
            });
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.25)
                  : (isToday
                      ? AppColors.textPrimary.withOpacity(0.04)
                      : Colors.transparent),
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: AppColors.primary, width: 1.2)
                  : (isToday
                      ? Border.all(
                          color: Colors.greenAccent.withOpacity(0.6),
                          width: 1.0)
                      : null),
            ),
            child: Text(
              '$day',
              style: TextStyle(
                color: isSelected
                    ? AppColors.textPrimary
                    : (isToday ? Colors.greenAccent : AppColors.textSecondary),
                fontWeight:
                    isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateClassesList(
      AppUser? user, Map<String, dynamic>? customSlots) {
    final String dayOfWeekName = _getDayOfWeekName(_selectedDate);
    final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);
    final isCR = user != null && (user.isCR || user.isAdmin || isRootAdmin);

    final schedulePath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'schedule')
        : 'schedule';
    final overridesPath = user != null && user.hasDeptScope
        ? deptBatchCol(user.department, user.batch, 'schedule_overrides')
        : 'schedule_overrides';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(schedulePath)
          .where('dayOfWeek', isEqualTo: dayOfWeekName)
          .snapshots(),
      builder: (context, scheduleSnap) {
        if (scheduleSnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final rawClasses = (scheduleSnap.data?.docs ?? [])
            .map((doc) => ClassSchedule.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .where((c) {
              if (c.scheduledDate != null) {
                return c.scheduledDate!.year == _selectedDate.year &&
                    c.scheduledDate!.month == _selectedDate.month &&
                    c.scheduledDate!.day == _selectedDate.day;
              }
              return true;
            })
            .toList();

        rawClasses.sort((a, b) => a.startSlot.compareTo(b.startSlot));

        if (rawClasses.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withOpacity(0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.textPrimary.withOpacity(0.04)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.weekend_rounded, color: AppColors.glassCardBorder, size: 24),
                  SizedBox(height: 4),
                  Text(
                    'No classes scheduled for this day.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection(overridesPath)
              .doc(dateStr)
              .snapshots(),
          builder: (context, overrideSnap) {
            final Map<String, dynamic> overrides =
                overrideSnap.hasData && overrideSnap.data!.exists
                    ? overrideSnap.data!.data() as Map<String, dynamic>
                    : {};

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rawClasses.length,
              itemBuilder: (context, i) {
                final cls = rawClasses[i];
                String displayStatus = cls.status;
                bool isOverridden = false;
                if (overrides.containsKey(cls.id) && overrides[cls.id] is Map) {
                  final overrideData = overrides[cls.id] as Map;
                  if (overrideData.containsKey('status')) {
                    displayStatus = overrideData['status'] as String;
                    isOverridden = true;
                  }
                }

                Color badgeBgColor;
                Color badgeTextColor;
                String badgeText;

                switch (displayStatus.trim().toLowerCase()) {
                  case 'upcoming':
                    badgeBgColor = Colors.blue.withOpacity(0.15);
                    badgeTextColor = Colors.blueAccent;
                    badgeText = 'Upcoming';
                    break;
                  case 'completed':
                    badgeBgColor = Colors.green.withOpacity(0.15);
                    badgeTextColor = Colors.greenAccent;
                    badgeText = 'Completed';
                    break;
                  case 'cancelled':
                  case 'no_class':
                  case 'no class':
                    badgeBgColor = Colors.amber.withOpacity(0.15);
                    badgeTextColor = Colors.amberAccent;
                    badgeText = 'No Class';
                    break;
                  default:
                    badgeBgColor = AppColors.textPrimary.withOpacity(0.08);
                    badgeTextColor = AppColors.textSecondary;
                    badgeText = displayStatus;
                }

                return Card(
                  color: AppColors.textPrimary.withOpacity(0.03),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: AppColors.textPrimary.withOpacity(0.06)),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cls.subject,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeBgColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: badgeTextColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                                color: badgeTextColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isOverridden) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: Colors.purpleAccent.withOpacity(0.3)),
                            ),
                            child: const Text(
                              'FIXED',
                              style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ]
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cls.subname.isNotEmpty)
                            Text(
                              cls.subname,
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  color: AppColors.textSecondary, size: 12),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${cls.time} (Slot ${cls.startSlot})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.room_rounded,
                                  color: AppColors.textSecondary, size: 12),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  cls.room,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          if (cls.teacher.isNotEmpty ||
                              cls.group.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (cls.teacher.isNotEmpty) ...[
                                  Icon(Icons.person_outline_rounded,
                                      color: AppColors.textSecondary, size: 12),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      cls.teacher,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 11),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (cls.group.isNotEmpty) ...[
                                  Icon(Icons.group_outlined,
                                      color: AppColors.textSecondary, size: 12),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      cls.group,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ]
                        ],
                      ),
                    ),
                    trailing: isCR
                        ? Icon(Icons.edit_calendar_rounded,
                            color: AppColors.textSecondary, size: 20)
                        : null,
                    onTap: isCR
                        ? () => _showOverrideStatusDialog(
                            context,
                            user,
                            overridesPath,
                            dateStr,
                            cls.id,
                            cls.subject,
                            displayStatus)
                        : null,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showOverrideStatusDialog(
      BuildContext context,
      AppUser? user,
      String overridesPath,
      String dateStr,
      String classId,
      String subject,
      String currentStatus) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Fix Class Status - $subject',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set date override status for this class on $dateStr.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _buildDialogStatusOption(ctx, overridesPath, dateStr, classId,
                'Upcoming', 'upcoming', Colors.blueAccent),
            const SizedBox(height: 10),
            _buildDialogStatusOption(ctx, overridesPath, dateStr, classId,
                'Completed', 'completed', Colors.greenAccent),
            const SizedBox(height: 10),
            _buildDialogStatusOption(ctx, overridesPath, dateStr, classId,
                'No Class / Cancelled', 'cancelled', Colors.amberAccent),
            const SizedBox(height: 20),
            Divider(color: AppColors.textPrimary.withOpacity(0.08)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection(overridesPath)
                      .doc(dateStr)
                      .set({
                    classId: FieldValue.delete(),
                  }, SetOptions(merge: true));
                  if (ctx.mounted) Navigator.pop(ctx);
                  InAppNotification.show(
                    context,
                    title: 'Schedule Reset',
                    message: 'Reset to weekly default status.',
                    accentColor: Colors.green,
                    icon: Icons.refresh_rounded,
                  );
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  InAppNotification.show(
                    context,
                    title: 'Reset Failed',
                    message: 'Reset failed: $e',
                    accentColor: Colors.redAccent,
                    icon: Icons.error_outline_rounded,
                  );
                }
              },
              child: Text(
                'Reset to Weekly Default',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogStatusOption(BuildContext dialogCtx, String overridesPath,
      String dateStr, String classId, String label, String value, Color color) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    return ElevatedButton(
      onPressed: () async {
        try {
          await FirebaseFirestore.instance
              .collection(overridesPath)
              .doc(dateStr)
              .set({
            classId: {
              'status': value,
              'updatedAt': FieldValue.serverTimestamp(),
            }
          }, SetOptions(merge: true));
          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
          InAppNotification.show(
            context,
            title: 'Schedule Updated',
            message: 'Successfully set class to "$label" for $dateStr.',
            accentColor: AppColors.primary,
            icon: Icons.edit_calendar_rounded,
          );
        } catch (e) {
          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
          InAppNotification.show(
            context,
            title: 'Override Failed',
            message: 'Override failed: $e',
            accentColor: Colors.redAccent,
            icon: Icons.error_outline_rounded,
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.12),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
