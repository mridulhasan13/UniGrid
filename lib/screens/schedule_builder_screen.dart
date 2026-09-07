import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../utils/schedule_constants.dart';
import '../widgets/glass_card.dart';
import '../notifications/in_app_notification.dart';
import '../notifications/fcm_service.dart';

class ScheduleBuilderScreen extends StatefulWidget {
  final ClassSchedule? classToEdit;
  final Map<String, dynamic>? customSlots;
  final String? initialDayOfWeek;
  final AppUser? user;
  final DateTime? selectedDate;

  const ScheduleBuilderScreen({
    super.key,
    this.classToEdit,
    this.customSlots,
    this.initialDayOfWeek,
    this.user,
    this.selectedDate,
  });

  @override
  State<ScheduleBuilderScreen> createState() => _ScheduleBuilderScreenState();
}

class _ScheduleBuilderScreenState extends State<ScheduleBuilderScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _selectedDay;
  late int _selectedStartSlot;
  late int _selectedSpan;
  late String _selectedGroup;

  final _subjectController = TextEditingController();
  final _teacherController = TextEditingController();
  final _roomController = TextEditingController();

  bool _isLoading = false;
  String? _selectedCourseId;

  final List<String> _groupOptions = ['None', 'Gr: A', 'Gr: B', 'Gr: C'];

  @override
  void initState() {
    super.initState();
    if (widget.classToEdit != null) {
      final cls = widget.classToEdit!;
      _selectedDay = cls.dayOfWeek;
      _selectedStartSlot = cls.startSlot;
      _selectedSpan = cls.span;
      _selectedGroup = cls.group.isEmpty ? 'None' : cls.group;
      if (!_groupOptions.contains(_selectedGroup)) {
        _groupOptions.add(_selectedGroup);
      }
      _subjectController.text = cls.subject;
      _teacherController.text = cls.teacher;
      _roomController.text = cls.room;
    } else {
      _selectedDay = widget.initialDayOfWeek ?? ScheduleConstants.days.first;
      _selectedStartSlot = 1;
      _selectedSpan = 1;
      _selectedGroup = 'None';
    }

    // Fallback if the day is a weekend day (e.g. Friday/Saturday) not in ScheduleConstants.days
    if (!ScheduleConstants.days.contains(_selectedDay)) {
      _selectedDay = ScheduleConstants.days.first;
    }
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

  DateTime _getDateForDayInWeek(DateTime sundayDate, String dayName) {
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
    return sundayDate.add(Duration(days: daysOffset));
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final String timeString = ScheduleConstants.getTimeForSlot(
          _selectedStartSlot, _selectedSpan, widget.customSlots);

      DateTime? targetScheduledDate;
      if (widget.selectedDate != null) {
        targetScheduledDate = widget.selectedDate;
      } else if (widget.classToEdit?.scheduledDate != null) {
        targetScheduledDate = widget.classToEdit!.scheduledDate;
      }

      String defaultStatus = widget.classToEdit?.status ?? 'upcoming';
      if (targetScheduledDate != null && widget.classToEdit == null) {
        final sunday = _getSundayOfWeek(targetScheduledDate);
        final currentSunday = _getSundayOfWeek(DateTime.now());
        if (sunday.isBefore(currentSunday)) {
          defaultStatus = 'completed';
        }
      }

      final Map<String, dynamic> scheduleData = {
        'dayOfWeek': _selectedDay,
        'subject': _subjectController.text.trim(),
        'teacher': _teacherController.text.trim(),
        'room': _roomController.text.trim(),
        'startSlot': _selectedStartSlot,
        'span': _selectedSpan,
        'group': _selectedGroup == 'None' ? '' : _selectedGroup,
        'time': timeString,
        'status': defaultStatus,
        'lastUpdatedDate': FieldValue.serverTimestamp(),
      };

      if (targetScheduledDate != null) {
        final sunday = _getSundayOfWeek(targetScheduledDate);
        final calculatedDate = _getDateForDayInWeek(sunday, _selectedDay);
        final normalized = DateTime(
          calculatedDate.year,
          calculatedDate.month,
          calculatedDate.day,
        );
        scheduleData['scheduledDate'] = Timestamp.fromDate(normalized);
      }

      final schedulePath = widget.user != null && widget.user!.hasDeptScope
          ? deptBatchCol(
              widget.user!.department, widget.user!.batch, 'schedule')
          : 'schedule';

      if (widget.classToEdit != null) {
        await FirebaseFirestore.instance
            .collection(schedulePath)
            .doc(widget.classToEdit!.id)
            .update(scheduleData);
      } else {
        await FirebaseFirestore.instance
            .collection(schedulePath)
            .add(scheduleData);
      }

      // Notify batch students of routine update in background
      if (widget.user != null && widget.user!.hasDeptScope) {
        FCMService.notifyRoutineUpdated(
          subject: _subjectController.text.trim(),
          action: widget.classToEdit != null ? 'Updated' : 'Added',
          dayOfWeek: _selectedDay,
          senderUserId: widget.user!.id,
          department: widget.user!.department,
          batch: widget.user!.batch,
        ).catchError((e) => debugPrint('[ScheduleBuilder] Notification error: $e'));
      }

      if (mounted) {
        InAppNotification.show(
          context,
          title: widget.classToEdit != null ? 'Class Updated' : 'Class Scheduled',
          message: widget.classToEdit != null
              ? 'Class details updated successfully!'
              : 'Class added to weekly schedule!',
          accentColor: Colors.green,
          icon: Icons.check_circle_rounded,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Schedule Error',
          message: 'Error: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _teacherController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  InputDecoration _buildInputDecoration(String labelText, IconData icon,
      {String? helperText, TextStyle? helperStyle}) {
    return InputDecoration(
      labelText: labelText,
      helperText: helperText,
      helperStyle: helperStyle,
      labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.glassCardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.glassCardBorder.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      filled: true,
      fillColor: AppColors.textPrimary.withOpacity(0.015),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(widget.user != null && widget.user!.hasDeptScope
              ? deptBatchCol(widget.user!.department, widget.user!.batch,
                  'routine_metadata')
              : 'routine_metadata')
          .doc('info')
          .snapshots(),
      builder: (context, infoSnapshot) {
        String activeLevelTerm = 'Level-1 Term-2';
        if (infoSnapshot.hasData && infoSnapshot.data!.exists) {
          final data = infoSnapshot.data!.data() as Map<String, dynamic>;
          activeLevelTerm = data['levelTerm'] ?? activeLevelTerm;
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection(widget.user != null && widget.user!.hasDeptScope
                  ? deptBatchCol(
                      widget.user!.department, widget.user!.batch, 'courses')
                  : 'courses')
              .snapshots(),
          builder: (context, coursesSnapshot) {
            final courseDocs = coursesSnapshot.data?.docs ?? [];
            final courses = courseDocs
                .map((d) => CourseDetail.fromMap(
                    d.data() as Map<String, dynamic>, d.id))
                .toList();
            courses.sort((a, b) => a.courseCode
                .toLowerCase()
                .compareTo(b.courseCode.toLowerCase()));

            // Sort: active level-term courses first
            final activeCourses =
                courses.where((c) => c.levelTerm == activeLevelTerm).toList();
            final otherCourses =
                courses.where((c) => c.levelTerm != activeLevelTerm).toList();
            final displayCourses = [...activeCourses, ...otherCourses];

            // Perform one-time matching in edit mode to set the dropdown selection
            if (_selectedCourseId == null && courses.isNotEmpty) {
              if (widget.classToEdit != null) {
                final editSubject = widget.classToEdit!.subject.trim().toLowerCase();
                final editTeacher = widget.classToEdit!.teacher.trim().toLowerCase();
                final editCode = editSubject.split(':').first.trim().toLowerCase();

                CourseDetail? bestCourse;

                // Priority 1: Exact courseCode + courseName match
                for (var c in courses) {
                  if ('${c.courseCode}: ${c.courseName}'.toLowerCase() == editSubject) {
                    bestCourse = c;
                    break;
                  }
                }

                // Priority 2: courseCode match + teacher initials match
                if (bestCourse == null && editTeacher.isNotEmpty) {
                  for (var c in courses) {
                    if (c.courseCode.toLowerCase() == editCode &&
                        c.teacherShort.toLowerCase() == editTeacher) {
                      bestCourse = c;
                      break;
                    }
                  }
                }

                // Priority 3: courseCode match + Part A/B match in subject
                if (bestCourse == null) {
                  for (var c in courses) {
                    if (c.courseCode.toLowerCase() == editCode) {
                      final cNameLower = c.courseName.toLowerCase();
                      if ((editSubject.contains('- a') || editSubject.contains('(a)')) &&
                          (cNameLower.contains('- a') || cNameLower.contains('(a)'))) {
                        bestCourse = c;
                        break;
                      } else if ((editSubject.contains('- b') || editSubject.contains('(b)')) &&
                          (cNameLower.contains('- b') || cNameLower.contains('(b)'))) {
                        bestCourse = c;
                        break;
                      }
                    }
                  }
                }

                // Priority 4: Fallback to first courseCode match
                if (bestCourse == null) {
                  for (var c in courses) {
                    if (c.courseCode.toLowerCase() == editCode) {
                      bestCourse = c;
                      break;
                    }
                  }
                }

                _selectedCourseId = bestCourse != null && bestCourse.id.isNotEmpty
                    ? bestCourse.id
                    : 'custom';
              } else {
                _selectedCourseId = 'custom';
              }
            } else {
              _selectedCourseId ??= 'custom';
            }

            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(
                  widget.classToEdit != null ? 'Edit Class Details' : 'Add Class',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                iconTheme: IconThemeData(color: AppColors.textPrimary),
                backgroundColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: Container(
                  color: AppColors.backgroundTop.withOpacity(0.6),
                ),
              ),
              body: Container(
                decoration: BoxDecoration(
                  gradient: AppGradients.mainBackground,
                ),
                height: double.infinity,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.classToEdit != null
                              ? 'Modify the details below to update the class. Changes will update instantly.'
                              : 'Add a new class to the routine. The slot time and weekly grid will automatically adjust.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        if (widget.selectedDate != null || widget.classToEdit?.scheduledDate != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'This is a week-specific class scheduled for the week of '
                                    '${DateFormat('d MMM yyyy').format(_getSundayOfWeek(widget.selectedDate ?? widget.classToEdit!.scheduledDate!))}. '
                                    'It will only display when that week comes.',
                                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12, height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Section 1: Timing & Placement
                        _buildSectionHeader(Icons.schedule_rounded, 'Timing & Placement'),
                        const SizedBox(height: 12),
                        GlassCard(
                          padding: const EdgeInsets.all(18),
                          margin: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedDay,
                                isExpanded: true,
                                decoration: _buildInputDecoration(
                                    'Day of Week', Icons.calendar_today_rounded),
                                dropdownColor: AppColors.backgroundTop,
                                items: ScheduleConstants.days.map((day) {
                                  return DropdownMenuItem(
                                      value: day,
                                      child: Text(day,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: AppColors.textPrimary, fontSize: 14)));
                                }).toList(),
                                onChanged: (val) =>
                                    setState(() => _selectedDay = val!),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _selectedStartSlot,
                                      isExpanded: true,
                                      decoration: _buildInputDecoration(
                                          'Start Slot', Icons.access_time_rounded),
                                      dropdownColor: AppColors.backgroundTop,
                                      items: List.generate(10, (i) => i + 1).map((slot) {
                                        final time = ScheduleConstants.getTimeForSlot(
                                            slot, 1, widget.customSlots);
                                        return DropdownMenuItem(
                                          value: slot,
                                          child: Text(
                                            'Slot $slot ($time)',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: AppColors.textPrimary, fontSize: 12.5),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) =>
                                          setState(() => _selectedStartSlot = val!),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _selectedSpan,
                                      isExpanded: true,
                                      decoration: _buildInputDecoration(
                                          'Span (Slots)', Icons.grid_view_rounded),
                                      dropdownColor: AppColors.backgroundTop,
                                      items: [1, 2, 3].map((span) {
                                        return DropdownMenuItem(
                                            value: span,
                                            child: Text('$span Slot(s)',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: AppColors.textPrimary, fontSize: 14)));
                                      }).toList(),
                                      onChanged: (val) =>
                                          setState(() => _selectedSpan = val!),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedGroup,
                                isExpanded: true,
                                decoration: _buildInputDecoration(
                                    'Parallel Lab Group (Optional)',
                                    Icons.group_work_rounded),
                                dropdownColor: AppColors.backgroundTop,
                                items: _groupOptions.map((group) {
                                  return DropdownMenuItem(
                                      value: group,
                                      child: Text(group,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: AppColors.textPrimary, fontSize: 14)));
                                }).toList(),
                                onChanged: (val) =>
                                    setState(() => _selectedGroup = val!),
                              ),
                            ],
                          ),
                        ),

                        // Section 2: Class & Course Details
                        _buildSectionHeader(Icons.menu_book_rounded, 'Class & Course Details'),
                        const SizedBox(height: 12),
                        GlassCard(
                          padding: const EdgeInsets.all(18),
                          margin: const EdgeInsets.only(bottom: 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedCourseId,
                                isExpanded: true,
                                dropdownColor: AppColors.backgroundTop,
                                style: TextStyle(color: AppColors.textPrimary),
                                decoration: _buildInputDecoration(
                                  'Select Course from Registry',
                                  Icons.assignment_turned_in_rounded,
                                  helperText: _selectedCourseId != 'custom'
                                      ? 'Details auto-filled from registry'
                                      : 'Choose a registered course to auto-fill details',
                                  helperStyle: TextStyle(
                                    color: _selectedCourseId != 'custom'
                                        ? AppColors.secondary
                                        : AppColors.textSecondary,
                                    fontSize: 10.5,
                                    fontWeight: _selectedCourseId != 'custom'
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: 'custom',
                                    child: Text('Custom / Manual Entry',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: Colors.amberAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5)),
                                  ),
                                  ...displayCourses.map((course) {
                                    final isCurrentTerm =
                                        course.levelTerm == activeLevelTerm;
                                    return DropdownMenuItem<String>(
                                      value: course.id,
                                      child: Text(
                                        '${course.courseCode}: ${course.courseName} (${course.teacherShort})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrentTerm
                                              ? AppColors.textPrimary
                                              : AppColors.textSecondary,
                                          fontWeight: isCurrentTerm
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (courseId) {
                                  setState(() {
                                    _selectedCourseId = courseId;
                                    if (courseId != null && courseId != 'custom') {
                                      final selected =
                                          courses.firstWhere((c) => c.id == courseId);
                                      _subjectController.text =
                                          '${selected.courseCode}: ${selected.courseName}';
                                      _teacherController.text = selected.teacherShort;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _subjectController,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                decoration: _buildInputDecoration(
                                    'Subject (e.g. CHEM 103: CHEM-II)',
                                    Icons.subject_rounded),
                                validator: (val) => val!.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _teacherController,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                decoration: _buildInputDecoration(
                                    'Teacher Initials (e.g. Dr. MMA)',
                                    Icons.badge_rounded),
                                validator: (val) => val!.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _roomController,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                decoration: _buildInputDecoration(
                                    'Room (e.g. R#413)', Icons.meeting_room_rounded),
                                validator: (val) => val!.isEmpty ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),

                        // Save Button
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.35),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveClass,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: AppColors.onPrimary,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        widget.classToEdit != null
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.add_circle_outline_rounded,
                                        color: AppColors.onPrimary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        widget.classToEdit != null
                                            ? 'Update Class Details'
                                            : 'Add to Schedule',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.onPrimary,
                                            letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppColors.secondary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.secondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
