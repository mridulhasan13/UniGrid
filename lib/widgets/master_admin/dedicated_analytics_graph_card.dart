import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../utils/constants.dart';
import '../../utils/dept_scope.dart';
import '../glass_card.dart';
import 'sparkline_graph_widget.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// DedicatedAnalyticsGraphCard
///
/// A standalone, deep-dive graph analytics dashboard section that represents
/// comprehensive campus telemetry:
///   • Daily Active Users (DAU) & traffic velocity
///   • Onboarding & signup progression
///   • Academic resource & routine engagement
///   • 24-Hour peak activity distribution heatmap
///   • Interactive touch crosshairs with granular details & department splits
/// ─────────────────────────────────────────────────────────────────────────────
class DedicatedAnalyticsGraphCard extends StatefulWidget {
  final List<QueryDocumentSnapshot> allUserDocs;

  const DedicatedAnalyticsGraphCard({
    super.key,
    required this.allUserDocs,
  });

  @override
  State<DedicatedAnalyticsGraphCard> createState() => _DedicatedAnalyticsGraphCardState();
}

enum _AnalyticsMetricMode {
  activeUsers,
  onboarding,
  academicResources,
  hourlyHeatmap,
}

class _DedicatedAnalyticsGraphCardState extends State<DedicatedAnalyticsGraphCard> {
  _AnalyticsMetricMode _selectedMode = _AnalyticsMetricMode.activeUsers;
  int _selectedDaysHorizon = 7; // 7, 14, or 30 days
  int? _hoveredIndex;
  String _selectedDeptFilter = 'All';

  StreamSubscription? _materialsSub;
  StreamSubscription? _auditSub;
  List<Map<String, dynamic>> _materialsList = [];
  List<Map<String, dynamic>> _auditLogsList = [];

  @override
  void initState() {
    super.initState();
    _subscribeLiveStreams();
  }

  void _subscribeLiveStreams() {
    try {
      _materialsSub = FirebaseFirestore.instance
          .collectionGroup('materials')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() {
          _materialsList = snap.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            final parts = d.reference.path.split('/');
            for (int i = 0; i < parts.length - 1; i++) {
              if (parts[i] == 'depts' && i + 1 < parts.length) m['department'] = parts[i + 1];
            }
            return m;
          }).toList();
        });
      }, onError: (_) {});
    } catch (_) {}

    try {
      _auditSub = FirebaseFirestore.instance
          .collection('admin_audit_logs')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() {
          _auditLogsList = snap.docs.map((d) => d.data()).toList();
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _materialsSub?.cancel();
    _auditSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // ── Generate Time Horizon Data Points ──────────────────────────────────
    final int pointsCount = _selectedDaysHorizon;
    final List<DateTime> dateList = List.generate(pointsCount, (i) {
      final daysAgo = pointsCount - 1 - i;
      return DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));
    });

    final List<String> xLabels = dateList.map((d) {
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return 'Today';
      }
      return _selectedDaysHorizon <= 7
          ? DateFormat('E').format(d)
          : (_selectedDaysHorizon <= 14 ? DateFormat('d MMM').format(d) : (d.day % 5 == 0 ? DateFormat('d MMM').format(d) : ''));
    }).toList();

    // Compute metric values based on selected mode
    List<double> values = List.filled(pointsCount, 0.0);

    final Map<int, Map<String, int>> deptDistributionPerDay = {};
    for (int i = 0; i < pointsCount; i++) {
      deptDistributionPerDay[i] = {};
    }

    final int totalUsers = widget.allUserDocs.length;

    // Filtered users by department
    final relevantDocs = widget.allUserDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final dept = (data['department'] ?? '').toString();
      if (dept == 'DEMO') return false;
      if (_selectedDeptFilter != 'All' && dept != _selectedDeptFilter) return false;
      return true;
    }).toList();

    if (_selectedMode == _AnalyticsMetricMode.activeUsers) {
      // 1. DAILY ACTIVE USERS (DAU)
      for (final doc in relevantDocs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final dept = (data['department'] ?? 'Other').toString();

        DateTime? activeDate;
        if (data['lastActive'] is Timestamp) {
          activeDate = (data['lastActive'] as Timestamp).toDate();
        } else if (data['lastActive'] is String) {
          activeDate = DateTime.tryParse(data['lastActive']);
        } else if (data['lastLogin'] is Timestamp) {
          activeDate = (data['lastLogin'] as Timestamp).toDate();
        }

        if (activeDate != null) {
          for (int i = 0; i < pointsCount; i++) {
            final targetDate = dateList[i];
            final isSameDay = activeDate.year == targetDate.year &&
                activeDate.month == targetDate.month &&
                activeDate.day == targetDate.day;

            if (isSameDay) {
              values[i] += 1.0;
              deptDistributionPerDay[i]![dept] = (deptDistributionPerDay[i]![dept] ?? 0) + 1;
            }
          }
        }
      }
    } else if (_selectedMode == _AnalyticsMetricMode.onboarding) {
      // 2. SIGNUPS & ONBOARDINGS OVER TIME (Exact Firestore accounts created)
      for (final doc in relevantDocs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final dept = (data['department'] ?? 'Other').toString();

        DateTime? createdDate;
        if (data['createdAt'] is Timestamp) {
          createdDate = (data['createdAt'] as Timestamp).toDate();
        } else if (data['createdAt'] is String) {
          createdDate = DateTime.tryParse(data['createdAt']);
        }

        if (createdDate != null) {
          for (int i = 0; i < pointsCount; i++) {
            final targetDate = dateList[i];
            if (createdDate.year == targetDate.year &&
                createdDate.month == targetDate.month &&
                createdDate.day == targetDate.day) {
              values[i] += 1.0;
              deptDistributionPerDay[i]![dept] = (deptDistributionPerDay[i]![dept] ?? 0) + 1;
            }
          }
        }
      }
    } else if (_selectedMode == _AnalyticsMetricMode.academicResources) {
      // 3. REAL ACADEMIC ENGAGEMENT (Material uploads, views & routine/audit actions)
      for (int i = 0; i < pointsCount; i++) {
        final targetDate = dateList[i];

        // 1) Count real study materials created or uploaded on this day
        for (final m in _materialsList) {
          final dept = (m['department'] ?? '').toString();
          if (_selectedDeptFilter != 'All' && dept.isNotEmpty && dept != _selectedDeptFilter) continue;

          DateTime? ts;
          if (m['timestamp'] is Timestamp) {
            ts = (m['timestamp'] as Timestamp).toDate();
          } else if (m['timestamp'] is String) {
            ts = DateTime.tryParse(m['timestamp']);
          }

          if (ts != null &&
              ts.year == targetDate.year &&
              ts.month == targetDate.month &&
              ts.day == targetDate.day) {
            values[i] += 1.0;
            final label = dept.isNotEmpty ? dept : 'Materials';
            deptDistributionPerDay[i]![label] = (deptDistributionPerDay[i]![label] ?? 0) + 1;
          }
        }

        // 2) Count real routine/admin updates from audit logs on this day
        for (final log in _auditLogsList) {
          DateTime? ts;
          if (log['timestamp'] is Timestamp) {
            ts = (log['timestamp'] as Timestamp).toDate();
          } else if (log['timestamp'] is String) {
            ts = DateTime.tryParse(log['timestamp']);
          }

          if (ts != null &&
              ts.year == targetDate.year &&
              ts.month == targetDate.month &&
              ts.day == targetDate.day) {
            values[i] += 1.0;
            deptDistributionPerDay[i]!['Routine Updates'] =
                (deptDistributionPerDay[i]!['Routine Updates'] ?? 0) + 1;
          }
        }

        // 3) Include student academic session activity on this day
        for (final doc in relevantDocs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final dept = (data['department'] ?? 'Other').toString();

          DateTime? activeDate;
          if (data['lastActive'] is Timestamp) {
            activeDate = (data['lastActive'] as Timestamp).toDate();
          } else if (data['lastActive'] is String) {
            activeDate = DateTime.tryParse(data['lastActive']);
          }

          if (activeDate != null &&
              activeDate.year == targetDate.year &&
              activeDate.month == targetDate.month &&
              activeDate.day == targetDate.day) {
            values[i] += 1.0;
            deptDistributionPerDay[i]![dept] = (deptDistributionPerDay[i]![dept] ?? 0) + 1;
          }
        }
      }
    }

    // ── Peak, Average & Summary Calculations ─────────────────────────────────
    final double maxVal = values.isNotEmpty ? values.reduce((a, b) => a > b ? a : b) : 1.0;
    final double minVal = values.isNotEmpty ? values.reduce((a, b) => a < b ? a : b) : 0.0;
    final double sumVal = values.fold(0.0, (a, b) => a + b);
    final double avgVal = values.isNotEmpty ? sumVal / values.length : 0.0;
    final int peakIndex = values.isNotEmpty ? values.indexOf(maxVal) : 0;
    final String peakDateStr = peakIndex < dateList.length ? DateFormat('EEEE, dd MMM').format(dateList[peakIndex]) : '';

    final int activeIndex = _hoveredIndex ?? (pointsCount - 1);
    final double activeValue = activeIndex < values.length ? values[activeIndex] : 0.0;
    final DateTime activeDate = activeIndex < dateList.length ? dateList[activeIndex] : now;
    final String activeDateLabel = DateFormat('EEEE, dd MMM yyyy').format(activeDate);

    // Delta comparison (first half vs second half of the horizon)
    final int half = (pointsCount / 2).floor();
    final double firstHalfSum = values.take(half).fold(0.0, (a, b) => a + b);
    final double secondHalfSum = values.skip(half).fold(0.0, (a, b) => a + b);
    final double deltaPeriod = firstHalfSum > 0
        ? (((secondHalfSum - firstHalfSum) / firstHalfSum) * 100)
        : (secondHalfSum > 0 ? 100.0 : 0.0);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header & Main Title ───────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.area_chart_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Campus Telemetry & Graph Analytics',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'Interactive',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Scrub graph to inspect granular daily counts, department splits & velocity shifts',
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
            ],
          ),
          const SizedBox(height: 16),

          // ── Metric Mode Selectors & Horizon Pills ──────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildModePill(
                  title: 'Active Members (DAU)',
                  icon: Icons.people_alt_rounded,
                  mode: _AnalyticsMetricMode.activeUsers,
                  color: const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 8),
                _buildModePill(
                  title: 'Academic Resources',
                  icon: Icons.menu_book_rounded,
                  mode: _AnalyticsMetricMode.academicResources,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 8),
                _buildModePill(
                  title: 'Signups & Onboarding',
                  icon: Icons.person_add_alt_1_rounded,
                  mode: _AnalyticsMetricMode.onboarding,
                  color: const Color(0xFFA855F7),
                ),
                const SizedBox(width: 8),
                _buildModePill(
                  title: '24h Peak Heatmap',
                  icon: Icons.access_time_filled_rounded,
                  mode: _AnalyticsMetricMode.hourlyHeatmap,
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Secondary Filter Toolbar: Horizon (7d/14d/30d) + Dept Filter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Department Filter Chips
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDeptMiniPill('All'),
                      ...kDepartments.map((d) => _buildDeptMiniPill(d['code']!)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Time Horizon Segments (7D, 14D, 30D)
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [7, 14, 30].map((days) {
                    final isSel = _selectedDaysHorizon == days;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedDaysHorizon = days;
                        _hoveredIndex = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${days}D',
                          style: TextStyle(
                            color: isSel ? Colors.white : AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── If Hourly Peak Mode Selected ──────────────────────────────────
          if (_selectedMode == _AnalyticsMetricMode.hourlyHeatmap) ...[
            _buildHourlyHeatmapView(relevantDocs.length),
          ] else ...[
            // ── Primary Interactive Telemetry Graph Canvas ───────────────────
            _buildDetailedGraphSection(
              values: values,
              xLabels: xLabels,
              maxVal: maxVal,
              minVal: minVal,
              avgVal: avgVal,
              sumVal: sumVal,
              peakIndex: peakIndex,
              peakDateStr: peakDateStr,
              deltaPeriod: deltaPeriod,
              activeIndex: activeIndex,
              activeValue: activeValue,
              activeDateLabel: activeDateLabel,
              totalUsers: totalUsers,
              deptSplit: deptDistributionPerDay[activeIndex] ?? {},
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModePill({
    required String title,
    required IconData icon,
    required _AnalyticsMetricMode mode,
    required Color color,
  }) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedMode = mode;
        _hoveredIndex = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSelected ? color : AppColors.textSecondary),
            const SizedBox(width: 5.5),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptMiniPill(String dept) {
    final isSel = _selectedDeptFilter == dept;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: () => setState(() => _selectedDeptFilter = dept),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF6366F1).withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSel ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Text(
            dept,
            style: TextStyle(
              color: isSel ? Colors.white : AppColors.textSecondary,
              fontSize: 9.5,
              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedGraphSection({
    required List<double> values,
    required List<String> xLabels,
    required double maxVal,
    required double minVal,
    required double avgVal,
    required double sumVal,
    required int peakIndex,
    required String peakDateStr,
    required double deltaPeriod,
    required int activeIndex,
    required double activeValue,
    required String activeDateLabel,
    required int totalUsers,
    required Map<String, int> deptSplit,
  }) {
    Color graphColor = const Color(0xFF38BDF8); // Default Cyan/Blue
    String unitLabel = 'Active Users';
    if (_selectedMode == _AnalyticsMetricMode.academicResources) {
      graphColor = const Color(0xFF10B981);
      unitLabel = 'Materials & Routine Views';
    } else if (_selectedMode == _AnalyticsMetricMode.onboarding) {
      graphColor = const Color(0xFFA855F7);
      unitLabel = 'New Onboardings';
    }

    final double engagementPercent = totalUsers > 0 ? ((activeValue / totalUsers) * 100).clamp(0.0, 100.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Top Detail Summary Strip ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: graphColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: graphColor.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          '${activeValue.toInt()} $unitLabel',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        TrendDeltaBadge(deltaPercent: deltaPeriod, compact: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeDateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: graphColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Campus Share',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${engagementPercent.toStringAsFixed(1)}% of total',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── 2. Interactive SVG Spline Canvas ─────────────────────────────────
        SizedBox(
          height: 135,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTapDown: (details) {
                  final stepX = constraints.maxWidth / (values.length - 1);
                  final idx = (details.localPosition.dx / stepX).round().clamp(0, values.length - 1);
                  setState(() => _hoveredIndex = idx);
                },
                onHorizontalDragUpdate: (details) {
                  final stepX = constraints.maxWidth / (values.length - 1);
                  final idx = (details.localPosition.dx / stepX).round().clamp(0, values.length - 1);
                  setState(() => _hoveredIndex = idx);
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 135),
                  painter: _MasterTelemetrySplinePainter(
                    data: values,
                    color: graphColor,
                    hoveredIndex: activeIndex,
                    peakIndex: peakIndex,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // X-Axis Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(xLabels.length, (i) {
            final isHovered = i == activeIndex;
            return Text(
              xLabels[i],
              style: TextStyle(
                color: isHovered ? graphColor : AppColors.textSecondary.withValues(alpha: 0.65),
                fontSize: 9,
                fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }),
        ),
        const SizedBox(height: 16),

        // ── 3. Detail Indicators Grid (4 Key Metrics) ─────────────────────────
        Row(
          children: [
            Expanded(
              child: _buildDetailTile(
                title: 'Peak Traffic Day',
                value: '${maxVal.toInt()} active',
                subtitle: peakDateStr,
                icon: Icons.star_rounded,
                iconColor: Colors.amberAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDetailTile(
                title: 'Daily Velocity',
                value: '${avgVal.toStringAsFixed(1)} / day',
                subtitle: 'Consistent baseline',
                icon: Icons.speed_rounded,
                iconColor: const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDetailTile(
                title: 'Selected Total',
                value: '${sumVal.toInt()}',
                subtitle: 'Over $_selectedDaysHorizon days',
                icon: Icons.bar_chart_rounded,
                iconColor: const Color(0xFF10B981),
              ),
            ),
          ],
        ),

        // ── 4. Department Engagement Breakdown for Hovered Day ────────────────
        if (deptSplit.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Department Traffic Distribution ($activeDateLabel):',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${deptSplit.values.fold(0, (a, b) => a + b)} members',
                      style: TextStyle(
                        color: graphColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: deptSplit.entries.map((e) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: graphColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${e.key}: ${e.value}',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHourlyHeatmapView(int totalDepartmentUsers) {
    // 24-hour campus peak activity curve computed from real Firestore timestamps
    final List<double> hourlyDistribution = List.filled(24, 0.0);

    for (final doc in widget.allUserDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final dept = (data['department'] ?? '').toString();
      if (dept == 'DEMO') continue;
      if (_selectedDeptFilter != 'All' && dept != _selectedDeptFilter) continue;

      DateTime? dt;
      if (data['lastActive'] is Timestamp) {
        dt = (data['lastActive'] as Timestamp).toDate();
      } else if (data['lastActive'] is String) {
        dt = DateTime.tryParse(data['lastActive']);
      } else if (data['lastLogin'] is Timestamp) {
        dt = (data['lastLogin'] as Timestamp).toDate();
      } else if (data['lastLogin'] is String) {
        dt = DateTime.tryParse(data['lastLogin']);
      }

      if (dt != null) {
        hourlyDistribution[dt.hour] += 1.0;
      }
    }

    // Include actions from real study materials
    for (final m in _materialsList) {
      final dept = (m['department'] ?? '').toString();
      if (_selectedDeptFilter != 'All' && dept.isNotEmpty && dept != _selectedDeptFilter) continue;

      DateTime? dt;
      if (m['timestamp'] is Timestamp) {
        dt = (m['timestamp'] as Timestamp).toDate();
      } else if (m['timestamp'] is String) {
        dt = DateTime.tryParse(m['timestamp']);
      }
      if (dt != null) hourlyDistribution[dt.hour] += 1.0;
    }

    // Include actions from real admin audit logs
    for (final log in _auditLogsList) {
      DateTime? dt;
      if (log['timestamp'] is Timestamp) {
        dt = (log['timestamp'] as Timestamp).toDate();
      } else if (log['timestamp'] is String) {
        dt = DateTime.tryParse(log['timestamp']);
      }
      if (dt != null) hourlyDistribution[dt.hour] += 1.0;
    }

    int peakHour = 0;
    double maxHourly = 0.0;
    for (int h = 0; h < 24; h++) {
      if (hourlyDistribution[h] > maxHourly) {
        maxHourly = hourlyDistribution[h];
        peakHour = h;
      }
    }

    final String peakLabel;
    if (maxHourly > 0) {
      final period = peakHour >= 12 ? 'PM' : 'AM';
      final hDisplay = peakHour == 0 ? 12 : (peakHour > 12 ? peakHour - 12 : peakHour);
      peakLabel = 'Peak: $hDisplay:00 $period (${maxHourly.toInt()} active)';
    } else {
      peakLabel = 'No hourly traffic logged yet';
    }

    int morningActions = 0; // 6 AM - 12 PM
    int eveningActions = 0; // 6 PM - 12 AM
    for (int h = 6; h < 12; h++) {
      morningActions += hourlyDistribution[h].toInt();
    }
    for (int h = 18; h < 24; h++) {
      eveningActions += hourlyDistribution[h].toInt();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '24-Hour Peak Activity Distribution',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Daily activity velocity distribution curve across 24 hours',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Text(
                peakLabel,
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Hourly Bar Distribution Chart
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(24, (hour) {
              final val = hourlyDistribution[hour];
              final ratio = maxHourly > 0 ? (val / maxHourly).clamp(0.06, 1.0) : 0.03;
              final isPeak = maxHourly > 0 && val == maxHourly;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Tooltip(
                    message: '$hour:00 - ${val.toInt()} actions',
                    child: Container(
                      height: 90 * ratio,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: isPeak
                              ? [const Color(0xFFF59E0B), const Color(0xFFEF4444)]
                              : (val > 0
                                  ? [
                                      const Color(0xFF38BDF8).withValues(alpha: 0.4),
                                      const Color(0xFF38BDF8).withValues(alpha: 0.8),
                                    ]
                                  : [
                                      Colors.white.withValues(alpha: 0.05),
                                      Colors.white.withValues(alpha: 0.1),
                                    ]),
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),

        // Hour labels
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('12 AM', style: TextStyle(color: Colors.white38, fontSize: 8.5)),
            Text('6 AM', style: TextStyle(color: Colors.white38, fontSize: 8.5)),
            Text('12 PM (Noon)', style: TextStyle(color: Colors.white38, fontSize: 8.5)),
            Text('6 PM', style: TextStyle(color: Colors.white38, fontSize: 8.5)),
            Text('11 PM', style: TextStyle(color: Colors.white38, fontSize: 8.5)),
          ],
        ),
        const SizedBox(height: 14),

        // Peak Phase Explanation Footnote
        Row(
          children: [
            Expanded(
              child: _buildHeatmapInsightCard(
                timeSlot: '6 AM – 12 PM',
                title: 'Morning Class Hours',
                desc: '$morningActions active students & updates',
                color: const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildHeatmapInsightCard(
                timeSlot: '6 PM – 12 AM',
                title: 'Evening & Night Peak',
                desc: '$eveningActions active students & updates',
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeatmapInsightCard({
    required String timeSlot,
    required String title,
    required String desc,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
              const SizedBox(width: 5),
              Text(
                timeSlot,
                style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(title, style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(desc, style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildDetailTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Icon(icon, size: 11, color: iconColor),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 8.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// _MasterTelemetrySplinePainter
///
/// High-definition cubic Bézier curve with glowing strokes, interactive
/// vertical tracker hairline, circular halo dots, and gradient area fills.
/// ─────────────────────────────────────────────────────────────────────────────
class _MasterTelemetrySplinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final int? hoveredIndex;
  final int peakIndex;

  _MasterTelemetrySplinePainter({
    required this.data,
    required this.color,
    this.hoveredIndex,
    required this.peakIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    double minVal = data.reduce((a, b) => a < b ? a : b);
    double maxVal = data.reduce((a, b) => a > b ? a : b);
    if ((maxVal - minVal).abs() < 0.0001) {
      maxVal += 1.0;
      minVal -= 1.0;
    }

    final double stepX = size.width / (data.length - 1);
    final points = <Offset>[];

    // Horizontal Guideline Grids (4 horizontal lines)
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    for (int g = 0; g <= 3; g++) {
      final gy = size.height * (g / 3);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    for (int i = 0; i < data.length; i++) {
      final double normalizedY = (data[i] - minVal) / (maxVal - minVal);
      final double y = size.height - (normalizedY * (size.height - 24)) - 12;
      final double x = i * stepX;
      points.add(Offset(x, y));
    }

    // Spline curve path
    final strokePath = Path();
    strokePath.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final cp1 = Offset(current.dx + (next.dx - current.dx) / 2, current.dy);
      final cp2 = Offset(current.dx + (next.dx - current.dx) / 2, next.dy);
      strokePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, next.dx, next.dy);
    }

    // Ambient Glow Stroke Underneath
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(strokePath, glowPaint);

    // Area Gradient Fill
    final fillPath = Path.from(strokePath);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.35),
          color.withValues(alpha: 0.01),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Sharp Foreground Stroke
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(strokePath, strokePaint);

    // Draw Data Point Rings & Touch Hairline
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final isHovered = hoveredIndex == i;
      final isPeak = peakIndex == i;

      if (isHovered) {
        // Vertical Hairline Tracker
        final hairlinePaint = Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset(pt.dx, 0), Offset(pt.dx, size.height), hairlinePaint);

        // Hover Ring Halos
        canvas.drawCircle(pt, 7.5, Paint()..color = color.withValues(alpha: 0.35));
        canvas.drawCircle(pt, 4.8, Paint()..color = Colors.white);
        canvas.drawCircle(pt, 3.0, Paint()..color = color);
      } else if (isPeak) {
        // Peak Ring (Gold)
        canvas.drawCircle(pt, 5.0, Paint()..color = Colors.amberAccent.withValues(alpha: 0.4));
        canvas.drawCircle(pt, 3.2, Paint()..color = Colors.amberAccent);
      } else {
        canvas.drawCircle(pt, 2.8, Paint()..color = color.withValues(alpha: 0.85));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MasterTelemetrySplinePainter oldDelegate) {
    return oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.data != data ||
        oldDelegate.color != color;
  }
}
