import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../utils/dept_scope.dart';
import '../glass_card.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// UserLifecycleCard
///
/// User Lifecycle & Retention Metrics: Computes Day 1, Day 7, and Day 30
/// retention rates across registered students and highlights inactive batches
/// that require CR onboarding outreach.
/// ─────────────────────────────────────────────────────────────────────────────
class UserLifecycleCard extends StatefulWidget {
  final List<QueryDocumentSnapshot> allUserDocs;

  const UserLifecycleCard({super.key, required this.allUserDocs});

  @override
  State<UserLifecycleCard> createState() => _UserLifecycleCardState();
}

class _UserLifecycleCardState extends State<UserLifecycleCard> {
  bool _onlyShowInactive = false;
  String _selectedDept = 'All';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // ── 1. Calculate Day 1, Day 7, Day 30 Retention Rates ───────────────────
    int day1Eligible = 0;
    int day1Retained = 0;

    int day7Eligible = 0;
    int day7Retained = 0;

    int day30Eligible = 0;
    int day30Retained = 0;

    // Batch groupings: Dept-Batch -> stats
    final Map<String, _BatchRetentionData> batchMap = {};

    for (final doc in widget.allUserDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final dept = (data['department'] ?? '').toString();
      final batch = (data['batch'] ?? '').toString();
      if (dept.isEmpty || batch.isEmpty || dept == 'DEMO') continue;

      DateTime? createdDate;
      if (data['createdAt'] is Timestamp) {
        createdDate = (data['createdAt'] as Timestamp).toDate();
      } else if (data['createdAt'] is String) {
        createdDate = DateTime.tryParse(data['createdAt']);
      }

      DateTime? lastActiveDate;
      if (data['lastActive'] is Timestamp) {
        lastActiveDate = (data['lastActive'] as Timestamp).toDate();
      } else if (data['lastActive'] is String) {
        lastActiveDate = DateTime.tryParse(data['lastActive']);
      } else if (data['lastLogin'] is Timestamp) {
        lastActiveDate = (data['lastLogin'] as Timestamp).toDate();
      } else if (data['lastLogin'] is String) {
        lastActiveDate = DateTime.tryParse(data['lastLogin']);
      }

      // Fallback: If createdAt is missing, use account registration date or assume user is mature
      createdDate ??= (lastActiveDate ?? now).subtract(const Duration(days: 35));

      final ageDays = now.difference(createdDate).inDays;
      final daysSinceActive = lastActiveDate != null ? now.difference(lastActiveDate).inDays : 999;

      // Day 1 Retention (Eligible if account is at least 1 day old)
      if (ageDays >= 1) {
        day1Eligible++;
        if (daysSinceActive <= 1) day1Retained++;
      }

      // Day 7 Retention (Eligible if account is at least 7 days old)
      if (ageDays >= 7) {
        day7Eligible++;
        if (daysSinceActive <= 7) day7Retained++;
      }

      // Day 30 Retention (Eligible if account is at least 30 days old)
      if (ageDays >= 30) {
        day30Eligible++;
        if (daysSinceActive <= 30) day30Retained++;
      }

      // Batch aggregation
      final batchKey = '$dept - Batch $batch';
      final bEntry = batchMap.putIfAbsent(
        batchKey,
        () => _BatchRetentionData(department: dept, batch: batch),
      );

      bEntry.totalStudents++;
      if (daysSinceActive <= 7) {
        bEntry.activeLast7Days++;
      } else if (daysSinceActive <= 30) {
        bEntry.activeLast30Days++;
      } else {
        bEntry.dormantStudents++;
      }
    }

    final double d1Rate = day1Eligible > 0 ? (day1Retained / day1Eligible) * 100 : 0.0;
    final double d7Rate = day7Eligible > 0 ? (day7Retained / day7Eligible) * 100 : 0.0;
    final double d30Rate = day30Eligible > 0 ? (day30Retained / day30Eligible) * 100 : 0.0;

    // Filter Batches by Department and Inactivity
    final batchesList = batchMap.values.where((b) {
      if (_selectedDept != 'All' && b.department != _selectedDept) return false;
      if (_onlyShowInactive && !b.needsOnboarding) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        // Sort lowest retention rate first to spotlight inactive batches
        return a.retentionRate.compareTo(b.retentionRate);
      });

    final int inactiveBatchesCount = batchMap.values.where((b) => b.needsOnboarding).length;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final isVeryNarrow = constraints.maxWidth < 440;
              final badgeWidget = inactiveBatchesCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$inactiveBatchesCount Batches Inactive',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.loop_rounded,
                          color: Color(0xFF34D399),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'User Lifecycle & Retention',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'Cohorts',
                                    style: TextStyle(
                                      color: Color(0xFF34D399),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Retention velocity & inactive batches',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isVeryNarrow && inactiveBatchesCount > 0) ...[
                        const SizedBox(width: 8),
                        badgeWidget,
                      ],
                    ],
                  ),
                  if (isVeryNarrow && inactiveBatchesCount > 0) ...[
                    const SizedBox(height: 8),
                    badgeWidget,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // ── Retention Cohort Progress Cards (Day 1, Day 7, Day 30) ─────────
          Row(
            children: [
              Expanded(
                child: _buildRetentionMetricCard(
                  period: 'Day 1',
                  label: 'Next-Day Return',
                  rate: d1Rate,
                  color: const Color(0xFF10B981),
                  icon: Icons.offline_bolt_outlined,
                  retainedCount: day1Retained,
                  eligibleCount: day1Eligible,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRetentionMetricCard(
                  period: 'Day 7',
                  label: 'Weekly Habit',
                  rate: d7Rate,
                  color: const Color(0xFF38BDF8),
                  icon: Icons.calendar_today_outlined,
                  retainedCount: day7Retained,
                  eligibleCount: day7Eligible,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRetentionMetricCard(
                  period: 'Day 30',
                  label: 'Monthly Stickiness',
                  rate: d30Rate,
                  color: const Color(0xFFA855F7),
                  icon: Icons.event_repeat_rounded,
                  retainedCount: day30Retained,
                  eligibleCount: day30Eligible,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Inactive Batch Spotlight & Filter Bar ──────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _onlyShowInactive ? 'Batches Needing Onboarding' : 'Batch Onboarding & Health Status',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _onlyShowInactive = !_onlyShowInactive),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: _onlyShowInactive
                        ? Colors.redAccent.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _onlyShowInactive
                          ? Colors.redAccent.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _onlyShowInactive ? Icons.warning_amber_rounded : Icons.filter_alt_outlined,
                        size: 12,
                        color: _onlyShowInactive ? Colors.redAccent : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _onlyShowInactive ? 'Show All Batches' : 'Only Inactive Batches',
                        style: TextStyle(
                          color: _onlyShowInactive ? Colors.redAccent : AppColors.textSecondary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDeptFilterChip('All'),
                ...kDepartments.map((d) => _buildDeptFilterChip(d['code']!)),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Batches List ───────────────────────────────────────────────────
          if (batchesList.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: Text(
                _onlyShowInactive
                    ? '🎉 All batches are currently active! Zero batches need onboarding.'
                    : 'No batch records found.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: batchesList.length > 5 ? 5 : batchesList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final batch = batchesList[index];
                return _buildBatchHealthRow(batch);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRetentionMetricCard({
    required String period,
    required String label,
    required double rate,
    required Color color,
    required IconData icon,
    required int retainedCount,
    required int eligibleCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                period,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
              Icon(icon, size: 13, color: color.withValues(alpha: 0.8)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${rate.toStringAsFixed(1)}%',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (rate / 100).clamp(0.0, 1.0),
              minHeight: 3.5,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$retainedCount of $eligibleCount students',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchHealthRow(_BatchRetentionData b) {
    Color statusColor = const Color(0xFF10B981); // Green
    String statusText = 'Healthy';

    if (b.needsOnboarding) {
      statusColor = const Color(0xFFF43F5E); // Red
      statusText = 'Needs Onboarding';
    } else if (b.retentionRate < 60) {
      statusColor = const Color(0xFFF59E0B); // Amber
      statusText = 'Moderate';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
      decoration: BoxDecoration(
        color: b.needsOnboarding
            ? Colors.redAccent.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: b.needsOnboarding
              ? Colors.redAccent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${b.department} Batch ${b.batch}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  '${b.activeStudents} active · ${b.dormantStudents} dormant (${b.totalStudents} total)',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${b.retentionRate.toStringAsFixed(0)}% retention',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 65,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (b.retentionRate / 100).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeptFilterChip(String dept) {
    final isSelected = _selectedDept == dept;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(dept),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedDept = dept),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppColors.textSecondary,
          fontSize: 10.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.03),
        selectedColor: const Color(0xFF10B981),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: isSelected ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

class _BatchRetentionData {
  final String department;
  final String batch;
  int totalStudents = 0;
  int activeLast7Days = 0;
  int activeLast30Days = 0;
  int dormantStudents = 0;

  _BatchRetentionData({required this.department, required this.batch});

  int get activeStudents => activeLast7Days + activeLast30Days;

  double get retentionRate {
    if (totalStudents == 0) return 0.0;
    return (activeStudents / totalStudents) * 100;
  }

  bool get needsOnboarding {
    // Flagged if retention rate is below 40% or if dormant members exceed 65%
    return retentionRate < 40.0 && totalStudents >= 3;
  }
}
