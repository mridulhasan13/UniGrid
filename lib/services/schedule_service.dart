import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../utils/dept_scope.dart';

/// Centralized Schedule Service
///
/// Unifies class schedule and day-status Firestore streams across:
/// 1. WeeklyRoutineTable (Home Screen)
/// 2. ScheduleScreen (Routine Tab)
/// 3. RoutineReminderService (Class reminders)
///
/// Instead of opening 3 independent .snapshots() queries, this service
/// maintains a single connection and broadcasts updates in-memory.
class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentDept;
  String? _currentBatch;

  StreamSubscription<QuerySnapshot>? _scheduleSub;
  StreamSubscription<DocumentSnapshot>? _dayStatusesSub;

  final ValueNotifier<List<ClassSchedule>> scheduleNotifier =
      ValueNotifier<List<ClassSchedule>>([]);

  final ValueNotifier<Map<String, String>> dayStatusesNotifier =
      ValueNotifier<Map<String, String>>({});

  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier<bool>(true);

  List<ClassSchedule> get classes => scheduleNotifier.value;
  Map<String, String> get dayStatuses => dayStatusesNotifier.value;

  /// Synchronize the schedule stream with the current user's department & batch.
  void syncScope(String? dept, String? batch) {
    final cleanDept = (dept ?? '').trim().toUpperCase();
    final cleanBatch = (batch ?? '').trim();

    if (cleanDept.isEmpty || cleanBatch.isEmpty) {
      _stop();
      return;
    }

    if (_currentDept == cleanDept &&
        _currentBatch == cleanBatch &&
        _scheduleSub != null) {
      // Already actively listening to this scope
      return;
    }

    _stop();
    _currentDept = cleanDept;
    _currentBatch = cleanBatch;
    isLoadingNotifier.value = true;

    final schedulePath = deptBatchCol(cleanDept, cleanBatch, 'schedule');
    final metaPath = deptBatchCol(cleanDept, cleanBatch, 'routine_metadata');

    // 1. Single stream for Class Schedule
    _scheduleSub = _firestore.collection(schedulePath).snapshots().listen(
      (snapshot) {
        final parsed = snapshot.docs.map((doc) {
          final data = doc.data();
          return ClassSchedule.fromMap(data, doc.id);
        }).toList();

        scheduleNotifier.value = parsed;
        isLoadingNotifier.value = false;
      },
      onError: (err) {
        debugPrint('[ScheduleService] Schedule stream error: $err');
        isLoadingNotifier.value = false;
      },
    );

    // 2. Single stream for Routine Day Statuses (e.g. holiday, exam, off-day)
    _dayStatusesSub =
        _firestore.collection(metaPath).doc('day_statuses').snapshots().listen(
      (doc) {
        final Map<String, String> map = {};
        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          data.forEach((k, v) {
            if (v is String && v.isNotEmpty) {
              map[k] = v.toLowerCase();
            }
          });
        }
        dayStatusesNotifier.value = map;
      },
      onError: (err) {
        debugPrint('[ScheduleService] DayStatuses stream error: $err');
      },
    );

    debugPrint('[ScheduleService] Active shared schedule stream for $cleanDept Batch $cleanBatch');
  }

  void _stop() {
    _scheduleSub?.cancel();
    _scheduleSub = null;
    _dayStatusesSub?.cancel();
    _dayStatusesSub = null;
    _currentDept = null;
    _currentBatch = null;
    scheduleNotifier.value = [];
    dayStatusesNotifier.value = {};
    isLoadingNotifier.value = false;
  }
}
