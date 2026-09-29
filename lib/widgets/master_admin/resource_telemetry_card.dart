import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/constants.dart';
import '../../utils/dept_scope.dart';
import '../glass_card.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ResourceTelemetryCard
///
/// Academic Resource Telemetry: Displays top-downloaded lecture materials,
/// notes, and routine views grouped by department (IPE, TMDM, ESE, etc.)
/// and highlights the most active batches across the campus.
/// ─────────────────────────────────────────────────────────────────────────────
class ResourceTelemetryCard extends StatefulWidget {
  final List<QueryDocumentSnapshot> allUserDocs;

  const ResourceTelemetryCard({super.key, required this.allUserDocs});

  @override
  State<ResourceTelemetryCard> createState() => _ResourceTelemetryCardState();
}

class _ResourceTelemetryCardState extends State<ResourceTelemetryCard> {
  String _selectedDept = 'All';
  String _selectedTab = 'batches'; // 'batches' or 'materials'
  Stream<List<_ResourceItem>>? _materialsStream;

  @override
  void initState() {
    super.initState();
    _initMaterialsStream();
  }

  void _initMaterialsStream() {
    _materialsStream = FirebaseFirestore.instance
        .collectionGroup('materials')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final pathSegments = doc.reference.path.split('/');
        String dept = '';
        String batch = '';
        for (int i = 0; i < pathSegments.length - 1; i++) {
          if (pathSegments[i] == 'depts' && i + 1 < pathSegments.length) {
            dept = pathSegments[i + 1];
          }
          if (pathSegments[i] == 'batches' && i + 1 < pathSegments.length) {
            batch = pathSegments[i + 1];
          }
        }

        DateTime? ts;
        if (data['timestamp'] is Timestamp) {
          ts = (data['timestamp'] as Timestamp).toDate();
        } else if (data['timestamp'] is String) {
          ts = DateTime.tryParse(data['timestamp']);
        }

        final int downloads = (data['downloads'] as num?)?.toInt() ??
            (data['downloadCount'] as num?)?.toInt() ??
            0;
        final int views = (data['views'] as num?)?.toInt() ??
            (data['viewCount'] as num?)?.toInt() ??
            0;

        final rawType = (data['type'] ?? 'Notes').toString().trim();
        final rawExt = (data['extension'] ?? 'pdf').toString().trim().toLowerCase();

        return _ResourceItem(
          id: doc.id,
          title: (data['title'] ?? data['fileName'] ?? 'Academic Material').toString(),
          subject: (data['subject'] ?? data['subjectCode'] ?? 'Course Resource').toString(),
          department: dept.isNotEmpty ? dept : (data['department'] ?? '').toString(),
          batch: batch.isNotEmpty ? batch : (data['batch'] ?? '').toString(),
          type: rawType.toUpperCase(),
          extension: rawExt,
          fileName: (data['fileName'] ?? '').toString(),
          uploadedBy: (data['uploadedBy'] ?? '').toString(),
          timestamp: ts,
          downloads: downloads,
          views: views,
        );
      }).toList();
    });
  }

  Future<List<_ResourceItem>> _fetchMaterialsFromActiveBatches() async {
    final List<_ResourceItem> items = [];
    final activeBatches = <String>{};
    for (final doc in widget.allUserDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final d = (data['department'] ?? '').toString();
      final b = (data['batch'] ?? '').toString();
      if (d.isNotEmpty && b.isNotEmpty && d != 'DEMO') {
        activeBatches.add('$d:$b');
      }
    }

    for (final pair in activeBatches) {
      final parts = pair.split(':');
      final d = parts[0];
      final b = parts[1];
      try {
        final snap = await FirebaseFirestore.instance
            .collection(deptBatchCol(d, b, 'materials'))
            .limit(25)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          DateTime? ts;
          if (data['timestamp'] is Timestamp) {
            ts = (data['timestamp'] as Timestamp).toDate();
          } else if (data['timestamp'] is String) {
            ts = DateTime.tryParse(data['timestamp']);
          }

          items.add(_ResourceItem(
            id: doc.id,
            title: (data['title'] ?? data['fileName'] ?? 'Academic Material').toString(),
            subject: (data['subject'] ?? data['subjectCode'] ?? 'Course Resource').toString(),
            department: d,
            batch: b,
            type: (data['type'] ?? 'Notes').toString().toUpperCase(),
            extension: (data['extension'] ?? 'pdf').toString().toLowerCase(),
            fileName: (data['fileName'] ?? '').toString(),
            uploadedBy: (data['uploadedBy'] ?? '').toString(),
            timestamp: ts,
            downloads: (data['downloads'] as num?)?.toInt() ?? 0,
            views: (data['views'] as num?)?.toInt() ?? 0,
          ));
        }
      } catch (_) {}
    }
    return items;
  }

  String _formatRelativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        color: Color(0xFF818CF8),
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
                                  'Academic Resource Telemetry',
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
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'Engagement',
                                  style: TextStyle(
                                    color: Color(0xFF818CF8),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Lecture downloads, notes & routine engagement by department',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
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
          const SizedBox(height: 12),

          // ── Department Selector & View Toggle ──────────────────────────────
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDeptChip('All'),
                      ...kDepartments.map((d) => _buildDeptChip(d['code']!)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // View Subtabs: Active Batches vs Top Materials
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSubTab(
                    title: 'Active Batches Leaderboard',
                    icon: Icons.leaderboard_rounded,
                    tabKey: 'batches',
                  ),
                ),
                Expanded(
                  child: _buildSubTab(
                    title: 'Top Academic Resources',
                    icon: Icons.menu_book_rounded,
                    tabKey: 'materials',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Tab Content ───────────────────────────────────────────────────
          if (_selectedTab == 'batches')
            _buildBatchesLeaderboard()
          else
            _buildTopMaterialsList(),
        ],
      ),
    );
  }

  Widget _buildDeptChip(String dept) {
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
        selectedColor: const Color(0xFF6366F1),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: isSelected ? const Color(0xFF6366F1) : Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  Widget _buildSubTab({
    required String title,
    required IconData icon,
    required String tabKey,
  }) {
    final isSelected = _selectedTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? const Color(0xFF818CF8) : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchesLeaderboard() {
    // Aggregate user interactions & activity by Dept & Batch
    final Map<String, _BatchActivityData> batchMap = {};

    for (final doc in widget.allUserDocs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final dept = (data['department'] ?? '').toString();
      final batch = (data['batch'] ?? '').toString();
      if (dept.isEmpty || batch.isEmpty || dept == 'DEMO') continue;

      if (_selectedDept != 'All' && dept != _selectedDept) continue;

      final key = '$dept - Batch $batch';
      final entry = batchMap.putIfAbsent(
        key,
        () => _BatchActivityData(department: dept, batch: batch),
      );

      entry.totalMembers++;

      // Check last activity
      DateTime? uDate;
      if (data['lastActive'] is Timestamp) {
        uDate = (data['lastActive'] as Timestamp).toDate();
      } else if (data['lastLogin'] is Timestamp) {
        uDate = (data['lastLogin'] as Timestamp).toDate();
      }

      if (uDate != null) {
        final diff = DateTime.now().difference(uDate);
        if (diff.inDays <= 7) entry.weeklyActiveMembers++;
        if (diff.inDays <= 30) entry.monthlyActiveMembers++;
      }
    }

    final sortedBatches = batchMap.values.toList()
      ..sort((a, b) => b.calculatedScore.compareTo(a.calculatedScore));

    if (sortedBatches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: Text(
          'No activity data found for selected department.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      );
    }

    final topScore = sortedBatches.first.calculatedScore;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedBatches.length > 6 ? 6 : sortedBatches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final item = sortedBatches[index];
        final rank = index + 1;
        final ratio = topScore > 0 ? (item.calculatedScore / topScore).clamp(0.05, 1.0) : 0.5;

        // Rank Badge
        Widget rankWidget;
        if (rank == 1) {
          rankWidget = const Text('🥇', style: TextStyle(fontSize: 16));
        } else if (rank == 2) {
          rankWidget = const Text('🥈', style: TextStyle(fontSize: 16));
        } else if (rank == 3) {
          rankWidget = const Text('🥉', style: TextStyle(fontSize: 16));
        } else {
          rankWidget = Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        final activePercent = item.totalMembers > 0
            ? ((item.weeklyActiveMembers / item.totalMembers) * 100).toInt()
            : 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: rank == 1
                ? const Color(0xFF6366F1).withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: rank == 1
                  ? const Color(0xFF6366F1).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  rankWidget,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${item.department} Batch ${item.batch}',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$activePercent% 7d active',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.weeklyActiveMembers} of ${item.totalMembers} students active this week · Score: ${item.calculatedScore}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    rank == 1
                        ? const Color(0xFF6366F1)
                        : (rank <= 3 ? const Color(0xFF38BDF8) : Colors.white38),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopMaterialsList() {
    return StreamBuilder<List<_ResourceItem>>(
      stream: _materialsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
              ),
            ),
          );
        }

        // If collectionGroup stream has error (e.g., security rule / index), fall back to active batch subcollections
        if (snapshot.hasError) {
          return FutureBuilder<List<_ResourceItem>>(
            future: _fetchMaterialsFromActiveBatches(),
            builder: (context, futureSnap) {
              if (futureSnap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                    ),
                  ),
                );
              }
              final items = futureSnap.data ?? [];
              return _renderMaterialsListView(items);
            },
          );
        }

        final items = snapshot.data ?? [];
        return _renderMaterialsListView(items);
      },
    );
  }

  Widget _renderMaterialsListView(List<_ResourceItem> allMaterials) {
    final filtered = allMaterials.where((r) {
      if (_selectedDept == 'All') return true;
      return r.department.toLowerCase() == _selectedDept.toLowerCase();
    }).toList()
      ..sort((a, b) {
        // Sort highest views first, then downloads, then newest
        final vComp = b.views.compareTo(a.views);
        if (vComp != 0) return vComp;
        final dComp = b.downloads.compareTo(a.downloads);
        if (dComp != 0) return dComp;
        if (a.timestamp != null && b.timestamp != null) {
          return b.timestamp!.compareTo(a.timestamp!);
        }
        return 0;
      });

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        alignment: Alignment.center,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 24, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedDept == 'All'
                  ? 'No study materials uploaded yet across campus departments.'
                  : 'No study materials uploaded for $_selectedDept yet.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length > 8 ? 8 : filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final item = filtered[index];

        Color typeColor = const Color(0xFF38BDF8); // Default Cyan
        final ext = item.extension.toLowerCase();
        final rawType = item.type.toUpperCase();

        if (ext == 'pdf' || rawType.contains('PDF')) {
          typeColor = const Color(0xFFF43F5E); // Rose Red
        } else if (ext.contains('doc') || rawType.contains('DOC')) {
          typeColor = const Color(0xFF3B82F6); // Blue
        } else if (ext.contains('ppt') || rawType.contains('PPT')) {
          typeColor = const Color(0xFFF59E0B); // Amber
        } else if (rawType.contains('BOOK')) {
          typeColor = const Color(0xFF6366F1); // Indigo
        } else if (rawType.contains('VIDEO')) {
          typeColor = const Color(0xFFA855F7); // Purple
        } else {
          typeColor = const Color(0xFF10B981); // Emerald
        }

        final timeStr = _formatRelativeTime(item.timestamp);
        final deptBatchBadge = item.department.isNotEmpty
            ? '${item.department}${item.batch.isNotEmpty ? ' • Batch ${item.batch}' : ''}'
            : '';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.extension.isNotEmpty ? item.extension.toUpperCase() : item.type,
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1.5),
                    Row(
                      children: [
                        if (deptBatchBadge.isNotEmpty) ...[
                          Text(
                            deptBatchBadge,
                            style: TextStyle(
                              color: typeColor.withValues(alpha: 0.85),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
                          ),
                        ],
                        Expanded(
                          child: Text(
                            item.subject,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 9.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (timeStr.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(alpha: 0.6),
                              fontSize: 8.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_rounded, size: 11, color: Color(0xFF10B981)),
                      const SizedBox(width: 2),
                      Text(
                        '${item.downloads}',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${item.views} views',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 8.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BatchActivityData {
  final String department;
  final String batch;
  int totalMembers = 0;
  int weeklyActiveMembers = 0;
  int monthlyActiveMembers = 0;

  _BatchActivityData({required this.department, required this.batch});

  int get calculatedScore {
    // Weighted engagement score based on user activity volume
    return (weeklyActiveMembers * 15) + (monthlyActiveMembers * 5) + (totalMembers * 2);
  }
}

class _ResourceItem {
  final String id;
  final String title;
  final String subject;
  final String department;
  final String batch;
  final String type;
  final String extension;
  final String fileName;
  final String uploadedBy;
  final DateTime? timestamp;
  final int downloads;
  final int views;

  _ResourceItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.department,
    required this.batch,
    required this.type,
    required this.extension,
    required this.fileName,
    required this.uploadedBy,
    this.timestamp,
    required this.downloads,
    required this.views,
  });
}
