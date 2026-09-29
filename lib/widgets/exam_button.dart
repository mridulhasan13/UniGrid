import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../screens/exam_schedule_screen.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';

/// Top-bar Exam Button placed beside the notification bell.
/// Shows live upcoming exam badge and navigates to ExamScheduleScreen.
class ExamButton extends StatelessWidget {
  final AppUser? user;

  const ExamButton({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    if (user == null || !user!.hasDeptScope) {
      return IconButton(
        icon: Icon(
          Icons.assignment_outlined,
          color: AppColors.textSecondary,
          size: 23,
        ),
        tooltip: 'Exams & Countdown',
        onPressed: () {
          if (user != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExamScheduleScreen(user: user!),
              ),
            );
          }
        },
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(deptBatchCol(user!.department, user!.batch, 'exams'))
          .snapshots(),
      builder: (context, snapshot) {
        int upcomingCount = 0;
        bool hasImminentExam = false; // Within 24 hours

        if (snapshot.hasData) {
          final now = DateTime.now();
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final exam = ExamModel.fromMap(data, doc.id);
            if (exam.endDateTime.isAfter(now)) {
              upcomingCount++;
              final diff = exam.startDateTime.difference(now);
              if (!diff.isNegative && diff.inHours < 24) {
                hasImminentExam = true;
              }
            }
          }
        }

        final iconColor = hasImminentExam
            ? Colors.amberAccent
            : (upcomingCount > 0 ? AppColors.secondary : AppColors.textSecondary);

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                upcomingCount > 0
                    ? Icons.assignment_rounded
                    : Icons.assignment_outlined,
                color: iconColor,
                size: 23,
              ),
              tooltip: 'Exam Countdown & Schedule',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExamScheduleScreen(user: user!),
                  ),
                );
              },
            ),
            if (upcomingCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: hasImminentExam ? Colors.amber : AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (hasImminentExam ? Colors.amber : AppColors.primary)
                            .withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    upcomingCount > 9 ? '9+' : '$upcomingCount',
                    style: TextStyle(
                      color: hasImminentExam ? Colors.black : Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
