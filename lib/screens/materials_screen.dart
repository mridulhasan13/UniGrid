import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../services/supabase_storage_service.dart';
import '../services/theme_service.dart';
import '../services/fcm_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/glass_card.dart';
import '../widgets/unigrid_loader.dart';
import '../widgets/floating_app_bar.dart';
import '../services/auth_service.dart';
import 'file_viewer_screen.dart';
import '../widgets/in_app_notification.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  String _selectedType = 'Notes';
  final List<String> _types = ['Notes', 'Books', 'Videos', 'Others'];
  String? _selectedSubject;

  String _getSubjectFolderName(StudyMaterial material) {
    final code = material.subjectCode.trim();
    final name = material.subject.trim();
    if (code.isNotEmpty && name.isNotEmpty) {
      return '$code: $name';
    } else if (name.isNotEmpty) {
      return name;
    } else if (code.isNotEmpty) {
      return code;
    } else {
      return 'Uncategorized';
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final isCR = user?.isCR ?? false;
    final isAdmin = user?.isAdmin ?? false;
    final authService = Provider.of<AuthService>(context, listen: false);
    final isAdminEmail = user != null &&
        authService.isRootAdmin(user.email);

    if (user == null || !user.hasDeptScope) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  height: 64,
                ),
                const SizedBox(height: 16),
                const Text('Department not set',
                    style: AppStyles.heading2, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Please complete your profile to view study materials.',
                    style: AppStyles.caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            FloatingAppBar(
              title: 'Study Materials',
              subtitle: '${deptFullName(user.department)} — Batch ${user.batch}',
              actions: [
                if (isCR || isAdmin || isAdminEmail)
                  Builder(
                    builder: (context) {
                      final width = MediaQuery.of(context).size.width;
                      if (width < 460) {
                        return IconButton(
                          icon: Icon(Icons.add, color: AppColors.primary),
                          tooltip: 'Add Material',
                          onPressed: () => _showAddMaterialDialog(user),
                        );
                      }
                      return TextButton.icon(
                        onPressed: () => _showAddMaterialDialog(user),
                        icon: Icon(Icons.add, color: AppColors.primary, size: 20),
                        label: Text(
                          'Add Material',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: AppColors.primary, width: 1),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          // Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.transparent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _types.map((type) {
                final isSelected = type == _selectedType;
                return InkWell(
                  onTap: () => setState(() {
                    _selectedType = type;
                    _selectedSubject = null;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Materials List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(
                      deptBatchCol(user.department, user.batch, 'materials'))
                  .where('type', isEqualTo: _selectedType)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(child: Text('Error loading materials'));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const UniGridLoader(
                    title: 'Loading Materials',
                    subtitle: 'Fetching notes and books...',
                    showBackground: false,
                  );
                }

                final materials = snapshot.data!.docs
                    .map((doc) => StudyMaterial.fromMap(
                        doc.data() as Map<String, dynamic>, doc.id))
                    .toList();

                // Sort automatically: newest first (timestamp descending), nulls last
                materials.sort((a, b) {
                  final aTime = a.timestamp;
                  final bTime = b.timestamp;
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

                if (materials.isEmpty) {
                  return const Center(
                      child: Text('No materials found in this category.'));
                }

                // Group materials by subject
                final Map<String, List<StudyMaterial>> grouped = {};
                for (var material in materials) {
                  final key = _getSubjectFolderName(material);
                  if (!grouped.containsKey(key)) {
                    grouped[key] = [];
                  }
                  grouped[key]!.add(material);
                }

                if (_selectedSubject == null) {
                  final subjects = grouped.keys.toList();
                  subjects.sort();

                  final double screenWidth = MediaQuery.of(context).size.width;
                  final int crossAxisCount = screenWidth < 600 ? 2 : (screenWidth < 900 ? 3 : 4);
                  final double childAspectRatio = screenWidth < 600 ? 1.15 : 1.35;

                  return GridView.builder(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 96,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: childAspectRatio,
                    ),
                    itemCount: subjects.length,
                    itemBuilder: (context, index) {
                      final subjectName = subjects[index];
                      final count = grouped[subjectName]!.length;

                      return GlassCard(
                        padding: EdgeInsets.zero,
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedSubject = subjectName;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withOpacity(0.08),
                                  Colors.transparent,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.folder_copy_rounded,
                                        size: 24,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.primary.withOpacity(0.15),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        '$count file${count == 1 ? "" : "s"}',
                                        style: TextStyle(
                                          color: AppColors.secondary,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        subjectName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedType.toUpperCase(),
                                        style: TextStyle(
                                          color: AppColors.textSecondary.withOpacity(0.7),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }

                final filesInSubject = grouped[_selectedSubject] ?? [];

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSubject = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Back to Folders',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '/',
                              style: TextStyle(
                                color: AppColors.textSecondary.withOpacity(0.5),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedSubject!,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 8,
                          bottom: MediaQuery.of(context).padding.bottom + 96,
                        ),
                        itemCount: filesInSubject.length,
                        itemBuilder: (context, index) {
                          final material = filesInSubject[index];                          return GlassCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: EdgeInsets.zero,
                            child: Material(
                              color: Colors.transparent,
                              child: ListTile(
                                onTap: () {
                                  if (material.fileUrl == null || material.fileUrl!.isEmpty) {
                                    InAppNotification.show(
                                      context,
                                      title: 'File Uploading',
                                      message: 'File is still uploading to the cloud. Please wait a moment...',
                                      accentColor: Colors.amber,
                                      icon: Icons.hourglass_top_rounded,
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => FileViewerScreen(
                                        fileName:
                                            material.fileName ?? material.title,
                                        fileUrl: material.fileUrl,
                                      ),
                                    ),
                                  );
                                },
                                leading:
                                    _getMaterialIcon(material.extension, material.type),
                                title: Text(material.title,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '${material.extension.toUpperCase()} File',
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                    if (material.teacherName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.person_outline,
                                              size: 12, color: AppColors.textSecondary),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Teacher: ${material.teacherName}',
                                            style: TextStyle(
                                                color: AppColors.textSecondary, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (material.fileUrl != null)
                                      IconButton(
                                        icon: Icon(Icons.remove_red_eye,
                                            color: AppColors.primary),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => FileViewerScreen(
                                                fileName:
                                                    material.fileName ?? 'material',
                                                fileUrl: material.fileUrl,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    if (isCR ||
                                        isAdmin ||
                                        isAdminEmail ||
                                        material.uploadedBy == user.email)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.redAccent),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: AppColors.backgroundTop,
                                              title: Text('Delete Material',
                                                  style:
                                                      TextStyle(color: AppColors.textPrimary)),
                                              content: Text(
                                                  'Are you sure you want to delete "${material.title}"? This action cannot be undone.',
                                                  style: TextStyle(
                                                      color: AppColors.textSecondary)),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: Text('Cancel',
                                                      style: TextStyle(
                                                          color: AppColors.textSecondary)),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.redAccent),
                                                  child: Text('Delete',
                                                      style: TextStyle(
                                                          color: AppColors.textPrimary)),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirm == true) {
                                            try {
                                              final fileUrl = material.fileUrl;

                                              // Delete Firestore document instantly (optimistic UI)
                                              FirebaseFirestore.instance
                                                  .collection(deptBatchCol(
                                                      user.department,
                                                      user.batch,
                                                      'materials'))
                                                  .doc(material.id)
                                                  .delete()
                                                  .catchError((e) {
                                                debugPrint('Failed to delete material doc: $e');
                                              });

                                              // Clean up Supabase file in background
                                              if (fileUrl != null && fileUrl.isNotEmpty) {
                                                SupabaseStorageService.deleteFileByUrl(fileUrl).catchError((e) {
                                                  debugPrint('[MaterialDelete] Error cleaning up file: $e');
                                                });
                                              }

                                              if (context.mounted) {
                                                InAppNotification.show(
                                                  context,
                                                  title: 'Material Deleted',
                                                  message: 'Material deleted successfully!',
                                                  accentColor: Colors.redAccent,
                                                  icon: Icons.delete_forever_rounded,
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                InAppNotification.show(
                                                  context,
                                                  title: 'Delete Failed',
                                                  message: 'Failed to delete material: $e',
                                                  accentColor: Colors.redAccent,
                                                  icon: Icons.error_outline_rounded,
                                                );
                                              }
                                            }
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
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
    ),
    );
  }

  Future<void> _showAddMaterialDialog(AppUser user) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isAdminEmail = authService.isRootAdmin(user.email);
    if (!user.isCR && !user.isAdmin && !isAdminEmail) {
      InAppNotification.show(
        context,
        title: 'Access Denied',
        message: 'Only CRs or Admins can upload materials.',
        accentColor: Colors.redAccent,
        icon: Icons.lock_rounded,
      );
      return;
    }
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();
    String materialType = 'Notes';
    List<PlatformFile> selectedFiles = [];
    bool isUploading = false;
    StateSetter? dialogSetState;

    String selectedCourseId = 'custom';

    await GlassCard.showGlassDialog(
      context: context,
      child: StatefulBuilder(builder: (context, setState) {
        dialogSetState = setState;
        return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(
                    deptBatchCol(user.department, user.batch, 'courses'))
                .snapshots(),
            builder: (context, coursesSnapshot) {
              final courseDocs = coursesSnapshot.data?.docs ?? [];
              final courses = courseDocs
                  .map((d) => CourseDetail.fromMap(
                      d.data() as Map<String, dynamic>, d.id))
                  .toList();
              courses.sort((a, b) => a.courseCode
                  .toLowerCase()
                  .compareTo(b.courseCode.toLowerCase()));

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Upload Study Material',
                    style: AppStyles.heading2,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: selectedCourseId,
                    dropdownColor: AppColors.backgroundTop,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Select Registered Course',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.glassCardBorder)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary)),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text('Custom Course (Type manually)',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                      ),
                      ...courses.map((course) {
                        return DropdownMenuItem(
                          value: course.id,
                          child: Text(
                              '${course.courseCode}: ${course.courseName} (${course.teacherShort})'),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedCourseId = val!;
                        if (selectedCourseId != 'custom') {
                          final match = courses
                              .firstWhere((c) => c.id == selectedCourseId);
                          subjectCtrl.text = match.courseName;
                          codeCtrl.text = match.courseCode;
                          teacherCtrl.text = match.teacherName;
                        } else {
                          subjectCtrl.clear();
                          codeCtrl.clear();
                          teacherCtrl.clear();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Material Title (e.g. Lecture 1 Slides)',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.glassCardBorder)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  TextField(
                    controller: subjectCtrl,
                    enabled: selectedCourseId == 'custom',
                    style: TextStyle(
                        color: selectedCourseId == 'custom'
                            ? AppColors.textPrimary
                            : AppColors.textSecondary),
                    decoration: InputDecoration(
                      labelText: 'Subject Name',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.glassCardBorder)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  TextField(
                    controller: codeCtrl,
                    enabled: selectedCourseId == 'custom',
                    style: TextStyle(
                        color: selectedCourseId == 'custom'
                            ? AppColors.textPrimary
                            : AppColors.textSecondary),
                    decoration: InputDecoration(
                      labelText: 'Subject Code',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.glassCardBorder)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  TextField(
                    controller: teacherCtrl,
                    enabled: selectedCourseId == 'custom',
                    style: TextStyle(
                        color: selectedCourseId == 'custom'
                            ? AppColors.textPrimary
                            : AppColors.textSecondary),
                    decoration: InputDecoration(
                      labelText: 'Teacher Name',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.glassCardBorder)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: materialType,
                    dropdownColor: AppColors.backgroundTop,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Material Category',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.glassCardBorder)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary)),
                    ),
                    items: ['Notes', 'Books', 'Videos', 'Others'].map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (val) => materialType = val!,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Attached Files / Books / Slides',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (selectedFiles.isNotEmpty)
                    Column(
                      children: List.generate(selectedFiles.length, (idx) {
                        final file = selectedFiles[idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.insert_drive_file,
                                  color: AppColors.primary, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Size: ${(file.size / 1024).toStringAsFixed(1)} KB',
                                      style: TextStyle(
                                          color: AppColors.textSecondary, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.redAccent),
                                onPressed: () {
                                  dialogSetState?.call(() {
                                    selectedFiles.removeAt(idx);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        FilePickerResult? result =
                            await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          withData: true,
                          allowMultiple: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          dialogSetState?.call(() {
                            selectedFiles.addAll(result.files);
                          });
                        }
                      } catch (e) {
                        if (context.mounted) {
                          InAppNotification.show(
                            context,
                            title: 'File Selection Error',
                            message: 'Error selecting files: $e',
                            accentColor: Colors.redAccent,
                            icon: Icons.error_outline_rounded,
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.glassCardBorder,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Attach File(s)',
                        style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                  if (isUploading)
                    Column(
                      children: [
                        LinearProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 8),
                        Text('Uploading material to Supabase...',
                            style:
                                TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed:
                              isUploading ? null : () => Navigator.pop(context),
                          child: Text('Cancel',
                              style: TextStyle(color: AppColors.textSecondary))),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: isUploading
                            ? null
                            : () async {
                                 if (titleCtrl.text.isEmpty ||
                                     subjectCtrl.text.isEmpty) {
                                   InAppNotification.show(
                                     context,
                                     title: 'Missing Fields',
                                     message: 'Please fill Title and Subject Name.',
                                     accentColor: Colors.amber,
                                     icon: Icons.warning_amber_rounded,
                                   );
                                   return;
                                 }
                                 if (selectedFiles.isEmpty) {
                                   InAppNotification.show(
                                     context,
                                     title: 'Missing File',
                                     message: 'Please attach at least one file.',
                                     accentColor: Colors.amber,
                                     icon: Icons.attach_file_rounded,
                                   );
                                   return;
                                 }

                                try {
                                  dialogSetState
                                      ?.call(() => isUploading = true);

                                  final title = titleCtrl.text.trim();
                                  final subject = subjectCtrl.text.trim();
                                  final subjectCode = codeCtrl.text.trim();
                                  final teacherName = teacherCtrl.text.trim();
                                  final type = materialType;
                                  final userEmail = Provider.of<AppUser?>(
                                              context,
                                              listen: false)
                                          ?.email ??
                                      'Admin';
                                  final userId = Provider.of<AppUser?>(context,
                                              listen: false)
                                          ?.id ??
                                      '';

                                  if (mounted) {
                                    Navigator.pop(context);
                                    InAppNotification.show(
                                      context,
                                      title: 'Material Uploading',
                                      message: 'Uploading ${selectedFiles.length} material(s) in background...',
                                      accentColor: AppColors.primary,
                                      icon: Icons.cloud_upload_rounded,
                                    );
                                  }

                                  for (final pickedFile in selectedFiles) {
                                    Uint8List? fileBytes = pickedFile.bytes;
                                    if (fileBytes == null &&
                                         pickedFile.path != null &&
                                         !kIsWeb) {
                                       final file = File(pickedFile.path!);
                                       fileBytes = await file.readAsBytes();
                                     }

                                    if (fileBytes != null) {
                                      final fileName = pickedFile.name;
                                      final extension =
                                          pickedFile.extension ?? 'unknown';

                                      final finalTitle =
                                          selectedFiles.length > 1
                                              ? '$title ($fileName)'
                                              : title;

                                      _performBackgroundMaterialUpload(
                                        finalTitle,
                                        subject,
                                        subjectCode,
                                        teacherName,
                                        type,
                                        fileBytes,
                                        fileName,
                                        extension,
                                        userEmail,
                                        userId,
                                        user,
                                      );
                                    }
                                  }
                                } catch (e) {
                                  dialogSetState
                                      ?.call(() => isUploading = false);
                                  if (context.mounted) {
                                    InAppNotification.show(
                                      context,
                                      title: 'Upload Error',
                                      message: 'Error starting upload: $e',
                                      accentColor: Colors.redAccent,
                                      icon: Icons.error_outline_rounded,
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        child: Text(
                          selectedFiles.isNotEmpty
                              ? 'Upload ${selectedFiles.length} File(s)'
                              : 'Select & Upload',
                          style: TextStyle(
                              color: AppColors.onPrimary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            });
      }),
    );
  }

  Future<void> _performBackgroundMaterialUpload(
    String title,
    String subject,
    String subjectCode,
    String teacherName,
    String type,
    Uint8List bytes,
    String fileName,
    String extension,
    String userEmail,
    String userId,
    AppUser user,
  ) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isAdminEmail = authService.isRootAdmin(user.email);
    if (!user.isCR && !user.isAdmin && !isAdminEmail) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Access Denied',
          message: 'Only CRs or Admins can upload materials.',
          accentColor: Colors.redAccent,
          icon: Icons.lock_rounded,
        );
      }
      return;
    }
    DocumentReference? docRef;
    try {
      // Stage 1: Post the metadata instantly
      docRef = await FirebaseFirestore.instance
          .collection(deptBatchCol(user.department, user.batch, 'materials'))
          .add({
        'title': title,
        'subject': subject,
        'subjectCode': subjectCode,
        'teacherName': teacherName,
        'type': type,
        'fileUrl': null, // Will update once upload finishes
        'fileName': fileName,
        'extension': extension,
        'uploadedBy': userEmail,
        'uploadedByUserId': userId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      FCMService.notifyNewMaterial(
        title: title,
        subject: subject,
        senderUserId: userId,
        department: user.department,
        batch: user.batch,
      );

      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Material Created',
          message: 'Material entry created. Uploading file...',
          accentColor: Colors.amber,
          icon: Icons.pending_actions_rounded,
        );
      }

      // Stage 2: Background File Upload (Supabase via HTTP)
      final downloadUrl = await SupabaseStorageService.uploadFile(
        bytes: bytes,
        fileName: fileName,
        folder: 'materials',
      );

      // Stage 3: Update document with URL
      await docRef.update({
        'fileUrl': downloadUrl,
      });

      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Upload Complete',
          message: 'Material file uploaded successfully!',
          accentColor: Colors.green,
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        InAppNotification.show(
          context,
          title: 'Upload Error',
          message: 'Error uploading material: $e',
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Widget _getMaterialIcon(String ext, String type) {
    if (type == 'Videos') {
      return const Icon(Icons.video_library, color: Colors.redAccent, size: 32);
    }
    final e = ext.trim().toLowerCase();
    if (e == 'pdf') {
      return const Icon(Icons.picture_as_pdf,
          color: Colors.redAccent, size: 32);
    }
    if (e == 'doc' || e == 'docx') {
      return const Icon(Icons.description, color: Colors.blueAccent, size: 32);
    }
    if (e == 'xls' || e == 'xlsx') {
      return const Icon(Icons.table_view, color: Colors.greenAccent, size: 32);
    }
    if (e == 'ppt' || e == 'pptx') {
      return const Icon(Icons.slideshow, color: Colors.orangeAccent, size: 32);
    }
    if (e == 'zip' || e == 'rar' || e == 'tar' || e == '7z') {
      return const Icon(Icons.archive, color: Colors.amberAccent, size: 32);
    }
    if (e == 'png' || e == 'jpg' || e == 'jpeg' || e == 'gif') {
      return const Icon(Icons.image, color: Colors.purpleAccent, size: 32);
    }
    return Icon(Icons.insert_drive_file, color: AppColors.textSecondary, size: 32);
  }
}
