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
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/glass_card.dart';
import '../widgets/linkified_text.dart';
import '../widgets/unigrid_loader.dart';
import 'file_viewer_screen.dart';
import '../notifications/in_app_notification.dart';

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

    String initialPart = 'None';
    String rawName = courseToEdit?.courseName.trim() ?? '';
    if (rawName.isNotEmpty) {
      final partMatch = RegExp(r'[\s\-_(]+([AB])[\s\-_)]*$', caseSensitive: false).firstMatch(rawName);
      if (partMatch != null) {
        initialPart = partMatch.group(1)!.toUpperCase();
        rawName = rawName.substring(0, partMatch.start).trim();
      }
    }
    final nameCtrl = TextEditingController(text: rawName);
    String selectedPart = initialPart;

    String getEffectiveCourseName() {
      final base = nameCtrl.text.trim();
      if (base.isEmpty) return '';
      if (selectedPart == 'A' || selectedPart == 'B') {
        return '$base - $selectedPart';
      }
      return base;
    }

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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: nameCtrl,
                            onChanged: (_) => setDialogState(() {}),
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Course Name (e.g. TTQC)',
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.glassCardBorder)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.primary)),
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: selectedPart,
                            dropdownColor: AppColors.backgroundTop,
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Part / Section',
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.glassCardBorder)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.primary)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'None', child: Text('None (Lab/Single)')),
                              DropdownMenuItem(value: 'A', child: Text('A (- A)')),
                              DropdownMenuItem(value: 'B', child: Text('B (- B)')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => selectedPart = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (selectedPart != 'None' && nameCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Course will be saved as: ${getEffectiveCourseName()}',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                                    pickedFile.path != null &&
                                    !kIsWeb) {
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
                               InAppNotification.show(
                                 ctx,
                                 title: 'Upload Error',
                                 message: 'Error uploading file: $e',
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
                            final finalCourseName = getEffectiveCourseName();
                            final newCourseData = {
                              'courseCode': codeCtrl.text.trim(),
                              'courseName': finalCourseName,
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

                              // Automatically sync update to all matching routine schedule entries
                              final schedulePath = user != null && user.hasDeptScope
                                  ? deptBatchCol(
                                      user.department, user.batch, 'schedule')
                                  : 'schedule';

                              final oldCode = courseToEdit.courseCode.trim();
                              final oldName = courseToEdit.courseName.trim();
                              final oldTShort = courseToEdit.teacherShort.trim();
                              final oldTName = courseToEdit.teacherName.trim();

                              final newCode = codeCtrl.text.trim();
                              final newName = finalCourseName.trim();
                              final newTShort = teacherShortCtrl.text.trim();
                              final newTName = teacherNameCtrl.text.trim();

                              final schedSnap = await FirebaseFirestore.instance
                                  .collection(schedulePath)
                                  .get();

                              final batch = FirebaseFirestore.instance.batch();
                              bool hasUpdates = false;

                              // Check if this course itself is a lab course
                              final isThisCourseLab = oldName.toLowerCase().contains('lab') ||
                                  oldName.toLowerCase().contains('practical') ||
                                  newName.toLowerCase().contains('lab') ||
                                  newName.toLowerCase().contains('practical') ||
                                  oldCode.toLowerCase().contains('lab') ||
                                  newCode.toLowerCase().contains('lab');

                              for (var doc in schedSnap.docs) {
                                final data = doc.data();
                                final schedSubject =
                                    (data['subject'] ?? '').toString().trim();
                                final schedTeacher =
                                    (data['teacher'] ?? '').toString().trim();
                                final schedGroup =
                                    (data['group'] ?? '').toString().trim();

                                // Protection for labs: "for the lab anything should not be changed"
                                final isSchedLab = schedSubject.toLowerCase().contains('lab') ||
                                    schedSubject.toLowerCase().contains('practical') ||
                                    schedGroup.isNotEmpty;

                                // Never alter a lab slot if editing a theory course, and vice versa
                                if (isThisCourseLab != isSchedLab) {
                                  continue;
                                }

                                bool isMatch = false;
                                final subjLower = schedSubject.toLowerCase();
                                final oldCodeLower = oldCode.toLowerCase();
                                final oldTShortLower = oldTShort.toLowerCase();
                                final oldTNameLower = oldTName.toLowerCase();
                                final schedTeacherLower = schedTeacher.toLowerCase();

                                if (oldCodeLower.isNotEmpty && subjLower.contains(oldCodeLower)) {
                                  if (isThisCourseLab) {
                                    isMatch = true;
                                  } else {
                                    // For theory courses: match by teacher or matching part/name
                                    if (oldTShortLower.isNotEmpty && schedTeacherLower.isNotEmpty) {
                                      if (schedTeacherLower == oldTShortLower ||
                                          (oldTNameLower.isNotEmpty && schedTeacherLower == oldTNameLower)) {
                                        isMatch = true;
                                      }
                                    }
                                    if (!isMatch && oldName.isNotEmpty && subjLower.contains(oldName.toLowerCase())) {
                                      isMatch = true;
                                    }
                                    if (!isMatch) {
                                      if (selectedPart == 'A' &&
                                          (subjLower.contains('(a)') || subjLower.contains('- a') || subjLower.endsWith(' a'))) {
                                        isMatch = true;
                                      } else if (selectedPart == 'B' &&
                                          (subjLower.contains('(b)') || subjLower.contains('- b') || subjLower.endsWith(' b'))) {
                                        isMatch = true;
                                      } else if (selectedPart == 'None' &&
                                          !subjLower.contains('(a)') &&
                                          !subjLower.contains('(b)') &&
                                          !subjLower.contains('- a') &&
                                          !subjLower.contains('- b')) {
                                        isMatch = true;
                                      }
                                    }
                                  }
                                } else if (oldName.isNotEmpty && subjLower.contains(oldName.toLowerCase())) {
                                  isMatch = true;
                                }

                                if (isMatch) {
                                  final updates = <String, dynamic>{
                                    'subject': '$newCode: $newName',
                                    'teacher': newTShort.isNotEmpty
                                        ? newTShort
                                        : newTName,
                                    'lastUpdatedDate':
                                        FieldValue.serverTimestamp(),
                                  };

                                  batch.update(doc.reference, updates);
                                  hasUpdates = true;
                                }
                              }

                              if (hasUpdates) {
                                await batch.commit();
                              }
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
            automaticallyImplyLeading: false,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.glassCardBorder),
                    ),
                    child: Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary, size: 18),
                  ),
                ),
              ),
            ),
            title: Row(
              children: [
                Icon(Icons.menu_book_rounded,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Course & Teacher Info',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundTop.withOpacity(0.75),
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.primary.withOpacity(0.2),
                        width: 1.0,
                      ),
                    ),
                  ),
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
                        horizontal: 16, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_rounded,
                                color: AppColors.primary, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                university,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.primary.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.school_rounded,
                                      color: AppColors.primary, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active Session:',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    activeLevelTerm,
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(color: AppColors.glassCardBorder, height: 1),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.filter_list_rounded,
                                    color: AppColors.textSecondary, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Filter Term:',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              height: 36,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.glassCardBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedLevelTermFilter,
                                  dropdownColor: AppColors.backgroundTop,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.5,
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

                              // Filter schedules belonging specifically to this course (matching section, lab/theory, course code, and teacher)
                              final courseSchedules = schedules.where((s) {
                                final sSub = s.subject.trim().toLowerCase();
                                final sSubname = s.subname.trim().toLowerCase();
                                final sTeacher = s.teacher.trim().toLowerCase();

                                final cCode = course.courseCode.trim().toLowerCase();
                                final cName = course.courseName.trim().toLowerCase();
                                final tShort = course.teacherShort.trim().toLowerCase();
                                final tName = course.teacherName.trim().toLowerCase();

                                // 1. Strict Lab vs Theory check
                                bool courseIsLab = cName.contains('lab') ||
                                    cCode.contains('lab');
                                bool scheduleIsLab = sSub.contains('lab') ||
                                    sSubname.contains('lab');

                                if (courseIsLab != scheduleIsLab) {
                                  return false; // One is lab, one is theory
                                }

                                // 2. Strict Section / Part check (A vs B vs C)
                                String? courseSection;
                                final courseSecMatch = RegExp(
                                        r'-\s*([a-c])\b|\(([a-c])\)|\bsec(tion)?\s*([a-c])\b|[\s\-_(]+([a-c])[\s\-_)]*$',
                                        caseSensitive: false)
                                    .firstMatch(cName);
                                if (courseSecMatch != null) {
                                  courseSection = (courseSecMatch.group(1) ??
                                          courseSecMatch.group(2) ??
                                          courseSecMatch.group(4) ??
                                          courseSecMatch.group(5))
                                      ?.toLowerCase();
                                }

                                String? schedSection;
                                final schedSecMatch = RegExp(
                                        r'-\s*([a-c])\b|\(([a-c])\)|\bsec(tion)?\s*([a-c])\b|[\s\-_(]+([a-c])[\s\-_)]*$',
                                        caseSensitive: false)
                                    .firstMatch(sSub);
                                if (schedSecMatch != null) {
                                  schedSection = (schedSecMatch.group(1) ??
                                          schedSecMatch.group(2) ??
                                          schedSecMatch.group(4) ??
                                          schedSecMatch.group(5))
                                      ?.toLowerCase();
                                }

                                if (courseSection != null && schedSection != null) {
                                  if (courseSection != schedSection) {
                                    return false; // Explicitly different sections (e.g. A vs B)
                                  }
                                }

                                // 3. Teacher mismatch check if both have teachers defined
                                if (tShort.isNotEmpty && sTeacher.isNotEmpty) {
                                  final sTeacherTokens = sTeacher
                                      .split(RegExp(r'[\s/,-]+'))
                                      .where((t) => t.isNotEmpty)
                                      .toList();
                                  final tShortTokens = tShort
                                      .split(RegExp(r'[\s/,-]+'))
                                      .where((t) => t.isNotEmpty)
                                      .toList();

                                  bool hasTeacherOverlap = tShortTokens.any((tok) => sTeacher.contains(tok)) ||
                                      (tName.isNotEmpty && (sTeacher.contains(tName) || tName.contains(sTeacher)));

                                  // If sections didn't distinguish them and teacher explicitly differs, don't mix them
                                  if (!hasTeacherOverlap && sTeacherTokens.isNotEmpty) {
                                    if (courseSection == null || schedSection == null) {
                                      // Only reject if schedule teacher doesn't match this course's teacher
                                      return false;
                                    }
                                  }
                                }

                                // 4. Strict Course Code matching
                                if (cCode.isNotEmpty && sSub.isNotEmpty) {
                                  final RegExp courseCodeRegex =
                                      RegExp(r'[a-z]{2,4}\s*\d{3}(-\d{4})?');
                                  final Iterable<Match> matches =
                                      courseCodeRegex.allMatches(sSub);
                                  if (matches.isNotEmpty) {
                                    bool codeMatched = false;
                                    final cleanCCode =
                                        cCode.replaceAll(RegExp(r'[\s-]'), '');
                                    final cleanSSub =
                                        sSub.replaceAll(RegExp(r'[\s-]'), '');

                                    for (final m in matches) {
                                      final text = m.group(0)!;
                                      final cleanText =
                                          text.replaceAll(RegExp(r'[\s-]'), '');
                                      if (cleanText == cleanCCode ||
                                          cleanSSub.contains(cleanCCode) ||
                                          cleanCCode.contains(cleanText)) {
                                        codeMatched = true;
                                        break;
                                      }
                                    }
                                    if (!codeMatched) {
                                      return false; // Mentions a different course code
                                    }
                                  }
                                }

                                // 5. Course Code or Name match
                                bool hasCodeMatch = cCode.isNotEmpty &&
                                    (sSub.contains(cCode) ||
                                        sSubname.contains(cCode));
                                bool hasNameMatch = cName.isNotEmpty &&
                                    (sSub.contains(cName) ||
                                        sSubname.contains(cName) ||
                                        cName.contains(sSub));

                                if (hasCodeMatch || hasNameMatch) {
                                  return true;
                                }

                                // 6. Teacher match fallback
                                if (sSub.isNotEmpty) {
                                  final subjectLetters =
                                      sSub.replaceAll(RegExp(r'[^a-z]'), '');
                                  if (subjectLetters.isNotEmpty &&
                                      subjectLetters.length >= 3) {
                                    return false; // Specifies a different course
                                  }
                                }

                                if (sTeacher.isNotEmpty) {
                                  if (tShort.isNotEmpty) {
                                    final tShortTokens = tShort
                                        .split(RegExp(r'[\s/,-]+'))
                                        .where((t) => t.isNotEmpty)
                                        .toList();
                                    for (var tok in tShortTokens) {
                                      if (sTeacher.contains(tok)) return true;
                                    }
                                  }
                                  if (tName.isNotEmpty &&
                                      (sTeacher.contains(tName) ||
                                          tName.contains(sTeacher))) {
                                    return true;
                                  }
                                }

                                return false;
                              }).toList();

                              // ─── Class Counting ───────────────────────────
                              // RULES:
                              //   • Lab course       → span is session duration, always counts as 1
                              //   • Normal class     → span = number of class periods
                              //                        (span 1 → 1,  span 2 → 2,  span 3 → 3)
                              //   • Parallel groups  → each sub-group (Gr A, Gr B) counts as 1 each
                              //
                              // De-duplicate first: the same recurring class slot appears as
                              // one Firestore document per week (from copy/auto-reset). We must
                              // collapse entries that share the same logical identity
                              // (dayOfWeek + startSlot + subject + group + teacher) so they are
                              // only counted once.

                              // Detect if the course is a lab
                              final bool courseIsLab =
                                  course.courseName.trim().toLowerCase().contains('lab') ||
                                  course.courseCode.trim().toLowerCase().contains('lab');

                              // ── Step 1: De-duplicate recurring slots ──────
                              // Group all matching schedule entries by their logical identity.
                              // For each unique logical slot, keep the MOST RECENT dated entry
                              // (or any entry if none are dated) to get the latest status.
                              final Map<String, ClassSchedule> dedupedSlots = {};
                              for (var s in courseSchedules) {
                                final identityKey =
                                    '${s.dayOfWeek.trim().toLowerCase()}_'
                                    '${s.startSlot}_'
                                    '${s.subject.trim().toLowerCase()}_'
                                    '${s.group.trim().toLowerCase()}_'
                                    '${s.teacher.trim().toLowerCase()}';

                                if (!dedupedSlots.containsKey(identityKey)) {
                                  dedupedSlots[identityKey] = s;
                                } else {
                                  // Keep the entry with the most recent scheduledDate
                                  final existing = dedupedSlots[identityKey]!;
                                  final existingDate = existing.scheduledDate;
                                  final newDate = s.scheduledDate;
                                  if (newDate != null &&
                                      (existingDate == null ||
                                          newDate.isAfter(existingDate))) {
                                    dedupedSlots[identityKey] = s;
                                  }
                                }
                              }

                              // ── Step 2: Count from de-duplicated slots ────
                              // Within the de-duplicated set, detect truly parallel
                              // groups (same day + slot but different group labels).
                              int totalClasses = 0;
                              int completedClasses = 0;
                              int cancelledClasses = 0;
                              int upcomingClasses = 0;

                              // Group de-duplicated entries by (day, slot) to detect parallels.
                              final Map<String, List<ClassSchedule>> slotGroups = {};
                              for (var s in dedupedSlots.values) {
                                final day = s.dayOfWeek.trim().toLowerCase();
                                final slot = s.startSlot;
                                final groupKey = '${day}_$slot';
                                slotGroups.putIfAbsent(groupKey, () => []).add(s);
                              }

                              for (var entry in slotGroups.entries) {
                                final list = entry.value;
                                if (list.isEmpty) continue;

                                // A slot group is truly parallel ONLY when there are
                                // multiple entries sharing the exact same (day, slot)
                                // — e.g. Group A and Group B scheduled simultaneously.
                                final bool isTrulyParallel = list.length > 1;

                                if (isTrulyParallel) {
                                  // Parallel groups: each sub-entry (Gr A, Gr B …) = 1 class.
                                  // Example: Gr A completed + Gr B cancelled → 1 completed + 1 cancelled.
                                  for (var s in list) {
                                    final stat = s.status.trim().toLowerCase();
                                    if (stat == 'auto' ||
                                        stat == 'boycott' ||
                                        stat == 'holiday' ||
                                        stat == 'no class' ||
                                        stat == 'no_class') {
                                      continue; // No Class, Auto, Boycott, and Holiday are uncounted!
                                    }
                                    totalClasses += 1;
                                    if (stat == 'completed') {
                                      completedClasses += 1;
                                    } else if (stat == 'cancelled') {
                                      cancelledClasses += 1;
                                    } else {
                                      upcomingClasses += 1;
                                    }
                                  }
                                } else {
                                  // Single entry (with or without a group label).
                                  final s = list.first;
                                  final stat = s.status.trim().toLowerCase();

                                  if (stat == 'auto' ||
                                      stat == 'boycott' ||
                                      stat == 'holiday' ||
                                      stat == 'no class' ||
                                      stat == 'no_class') {
                                    continue; // No Class, Auto, Boycott, and Holiday are uncounted!
                                  }

                                  // Lab → 1 session regardless of how many slots it fills.
                                  // Normal class → span IS the class count
                                  //   (2-slot merged theory class = 2 classes).
                                  final int weight = courseIsLab ? 1 : (s.span > 0 ? s.span : 1);

                                  totalClasses += weight;
                                  if (stat == 'completed') {
                                    completedClasses += weight;
                                  } else if (stat == 'cancelled') {
                                    cancelledClasses += weight;
                                  } else {
                                    upcomingClasses += weight;
                                  }
                                }
                              }


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
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
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
                                                  course.teacherName.isEmpty ? 'Teacher TBD' : course.teacherName,
                                                  style: TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (course.teacherShort.isNotEmpty) ...[
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
