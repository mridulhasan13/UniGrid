import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/supabase_storage_service.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/glass_card.dart';
import '../widgets/unigrid_loader.dart';
import 'schedule_builder_screen.dart';
import '../services/fcm_service.dart';
import 'course_registry_screen.dart';
import '../widgets/custom_snack_bar.dart';
import '../widgets/in_app_notification.dart';

class CRPanelScreen extends StatefulWidget {
  const CRPanelScreen({super.key});

  @override
  State<CRPanelScreen> createState() => _CRPanelScreenState();
}

class _CRPanelScreenState extends State<CRPanelScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _detailsController = TextEditingController();
  String _announcementType = 'Notice';
  PlatformFile? _announcementFile;
  bool _isPostingAnnouncement = false;
  String _memberSearchQuery = '';

  Future<void> _seedDatabase() async {
    final user = Provider.of<AppUser?>(context, listen: false);
    if (user == null || !user.hasDeptScope) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Seed Error',
          message: 'Cannot seed: department or batch is missing.',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
      return;
    }
    final annPath = deptBatchCol(user.department, user.batch, 'announcements');
    final schedulePath = deptBatchCol(user.department, user.batch, 'schedule');

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Sample Announcements
      final annRef = FirebaseFirestore.instance.collection(annPath).doc();
      batch.set(annRef, {
        'title': 'Welcome to ${user.department} Portal',
        'content': 'This is your central hub for all academic activities.',
        'type': 'Notice',
        'timestamp': FieldValue.serverTimestamp(),
        'postedBy': 'System',
      });

      // Sample Schedule
      final scheduleItems = [
        {
          'subject': 'Operations Research',
          'room': 'Room 402',
          'time': '10:00 AM',
          'dayOfWeek': 'Monday',
          'isCancelled': false,
          'startSlot': 3,
          'span': 2,
          'teacher': 'TBD',
          'group': 'Gr: A',
          'lastUpdatedDate': FieldValue.serverTimestamp()
        },
        {
          'subject': 'Supply Chain Management',
          'room': 'Room 501',
          'time': '12:00 PM',
          'dayOfWeek': 'Monday',
          'isCancelled': false,
          'startSlot': 6,
          'span': 1,
          'teacher': 'TBD',
          'group': 'Gr: A',
          'lastUpdatedDate': FieldValue.serverTimestamp()
        },
        {
          'subject': 'Manufacturing Processes',
          'room': 'Lab 1',
          'time': '02:00 PM',
          'dayOfWeek': 'Tuesday',
          'isCancelled': false,
          'startSlot': 7,
          'span': 3,
          'teacher': 'TBD',
          'group': 'Gr: B',
          'lastUpdatedDate': FieldValue.serverTimestamp()
        },
      ];

      for (var item in scheduleItems) {
        final ref = FirebaseFirestore.instance.collection(schedulePath).doc();
        batch.set(ref, item);
      }

      await batch.commit();

      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Database Seeded',
          message: 'Database seeded with sample data!',
          accentColor: Colors.green,
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Seed Error',
          message: 'Error seeding: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _clearDatabase() async {
    final user = Provider.of<AppUser?>(context, listen: false);
    if (user == null || !user.hasDeptScope) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Reset Error',
          message: 'Cannot reset: department or batch is missing.',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        title:
            Text('Reset Database', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Are you sure you want to delete all previous announcements, chats, and private conversations? This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wipe Data',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final annPath =
          deptBatchCol(user.department, user.batch, 'announcements');
      final chatPath =
          deptBatchCol(user.department, user.batch, 'chat_messages');

      try {
        final batch = FirebaseFirestore.instance.batch();

        final annQuery =
            await FirebaseFirestore.instance.collection(annPath).get();
        for (var doc in annQuery.docs) {
          final data = doc.data();
          final fileUrl = data['fileUrl'];
          if (fileUrl != null && fileUrl is String && fileUrl.isNotEmpty) {
            try {
              await SupabaseStorageService.deleteFileByUrl(fileUrl);
            } catch (e) {
              debugPrint('[WipeData] Error deleting file: $e');
            }
          }
          batch.delete(doc.reference);
        }

        final chatQuery =
            await FirebaseFirestore.instance.collection(chatPath).get();
        for (var doc in chatQuery.docs) {
          batch.delete(doc.reference);
        }

        // Wipe conversations
        final convQuery =
            await FirebaseFirestore.instance.collection('conversations').get();
        for (var doc in convQuery.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();

        if (mounted) {
          InAppNotification.show(
            context,
            title: 'Database Cleared',
            message: 'All announcements and chat messages cleared!',
            accentColor: Colors.green,
            icon: Icons.cleaning_services_rounded,
          );
        }
      } catch (e) {
        if (mounted) {
          InAppNotification.show(
            context,
            title: 'Reset Error',
            message: 'Error resetting data: $e',
            accentColor: Colors.redAccent,
            icon: Icons.error_outline_rounded,
          );
        }
      }
    }
  }

  void _postAnnouncement() {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty)
      return;

    final user = Provider.of<AppUser?>(context, listen: false);
    if (user == null) return;

    // Capture data synchronously
    final title = _titleController.text;
    final content = _contentController.text;
    final details = _detailsController.text.trim();
    final type = _announcementType;
    final postedBy =
        user.name.isNotEmpty ? user.name : user.email.split('@')[0];
    final userId = user.id;
    final PlatformFile? fileToUpload = _announcementFile;

    // Clear UI instantly
    _titleController.clear();
    _contentController.clear();
    _detailsController.clear();
    setState(() {
      _announcementFile = null;
      _isPostingAnnouncement = false;
    });

    CustomSnackBar.show(
      context,
      message: 'Posting announcement in background...',
      icon: Icons.cloud_upload_rounded,
    );

    final announcementsPath =
        deptBatchCol(user.department, user.batch, 'announcements');
    // Fire and forget asynchronous upload
    _performBackgroundUpload(title, content, details, type, postedBy, fileToUpload,
        userId, announcementsPath, user.department, user.batch);
  }

  Future<void> _performBackgroundUpload(
      String title,
      String content,
      String details,
      String type,
      String postedBy,
      PlatformFile? file,
      String userId,
      String announcementsPath,
      String department,
      String batch) async {
    DocumentReference? docRef;
    try {
      // Stage 1: Post the text instantly
      docRef = await FirebaseFirestore.instance.collection(announcementsPath).add({
        'title': title,
        'content': content,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'postedBy': postedBy,
        'postedByUserId': userId,
        'fileUrl': null,
        'fileName': file?.name,
        if (details.isNotEmpty) 'details': details,
      });

      FCMService.notifyNewAnnouncement(
        title: title,
        type: type,
        senderUserId: userId,
        department: department,
        batch: batch,
        messageId: docRef.id,
      );



      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Announcement Posted',
          message: 'Announcement posted! Uploading file in background...',
          accentColor: Colors.green,
          icon: Icons.campaign_rounded,
        );
      }

      // Stage 2: Background File Upload (if any)
      if (file != null) {
        Uint8List? fileBytes = file.bytes;
        if ((fileBytes == null || fileBytes.isEmpty) && file.path != null) {
          if (!kIsWeb) {
            fileBytes = await File(file.path!).readAsBytes();
          }
        }

        if (fileBytes != null) {
          final fileUrl = await SupabaseStorageService.uploadFile(
            bytes: fileBytes,
            fileName: file.name,
            folder: 'announcements',
          );

          // Stage 3: Update document with file URL
          await docRef.update({
            'fileUrl': fileUrl,
          });

          if (mounted) {
            InAppNotification.show(
              context,
              title: 'File Attached',
              message: 'File attached successfully!',
              accentColor: Colors.green,
              icon: Icons.attach_file_rounded,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Post Error',
          message: 'Update failed: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
      if (docRef == null && mounted) {
        InAppNotification.show(
          context,
          title: 'Post Failed',
          message: 'Failed to post announcement.',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _nominateAdminDialog() async {
    final emailCtrl = TextEditingController();
    await GlassCard.showGlassDialog(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Nominate Admin', style: AppStyles.heading2),
          const SizedBox(height: 20),
          TextField(
            controller: emailCtrl,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
                labelText: 'Student Email',
                labelStyle: TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (emailCtrl.text.isEmpty) return;
                  final user = Provider.of<AppUser?>(context, listen: false);
                  await FirebaseFirestore.instance
                      .collection('admin_requests')
                      .add({
                    'requestedEmail': emailCtrl.text.trim(),
                    'requestedBy': user?.email ?? 'Unknown',
                    'status': 'pending',
                    'timestamp': FieldValue.serverTimestamp(),
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    InAppNotification.show(
                      context,
                      title: 'Nomination Sent',
                      message: 'Nomination sent for approval!',
                      accentColor: Colors.green,
                      icon: Icons.send_rounded,
                    );
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _manageAdminsDialog() async {
    final emailCtrl = TextEditingController();
    await GlassCard.showGlassDialog(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Manage Admins', style: AppStyles.heading2),
          const SizedBox(height: 20),
          SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailCtrl,
                        style: TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                            labelText: 'Direct Add Email',
                            labelStyle: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: AppColors.primary),
                      onPressed: () async {
                        if (emailCtrl.text.isEmpty) return;
                        final query = await FirebaseFirestore.instance
                            .collection('users')
                            .where('email', isEqualTo: emailCtrl.text.trim())
                            .get();
                        if (query.docs.isNotEmpty) {
                          await query.docs.first.reference
                              .update({'isCR': true});
                          emailCtrl.clear();
                          if (!context.mounted) return;
                          InAppNotification.show(
                            context,
                            title: 'Admin Added',
                            message: 'Admin added directly!',
                            accentColor: Colors.green,
                            icon: Icons.person_add_rounded,
                          );
                        } else {
                          if (!context.mounted) return;
                          InAppNotification.show(
                            context,
                            title: 'User Not Found',
                            message: 'User not found in database.',
                            accentColor: Colors.redAccent,
                            icon: Icons.search_off_rounded,
                          );
                        }
                      },
                    )
                  ],
                ),
                Divider(color: AppColors.glassCardBorder),
                Text('Pending Nominations:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('admin_requests')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(
                          child: UniGridLoader(
                            title: 'Checking nominations',
                            subtitle: 'Loading candidates...',
                            showBackground: false,
                          ),
                        );
                      final requests = snapshot.data!.docs;
                      if (requests.isEmpty)
                        return Center(
                            child: Text('No pending requests.',
                                style: TextStyle(color: AppColors.textSecondary)));
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final req =
                              requests[index].data() as Map<String, dynamic>;
                          final reqId = requests[index].id;
                          return ListTile(
                            title: Text(req['requestedEmail'] ?? '',
                                style: TextStyle(color: AppColors.textPrimary)),
                            subtitle: Text('By: ${req['requestedBy']}',
                                style: TextStyle(color: AppColors.textSecondary)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check,
                                      color: Colors.green),
                                  onPressed: () async {
                                    final query = await FirebaseFirestore
                                        .instance
                                        .collection('users')
                                        .where('email',
                                            isEqualTo: req['requestedEmail'])
                                        .get();
                                    if (query.docs.isNotEmpty) {
                                      await query.docs.first.reference
                                          .update({'isCR': true});
                                      await FirebaseFirestore.instance
                                          .collection('admin_requests')
                                          .doc(reqId)
                                          .update({'status': 'approved'});
                                    } else {
                                      if (context.mounted)
                                        InAppNotification.show(
                                          context,
                                          title: 'User Not Found',
                                          message: 'User not found in database.',
                                          accentColor: Colors.redAccent,
                                          icon: Icons.search_off_rounded,
                                        );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection('admin_requests')
                                        .doc(reqId)
                                        .update({'status': 'rejected'});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = authService.isRootAdmin(authService.currentAuthEmail);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('CR Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: AppColors.backgroundTop.withOpacity(0.5),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 96,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Post New Announcement',
              style: AppStyles.heading2,
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.glassCardBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _contentController,
                    maxLines: 4,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Content',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.glassCardBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _detailsController,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Details (optional)',
                      hintText: 'e.g. Room No: TA06 · Venue: Main Hall',
                      hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.3), fontSize: 13),
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      prefixIcon: Icon(Icons.info_outline_rounded,
                          color: AppColors.textSecondary, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.glassCardBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _announcementType,
                    dropdownColor: AppColors.backgroundTop,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Type',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.glassCardBorder),
                      ),
                    ),
                    items: ['Notice', 'Urgent', 'Material'].map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (val) =>
                        setState(() => _announcementType = val!),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          FilePickerResult? result =
                              await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: [
                              'pdf',
                              'jpg',
                              'jpeg',
                              'png',
                              'gif',
                              'webp',
                              'mp4',
                              'doc',
                              'docx',
                              'ppt',
                              'pptx',
                              'txt'
                            ],
                            withData: true,
                          );
                          if (result != null) {
                            setState(() {
                              _announcementFile = result.files.single;
                            });
                          }
                        },
                        icon: Icon(Icons.attach_file,
                            color: AppColors.textPrimary, size: 18),
                        label: Text('Attach File',
                            style: TextStyle(color: AppColors.textPrimary)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side:
                              BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shadowColor: Colors.transparent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _announcementFile?.name ?? 'No file attached',
                          style: TextStyle(
                              color: _announcementFile != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_announcementFile != null)
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.redAccent, size: 20),
                          onPressed: () {
                            setState(() {
                              _announcementFile = null;
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isPostingAnnouncement ? null : _postAnnouncement,
                      icon: _isPostingAnnouncement
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: AppColors.onPrimary, strokeWidth: 2))
                          : Icon(Icons.send, color: AppColors.onPrimary),
                      label: Text(
                          _isPostingAnnouncement
                              ? 'Posting...'
                              : 'Post Announcement',
                          style: TextStyle(
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 48, thickness: 2),
            const Text('Schedule Management', style: AppStyles.heading2),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(Icons.table_chart, color: Colors.blueAccent),
                    title: Text('Schedule Builder',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'Add, edit, or merge classes in the routine',
                        style: TextStyle(color: AppColors.textSecondary)),
                    trailing: Icon(Icons.arrow_forward_ios,
                        color: AppColors.textSecondary, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ScheduleBuilderScreen(user: user)),
                      );
                    },
                  ),
                  Divider(color: AppColors.glassCardBorder),
                  ListTile(
                    leading: Icon(Icons.menu_book, color: AppColors.primary),
                    title: Text('Course & Teacher Registry',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'Manage course codes, names, and teaching teacher names/initials',
                        style: TextStyle(color: AppColors.textSecondary)),
                    trailing: Icon(Icons.arrow_forward_ios,
                        color: AppColors.textSecondary, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CourseRegistryScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 48, thickness: 2),
            const Text(
              'Admin Management',
              style: AppStyles.heading2,
            ),
            // Pending Approvals — visible to ALL CRs
            // Pending Approvals — properly scoped and error-handled
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(), // Query all users, filter in memory to avoid composite index errors
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'Error loading pending approvals: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red)),
                  );
                }

                final allDocs = snapshot.data?.docs ?? [];

                // Root admins can see all pending users, CRs only see their dept/batch
                final isRoot = isRootAdmin;

                final pendingDocs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final bool isApproved = data['isApproved'] == true;
                  final bool isRejected = data['isRejected'] == true;

                  if (isApproved || isRejected)
                    return false; // Must be unapproved and not rejected

                  // If not root, filter by department and batch
                  if (!isRoot) {
                    final dept = data['department'] ?? '';
                    final b = data['batch'] ?? '';
                    if (user == null ||
                        dept != user.department ||
                        b != user.batch) return false;
                  }

                  return true;
                }).toList();

                final pendingCount = pendingDocs.length;

                return GlassCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: pendingCount > 0,
                      leading: Stack(
                        children: [
                          const Icon(Icons.pending_actions,
                              color: Colors.amber),
                          if (pendingCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: Colors.red, shape: BoxShape.circle),
                                child: Text('$pendingCount',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                      title: Text('Pending Approvals',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        pendingCount > 0
                            ? '$pendingCount user(s) waiting for approval'
                            : 'No pending approvals',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      children: [
                        if (pendingCount == 0)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No pending approvals at the moment.',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        ...pendingDocs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final docId = doc.id;
                          final name = (data['name'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final batch = (data['batch'] ?? '').toString();
                          final studentId =
                              (data['studentId'] ?? '').toString();
                          final photoUrl = data['photoUrl'] as String?;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading: CircleAvatar(
                              backgroundImage:
                                  (photoUrl != null && photoUrl.isNotEmpty && (!kIsWeb || photoUrl.contains('supabase')))
                                      ? NetworkImage(photoUrl)
                                      : null,
                              backgroundColor:
                                  AppColors.primary.withOpacity(0.2),
                              child: (photoUrl == null || photoUrl.isEmpty || (kIsWeb && !photoUrl.contains('supabase')))
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : (email.isNotEmpty
                                              ? email[0].toUpperCase()
                                              : 'U'),
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            title: Text(
                              name.isNotEmpty ? name : email,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '$email${batch.isNotEmpty ? ' · Batch $batch' : ''}${studentId.isNotEmpty ? ' · ID: $studentId' : ''}',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Approve',
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.greenAccent),
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(docId)
                                        .update({'isApproved': true});
                                    if (context.mounted) {
                                      InAppNotification.show(
                                        context,
                                        title: 'User Approved',
                                        message: '${name.isNotEmpty ? name : email} has been approved.',
                                        accentColor: Colors.green,
                                        icon: Icons.check_circle_rounded,
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Reject',
                                  icon: const Icon(Icons.cancel,
                                      color: Colors.redAccent),
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(docId)
                                        .update({
                                      'isApproved': false,
                                      'isRejected': true
                                    });
                                    if (context.mounted) {
                                      InAppNotification.show(
                                        context,
                                        title: 'User Rejected',
                                        message: '${name.isNotEmpty ? name : email} was rejected.',
                                        accentColor: Colors.redAccent,
                                        icon: Icons.remove_circle_rounded,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Member Directory — visible to ALL CRs and Root Admins
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading members: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red)),
                  );
                }

                if (!snapshot.hasData) {
                  return const SizedBox();
                }

                final allDocs = snapshot.data?.docs ?? [];
                final isRoot = isRootAdmin;

                final filteredMembers = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  if (!isRoot) {
                    final dept = data['department'] ?? '';
                    final b = data['batch'] ?? '';
                    if (user == null || dept != user.department || b != user.batch) {
                      return false;
                    }
                  }

                  if (_memberSearchQuery.isNotEmpty) {
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final email = (data['email'] ?? '').toString().toLowerCase();
                    final studentId = (data['studentId'] ?? '').toString().toLowerCase();
                    final query = _memberSearchQuery.toLowerCase();
                    return name.contains(query) || email.contains(query) || studentId.contains(query);
                  }

                  return true;
                }).toList();

                filteredMembers.sort((a, b) {
                  final aName = ((a.data() as Map<String, dynamic>)['name'] ?? '').toString().toLowerCase();
                  final bName = ((b.data() as Map<String, dynamic>)['name'] ?? '').toString().toLowerCase();
                  return aName.compareTo(bName);
                });

                final totalMembersCount = allDocs.length;
                final scopedMembersCount = filteredMembers.length;

                return GlassCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: const Icon(Icons.people, color: Colors.blueAccent),
                      title: Text(
                        isRoot ? 'Registered Members' : 'Class Members',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        isRoot
                            ? 'Total App Members: $totalMembersCount (Showing $scopedMembersCount)'
                            : 'Total members: $scopedMembersCount in ${user?.department} ${user?.batch}',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: TextField(
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search members...',
                              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                              prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: AppColors.glassCardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: AppColors.glassCardBorder.withOpacity(0.5)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onChanged: (val) {
                              setState(() {
                                _memberSearchQuery = val;
                              });
                            },
                          ),
                        ),
                        if (filteredMembers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No members found.',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ),
                        ...filteredMembers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['name'] ?? '').toString();
                          final email = (data['email'] ?? '').toString();
                          final dept = (data['department'] ?? '').toString();
                          final batch = (data['batch'] ?? '').toString();
                          final studentId = (data['studentId'] ?? '').toString();
                          final phone = (data['phoneNumber'] ?? '').toString();
                          final photoUrl = data['photoUrl'] as String?;
                          final bool isCRUser = data['isCR'] == true;
                          final bool isApproved = data['isApproved'] == true;
                          final bool isThisUserRoot = authService.isRootAdmin(email);

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.textPrimary.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.glassCardBorder.withOpacity(0.1)),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              leading: CircleAvatar(
                                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty && (!kIsWeb || photoUrl.contains('supabase')))
                                    ? NetworkImage(photoUrl)
                                    : null,
                                backgroundColor: AppColors.primary.withOpacity(0.2),
                                child: (photoUrl == null || photoUrl.isEmpty || (kIsWeb && !photoUrl.contains('supabase')))
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : (email.isNotEmpty
                                                ? email[0].toUpperCase()
                                                : 'U'),
                                        style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name.isNotEmpty ? name : email,
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isThisUserRoot)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Root',
                                          style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    )
                                  else if (isCRUser)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('CR',
                                          style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    isRoot
                                        ? '$email • $dept Batch $batch'
                                        : '$email${studentId.isNotEmpty ? " • ID: $studentId" : ""}',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                  if (isRoot && studentId.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'ID: $studentId${phone.isNotEmpty ? " • Phone: $phone" : ""}',
                                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    )
                                  else if (!isRoot && phone.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Phone: $phone',
                                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isApproved
                                      ? Colors.greenAccent.withOpacity(0.15)
                                      : Colors.amberAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isApproved ? 'Approved' : 'Pending',
                                  style: TextStyle(
                                    color: isApproved ? Colors.greenAccent : Colors.amberAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            if (isRootAdmin) ...[
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('admin_requests')
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snapshot) {
                  final pendingCount = snapshot.data?.docs.length ?? 0;
                  final requests = snapshot.data?.docs ?? [];
                  return GlassCard(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: pendingCount > 0,
                        leading: Stack(
                          children: [
                            const Icon(Icons.admin_panel_settings,
                                color: Colors.amber),
                            if (pendingCount > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  child: Text('$pendingCount',
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                        title: Text('Manage Admins',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          pendingCount > 0
                              ? '$pendingCount admin nomination(s) pending'
                              : 'Approve or reject nominations',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        children: [
                          ...requests.map((doc) {
                            final req = doc.data() as Map<String, dynamic>;
                            final reqId = doc.id;
                            final email = req['requestedEmail'] ?? '';
                            return FutureBuilder<QuerySnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('users')
                                    .where('email', isEqualTo: email)
                                    .get(),
                                builder: (ctx, userSnap) {
                                  String name = '';
                                  String? photoUrl;
                                  if (userSnap.hasData &&
                                      userSnap.data!.docs.isNotEmpty) {
                                    final userData = userSnap.data!.docs.first
                                        .data() as Map<String, dynamic>;
                                    name = userData['name'] ?? '';
                                    photoUrl = userData['photoUrl'];
                                  }

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 4),
                                    leading: CircleAvatar(
                                      backgroundImage: (photoUrl != null &&
                                              photoUrl.isNotEmpty && (!kIsWeb || photoUrl.contains('supabase')))
                                          ? NetworkImage(photoUrl)
                                          : null,
                                      backgroundColor:
                                          Colors.amber.withOpacity(0.2),
                                      child: (photoUrl == null ||
                                              photoUrl.isEmpty || (kIsWeb && !photoUrl.contains('supabase')))
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : (email.isNotEmpty
                                                      ? email[0].toUpperCase()
                                                      : 'A'),
                                              style: const TextStyle(
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.bold),
                                            )
                                          : null,
                                    ),
                                    title: Text(name.isNotEmpty ? name : email,
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                        'Requested by: ${req['requestedBy']}',
                                        style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.check_circle,
                                              color: Colors.greenAccent),
                                          onPressed: () async {
                                            final query =
                                                await FirebaseFirestore.instance
                                                    .collection('users')
                                                    .where('email',
                                                        isEqualTo: email)
                                                    .get();
                                            if (query.docs.isNotEmpty) {
                                              await query.docs.first.reference
                                                  .update({
                                                'isCR': true,
                                                'isApproved': true
                                              });
                                              await FirebaseFirestore.instance
                                                  .collection('admin_requests')
                                                  .doc(reqId)
                                                  .update({'status': 'approved'});
                                              if (context.mounted)
                                                InAppNotification.show(
                                                  context,
                                                  title: 'Admin Approved',
                                                  message: 'Admin approved!',
                                                  accentColor: Colors.green,
                                                  icon: Icons.check_circle_rounded,
                                                );
                                            } else {
                                              if (context.mounted)
                                                InAppNotification.show(
                                                  context,
                                                  title: 'User Not Found',
                                                  message: 'User not found in database.',
                                                  accentColor: Colors.redAccent,
                                                  icon: Icons.search_off_rounded,
                                                );
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.cancel,
                                              color: Colors.redAccent),
                                          onPressed: () async {
                                            await FirebaseFirestore.instance
                                                .collection('admin_requests')
                                                .doc(reqId)
                                                .update({'status': 'rejected'});
                                            if (context.mounted)
                                              InAppNotification.show(
                                                context,
                                                title: 'Admin Rejected',
                                                message: 'Admin request rejected.',
                                                accentColor: Colors.redAccent,
                                                icon: Icons.remove_circle_rounded,
                                              );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                });
                          }),
                          ListTile(
                            leading: const Icon(Icons.add_circle_outline,
                                color: Colors.blueAccent),
                            title: const Text('Advanced Manage Admins',
                                style: TextStyle(color: Colors.blueAccent)),
                            subtitle: Text(
                                'Direct add or view past requests',
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontSize: 11)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 0),
                            onTap: _manageAdminsDialog,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.storage, color: Colors.blueAccent),
                  title: Text('Initialize Database',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Seed sample announcements and schedules',
                      style: TextStyle(color: AppColors.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios,
                      color: AppColors.glassCardBorder, size: 16),
                  onTap: _seedDatabase,
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Reset Database Data',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Wipe all previous announcements, chats and group history',
                      style: TextStyle(color: AppColors.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios,
                      color: AppColors.glassCardBorder, size: 16),
                  onTap: _clearDatabase,
                ),
              ),
            ] else
              GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.person_add, color: AppColors.textSecondary),
                  title: Text('Nominate Admin',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Request rights for a student',
                      style: TextStyle(color: AppColors.textSecondary)),
                  trailing: Icon(Icons.arrow_forward_ios,
                      color: AppColors.glassCardBorder, size: 16),
                  onTap: _nominateAdminDialog,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
