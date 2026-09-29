import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/custom_snack_bar.dart';
import '../notifications/exam_notification_service.dart';

class ExamScheduleScreen extends StatefulWidget {
  final AppUser user;

  const ExamScheduleScreen({super.key, required this.user});

  @override
  State<ExamScheduleScreen> createState() => _ExamScheduleScreenState();
}

class _ExamScheduleScreenState extends State<ExamScheduleScreen> {
  Timer? _ticker;
  int _selectedTab = 0; // 0: Upcoming, 1: Past / Completed

  @override
  void initState() {
    super.initState();
    // Live countdown ticker every second
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _isCRorAdmin(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRoot = authService.isRootAdmin(authService.currentAuthEmail) ||
        authService.isRootAdmin(widget.user.email);
    return widget.user.isCR || widget.user.isAdmin || isRoot;
  }

  static Color getExamColor(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('final') && !lower.contains('lab')) {
      return const Color(0xFFEF4444); // Red/Coral
    } else if (lower.contains('mid')) {
      return const Color(0xFFF59E0B); // Amber
    } else if (lower.contains('lab')) {
      return const Color(0xFF10B981); // Emerald
    } else if (lower.contains('quiz')) {
      return const Color(0xFFA855F7); // Purple
    } else if (lower.contains('presentation') || lower.contains('viva')) {
      return const Color(0xFF06B6D4); // Cyan
    } else if (lower.contains('assignment')) {
      return const Color(0xFF14B8A6); // Teal
    } else {
      return const Color(0xFF3B82F6); // Sapphire Blue (CT)
    }
  }

  static IconData getExamIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('lab')) {
      return Icons.science_outlined;
    } else if (lower.contains('quiz')) {
      return Icons.psychology_outlined;
    } else if (lower.contains('presentation') || lower.contains('viva')) {
      return Icons.co_present_outlined;
    } else if (lower.contains('assignment')) {
      return Icons.task_outlined;
    } else if (lower.contains('final') || lower.contains('mid')) {
      return Icons.school_outlined;
    } else {
      return Icons.assignment_outlined;
    }
  }

  Color _getExamColor(String type) => getExamColor(type);
  IconData _getExamIcon(String type) => getExamIcon(type);

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context);
    final hasScope = widget.user.hasDeptScope;
    final isCR = _isCRorAdmin(context);

    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.mainBackground,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam Countdown',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              if (hasScope)
                Text(
                  '${deptFullName(widget.user.department)} • Batch ${widget.user.batch}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          actions: [
            if (isCR && hasScope)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Center(
                  child: InkWell(
                    onTap: () => _openSetExamDialog(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.secondary.withOpacity(0.85)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text(
                            'Set Exam',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: !hasScope
            ? _buildNoScopeState()
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(deptBatchCol(
                        widget.user.department, widget.user.batch, 'exams'))
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading exams: ${snapshot.error}',
                        style: TextStyle(color: Colors.redAccent.shade100),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final allExams = docs.map((doc) {
                    return ExamModel.fromMap(
                        doc.data() as Map<String, dynamic>, doc.id);
                  }).toList();

                  final now = DateTime.now();

                  // Sort by start date ascending
                  allExams.sort(
                      (a, b) => a.startDateTime.compareTo(b.startDateTime));

                  final upcoming = allExams
                      .where((e) => e.endDateTime.isAfter(now))
                      .toList();
                  final completed = allExams
                      .where((e) => !e.endDateTime.isAfter(now))
                      .toList()
                      .reversed
                      .toList(); // most recently finished first

                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      // Tab selector
                      _buildTabFilter(upcoming.length, completed.length),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _selectedTab == 0
                            ? _buildUpcomingList(upcoming, isCR)
                            : _buildCompletedList(completed, isCR),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTabFilter(int upcomingCount, int completedCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassCardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassCardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'Upcoming',
              count: upcomingCount,
              isSelected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Past / Done',
              count: completedCount,
              isSelected: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withOpacity(0.25)
                    : AppColors.glassCardBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingList(List<ExamModel> exams, bool isCR) {
    if (exams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'No Upcoming Exams',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isCR
                    ? 'You have not scheduled any tests or exams yet.\nTap "+ Set Exam" at the top right to create one.'
                    : 'Relax! There are no upcoming exams scheduled for your batch.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final nextExam = exams.first;
    final otherExams = exams.length > 1 ? exams.sublist(1) : <ExamModel>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Hero Highlight Card for Next Upcoming Exam
        _buildHeroNextExamCard(nextExam, isCR),

        if (otherExams.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 8),
              Text(
                'Subsequent Exams (${otherExams.length})',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...otherExams.map((e) => _buildExamCard(e, isCR)),
        ],
      ],
    );
  }

  Widget _buildCompletedList(List<ExamModel> exams, bool isCR) {
    if (exams.isEmpty) {
      return Center(
        child: Text(
          'No past exams recorded.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: exams.length,
      itemBuilder: (context, index) {
        return _buildExamCard(exams[index], isCR, isPast: true);
      },
    );
  }

  /// Big Hero Card for the very next exam with prominent live countdown!
  Widget _buildHeroNextExamCard(ExamModel exam, bool isCR) {
    final now = DateTime.now();
    final isOngoing =
        now.isAfter(exam.startDateTime) && now.isBefore(exam.endDateTime);
    final examColor = _getExamColor(exam.examType);
    final diff = exam.startDateTime.difference(now);

    return InkWell(
      onTap: () => _openExamDetailsSheet(exam, isCR),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              AppColors.glassCardColor,
              examColor.withOpacity(0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: examColor.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: examColor.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header tag
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: examColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: examColor.withOpacity(0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOngoing
                              ? Icons.radio_button_checked
                              : Icons.access_time_filled_rounded,
                          color: isOngoing ? Colors.amberAccent : examColor,
                          size: 13,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOngoing
                              ? 'EXAM IN PROGRESS'
                              : 'NEXT UP • ${exam.examType.toUpperCase()}',
                          style: TextStyle(
                            color: isOngoing ? Colors.amberAccent : examColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCR)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          color: AppColors.textSecondary, size: 20),
                      color: AppColors.glassCardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: AppColors.glassCardBorder),
                      ),
                      onSelected: (val) {
                        if (val == 'edit') {
                          _openSetExamDialog(context, examToEdit: exam);
                        } else if (val == 'delete') {
                          _confirmDeleteExam(exam);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined,
                                  color: Colors.white70, size: 18),
                              SizedBox(width: 8),
                              Text('Edit Exam',
                                  style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 18),
                              SizedBox(width: 8),
                              Text('Delete Exam',
                                  style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Course code & title
              if (exam.courseCode.isNotEmpty)
                Text(
                  exam.courseCode,
                  style: TextStyle(
                    color: examColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              Text(
                exam.courseName.isNotEmpty ? exam.courseName : 'Scheduled Exam',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),

              const SizedBox(height: 16),

              // Countdown Grid/Boxes
              if (isOngoing)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.alarm_on_rounded,
                          color: Colors.amberAccent, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        'Exam Currently Taking Place!',
                        style: TextStyle(
                          color: Colors.amber.shade200,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildCountdownBoxHero(diff, examColor),

              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 12),

              // Date, Room & Teacher row
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildMetaItem(
                    icon: Icons.calendar_today_rounded,
                    label: DateFormat('EEE, MMM d, yyyy')
                        .format(exam.startDateTime),
                  ),
                  if (exam.startTime.isNotEmpty)
                    _buildMetaItem(
                      icon: Icons.access_time_rounded,
                      label: exam.endTime.isNotEmpty
                          ? '${exam.startTime} - ${exam.endTime}'
                          : exam.startTime,
                    ),
                  if (exam.room.isNotEmpty)
                    _buildMetaItem(
                      icon: Icons.location_on_outlined,
                      label: exam.room,
                    ),
                  if (exam.teacherName.isNotEmpty)
                    _buildMetaItem(
                      icon: Icons.person_outline_rounded,
                      label: exam.teacherName,
                    ),
                ],
              ),

              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Tap for syllabus & details',
                    style: TextStyle(
                      color: examColor.withOpacity(0.9),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 11, color: examColor.withOpacity(0.9)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownBoxHero(Duration diff, Color accent) {
    return CountdownBoxes(diff: diff, accent: accent);
  }

  Widget _buildExamCard(ExamModel exam, bool isCR, {bool isPast = false}) {
    final now = DateTime.now();
    final isOngoing =
        now.isAfter(exam.startDateTime) && now.isBefore(exam.endDateTime);
    final examColor = _getExamColor(exam.examType);
    final diff = exam.startDateTime.difference(now);

    final days = diff.isNegative ? 0 : diff.inDays;
    final hours = diff.isNegative ? 0 : (diff.inHours % 24);
    final mins = diff.isNegative ? 0 : (diff.inMinutes % 60);
    final secs = diff.isNegative ? 0 : (diff.inSeconds % 60);

    String countdownSummary;
    if (isPast) {
      countdownSummary = 'Completed';
    } else if (isOngoing) {
      countdownSummary = '● In Progress';
    } else if (days > 0) {
      countdownSummary = '${days}d ${hours}h ${mins}m ${secs}s';
    } else if (hours > 0) {
      countdownSummary = '${hours}h ${mins}m ${secs}s';
    } else if (mins > 0) {
      countdownSummary = '${mins}m ${secs}s';
    } else {
      countdownSummary = '${secs}s left';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.glassCardColor.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOngoing
              ? Colors.amberAccent.withOpacity(0.5)
              : AppColors.glassCardBorder,
        ),
      ),
      child: InkWell(
        onTap: () => _openExamDetailsSheet(exam, isCR),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: examColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: examColor.withOpacity(0.3)),
                    ),
                    child: Icon(
                      _getExamIcon(exam.examType),
                      color: examColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Titles
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: examColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                exam.examType,
                                style: TextStyle(
                                  color: examColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (exam.courseCode.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                exam.courseCode,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          exam.courseName.isNotEmpty
                              ? exam.courseName
                              : 'Exam',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Countdown chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPast
                          ? Colors.white.withOpacity(0.06)
                          : isOngoing
                              ? Colors.amber.withOpacity(0.2)
                              : AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPast
                            ? Colors.white12
                            : isOngoing
                                ? Colors.amberAccent
                                : AppColors.primary.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOngoing
                              ? Icons.radio_button_checked
                              : Icons.timer_outlined,
                          size: 12,
                          color: isPast
                              ? AppColors.textSecondary
                              : isOngoing
                                  ? Colors.amberAccent
                                  : AppColors.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          countdownSummary,
                          style: TextStyle(
                            color: isPast
                                ? AppColors.textSecondary
                                : isOngoing
                                    ? Colors.amberAccent
                                    : AppColors.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 8),
              // Meta info
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    DateFormat('MMM d, yyyy').format(exam.startDateTime),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (exam.startTime.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.access_time_rounded,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Text(
                      exam.startTime,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (exam.room.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.room_rounded,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        exam.room,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaItem({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textPrimary.withOpacity(0.9),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildNoScopeState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined,
                size: 60, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No Department & Batch Set',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please complete your profile department & batch to view exams.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Exam Details Bottom Sheet
  // ─────────────────────────────────────────────────────────────────────────────
  void _openExamDetailsSheet(ExamModel exam, bool isCR) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ExamDetailsModalSheet(
          exam: exam,
          isCR: isCR,
          onEdit: () {
            Navigator.of(sheetContext).pop();
            _openSetExamDialog(context, examToEdit: exam);
          },
          onDelete: () {
            Navigator.of(sheetContext).pop();
            _confirmDeleteExam(exam);
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CR Set / Edit Exam Dialog
  // ─────────────────────────────────────────────────────────────────────────────
  void _openSetExamDialog(BuildContext context, {ExamModel? examToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return _SetExamFormSheet(
          user: widget.user,
          examToEdit: examToEdit,
        );
      },
    );
  }

  void _confirmDeleteExam(ExamModel exam) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.glassCardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.glassCardBorder),
        ),
        title: Text(
          'Delete Exam',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${exam.courseName}" (${exam.examType})? This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await FirebaseFirestore.instance
                    .collection(deptBatchCol(
                        widget.user.department, widget.user.batch, 'exams'))
                    .doc(exam.id)
                    .delete();
                ExamNotificationService.notifyExamDeleted(
                  exam: exam,
                  user: widget.user,
                ).catchError((_) {});
                if (mounted) {
                  CustomSnackBar.show(
                    context,
                    message: 'Exam deleted successfully',
                    icon: Icons.delete_outline,
                  );
                }
              } catch (e) {
                if (mounted) {
                  CustomSnackBar.show(
                    context,
                    message: 'Failed to delete: $e',
                    iconColor: Colors.redAccent,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Countdown Unit Boxes (Days : Hours : Mins : Secs)
// ─────────────────────────────────────────────────────────────────────────────
class CountdownBoxes extends StatelessWidget {
  final Duration diff;
  final Color accent;

  const CountdownBoxes({super.key, required this.diff, required this.accent});

  @override
  Widget build(BuildContext context) {
    final days = diff.isNegative ? 0 : diff.inDays;
    final hours = diff.isNegative ? 0 : (diff.inHours % 24);
    final mins = diff.isNegative ? 0 : (diff.inMinutes % 60);
    final secs = diff.isNegative ? 0 : (diff.inSeconds % 60);

    return Row(
      children: [
        _buildCountUnit(days.toString().padLeft(2, '0'), 'DAYS', accent),
        _buildCountSeparator(accent),
        _buildCountUnit(hours.toString().padLeft(2, '0'), 'HOURS', accent),
        _buildCountSeparator(accent),
        _buildCountUnit(mins.toString().padLeft(2, '0'), 'MINS', accent),
        _buildCountSeparator(accent),
        _buildCountUnit(secs.toString().padLeft(2, '0'), 'SECS', accent),
      ],
    );
  }

  Widget _buildCountUnit(String val, String label, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.backgroundTop.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              val,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountSeparator(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        ':',
        style: TextStyle(
          color: accent.withOpacity(0.6),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Exam Details Modal Sheet (Ticking Every Second)
// ─────────────────────────────────────────────────────────────────────────────
class _ExamDetailsModalSheet extends StatefulWidget {
  final ExamModel exam;
  final bool isCR;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExamDetailsModalSheet({
    required this.exam,
    required this.isCR,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ExamDetailsModalSheet> createState() => _ExamDetailsModalSheetState();
}

class _ExamDetailsModalSheetState extends State<_ExamDetailsModalSheet> {
  Timer? _sheetTicker;

  @override
  void initState() {
    super.initState();
    // Live ticking countdown timer inside the exam details sheet
    _sheetTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sheetTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    final now = DateTime.now();
    final isOngoing =
        now.isAfter(exam.startDateTime) && now.isBefore(exam.endDateTime);
    final isPast = now.isAfter(exam.endDateTime);
    final diff = exam.startDateTime.difference(now);
    final examColor = _ExamScheduleScreenState.getExamColor(exam.examType);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: AppColors.backgroundTop.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.12)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: examColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _ExamScheduleScreenState.getExamIcon(exam.examType),
                        color: examColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: examColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  exam.examType,
                                  style: TextStyle(
                                    color: examColor,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (exam.courseCode.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  exam.courseCode,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            exam.courseName.isNotEmpty
                                ? exam.courseName
                                : 'Exam Details',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              // Scrollable content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Big Live Countdown in details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            examColor.withOpacity(0.15),
                            AppColors.glassCardColor,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: examColor.withOpacity(0.35)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isPast
                                    ? Icons.check_circle_outline_rounded
                                    : isOngoing
                                        ? Icons.radio_button_checked
                                        : Icons.timer_outlined,
                                color: isPast
                                    ? Colors.white54
                                    : isOngoing
                                        ? Colors.amberAccent
                                        : examColor,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isPast
                                    ? 'EXAM COMPLETED'
                                    : isOngoing
                                        ? 'EXAM IN PROGRESS'
                                        : 'LIVE COUNTDOWN TO EXAM',
                                style: TextStyle(
                                  color: isPast
                                      ? Colors.white54
                                      : isOngoing
                                          ? Colors.amberAccent
                                          : examColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (isPast)
                            Text(
                              'This exam was concluded.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          else if (isOngoing)
                            Text(
                              'Good luck! The exam is currently in progress.',
                              style: TextStyle(
                                color: Colors.amber.shade200,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            CountdownBoxes(diff: diff, accent: examColor),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Meta info grid
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.glassCardColor.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppColors.glassCardBorder),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            icon: Icons.calendar_month_rounded,
                            title: 'Exam Date',
                            value: DateFormat('EEEE, MMMM d, yyyy')
                                .format(exam.startDateTime),
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.access_time_filled_rounded,
                            title: 'Time Slot',
                            value: exam.startTime.isNotEmpty
                                ? (exam.endTime.isNotEmpty
                                    ? '${exam.startTime} – ${exam.endTime}'
                                    : exam.startTime)
                                : 'Time not specified',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.room_rounded,
                            title: 'Room / Hall',
                            value: exam.room.isNotEmpty
                                ? exam.room
                                : 'To be announced',
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.person_rounded,
                            title: 'Course Teacher',
                            value: exam.teacherName.isNotEmpty
                                ? exam.teacherName
                                : 'Not specified',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Syllabus Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.glassCardColor.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppColors.glassCardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.menu_book_rounded,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Exam Syllabus / Topics',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            exam.syllabus.trim().isNotEmpty
                                ? exam.syllabus.trim()
                                : 'No specific syllabus details provided by CR yet.',
                            style: TextStyle(
                              color: exam.syllabus.trim().isNotEmpty
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Notes / Special Instructions
                    if (exam.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.amber.withOpacity(0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Colors.amberAccent, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Special Instructions / Notes',
                                  style: TextStyle(
                                    color: Colors.amber.shade200,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              exam.notes.trim(),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // CR Management actions
                    if (widget.isCR) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.onEdit,
                              icon:
                                  const Icon(Icons.edit_outlined, size: 17),
                              label: const Text('Edit Exam'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: BorderSide(color: AppColors.primary),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: widget.onDelete,
                              icon: const Icon(Icons.delete_outline,
                                  size: 17),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.redAccent.withOpacity(0.85),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        SizedBox(
          width: 95,
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Set / Edit Exam Form Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _SetExamFormSheet extends StatefulWidget {
  final AppUser user;
  final ExamModel? examToEdit;

  const _SetExamFormSheet({required this.user, this.examToEdit});

  @override
  State<_SetExamFormSheet> createState() => _SetExamFormSheetState();
}

class _SetExamFormSheetState extends State<_SetExamFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _courseCodeCtrl;
  late TextEditingController _courseNameCtrl;
  late TextEditingController _roomCtrl;
  late TextEditingController _teacherCtrl;
  late TextEditingController _syllabusCtrl;
  late TextEditingController _notesCtrl;

  late String _selectedType;
  late DateTime _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  bool _isSaving = false;
  List<CourseDetail> _registeredCourses = [];
  CourseDetail? _selectedRegisteredCourse;

  final List<String> _examTypes = [
    'Class Test',
    'Midterm',
    'Term Final',
    'Quiz',
    'Assignment',
    'Lab Final',
    'Presentation',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.examToEdit;

    _courseCodeCtrl = TextEditingController(text: edit?.courseCode ?? '');
    _courseNameCtrl = TextEditingController(text: edit?.courseName ?? '');
    _roomCtrl = TextEditingController(text: edit?.room ?? '');
    _teacherCtrl = TextEditingController(text: edit?.teacherName ?? '');
    _syllabusCtrl = TextEditingController(text: edit?.syllabus ?? '');
    _notesCtrl = TextEditingController(text: edit?.notes ?? '');

    _selectedType = edit?.examType ?? 'Class Test';
    if (!_examTypes.contains(_selectedType)) {
      _selectedType = 'Class Test';
    }

    _selectedDate = edit?.examDate ?? DateTime.now().add(const Duration(days: 3));

    if (edit != null && edit.startTime.isNotEmpty) {
      _startTime = _parseTimeOfDay(edit.startTime);
    } else {
      _startTime = const TimeOfDay(hour: 10, minute: 0);
    }

    if (edit != null && edit.endTime.isNotEmpty) {
      _endTime = _parseTimeOfDay(edit.endTime);
    } else {
      _endTime = const TimeOfDay(hour: 11, minute: 0);
    }

    _loadRegisteredCourses();
  }

  TimeOfDay? _parseTimeOfDay(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPM = clean.contains('PM');
      final isAM = clean.contains('AM');
      final raw = clean.replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = raw.split(':');
      if (parts.isNotEmpty) {
        int hour = int.parse(parts[0].trim());
        int minute = parts.length > 1 ? int.parse(parts[1].trim()) : 0;
        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return null;
  }

  String _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return '';
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _loadRegisteredCourses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(
              deptBatchCol(widget.user.department, widget.user.batch, 'courses'))
          .get();
      if (mounted) {
        setState(() {
          _registeredCourses = snap.docs
              .map((d) => CourseDetail.fromMap(d.data(), d.id))
              .toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _courseCodeCtrl.dispose();
    _courseNameCtrl.dispose();
    _roomCtrl.dispose();
    _teacherCtrl.dispose();
    _syllabusCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.glassCardColor,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: AppColors.backgroundTop,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart
        ? (_startTime ?? const TimeOfDay(hour: 10, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 11, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.glassCardColor,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
          // Auto set end time to 1 hr after if unset or earlier
          if (_endTime == null) {
            _endTime = TimeOfDay(
                hour: (picked.hour + 1) % 24, minute: picked.minute);
          }
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _saveExam() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final cleanDept = widget.user.department.trim().isNotEmpty
          ? widget.user.department.trim()
          : 'IPE';
      final cleanBatch = widget.user.batch.trim().isNotEmpty
          ? widget.user.batch.trim()
          : '51';
      final examsCol = FirebaseFirestore.instance.collection(
          deptBatchCol(cleanDept, cleanBatch, 'exams'));

      final startTimeStr = _formatTimeOfDay(_startTime);
      final endTimeStr = _formatTimeOfDay(_endTime);

      final examData = ExamModel(
        id: widget.examToEdit?.id ?? '',
        courseName: _courseNameCtrl.text.trim(),
        courseCode: _courseCodeCtrl.text.trim().toUpperCase(),
        examType: _selectedType,
        examDate: _selectedDate,
        startTime: startTimeStr,
        endTime: endTimeStr,
        room: _roomCtrl.text.trim(),
        teacherName: _teacherCtrl.text.trim(),
        syllabus: _syllabusCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        createdBy: widget.user.id,
      );

      if (widget.examToEdit != null) {
        await examsCol.doc(widget.examToEdit!.id).update(examData.toMap());
      } else {
        final newDoc = examsCol.doc();
        await newDoc.set(examData.toMap());
      }

      ExamNotificationService.notifyExamSaved(
        exam: examData,
        user: widget.user,
        isUpdate: widget.examToEdit != null,
      ).catchError((_) {});

      if (mounted) {
        Navigator.of(context).pop();
        CustomSnackBar.show(
          context,
          message: widget.examToEdit != null
              ? 'Exam details updated successfully! 🎉'
              : 'Exam scheduled successfully! 🎉',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        CustomSnackBar.show(
          context,
          message: 'Failed to save exam: $e',
          iconColor: Colors.redAccent,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.examToEdit != null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: BoxDecoration(
            color: AppColors.backgroundTop.withOpacity(0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.12)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_calendar_rounded
                            : Icons.add_alarm_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Exam' : 'Set New Exam',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Schedule and set syllabus for your batch',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              // Form fields
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      // Course quick selector (if available)
                      if (_registeredCourses.isNotEmpty) ...[
                        Text(
                          'Quick Pick from Batch Courses',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppColors.glassCardColor,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: AppColors.glassCardBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<CourseDetail?>(
                              value: _selectedRegisteredCourse,
                              isExpanded: true,
                              dropdownColor: AppColors.backgroundTop,
                              hint: Text(
                                'Select registered course (optional)',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem<CourseDetail?>(
                                  value: null,
                                  child: Text('Manual / Custom Entry',
                                      style: TextStyle(color: Colors.white70)),
                                ),
                                ..._registeredCourses.map((c) {
                                  return DropdownMenuItem<CourseDetail?>(
                                    value: c,
                                    child: Text(
                                      '${c.courseCode}: ${c.courseName}',
                                      style:
                                          const TextStyle(color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (course) {
                                setState(() {
                                  _selectedRegisteredCourse = course;
                                  if (course != null) {
                                    _courseCodeCtrl.text = course.courseCode;
                                    _courseNameCtrl.text = course.courseName;
                                    if (course.teacherName.isNotEmpty) {
                                      _teacherCtrl.text = course.teacherName;
                                    }
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Exam Type Selector Chips
                      Text(
                        'Exam Type *',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _examTypes.map((type) {
                          final isSelected = _selectedType == type;
                          return ChoiceChip(
                            label: Text(type),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.glassCardColor,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.glassCardBorder,
                              ),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedType = type);
                              }
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 18),

                      // Course Name & Code row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildTextField(
                              controller: _courseNameCtrl,
                              label: 'Course Name *',
                              hint: 'e.g. Operations Research',
                              validator: (val) => val == null || val.trim().isEmpty
                                  ? 'Course name required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              controller: _courseCodeCtrl,
                              label: 'Course Code',
                              hint: 'e.g. IPE 3105',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Date & Time pickers
                      Text(
                        'Schedule Date & Time *',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Date button
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.glassCardColor,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: AppColors.glassCardBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_rounded,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  DateFormat('EEEE, MMMM d, yyyy')
                                      .format(_selectedDate),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(Icons.edit_calendar_rounded,
                                  color: AppColors.textSecondary, size: 18),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Start & End Time row
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickTime(isStart: true),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.glassCardColor,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.glassCardBorder),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time_rounded,
                                        color: AppColors.secondary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Start Time',
                                              style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 10.5)),
                                          Text(
                                            _formatTimeOfDay(_startTime),
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickTime(isStart: false),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.glassCardColor,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.glassCardBorder),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.timelapse_rounded,
                                        color: AppColors.secondary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('End Time',
                                              style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 10.5)),
                                          Text(
                                            _formatTimeOfDay(_endTime),
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Room & Teacher row
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _roomCtrl,
                              label: 'Room / Venue',
                              hint: 'e.g. Room 402',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _teacherCtrl,
                              label: 'Course Teacher',
                              hint: 'e.g. Prof. Dr. Rahman',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Syllabus Text Area
                      _buildTextField(
                        controller: _syllabusCtrl,
                        label: 'Exam Syllabus & Topics Covered',
                        hint:
                            'Enter syllabus, topics, chapters, lecture slide ranges...',
                        maxLines: 5,
                      ),

                      const SizedBox(height: 16),

                      // Notes / Special Instructions
                      _buildTextField(
                        controller: _notesCtrl,
                        label: 'Special Instructions / Notes',
                        hint:
                            'e.g. Scientific calculators allowed, formulas sheet provided, bring student ID...',
                        maxLines: 3,
                      ),

                      const SizedBox(height: 24),

                      // Submit Button
                      ElevatedButton(
                        onPressed: _isSaving ? null : _saveExam,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                          shadowColor: AppColors.primary.withOpacity(0.4),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isEditing
                                        ? Icons.save_rounded
                                        : Icons.add_alarm_rounded,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isEditing ? 'Save Changes' : 'Schedule Exam',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                TextStyle(color: AppColors.textSecondary.withOpacity(0.6), fontSize: 13),
            filled: true,
            fillColor: AppColors.glassCardColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.glassCardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
