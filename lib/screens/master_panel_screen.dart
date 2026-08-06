import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/constants.dart';
import '../widgets/glass_card.dart';
import '../widgets/unigrid_loader.dart';
import '../utils/dept_scope.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../notifications/in_app_notification.dart';

class MasterPanelScreen extends StatefulWidget {
  const MasterPanelScreen({super.key});

  @override
  State<MasterPanelScreen> createState() => _MasterPanelScreenState();
}

class _MasterPanelScreenState extends State<MasterPanelScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  String _selectedDeptFilter = 'All';
  String _selectedBatchFilter = 'All';

  Future<void> _updateUserStatus(
      String uid, String field, dynamic value) async {
    try {
      await _firestore.collection('users').doc(uid).update({field: value});
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'User Updated',
          message: 'User updated successfully',
          accentColor: Colors.green,
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Update Failed',
          message: 'Failed to update user: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _deleteUser(String uid, String email) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        title: Text('Confirm Deletion',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'Are you sure you want to completely remove $email from the database?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestore.collection('users').doc(uid).delete();
        if (mounted) {
          InAppNotification.show(
            context,
            title: 'User Deleted',
            message: 'User deleted permanently.',
            accentColor: Colors.redAccent,
            icon: Icons.delete_forever_rounded,
          );
        }
      } catch (e) {
        if (mounted) {
          InAppNotification.show(
            context,
            title: 'Deletion Failed',
            message: 'Failed to delete user: $e',
            accentColor: Colors.redAccent,
            icon: Icons.error_outline_rounded,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.security,
                      color: Colors.redAccent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Master Admin',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Manage Users & Roles',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.2, end: 0),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search any user information...',
                  hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

          // Filters Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: GlassCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedDeptFilter,
                        isExpanded: true,
                        dropdownColor: AppColors.backgroundTop,
                        style:
                            TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Depts')),
                          ...kDepartments.map((d) => DropdownMenuItem(
                                value: d['code'],
                                child: Text(d['code']!),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedDeptFilter = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GlassCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedBatchFilter,
                        isExpanded: true,
                        dropdownColor: AppColors.backgroundTop,
                        style:
                            TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        items: [
                          const DropdownMenuItem(
                              value: 'All', child: Text('All Batches')),
                          ...kBatches.map((b) => DropdownMenuItem(
                                value: b,
                                child: Text('Batch $b'),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedBatchFilter = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.2, end: 0),

          // Users List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red)));
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: UniGridLoader(
                      title: 'Loading Users',
                      subtitle: 'Fetching active profiles...',
                      showBackground: false,
                    ),
                  );
                }

                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final studentId = (data['studentId'] ?? '').toString().toLowerCase();
                  final deptVal = (data['department'] ?? '').toString().toLowerCase();
                  final batchVal = (data['batch'] ?? '').toString().toLowerCase();
                  final phone = (data['phoneNumber'] ?? '').toString().toLowerCase();
                  final school = (data['schoolName'] ?? '').toString().toLowerCase();
                  final college = (data['collegeName'] ?? '').toString().toLowerCase();

                  final matchesSearch = name.contains(_searchQuery) ||
                      email.contains(_searchQuery) ||
                      studentId.contains(_searchQuery) ||
                      deptVal.contains(_searchQuery) ||
                      batchVal.contains(_searchQuery) ||
                      phone.contains(_searchQuery) ||
                      school.contains(_searchQuery) ||
                      college.contains(_searchQuery);
                  final matchesDept = _selectedDeptFilter == 'All' ||
                      (data['department'] ?? '') == _selectedDeptFilter;
                  final matchesBatch = _selectedBatchFilter == 'All' ||
                      (data['batch'] ?? '') == _selectedBatchFilter;

                  return matchesSearch && matchesDept && matchesBatch;
                }).toList()
                  ..sort((a, b) {
                    final aName =
                        ((a.data() as Map<String, dynamic>)['name'] ?? '')
                            .toString()
                            .toLowerCase();
                    final bName =
                        ((b.data() as Map<String, dynamic>)['name'] ?? '')
                            .toString()
                            .toLowerCase();
                    return aName.compareTo(bName);
                  });

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDeptFilter == 'All' && _selectedBatchFilter == 'All'
                                ? 'All Registered Members'
                                : '${_selectedDeptFilter == 'All' ? 'All Depts' : _selectedDeptFilter} · ${_selectedBatchFilter == 'All' ? 'All Batches' : 'Batch $_selectedBatchFilter'}',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              '${users.length} Member${users.length == 1 ? "" : "s"}',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (users.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('No users found.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.only(left: 24, right: 24, bottom: 100),
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                    final doc = users[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final uid = doc.id;
                    final email = data['email'] ?? 'No Email';
                    final name = data['name'] ?? 'Unknown User';
                    final photoUrl = data['photoUrl'] ?? '';
                    final isCR = data['isCR'] ?? false;
                    final isApproved = data['isApproved'] ?? false;
                    final isRoot = Provider.of<AuthService>(context, listen: false)
                        .isRootAdmin(email);

                    return GlassCard(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    AppColors.primary.withOpacity(0.2),
                                backgroundImage: (photoUrl.isNotEmpty && (!kIsWeb || photoUrl.contains('supabase')))
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: (photoUrl.isEmpty || (kIsWeb && !photoUrl.contains('supabase')))
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : (email.isNotEmpty
                                                ? email[0].toUpperCase()
                                                : 'U'),
                                        style: TextStyle(
                                            color: AppColors.textPrimary))
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      email,
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 14),
                                    ),
                                    if (data['department'] != null ||
                                        data['batch'] != null ||
                                        data['studentId'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '${data['department'] ?? 'N/A'} • Batch ${data['batch'] ?? 'N/A'} • ID: ${data['studentId'] ?? 'N/A'}',
                                          style: TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 12),
                                        ),
                                      ),
                                    Builder(builder: (context) {
                                      final dynamic rawJoined = data['createdAt'];
                                      DateTime? joinedDate;
                                      if (rawJoined != null) {
                                        if (rawJoined is Timestamp) {
                                          joinedDate = rawJoined.toDate();
                                        } else if (rawJoined is String) {
                                          joinedDate = DateTime.tryParse(rawJoined);
                                        }
                                      }
                                      final String joinedStr = joinedDate != null
                                          ? DateFormat('dd MMM yyyy, hh:mm a').format(joinedDate)
                                          : 'N/A';
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                size: 13,
                                                color: AppColors.textSecondary),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Joined: $joinedStr',
                                              style: TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    if ((data['phoneNumber'] ?? '').toString().isNotEmpty ||
                                        (data['schoolName'] ?? '').toString().isNotEmpty ||
                                        (data['collegeName'] ?? '').toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if ((data['phoneNumber'] ?? '').toString().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 2),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.phone_outlined,
                                                        size: 13,
                                                        color: AppColors.textSecondary),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      data['phoneNumber'].toString(),
                                                      style: TextStyle(
                                                          color: AppColors.textSecondary,
                                                          fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if ((data['schoolName'] ?? '').toString().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 2),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.school_outlined,
                                                        size: 13,
                                                        color: AppColors.textSecondary),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        'School: ${data['schoolName']}',
                                                        style: TextStyle(
                                                            color: AppColors.textSecondary,
                                                            fontSize: 12),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if ((data['collegeName'] ?? '').toString().isNotEmpty)
                                              Row(
                                                children: [
                                                  Icon(Icons.account_balance_outlined,
                                                      size: 13,
                                                      color: AppColors.textSecondary),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'College: ${data['collegeName']}',
                                                      style: TextStyle(
                                                          color: AppColors.textSecondary,
                                                          fontSize: 12),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isRoot)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('ROOT',
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                  tooltip: 'Delete User',
                                  onPressed: () => _deleteUser(uid, email),
                                ),
                            ],
                          ),
                          if (!isRoot) ...[
                            Divider(color: AppColors.glassCardBorder, height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('CR / Admin Access',
                                    style: TextStyle(color: AppColors.textPrimary)),
                                Switch(
                                  value: isCR,
                                  activeColor: AppColors.primary,
                                  onChanged: (val) =>
                                      _updateUserStatus(uid, 'isCR', val),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Approve Account',
                                    style: TextStyle(color: AppColors.textPrimary)),
                                Switch(
                                  value: isApproved,
                                  activeColor: Colors.greenAccent,
                                  onChanged: (val) =>
                                      _updateUserStatus(uid, 'isApproved', val),
                                ),
                              ],
                            ),
                            Divider(color: AppColors.glassCardBorder, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Department',
                                    style: TextStyle(
                                        color: AppColors.textSecondary, fontSize: 13)),
                                DropdownButton<String>(
                                  value: kDeptCodes.contains(data['department'])
                                      ? data['department']
                                      : null,
                                  hint: Text('Select Dept',
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 13)),
                                  dropdownColor: AppColors.backgroundTop,
                                  style: TextStyle(
                                      color: AppColors.textPrimary, fontSize: 13),
                                  underline: Container(),
                                  items: kDepartments
                                      .map((d) => DropdownMenuItem<String>(
                                            value: d['code'],
                                            child: Text(d['code']!,
                                                style: TextStyle(
                                                    color: AppColors.textPrimary)),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      _updateUserStatus(uid, 'department', val);
                                    }
                                  },
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Batch',
                                    style: TextStyle(
                                        color: AppColors.textSecondary, fontSize: 13)),
                                DropdownButton<String>(
                                  value: kBatches.contains(data['batch'])
                                      ? data['batch']
                                      : null,
                                  hint: Text('Select Batch',
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 13)),
                                  dropdownColor: AppColors.backgroundTop,
                                  style: TextStyle(
                                      color: AppColors.textPrimary, fontSize: 13),
                                  underline: Container(),
                                  items: kBatches
                                      .map((b) => DropdownMenuItem<String>(
                                            value: b,
                                            child: Text(b,
                                                style: TextStyle(
                                                    color: AppColors.textPrimary)),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      _updateUserStatus(uid, 'batch', val);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(
                            delay: Duration(milliseconds: 300 + (index * 50)))
                        .slideY(begin: 0.1, end: 0);
                      },
                    ),
                  ),
                ],
              );
            },
            ),
          ),
        ],
      ),
    );
  }
}
