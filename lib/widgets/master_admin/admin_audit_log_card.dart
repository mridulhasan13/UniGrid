import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/admin_audit_service.dart';
import '../../utils/constants.dart';
import '../glass_card.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AdminAuditLogCard
///
/// Chronological feed recording admin actions (e.g. maintenance mode toggles,
/// CR status approvals, role modifications, broadcast notifications) to prevent
/// unauthorized changes and maintain an immutable administrative audit trail.
/// ─────────────────────────────────────────────────────────────────────────────
class AdminAuditLogCard extends StatefulWidget {
  const AdminAuditLogCard({super.key});

  @override
  State<AdminAuditLogCard> createState() => _AdminAuditLogCardState();
}

class _AdminAuditLogCardState extends State<AdminAuditLogCard> {
  String _selectedCategory = 'All';
  String _searchFilter = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isExpanded = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                        color: Colors.amberAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.history_edu_rounded,
                        color: Colors.amberAccent,
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
                              Text(
                                'Audit & Admin Activity Log',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.amberAccent.withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'Security',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Chronological feed of root admin actions and overrides',
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
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                ),
                tooltip: _isExpanded ? 'Collapse' : 'Expand Feed',
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Search & Filter Chips ──────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5),
                          decoration: InputDecoration(
                            hintText: 'Filter by admin or action...',
                            hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 11.5),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) => setState(() => _searchFilter = val.trim().toLowerCase()),
                        ),
                      ),
                      if (_searchFilter.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _searchFilter = '');
                          },
                          child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Category Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Security', 'Roles', 'User', 'Broadcast', 'System'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : AppColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    selectedColor: Colors.amberAccent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(
                      color: isSelected ? Colors.amberAccent : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // ── Stream Feed ────────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: AdminAuditService.getAuditLogsStream(limit: _isExpanded ? 50 : 8),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                    ),
                  ),
                );
              }

              final allLogs = snapshot.data?.docs ?? [];
              final filteredLogs = allLogs.where((doc) {
                final data = doc.data();
                final cat = (data['category'] ?? '').toString();
                final action = (data['action'] ?? '').toString().toLowerCase();
                final admin = (data['adminName'] ?? '').toString().toLowerCase();
                final target = (data['targetName'] ?? '').toString().toLowerCase();

                final matchesCategory = _selectedCategory == 'All' || cat.toLowerCase() == _selectedCategory.toLowerCase();
                final matchesSearch = _searchFilter.isEmpty ||
                    action.contains(_searchFilter) ||
                    admin.contains(_searchFilter) ||
                    target.contains(_searchFilter);

                return matchesCategory && matchesSearch;
              }).toList();

              if (filteredLogs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 28, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 6),
                      Text(
                        _searchFilter.isNotEmpty || _selectedCategory != 'All'
                            ? 'No logs matching current filter'
                            : 'No administrative logs recorded yet',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Administrative actions (maintenance toggles, role updates, announcements) will automatically appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredLogs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final logData = filteredLogs[index].data();
                      return _buildAuditItem(logData);
                    },
                  ),
                  if (allLogs.length > 8) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _isExpanded = !_isExpanded),
                        icon: Icon(
                          _isExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                          size: 14,
                          color: Colors.amberAccent,
                        ),
                        label: Text(
                          _isExpanded ? 'Show Less' : 'View All ${allLogs.length} Records',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAuditItem(Map<String, dynamic> log) {
    final action = log['action'] ?? 'Admin action';
    final adminName = log['adminName'] ?? 'Admin';
    final category = log['category'] ?? 'System';
    final targetName = log['targetName'] ?? '';

    DateTime logTime = DateTime.now();
    if (log['timestamp'] is Timestamp) {
      logTime = (log['timestamp'] as Timestamp).toDate();
    } else if (log['clientTimestamp'] is String) {
      logTime = DateTime.tryParse(log['clientTimestamp']) ?? DateTime.now();
    }

    final relativeTime = _formatRelativeTime(logTime);

    // Color & Icon mapping based on category
    Color catColor = const Color(0xFF38BDF8); // Blue default
    IconData catIcon = Icons.admin_panel_settings_outlined;

    switch (category.toString().toLowerCase()) {
      case 'security':
        catColor = const Color(0xFFF43F5E); // Red
        catIcon = Icons.shield_outlined;
        break;
      case 'roles':
        catColor = const Color(0xFFF59E0B); // Amber
        catIcon = Icons.badge_outlined;
        break;
      case 'user':
        catColor = const Color(0xFF10B981); // Emerald
        catIcon = Icons.person_outline_rounded;
        break;
      case 'broadcast':
        catColor = const Color(0xFFA855F7); // Purple
        catIcon = Icons.campaign_outlined;
        break;
      case 'system':
        catColor = const Color(0xFF14B8A6); // Teal
        catIcon = Icons.settings_suggest_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8.5),
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: catColor.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5.5),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(catIcon, color: catColor, size: 14),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        action,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      relativeTime,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'By: $adminName',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (targetName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Target: $targetName',
                          style: TextStyle(
                            color: catColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, h:mm a').format(time);
  }
}
