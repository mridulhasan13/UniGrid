import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../services/supabase_storage_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/glass_card.dart';
import '../widgets/unigrid_loader.dart';
import 'file_viewer_screen.dart';

class CourseRegistryScreen extends StatefulWidget {
  const CourseRegistryScreen({super.key});

  @override
  State<CourseRegistryScreen> createState() => _CourseRegistryScreenState();
}

class _CourseRegistryScreenState extends State<CourseRegistryScreen> {
  String _selectedLevelTermFilter =
      'Active'; // 'Active', 'All', or specific Level-Term
  final List<String> _levelTermOptions = [
    'Active',
    'All',
    'Level-1 Term-1',
    'Level-1 Term-2',
    'Level-2 Term-1',
    'Level-2 Term-2',
    'Level-3 Term-1',
    'Level-3 Term-2',
    'Level-4 Term-1',
    'Level-4 Term-2',
  ];

  Future<void> _showAddEditCourseDialog({
    CourseDetail? courseToEdit,
    required String activeLevelTerm,
  }) async {
    final codeCtrl = TextEditingController(text: courseToEdit?.courseCode);
    final nameCtrl = TextEditingController(text: courseToEdit?.courseName);
    final teacherNameCtrl =
        TextEditingController(text: courseToEdit?.teacherName);
    final teacherShortCtrl =
        TextEditingController(text: courseToEdit?.teacherShort);
    final creditCtrl =
        TextEditingController(text: courseToEdit?.totalCredit ?? '3.0');
    List<String> uploadedPdfUrls =
        courseToEdit != null ? List<String>.from(courseToEdit.ctMarksUrls) : [];
    List<String> uploadedPdfNames = courseToEdit != null
        ? List<String>.from(courseToEdit.ctMarksNames)
        : [];
    bool isUploading = false;
    String selectedDialogLevelTerm = courseToEdit?.levelTerm ?? activeLevelTerm;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      courseToEdit != null
                          ? 'Edit Course Details'
                          : 'Add Course details',
                      style: AppStyles.heading2
                          .copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: selectedDialogLevelTerm,
                      dropdownColor: AppColors.backgroundTop,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Level & Term',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.glassCardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary)),
                      ),
                      items: _levelTermOptions
                          .where((opt) => opt != 'Active' && opt != 'All')
                          .map((val) =>
                              DropdownMenuItem(value: val, child: Text(val)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedDialogLevelTerm = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: codeCtrl,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Course Code (e.g. IPE 101)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.glassCardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary)),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Course Name (e.g. Introduction to IPE)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.glassCardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary)),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: teacherNameCtrl,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText:
                            'Teaching Teacher Full Name (e.g. Dr. Mohammad)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.glassCardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary)),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: teacherShortCtrl,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Teacher Initials / Short Form (e.g. MM)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.glassCardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary)),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: creditCtrl,
                      style: TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Total Credit (e.g. 3.0 or 1.5)',
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.glassCardBorder)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary)),
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Class Test (CT) Marks PDFs',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (isUploading)
                      Column(
                        children: [
                          LinearProgressIndicator(color: AppColors.primary),
                          const SizedBox(height: 8),
                          Text('Uploading PDFs to Supabase...',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      )
                    else ...[
                      if (uploadedPdfUrls.isNotEmpty)
                        Column(
                          children:
                              List.generate(uploadedPdfUrls.length, (idx) {
                            final name = uploadedPdfNames.length > idx
                                ? uploadedPdfNames[idx]
                                : 'CT_Marks_${idx + 1}.pdf';
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
                                  const Icon(Icons.picture_as_pdf,
                                      color: Colors.redAccent, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Ready to save',
                                          style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent),
                                    onPressed: () {
                                      setDialogState(() {
                                        uploadedPdfUrls.removeAt(idx);
                                        if (uploadedPdfNames.length > idx) {
                                          uploadedPdfNames.removeAt(idx);
                                        }
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
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf'],
                              allowMultiple: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              setDialogState(() => isUploading = true);

                              for (final pickedFile in result.files) {
                                Uint8List? fileBytes = pickedFile.bytes;
                                if (fileBytes == null &&
                                    pickedFile.path != null) {
                                  final file = File(pickedFile.path!);
                                  fileBytes = await file.readAsBytes();
                                }

                                if (fileBytes != null) {
                                  final url =
                                      await SupabaseStorageService.uploadFile(
                                    bytes: fileBytes,
                                    fileName: pickedFile.name,
                                    folder: 'ct_marks',
                                  );
                                  setDialogState(() {
                                    uploadedPdfUrls.add(url);
                                    uploadedPdfNames.add(pickedFile.name);
                                  });
                                }
                              }
                              setDialogState(() => isUploading = false);
                            }
                          } catch (e) {
                            setDialogState(() => isUploading = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text('Error uploading file: $e')),
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
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Upload CT Marks PDF(s)',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Cancel',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final newCourseData = {
                              'courseCode': codeCtrl.text.trim(),
                              'courseName': nameCtrl.text.trim(),
                              'teacherName': teacherNameCtrl.text.trim(),
                              'teacherShort': teacherShortCtrl.text.trim(),
                              'totalCredit': creditCtrl.text.trim(),
                              'ctMarksUrls': uploadedPdfUrls,
                              'ctMarksNames': uploadedPdfNames,
                              'ctMarksUrl': uploadedPdfUrls.isNotEmpty
                                  ? uploadedPdfUrls.first
                                  : null,
                              'ctMarksName': uploadedPdfNames.isNotEmpty
                                  ? uploadedPdfNames.first
                                  : null,
                              'levelTerm': selectedDialogLevelTerm,
                              'timestamp': FieldValue.serverTimestamp(),
                            };

                            final user =
                                Provider.of<AppUser?>(context, listen: false);
                            final coursesPath =
                                user != null && user.hasDeptScope
                                    ? deptBatchCol(
                                        user.department, user.batch, 'courses')
                                    : 'courses';
                            if (courseToEdit != null) {
                              await FirebaseFirestore.instance
                                  .collection(coursesPath)
                                  .doc(courseToEdit.id)
                                  .update(newCourseData);
                            } else {
                              await FirebaseFirestore.instance
                                  .collection(coursesPath)
                                  .add(newCourseData);
                            }

                            if (ctx.mounted) Navigator.pop(ctx);
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
                            courseToEdit != null ? 'Update' : 'Add Course',
                            style: TextStyle(
                                color: AppColors.onPrimary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteCourse(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        title: Text('Delete Course Detail?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Are you sure you want to remove this course and teacher detail from the registry?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      final user = Provider.of<AppUser?>(context, listen: false);
      final coursesPath = user != null && user.hasDeptScope
          ? deptBatchCol(user.department, user.batch, 'courses')
          : 'courses';
      
      // Clean up Supabase storage files in background
      FirebaseFirestore.instance.collection(coursesPath).doc(id).get().then((docSnapshot) {
        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          if (data != null) {
            final rawUrls = data['ctMarksUrls'] ?? data['ctMarksUrl'];
            if (rawUrls is String && rawUrls.isNotEmpty) {
              SupabaseStorageService.deleteFileByUrl(rawUrls);
            } else if (rawUrls is List) {
              for (final url in rawUrls) {
                if (url is String && url.isNotEmpty) {
                  SupabaseStorageService.deleteFileByUrl(url);
                }
              }
            }
          }
        }
      }).catchError((e) {
        debugPrint('[CourseDelete] Error retrieving file URLs for deletion: $e');
      });

      // Delete Firestore document instantly (optimistic UI)
      FirebaseFirestore.instance.collection(coursesPath).doc(id).delete().catchError((e) {
        debugPrint('[CourseDelete] Failed to delete course doc: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AppUser?>(context);
    final isCR = user != null && user.isCR;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection(user != null && user.hasDeptScope
              ? deptBatchCol(user.department, user.batch, 'routine_metadata')
              : 'routine_metadata')
          .doc('info')
          .snapshots(),
      builder: (context, metaSnapshot) {
        String university = 'Bangladesh University of Textiles';
        String activeLevelTerm = 'Level-1 Term-2';

        if (metaSnapshot.hasData && metaSnapshot.data!.exists) {
          final data = metaSnapshot.data!.data() as Map<String, dynamic>;
          university = data['university'] ?? university;
          activeLevelTerm = data['levelTerm'] ?? activeLevelTerm;
        }

        final queryLevelTerm = _selectedLevelTermFilter == 'Active'
            ? activeLevelTerm
            : _selectedLevelTermFilter;

        final coursesPath = user != null && user.hasDeptScope
            ? deptBatchCol(user.department, user.batch, 'courses')
            : 'courses';
        final schedulePath = user != null && user.hasDeptScope
            ? deptBatchCol(user.department, user.batch, 'schedule')
            : 'schedule';
        final Query coursesQuery =
            FirebaseFirestore.instance.collection(coursesPath);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Course & Teacher Info'),
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
          body: Container(
            decoration: BoxDecoration(
              gradient: AppGradients.mainBackground,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Info & Filter Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          university,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Active Session: ',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12),
                            ),
                            Text(
                              activeLevelTerm,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Divider(color: AppColors.glassCardBorder, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Filter Term:',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              height: 38,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.glassCardBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedLevelTermFilter,
                                  dropdownColor: AppColors.backgroundTop,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(
                                          () => _selectedLevelTermFilter = val);
                                    }
                                  },
                                  items: _levelTermOptions.map((opt) {
                                    return DropdownMenuItem(
                                      value: opt,
                                      child: Text(opt == 'Active'
                                          ? 'Active ($activeLevelTerm)'
                                          : opt),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Course List
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: coursesQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        debugPrint('Courses Fetch Error: ${snapshot.error}');
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Failed to fetch registry data. Make sure Firestore indexes are built, or try again later.',
                              style: TextStyle(
                                  color: Colors.redAccent.withOpacity(0.8),
                                  fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: UniGridLoader(
                            title: 'Loading Syllabus & Registry',
                            subtitle: 'Syncing courses from department...',
                            showBackground: false,
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      var courses = docs
                          .map((d) => CourseDetail.fromMap(
                              d.data() as Map<String, dynamic>, d.id))
                          .toList();

                      // Filter in memory
                      if (_selectedLevelTermFilter != 'All') {
                        courses = courses
                            .where((c) => c.levelTerm == queryLevelTerm)
                            .toList();
                      }

                      // Sort in memory by courseCode
                      courses.sort((a, b) => a.courseCode
                          .toLowerCase()
                          .compareTo(b.courseCode.toLowerCase()));

                      if (courses.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.menu_book_outlined,
                                  size: 64,
                                  color: AppColors.textPrimary.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(
                                'No course details added yet\nfor $_selectedLevelTermFilter.',
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection(schedulePath)
                            .snapshots(),
                        builder: (context, scheduleSnapshot) {
                          final scheduleDocs = scheduleSnapshot.data?.docs ?? [];

                          final schedules = scheduleDocs
                              .map((d) => ClassSchedule.fromMap(
                                  d.data() as Map<String, dynamic>, d.id))
                              .toList();

                          return ListView.builder(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 80),
                            itemCount: courses.length,
                            itemBuilder: (context, index) {
                              final course = courses[index];

                              // Filter teacher schedules
                              final teacherSchedules = schedules.where((s) {
                                final schedTeacher =
                                    s.teacher.trim().toLowerCase();
                                final tShort =
                                    course.teacherShort.trim().toLowerCase();
                                final tName =
                                    course.teacherName.trim().toLowerCase();

                                if (schedTeacher.isEmpty) return false;

                                // Exact matches
                                if (tShort.isNotEmpty && schedTeacher == tShort)
                                  return true;
                                if (tName.isNotEmpty && schedTeacher == tName)
                                  return true;

                                // Substring matches (e.g. "MM / SA" contains "MM" or "Dr. Mohammad" contains "Mohammad")
                                if (tShort.isNotEmpty &&
                                    schedTeacher.contains(tShort)) return true;
                                if (tName.isNotEmpty &&
                                    (schedTeacher.contains(tName) ||
                                        tName.contains(schedTeacher)))
                                  return true;

                                return false;
                              }).toList();

                              final totalClasses = teacherSchedules.length;
                              final completedClasses = teacherSchedules
                                  .where((s) =>
                                      s.status.trim().toLowerCase() ==
                                      'completed')
                                  .length;
                               final cancelledClasses = teacherSchedules
                                  .where((s) {
                                    final stat = s.status.trim().toLowerCase();
                                    return stat == 'cancelled' ||
                                        stat == 'no class' ||
                                        stat == 'no_class';
                                  })
                                  .length;
                               final upcomingClasses = teacherSchedules
                                  .where((s) =>
                                      s.status.trim().toLowerCase() ==
                                          'upcoming' ||
                                      s.status.trim().toLowerCase() ==
                                          'pending')
                                  .length;

                              return GlassCard(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Course Code & Credit Badges Stacked Vertically
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                AppColors.primary
                                                    .withOpacity(0.2),
                                                AppColors.secondary
                                                    .withOpacity(0.1),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: AppColors.primary
                                                    .withOpacity(0.4)),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary
                                                    .withOpacity(0.15),
                                                blurRadius: 10,
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            course.courseCode,
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                AppColors.textPrimary.withOpacity(0.05),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: AppColors.glassCardBorder),
                                          ),
                                          child: Text(
                                            '${course.totalCredit} Cr',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),

                                    // Course Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            course.courseName,
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(Icons.person_outline,
                                                  size: 14,
                                                  color: AppColors.textSecondary),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  course.teacherName,
                                                  style: TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: AppColors.primary
                                                          .withOpacity(0.3)),
                                                ),
                                                child: Text(
                                                  course.teacherShort,
                                                  style: const TextStyle(
                                                    color: Color(0xFF00FF87),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_selectedLevelTermFilter ==
                                              'All') ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              course.levelTerm,
                                              style: TextStyle(
                                                color: AppColors.textSecondary.withOpacity(0.3),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          // Class Statistics Row
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                _buildStatBadge(
                                                    'Total: $totalClasses',
                                                    Colors.deepPurpleAccent
                                                        .withOpacity(0.12),
                                                    Colors.deepPurpleAccent),
                                                const SizedBox(width: 6),
                                                _buildStatBadge(
                                                    'Completed: $completedClasses',
                                                    Colors.greenAccent
                                                        .withOpacity(0.12),
                                                    Colors.greenAccent),
                                                const SizedBox(width: 6),
                                                _buildStatBadge(
                                                    'Cancelled: $cancelledClasses',
                                                    Colors.redAccent
                                                        .withOpacity(0.12),
                                                    Colors.redAccent),
                                                const SizedBox(width: 6),
                                                _buildStatBadge(
                                                    'Upcoming: $upcomingClasses',
                                                    Colors.blueAccent
                                                        .withOpacity(0.12),
                                                    Colors.blueAccent),
                                              ],
                                            ),
                                          ),
                                          if (course
                                              .ctMarksUrls.isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: List.generate(
                                                  course.ctMarksUrls.length,
                                                  (reverseIdx) {
                                                final pIdx = course.ctMarksUrls.length - 1 - reverseIdx;
                                                final urlString =
                                                    course.ctMarksUrls[pIdx];
                                                final pName = course
                                                            .ctMarksNames
                                                            .length >
                                                        pIdx
                                                    ? course.ctMarksNames[pIdx]
                                                    : 'CT Marks ${pIdx + 1}';
                                                return InkWell(
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            FileViewerScreen(
                                                          fileName: pName,
                                                          fileUrl: urlString,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 6),
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          Colors.redAccent
                                                              .withOpacity(
                                                                  0.15),
                                                          Colors.amber
                                                              .withOpacity(
                                                                  0.08),
                                                        ],
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                          color: Colors
                                                              .redAccent
                                                              .withOpacity(
                                                                  0.3)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                            Icons
                                                                .picture_as_pdf,
                                                            color: Colors
                                                                .redAccent,
                                                            size: 14),
                                                        const SizedBox(
                                                            width: 6),
                                                        Text(
                                                          pName.length > 25
                                                              ? '${pName.substring(0, 22)}...'
                                                              : pName,
                                                          style:
                                                              TextStyle(
                                                            color: AppColors.textPrimary,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Actions for CRs
                                    if (isCR) ...[
                                      const SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert,
                                            color: AppColors.textSecondary),
                                        color: AppColors.backgroundTop,
                                        onSelected: (val) {
                                          if (val == 'edit') {
                                            _showAddEditCourseDialog(
                                              courseToEdit: course,
                                              activeLevelTerm: activeLevelTerm,
                                            );
                                          } else if (val == 'delete') {
                                            _deleteCourse(course.id);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit details',
                                                style: TextStyle(
                                                    color: Colors.amberAccent)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete details',
                                                style: TextStyle(
                                                    color: Colors.redAccent)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: isCR
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddEditCourseDialog(
                      activeLevelTerm: activeLevelTerm),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  icon: Icon(Icons.menu_book, color: AppColors.onPrimary),
                  label: Text(
                    'Add Course',
                    style: TextStyle(
                        color: AppColors.onPrimary, fontWeight: FontWeight.bold),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildStatBadge(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
