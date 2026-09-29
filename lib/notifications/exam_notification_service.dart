import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'fcm_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ExamNotificationService
///
/// Standalone, decoupled service for dispatching Exam and Assignment push
/// notifications across web and mobile platforms.
/// Keeps existing notification handlers isolated and untouched.
/// ─────────────────────────────────────────────────────────────────────────────
class ExamNotificationService {
  ExamNotificationService._();

  /// Dispatches a push broadcast to all students in the department & batch
  /// when an Exam or Assignment is scheduled or updated by a CR / Admin.
  static Future<void> notifyExamSaved({
    required ExamModel exam,
    required AppUser user,
    bool isUpdate = false,
  }) async {
    if (!user.hasDeptScope) return;

    try {
      final isAssignment = exam.examType.trim().toLowerCase() == 'assignment';
      final actionWord = isUpdate ? 'Updated' : (isAssignment ? 'Assigned' : 'Scheduled');
      
      final title = isAssignment
          ? (isUpdate ? 'Assignment Updated: ${exam.courseName}' : 'New Assignment: ${exam.courseName}')
          : '${exam.examType} $actionWord: ${exam.courseName}';

      final dateStr = DateFormat('EEE, dd MMM').format(exam.examDate);
      final timeStr = exam.startTime.isNotEmpty ? exam.startTime : '';
      final roomStr = exam.room.isNotEmpty ? 'Room ${exam.room}' : '';
      final codeStr = exam.courseCode.isNotEmpty ? exam.courseCode : '';

      final parts = <String>[];
      if (codeStr.isNotEmpty) parts.add(codeStr);
      parts.add(isAssignment ? 'Due: $dateStr' : dateStr);
      if (timeStr.isNotEmpty) parts.add(timeStr);
      if (roomStr.isNotEmpty) parts.add(roomStr);

      final body = parts.join(' · ');

      final messageId = 'exam_${exam.id.isNotEmpty ? exam.id : DateTime.now().millisecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch}';

      await FCMService.sendToDeptAndBatch(
        department: user.department,
        batch: user.batch,
        title: title,
        body: body.isNotEmpty ? body : 'Tap to view schedule details.',
        senderUserId: user.id,
        messageId: messageId,
        extraData: {
          'target': 'schedule',
          'type': 'exam_schedule',
          'route': '/schedule',
          'tabIndex': '1',
          'preferenceField': 'notifAlerts',
          'categoryTag': 'unigrid_alerts',
          'examId': exam.id,
          'examType': exam.examType,
          'courseName': exam.courseName,
        },
      );

      debugPrint('[ExamNotification] ✓ Dispatched notification for "${exam.courseName}" ($title)');
    } catch (e) {
      debugPrint('[ExamNotification] Notification dispatch notice (non-fatal): $e');
    }
  }

  /// Dispatches a push broadcast when an Exam or Assignment is cancelled or deleted.
  static Future<void> notifyExamDeleted({
    required ExamModel exam,
    required AppUser user,
  }) async {
    if (!user.hasDeptScope) return;

    try {
      final isAssignment = exam.examType.trim().toLowerCase() == 'assignment';
      final title = isAssignment
          ? 'Assignment Removed: ${exam.courseName}'
          : '${exam.examType} Cancelled: ${exam.courseName}';

      final dateStr = DateFormat('EEE, dd MMM').format(exam.examDate);
      final body = '${exam.courseName} (${exam.examType}) originally on $dateStr has been removed from the schedule.';

      final messageId = 'exam_del_${exam.id}_${DateTime.now().millisecondsSinceEpoch}';

      await FCMService.sendToDeptAndBatch(
        department: user.department,
        batch: user.batch,
        title: title,
        body: body,
        senderUserId: user.id,
        messageId: messageId,
        extraData: {
          'target': 'schedule',
          'type': 'exam_deleted',
          'route': '/schedule',
          'tabIndex': '1',
          'preferenceField': 'notifAlerts',
          'categoryTag': 'unigrid_alerts',
        },
      );

      debugPrint('[ExamNotification] ✓ Dispatched deletion notice for "${exam.courseName}"');
    } catch (e) {
      debugPrint('[ExamNotification] Notification dispatch notice (non-fatal): $e');
    }
  }
}
