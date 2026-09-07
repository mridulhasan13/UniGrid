import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../widgets/glass_card.dart';
import '../widgets/linkified_text.dart';
import '../widgets/floating_app_bar.dart';
import '../widgets/unigrid_loader.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/dept_scope.dart';
import '../notifications/in_app_notification.dart';
import '../notifications/routine_reminder_service.dart';
import '../widgets/image_crop_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Upload and Update states
  bool _isUploading = false;

  // Tabs navigation state
  String _activeTab = 'Edit profile';

  // Notifications State Toggles
  bool _notifRoutine = true;
  bool _notifChat = true;
  bool _notifAlerts = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }



  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    bool rVal = prefs.getBool('notif_routine') ?? true;
    bool cVal = prefs.getBool('notif_chat') ?? true;
    bool aVal = prefs.getBool('notif_alerts') ?? true;

    final user = Provider.of<AppUser?>(context, listen: false);
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.id).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data['notifRoutine'] is bool && prefs.getBool('notif_routine') == null) {
            rVal = data['notifRoutine'] as bool;
            await prefs.setBool('notif_routine', rVal);
          }
          if (data['notifChat'] is bool && prefs.getBool('notif_chat') == null) {
            cVal = data['notifChat'] as bool;
            await prefs.setBool('notif_chat', cVal);
          }
          if (data['notifAlerts'] is bool && prefs.getBool('notif_alerts') == null) {
            aVal = data['notifAlerts'] as bool;
            await prefs.setBool('notif_alerts', aVal);
          }
        }
      } catch (e) {
        debugPrint('[ProfileScreen] Error checking cloud notification settings: $e');
      }

      if (rVal) {
        RoutineReminderService.syncRoutineReminders(user);
      }
    }

    if (mounted) {
      setState(() {
        _notifRoutine = rVal;
        _notifChat = cVal;
        _notifAlerts = aVal;
      });
    }
  }

  Future<void> _saveNotificationSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);

    final user = Provider.of<AppUser?>(context, listen: false);
    if (user != null) {
      String firestoreField = 'notifAlerts';
      if (key == 'notif_routine') firestoreField = 'notifRoutine';
      if (key == 'notif_chat') firestoreField = 'notifChat';
      if (key == 'notif_alerts') firestoreField = 'notifAlerts';

      FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .set({firestoreField: value}, SetOptions(merge: true))
          .catchError((e) {
        debugPrint('Failed to sync notification pref to Firestore: $e');
      });

      if (key == 'notif_routine') {
        RoutineReminderService.syncRoutineReminders(user);
      }
    }

    if (mounted) {
      String titleText = 'Routine Reminders';
      if (key == 'notif_chat') titleText = 'Chat Notifications';
      if (key == 'notif_alerts') titleText = 'Announcements & Alerts';

      InAppNotification.show(
        context,
        title: titleText,
        message: value ? 'Alerts enabled' : 'Alerts disabled',
        accentColor: value ? AppColors.primary : Colors.amber,
        icon: value ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
      );
    }
  }

  // Text Form Controllers
  late TextEditingController _nameController;
  late TextEditingController _idController;
  late TextEditingController _deptController;
  late TextEditingController _batchController;
  late TextEditingController _phoneController;
  late TextEditingController _schoolController;
  late TextEditingController _collegeController;
  late TextEditingController _emailController;
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;

  bool _isInitialized = false;
  bool _isSaving = false;
  String _saveError = '';

  @override
  void dispose() {
    if (_isInitialized) {
      _nameController.dispose();
      _idController.dispose();
      _deptController.dispose();
      _batchController.dispose();
      _phoneController.dispose();
      _schoolController.dispose();
      _collegeController.dispose();
      _emailController.dispose();
      _currentPasswordController.dispose();
      _newPasswordController.dispose();
    }
    super.dispose();
  }



  // Base64 vs Network Image Loader (Optimized with ResizeImage for instant rendering)
  ImageProvider? _getProfileImage(String photoUrl) {
    if (photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('data:image')) {
      try {
        final base64String = photoUrl.split(',').last;
        return ResizeImage(MemoryImage(base64Decode(base64String)), width: 180, height: 180);
      } catch (e) {
        return null;
      }
    }
    return ResizeImage(NetworkImage(photoUrl), width: 180, height: 180);
  }

  // Profile image upload picker
  Future<void> _pickAndUploadPhoto() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      final result = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (result == null) return;
      final file = result.files.first;
      Uint8List? fileBytes;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        fileBytes = file.bytes!;
      } else if (file.path != null) {
        fileBytes = await File(file.path!).readAsBytes();
      }

      if (fileBytes == null) return;

      // Show interactive image cropper/editor dialog to crop, rotate, and scale
      if (!mounted) return;
      final croppedBytes = await ImageCropDialog.show(
        context,
        imageBytes: fileBytes,
        initialShape: CropShape.circle,
        title: 'Adjust Profile Picture',
      );

      // If user cancelled the crop dialog, abort upload
      if (croppedBytes == null) return;

      setState(() {
        _isUploading = true;
      });

      await authService.uploadProfilePhoto(
        croppedBytes,
        'png',
      );

      if (mounted) {
        setState(() => _isUploading = false);
        InAppNotification.show(
          context,
          title: 'Photo Updated',
          message: 'Profile photo updated successfully!',
          accentColor: Colors.green,
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        InAppNotification.show(
          context,
          title: 'Upload Failed',
          message: e.toString().split(']').last.trim(),
          accentColor: Colors.redAccent,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  // Save changes popup trigger
  void _showSavedPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            decoration: BoxDecoration(
              color: AppColors.glassCardColor.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.15),
                    blurRadius: 30,
                    spreadRadius: 5),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_circle_rounded,
                      color: AppColors.primary, size: 56),
                ),
                const SizedBox(height: 16),
                Text(
                  'Saved!',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your profile has been updated.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    if (user == null)
      return const Scaffold(
        body: UniGridLoader(
          title: 'Retrieving Workspace Profile',
          subtitle: 'Syncing settings with server...',
        ),
      );

    // One-time load initialization
    if (!_isInitialized) {
      _nameController = TextEditingController(text: user.name);
      _idController = TextEditingController(text: user.studentId);
      _deptController = TextEditingController(text: user.department);
      _batchController = TextEditingController(text: user.batch);
      _phoneController = TextEditingController(text: user.phoneNumber);
      _schoolController = TextEditingController(text: user.schoolName);
      _collegeController = TextEditingController(text: user.collegeName);
      _emailController = TextEditingController(text: user.email);
      _currentPasswordController = TextEditingController();
      _newPasswordController = TextEditingController();
      _isInitialized = true;
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth <= 760;

    // Resolve navigation active pane
    final Widget activePane;
    switch (_activeTab) {
      case 'Edit profile':
        activePane = _buildEditProfilePane(user);
        break;
      case 'Notification':
        activePane = _buildNotificationPane();
        break;
      case 'Security':
        activePane = _buildSecurityPane(user);
        break;
      case 'Appearance':
        activePane = _buildAppearancePane(user);
        break;
      case 'Officers':
        activePane = _buildOfficersPane();
        break;
      case 'About':
        activePane = _buildAboutPane();
        break;
      case 'Help':
        activePane = _buildHelpPane();
        break;
      case 'Terms & Conditions':
        activePane = _buildTermsPane();
        break;
      case 'Privacy Policy':
        activePane = _buildPrivacyPane();
        break;
      case 'Community Guidelines':
        activePane = _buildCommunityGuidelinesPane();
        break;
      default:
        activePane = _buildEditProfilePane(user);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.mainBackground,
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FloatingAppBar(
                title: 'My Settings',
                actions: [
                  IconButton(
                    icon: Icon(Icons.logout_rounded, color: AppColors.textSecondary),
                    tooltip: 'Logout',
                    onPressed: () {
                      Provider.of<AuthService>(context, listen: false).signOut();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              Expanded(
                child: isMobile
                    ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Horizontal tab row for mobile
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildHorizontalTabItem(
                              'Edit profile', Icons.edit_outlined),
                          _buildHorizontalTabItem('Notification',
                              Icons.notifications_none_outlined),
                          _buildHorizontalTabItem(
                              'Security', Icons.lock_outline_rounded),
                          _buildHorizontalTabItem(
                              'Appearance', Icons.settings_outlined),
                          _buildHorizontalTabItem(
                              'Officers', Icons.people_outline_rounded),
                          _buildHorizontalTabItem(
                              'About', Icons.info_outline_rounded),
                          _buildHorizontalTabItem(
                              'Help', Icons.help_outline_rounded),
                          _buildHorizontalTabItem(
                              'Terms & Conditions', Icons.gavel_outlined),
                          _buildHorizontalTabItem(
                              'Privacy Policy', Icons.privacy_tip_outlined),
                          _buildHorizontalTabItem(
                              'Community Guidelines', Icons.verified_user_outlined),
                        ],
                      ),
                    ),
                  ),
                  Divider(color: AppColors.glassCardBorder, height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 16,
                        bottom: MediaQuery.of(context).padding.bottom + 96,
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: activePane,
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).padding.bottom + 96,
                ),
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Navigation Sidebar
                      SizedBox(
                        width: 220,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.chevron_left,
                                    color: AppColors.textSecondary, size: 20),
                                SizedBox(width: 4),
                                Text(
                                  'settings',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _buildSidebarItem(
                                'Edit profile', Icons.edit_outlined),
                            _buildSidebarItem('Notification',
                                Icons.notifications_none_outlined),
                            _buildSidebarItem(
                                'Security', Icons.lock_outline_rounded),
                            _buildSidebarItem(
                                'Appearance', Icons.settings_outlined),
                            _buildSidebarItem(
                                'Officers', Icons.people_outline_rounded),
                            _buildSidebarItem(
                                'About', Icons.info_outline_rounded),
                            _buildSidebarItem(
                                'Help', Icons.help_outline_rounded),
                            _buildSidebarItem(
                                'Terms & Conditions', Icons.gavel_outlined),
                            _buildSidebarItem(
                                'Privacy Policy', Icons.privacy_tip_outlined),
                            _buildSidebarItem(
                                'Community Guidelines', Icons.verified_user_outlined),
                          ],
                        ),
                      ),
                      // Thin vertical divider line
                      Container(
                        width: 1,
                        height: 540,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        color: AppColors.glassCardBorder,
                      ),
                      // Main Content Area Pane
                      Expanded(
                        child: activePane,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  // Sidebar navigation item widget
  Widget _buildSidebarItem(String title, IconData icon) {
    final bool isActive = _activeTab == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = title;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile Swipeable Tab widget
  Widget _buildHorizontalTabItem(String title, IconData icon) {
    final bool isActive = _activeTab == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = title;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.textPrimary.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // PANES IMPLEMENTATIONS
  // -------------------------------------------------------------

  // Pane 1: Edit Profile Form Content
  Widget _buildEditProfilePane(AppUser user) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth <= 520;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title Header & Photo edit row (Centered Column on Mobile, Split Row on Tablet/Desktop)
        if (isNarrow) ...[
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                        ),
                      ),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: AppColors.backgroundTop,
                            backgroundImage: _getProfileImage(user.photoUrl),
                            child: user.photoUrl.isEmpty
                                ? Text(
                                    user.name.isNotEmpty
                                        ? user.name[0].toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary),
                                  )
                                : null,
                          ),
                          if (_isUploading)
                            const Positioned.fill(
                              child: CircleAvatar(
                                backgroundColor: Colors.black45,
                                radius: 44,
                                child: CircularProgressIndicator(
                                    color: AppColors.textPrimary, strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _isUploading ? null : _pickAndUploadPhoto,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                _isUploading ? Colors.grey : AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.backgroundTop, width: 1.5),
                          ),
                          child: Icon(
                            _isUploading
                                ? Icons.hourglass_top
                                : Icons.camera_alt,
                            color: AppColors.textPrimary,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Edit profile',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                if (user.isCR) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: const Text(
                      'Root Admin',
                      style: TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'Edit profile',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.backgroundTop,
                          backgroundImage: _getProfileImage(user.photoUrl),
                          child: user.photoUrl.isEmpty
                              ? Text(
                                  user.name.isNotEmpty
                                      ? user.name[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary),
                                )
                              : null,
                        ),
                        if (_isUploading)
                          const Positioned.fill(
                            child: CircleAvatar(
                              backgroundColor: Colors.black45,
                              radius: 36,
                              child: CircularProgressIndicator(
                                  color: AppColors.textPrimary, strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadPhoto,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _isUploading ? Colors.grey : AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.backgroundTop, width: 1.5),
                        ),
                        child: Icon(
                          _isUploading ? Icons.hourglass_top : Icons.camera_alt,
                          color: AppColors.textPrimary,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // Text Form inputs layout
        if (isNarrow) ...[
          _buildFormInput(
              label: 'First Name (Full Name)', controller: _nameController),
          const SizedBox(height: 14),
          _buildFormInput(label: 'Student ID', controller: _idController),
          const SizedBox(height: 14),
          _buildFormInput(
              label: 'Email',
              controller: _emailController,
              readOnly: true,
              showCheckmark: true),
          const SizedBox(height: 14),
          _buildDeptDropdown(user),
          const SizedBox(height: 14),
          _buildBatchDropdown(user),
          const SizedBox(height: 14),
          _buildFormInput(
              label: 'Contact Number', controller: _phoneController),
          const SizedBox(height: 14),
          _buildFormInput(label: 'School Name', controller: _schoolController),
          const SizedBox(height: 14),
          _buildFormInput(
              label: 'College Name', controller: _collegeController),
        ] else ...[
          Row(
            children: [
              Expanded(
                  child: _buildFormInput(
                      label: 'First Name (Full Name)',
                      controller: _nameController)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildFormInput(
                      label: 'Student ID', controller: _idController)),
            ],
          ),
          const SizedBox(height: 14),
          _buildFormInput(
              label: 'Email',
              controller: _emailController,
              readOnly: true,
              showCheckmark: true),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildDeptDropdown(user)),
              const SizedBox(width: 16),
              Expanded(child: _buildBatchDropdown(user)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _buildFormInput(
                      label: 'Contact Number', controller: _phoneController)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildFormInput(
                      label: 'School Name', controller: _schoolController)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _buildFormInput(
                      label: 'College Name', controller: _collegeController)),
              const SizedBox(width: 16),
              Expanded(child: Container()), // empty space for alignment
            ],
          ),
        ],

        // Error display panel
        if (_saveError.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Text(
              _saveError,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],

        const SizedBox(height: 28),

        // Cancel / Save buttons (Stacked vertically on Mobile, side-by-side Row on Desktop)
        if (isNarrow) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      setState(() {
                        _isSaving = true;
                        _saveError = '';
                      });
                      try {
                        await Provider.of<AuthService>(context, listen: false)
                            .updateUserProfile(
                              name: _nameController.text.trim(),
                              studentId: _idController.text.trim(),
                              department: _deptController.text.trim(),
                              batch: _batchController.text.trim(),
                              phoneNumber: _phoneController.text.trim(),
                              schoolName: _schoolController.text.trim(),
                              collegeName: _collegeController.text.trim(),
                            );
                        if (mounted) {
                          setState(() {
                            _isSaving = false;
                          });
                          _showSavedPopup();
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _isSaving = false;
                            _saveError = e.toString();
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.onPrimary, strokeWidth: 1.5),
                    )
                  : Text(
                      'Save Changes',
                      style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _nameController.text = user.name;
                        _idController.text = user.studentId;
                        _deptController.text = user.department;
                        _batchController.text = user.batch;
                        _phoneController.text = user.phoneNumber;
                        _schoolController.text = user.schoolName;
                        _collegeController.text = user.collegeName;
                        _saveError = '';
                      });
                      InAppNotification.show(
                        context,
                        title: 'Form Reset',
                        message: 'Form fields reset to original values.',
                        accentColor: AppColors.primary,
                        icon: Icons.refresh_rounded,
                      );
                    },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primary, width: 1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _nameController.text = user.name;
                          _idController.text = user.studentId;
                          _deptController.text = user.department;
                          _batchController.text = user.batch;
                          _phoneController.text = user.phoneNumber;
                          _schoolController.text = user.schoolName;
                          _collegeController.text = user.collegeName;
                          _saveError = '';
                        });
                        InAppNotification.show(
                          context,
                          title: 'Form Reset',
                          message: 'Form fields reset to original values.',
                          accentColor: AppColors.primary,
                          icon: Icons.refresh_rounded,
                        );
                      },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary, width: 1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        setState(() {
                          _isSaving = true;
                          _saveError = '';
                        });
                        try {
                          await Provider.of<AuthService>(context, listen: false)
                              .updateUserProfile(
                                name: _nameController.text.trim(),
                                studentId: _idController.text.trim(),
                                department: _deptController.text.trim(),
                                batch: _batchController.text.trim(),
                                phoneNumber: _phoneController.text.trim(),
                                schoolName: _schoolController.text.trim(),
                                collegeName: _collegeController.text.trim(),
                              );
                          if (mounted) {
                            setState(() {
                              _isSaving = false;
                            });
                            _showSavedPopup();
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _isSaving = false;
                              _saveError = e.toString();
                            });
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppColors.onPrimary, strokeWidth: 1.5),
                      )
                    : Text(
                        'Save',
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Custom Outline Form Input Generator
  Widget _buildFormInput({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    bool showCheckmark = false,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          obscureText: isPassword,
          style: TextStyle(
              color: readOnly ? AppColors.textSecondary : AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.textPrimary.withOpacity(0.03),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
            suffixIcon: showCheckmark
                ? Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDeptDropdown(AppUser user) {
    if (user.isApproved) {
      return _buildFormInput(
        label: 'Department',
        controller: _deptController,
        readOnly: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Department',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: kDeptCodes.contains(_deptController.text)
              ? _deptController.text
              : null,
          isExpanded: true,
          dropdownColor: AppColors.backgroundTop,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.textPrimary.withOpacity(0.03),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          items: kDepartments
              .map((d) => DropdownMenuItem<String>(
                    value: d['code'],
                    child: Text(
                      '${d['code']} — ${d['name']}',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _deptController.text = v;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildBatchDropdown(AppUser user) {
    if (user.isApproved) {
      return _buildFormInput(
        label: 'Batch',
        controller: _batchController,
        readOnly: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Batch',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: kBatches.contains(_batchController.text)
              ? _batchController.text
              : null,
          isExpanded: true,
          dropdownColor: AppColors.backgroundTop,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.textPrimary.withOpacity(0.03),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          items: kBatches
              .map((b) => DropdownMenuItem<String>(
                    value: b,
                    child: Text(
                      'Batch $b',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _batchController.text = v;
              });
            }
          },
        ),
      ],
    );
  }

  // Pane 2: Notification Switches Content
  Widget _buildNotificationPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Notification Settings',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Customize your app notification alerts.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
            'Routine Reminders',
            'Notify me 10 minutes before class starts.',
            _notifRoutine, (newVal) async {
          setState(() {
            _notifRoutine = newVal;
          });
          await _saveNotificationSetting('notif_routine', newVal);
        }),
        const SizedBox(height: 12),
        _buildSwitchTile(
            'New Chat Messages',
            'Receive real-time push notifications for chat.',
            _notifChat, (newVal) async {
          setState(() {
            _notifChat = newVal;
          });
          await _saveNotificationSetting('notif_chat', newVal);
        }),
        const SizedBox(height: 12),
        _buildSwitchTile(
            'Announcements & CR Alerts',
            'Receive alerts for class cancellations or updates.',
            _notifAlerts, (newVal) async {
          setState(() {
            _notifAlerts = newVal;
          });
          await _saveNotificationSetting('notif_alerts', newVal);
        }),
      ],
    );
  }

  // Custom Switch row
  Widget _buildSwitchTile(String title, String subtitle, bool currentVal,
      ValueChanged<bool> onChanged) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!currentVal),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.04)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: currentVal,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withOpacity(0.3),
                inactiveThumbColor: AppColors.textSecondary.withOpacity(0.3),
                inactiveTrackColor: AppColors.glassCardBorder,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Pane 3: Security & Credentials Content
  Widget _buildSecurityPane(AppUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Security Settings',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage password resets and credentials.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.04)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Password & Login Security',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'A secure reset link can be sent to your email (${user.email}) to safely change your account password.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  if (user.email.isNotEmpty) {
                    try {
                      await Provider.of<AuthService>(context, listen: false)
                          .sendPasswordResetEmail(user.email);
                      if (mounted) {
                        InAppNotification.show(
                          context,
                          title: 'Password Reset',
                          message: 'Password reset email dispatched successfully!',
                          accentColor: Colors.green,
                          icon: Icons.mark_email_read_rounded,
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        InAppNotification.show(
                          context,
                          title: 'Password Reset Failed',
                          message: 'Failed: $e',
                          accentColor: Colors.redAccent,
                          icon: Icons.error_outline_rounded,
                        );
                      }
                    }
                  }
                },
                icon: Icon(Icons.mail_outline_rounded,
                    size: 16, color: AppColors.onPrimary),
                label: Text('Send Password Reset Email',
                    style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Divider(color: AppColors.glassCardBorder, height: 1),
              ),
              Text('Change Password',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              const SizedBox(height: 12),
              _buildFormInput(
                  label: 'Current Password',
                  controller: _currentPasswordController,
                  isPassword: true),
              const SizedBox(height: 12),
              _buildFormInput(
                  label: 'New Password',
                  controller: _newPasswordController,
                  isPassword: true),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (_currentPasswordController.text.isEmpty ||
                            _newPasswordController.text.isEmpty) {
                          InAppNotification.show(
                            context,
                            title: 'Password Required',
                            message: 'Please fill both password fields.',
                            accentColor: Colors.amber,
                            icon: Icons.lock_outline_rounded,
                          );
                          return;
                        }
                        setState(() => _isSaving = true);
                        try {
                          await Provider.of<AuthService>(context, listen: false)
                              .updatePassword(
                            _currentPasswordController.text,
                            _newPasswordController.text,
                          );
                          _currentPasswordController.clear();
                          _newPasswordController.clear();
                          if (mounted) {
                            InAppNotification.show(
                              context,
                              title: 'Password Updated',
                              message: 'Password updated successfully!',
                              accentColor: Colors.green,
                              icon: Icons.lock_reset_rounded,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            InAppNotification.show(
                              context,
                              title: 'Password Update Failed',
                              message: 'Failed: $e',
                              accentColor: Colors.redAccent,
                              icon: Icons.error_outline_rounded,
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isSaving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppColors.onPrimary, strokeWidth: 2))
                    : Text('Update Password',
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Danger Zone: Delete Account (Play Store Compliance) ───────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  const Text('Danger Zone: Delete Account',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Permanently delete your account, profile data, and credentials from UniGrid. This action is irreversible.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showDeleteAccountDialog(user),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: Colors.white),
                label: const Text('Delete My Account',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade700,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDeleteAccountDialog(AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.glassCardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.redAccent.withOpacity(0.3))),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                  SizedBox(width: 10),
                  Text('Delete Account?',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                'Are you sure you want to permanently delete your account (${user.email})?\n\n'
                'All your personal data, department profile, and cloud sessions will be completely purged. This cannot be undone.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(dialogCtx),
                  child: Text('Cancel',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setDialogState(() => isDeleting = true);
                          try {
                            await Provider.of<AuthService>(context, listen: false)
                                .deleteAccount();
                            if (mounted) {
                              Navigator.pop(dialogCtx);
                              InAppNotification.show(
                                context,
                                title: 'Account Deleted',
                                message: 'Your account has been deleted permanently.',
                                accentColor: Colors.redAccent,
                                icon: Icons.check_circle_outline_rounded,
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isDeleting = false);
                            if (mounted) {
                              InAppNotification.show(
                                context,
                                title: 'Deletion Failed',
                                message: 'Error: $e. If required, re-login and try again.',
                                accentColor: Colors.redAccent,
                                icon: Icons.error_outline_rounded,
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Permanently Delete',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Pane 4: Appearance & Styling Themes Content
  Widget _buildAppearancePane(AppUser user) {
    final themeService = Provider.of<ThemeService>(context);
    final activeTheme = themeService.currentTheme;
    final bool isRootAdmin = Provider.of<AuthService>(context, listen: false)
        .isRootAdmin(user.email);
    final bool hasAdminAccess = user.isCR || isRootAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Appearance & Themes',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Personalize the visual coloring style of the application.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        if (!hasAdminAccess) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: Colors.amber, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Global Theme Locked',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Only Class Representatives (CRs) or Admins can customize the visual theme color globally for everyone.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        _buildThemeCard(
            'Mist Emerald',
            'Primary Green & Slate Mist (Default Active)',
            const Color(0xFF10B981),
            activeTheme == 'Mist Emerald',
            hasAdminAccess),
        const SizedBox(height: 12),
        _buildThemeCard(
            'Sky Sapphire',
            'Vibrant Indigo & Deep Cosmic Blue',
            const Color(0xFF3B82F6),
            activeTheme == 'Sky Sapphire',
            hasAdminAccess),
        const SizedBox(height: 12),
        _buildThemeCard(
            'Pastel Bloom',
            'Soft Lilac Pink & Deep Plum Dark',
            const Color(0xFFEC4899),
            activeTheme == 'Pastel Bloom',
            hasAdminAccess),
        const SizedBox(height: 12),
        _buildThemeCard(
            'Sayan Cyan',
            'Deep Ocean Teal & Icy Cyan Glow',
            const Color(0xFF06B6D4),
            activeTheme == 'Sayan Cyan',
            hasAdminAccess),
        const SizedBox(height: 12),
        _buildThemeCard(
            'Ruby Rose',
            'Elegant Crimson & Dark Cherry Red',
            const Color(0xFFEF4444),
            activeTheme == 'Ruby Rose',
            hasAdminAccess),
        const SizedBox(height: 12),
        _buildThemeCard(
            'Amethyst Orchid',
            'Royal Velvet & Amethyst Charcoal',
            const Color(0xFF8B5CF6),
            activeTheme == 'Amethyst Orchid',
            hasAdminAccess),
        _buildThemeCard(
            'Sunset Coral',
            'Vibrant Sunset Coral & Deep Ember',
            const Color(0xFFF97316),
            activeTheme == 'Sunset Coral',
            hasAdminAccess),
        const SizedBox(height: 12),
        _buildThemeCard(
            'Black & White',
            'Minimalist Pure Black & High-Contrast White',
            const Color(0xFFFFFFFF),
            activeTheme == 'Black & White',
            hasAdminAccess),
      ],
    );
  }

  // Theme selector card template
  Widget _buildThemeCard(String name, String desc, Color color, bool isActive,
      bool hasAdminAccess) {
    final themeService = Provider.of<ThemeService>(context, listen: false);
    return GestureDetector(
      onTap: () {
        if (hasAdminAccess) {
          themeService.setTheme(name, syncToFirestore: true);
        } else {
          InAppNotification.show(
            context,
            title: 'Admin Required',
            message: 'Only CRs or Admins can customize global themes.',
            accentColor: Colors.amber,
            icon: Icons.lock_rounded,
          );
        }
      },
      child: Opacity(
        opacity: isActive ? 1.0 : (hasAdminAccess ? 0.95 : 0.45),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.textPrimary.withOpacity(0.04),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.glassCardBorder, width: 1.5),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(desc,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              if (isActive)
                Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 20)
              else if (!hasAdminAccess)
                Icon(Icons.lock_outline_rounded,
                    color: AppColors.textSecondary.withOpacity(0.3), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // Pane 5: About Developer
  Widget _buildAboutPane() {
    const String portfolioUrl = 'https://mahmudulhasanmridul.netlify.app/';
    const String linkedinUrl =
        'https://www.linkedin.com/in/mahmudul-hasan-mridul1/';
    const String githubUrl = 'https://github.com/mridulhasan13';
    const String facebookUrl =
        'https://www.facebook.com/mahmudulhasan.mridul01/';
    const String xUrl = 'https://x.com/m_h_mridul';
    const String instagramUrl = 'https://www.instagram.com/mustard_slevalion/';

    Widget socialIconBtn(FaIconData icon, String url) {
      return GestureDetector(
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.textPrimary.withOpacity(0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: FaIcon(
              icon,
              color: AppColors.textPrimary.withOpacity(0.65),
              size: 19,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Text('About UniGrid',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Platform details, mission & developer information',
            style:
                TextStyle(color: AppColors.textPrimary.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 24),

        // ── 1. Top: App Info ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.apps_rounded, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('App Info',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 16),
              _aboutInfoRow(Icons.grid_view_rounded, 'App Name', 'UniGrid'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoRow(Icons.devices_rounded, 'Platform', 'Web, Android & Cross-Platform'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoRow(Icons.person_outline_rounded, 'Built by',
                  'Mahmudul Hasan Mridul - BUTEX - IPE - 51'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoRow(Icons.terminal_rounded, 'Built with',
                  'Flutter + Firebase + Supabase'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoLinkRow(Icons.language_rounded, 'Website',
                  'unigrid.netlify.app', 'https://unigrid.netlify.app'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoLinkRow(Icons.explore_outlined, 'More Info',
                  'info-unigrid.netlify.app', 'https://info-unigrid.netlify.app/'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoLinkRow(Icons.email_outlined, 'Support',
                  'support.unigrid@gmail.com', 'mailto:support.unigrid@gmail.com'),
              const Divider(color: Colors.white10, height: 16),
              _aboutInfoRow(Icons.info_outline_rounded, 'Version', '1.0.2'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 2. Middle: About UniGrid ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.school_rounded, color: AppColors.secondary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('About UniGrid',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 12),
              LinkifiedText(
                'UniGrid is a modern academic coordination and scheduling ecosystem engineered specifically for university campuses. Designed to bridge the communication gap between students, Class Representatives (CRs), and faculty members, UniGrid streamlines daily university life into a centralized, intelligent workspace.\n\n'
                'Key Capabilities:\n'
                '• Smart Routine & Timetable: Dynamic weekly schedule tables with real-time class status tracking (Upcoming, Completed, Cancelled, No Class) and faculty details.\n'
                '• Academic Hub: High-speed distribution of lecture slides, syllabus sheets, and coursework materials hosted on Supabase cloud storage.\n'
                '• Real-Time Announcements & Chat: Interactive batch messenger featuring @user mentions, instant push notifications, and emergency broadcast alerts.\n'
                '• CR & Admin Management: Dedicated leadership tools for slot building, student approval, and batch-wide moderation.',
                selectable: true,
                textAlign: TextAlign.justify,
                style: TextStyle(
                    color: AppColors.textPrimary.withOpacity(0.75),
                    fontSize: 12.5,
                    height: 1.65),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── 3. Bottom: Developer Hero Card ────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0.15),
                AppColors.primary.withOpacity(0.05),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.28), width: 1.5),
          ),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: 'hmridul27@gmail.com')
                .limit(1)
                .get()
                .then((q) => q.docs.isNotEmpty ? q.docs.first.data() : null),
            builder: (context, snap) {
              final Map<String, dynamic>? devData = snap.data;
              final String? photoUrl = devData?['photoUrl'];
              final String? phoneNumber = devData?['phoneNumber'];

              String whatsappUrl =
                  'https://wa.me/8801521757204'; // Default fallback
              if (phoneNumber != null && phoneNumber.isNotEmpty) {
                String cleanPhone =
                    phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
                if (cleanPhone.startsWith('0') &&
                    !cleanPhone.startsWith('880')) {
                  cleanPhone = '880${cleanPhone.substring(1)}';
                } else if (!cleanPhone.startsWith('880')) {
                  cleanPhone = '880$cleanPhone';
                }
                whatsappUrl = 'https://wa.me/$cleanPhone';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Photo ──────────────────────────────────────────────────
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.secondary.withOpacity(0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.45),
                          blurRadius: 24,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.15),
                          blurRadius: 48,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3), // ring gap
                      child: ClipOval(
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 220,
                                cacheHeight: 220,
                                gaplessPlayback: true,
                                loadingBuilder: (ctx, child, progress) =>
                                    progress == null
                                        ? child
                                        : Container(
                                            color: AppColors.glassCardColor,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                errorBuilder: (ctx, e, s) => Image.asset(
                                  'assets/images/mridul_profile.png',
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                'assets/images/mridul_profile.png',
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Name ───────────────────────────────────────────────────
                  Text(
                    'Mahmudul Hasan Mridul',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Founder & Lead Developer',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_rounded,
                            color: AppColors.primary, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Bangladesh University of Textiles (BUTEX)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textPrimary.withOpacity(0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Social Buttons ──────────────────────────────────────────
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      socialIconBtn(FontAwesomeIcons.envelope,
                          'mailto:hmridul27@gmail.com'),
                      socialIconBtn(FontAwesomeIcons.globe, portfolioUrl),
                      socialIconBtn(FontAwesomeIcons.linkedin, linkedinUrl),
                      socialIconBtn(FontAwesomeIcons.github, githubUrl),
                      socialIconBtn(FontAwesomeIcons.instagram, instagramUrl),
                      socialIconBtn(FontAwesomeIcons.whatsapp, whatsappUrl),
                      socialIconBtn(FontAwesomeIcons.facebook, facebookUrl),
                      socialIconBtn(FontAwesomeIcons.xTwitter, xUrl),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── About Me ──────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.format_quote_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('About the Developer',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              LinkifiedText(
                'Hey there! I’m Mridul, a visual storyteller, handwriting artist, and designer disguised as an engineering student. My journey is fueled by a love for aesthetics and structure, bridging the gap between the meticulous world of engineering and the fluid world of graphic design and calligraphy.\n\n'
                'From running leadership initiatives in science and photography to digitalizing ideas into clean, striking graphics, I thrive on turning creative visions into reality.',
                selectable: true,
                textAlign: TextAlign.justify,
                style: TextStyle(
                    color: AppColors.textPrimary.withOpacity(0.7),
                    fontSize: 12.5,
                    height: 1.65),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Footer ────────────────────────────────────────────────────────────
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Copyright © 2026 - UniGrid',
              style: TextStyle(
                  color: AppColors.textPrimary.withOpacity(0.35), fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // Pane: Officers & Founders
  Widget _buildOfficersPane() {
    final List<Map<String, dynamic>> officers = [
      {
        'name': 'Mahmudul Hasan Mridul',
        'designation': 'Founder & Lead Developer',
        'department': 'IPE',
        'batch': '51',
        'photo': 'assets/images/mridul_profile.png',
        'socials': [
          {
            'icon': FontAwesomeIcons.globe,
            'url': 'https://mahmudulhasanmridul.netlify.app/'
          },
          {
            'icon': FontAwesomeIcons.linkedin,
            'url': 'https://www.linkedin.com/in/mahmudul-hasan-mridul1/'
          },
          {
            'icon': FontAwesomeIcons.facebook,
            'url': 'https://www.facebook.com/mahmudulhasan.mridul01/'
          },
          {
            'icon': FontAwesomeIcons.instagram,
            'url': 'https://www.instagram.com/mustard_slevalion/'
          },
          {
            'icon': FontAwesomeIcons.envelope,
            'url': 'mailto:hmridul27@gmail.com'
          },
        ]
      },
      {
        'name': 'Md. Sakibul Sahon',
        'designation': 'COO',
        'department': 'ESE',
        'batch': '51',
        'photo': 'assets/images/sahon_profile.jpg',
        'socials': [
          {
            'icon': FontAwesomeIcons.facebook,
            'url': 'https://www.facebook.com/share/192jKr7bWw/'
          },
          {
            'icon': FontAwesomeIcons.instagram,
            'url': 'https://www.instagram.com/___its_sahon___?utm_source=qr&igsh=ZmlvMDBzcTlldGkw'
          },
          {
            'icon': FontAwesomeIcons.linkedin,
            'url': 'https://www.linkedin.com/in/md-sakibul-sahon-b54315304?utm_source=share_via&utm_content=profile&utm_medium=member_android'
          },
          {
            'icon': FontAwesomeIcons.envelope,
            'url': 'mailto:alwaysongame134@gmail.com'
          },
        ]
      },
      {
        'name': 'Farhan Ishrak Shoron',
        'designation': 'Marketing Officer',
        'department': 'TMDM',
        'batch': '51',
        'photo': 'assets/images/shoron_profile.png',
        'socials': [
          {
            'icon': FontAwesomeIcons.facebook,
            'url': 'https://www.facebook.com/farhanishrakshoron404'
          },
          {
            'icon': FontAwesomeIcons.linkedin,
            'url': 'https://www.linkedin.com/in/md-farhan-ishrak-864035362/?skipRedirect=true'
          },
          {
            'icon': FontAwesomeIcons.envelope,
            'url': 'mailto:farhanishrak064@gmail.com'
          },
        ]
      }
    ];

    Widget socialIconBtn(dynamic icon, String url) {
      return GestureDetector(
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.textPrimary.withOpacity(0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: FaIcon(
              icon,
              color: AppColors.textPrimary.withOpacity(0.65),
              size: 16,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Officers & Leadership',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('The core team managing UniGrid',
            style:
                TextStyle(color: AppColors.textPrimary.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: officers.map((officer) {
            return Container(
              width: 290,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    AppColors.primary.withOpacity(0.03),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar Photo
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.secondary.withOpacity(0.6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: Image.asset(
                          officer['photo'],
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, e, s) => Container(
                            color: AppColors.glassCardColor,
                            child: Icon(
                              Icons.person_rounded,
                              size: 44,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name
                  Text(
                    officer['name'],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Designation Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      officer['designation'],
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${officer['department']} — Batch ${officer['batch']}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Social Links
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: (officer['socials'] as List<Map<String, dynamic>>).map((soc) {
                      return socialIconBtn(soc['icon'], soc['url']);
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _aboutInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary.withOpacity(0.8), size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary.withOpacity(0.6),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Pane 6: Help & Updates Content

  Widget _buildHelpPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Help & Support',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Technical assistance, support inquiries, and developer contacts.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.04)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Contact Support Team',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                  'Need assistance, found a bug, or have suggestions for UniGrid? Reach out to our team directly via email.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
              const SizedBox(height: 14),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    final uri = Uri.parse('mailto:support.unigrid@gmail.com?subject=UniGrid%20Support%20Request');
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        await launchUrl(uri);
                      }
                    } catch (_) {
                      Clipboard.setData(const ClipboardData(text: 'support.unigrid@gmail.com'));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Email copied to clipboard: support.unigrid@gmail.com')),
                        );
                      }
                    }
                  },
                  onLongPress: () {
                    Clipboard.setData(const ClipboardData(text: 'support.unigrid@gmail.com'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Email copied to clipboard: support.unigrid@gmail.com')),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.email_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'support.unigrid@gmail.com',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.primary.withOpacity(0.7)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => launchUrl(
                    Uri.parse('https://mahmudulhasanmridul.netlify.app/'),
                    mode: LaunchMode.externalApplication),
                icon: Icon(Icons.open_in_new,
                    size: 16, color: AppColors.onPrimary),
                label: Text('Visit Developer Portfolio',
                    style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),

      ],
    );
  }

  Widget _aboutInfoLinkRow(IconData icon, String label, String value, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary.withOpacity(0.8), size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 115,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary.withOpacity(0.6),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.primary.withOpacity(0.7)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Terms & Conditions Pane
  Widget _buildTermsPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Terms & Conditions',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Effective Date: August 20, 2026',
            style:
                TextStyle(color: AppColors.textPrimary.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('1. Acceptance of Terms'),
              _buildSectionBody(
                'By accessing or using UniGrid, you agree to comply with and be bound by these Terms and Conditions. If you do not agree, please do not use the app.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('2. User Accounts & Security'),
              _buildSectionBody(
                'You are responsible for maintaining the confidentiality of your login credentials. Any activity under your account is your sole responsibility. You agree to notify us immediately of any unauthorized use.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('3. Acceptable Use'),
              _buildSectionBody(
                'You agree to use UniGrid only for educational, organizational, and collaborative purposes within your department. Harassment, sharing inappropriate content, or attempting to disrupt the application services is strictly prohibited.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('4. Uploaded Materials & Rights'),
              _buildSectionBody(
                'Users (specifically CRs and Admins) uploading study materials, guides, or announcements retain ownership of their content but grant UniGrid the necessary rights to distribute and host it for academic access.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('5. Limitation of Liability'),
              _buildSectionBody(
                'UniGrid is provided "as is" without warranties of any kind. We are not liable for any service interruptions, loss of academic data, or incorrect information uploaded by users.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('6. Changes to Terms'),
              _buildSectionBody(
                'We reserve the right to modify these terms at any time. Continued use of the app after modifications constitutes acceptance of the new terms.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('7. Class Representative (CR) Responsibilities'),
              _buildSectionBody(
                'Students assigned Class Representative privileges must exercise due care when publishing timetable adjustments, routine changes, and classroom announcements. Misrepresentation of official department schedules or arbitrary deletion of peer materials is grounds for role revocation.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('8. Over-The-Air (OTA) & Automatic Updates'),
              _buildSectionBody(
                'UniGrid incorporates built-in over-the-air update mechanisms to deliver security patches, theme assets, and performance enhancements. Users are encouraged to maintain the latest build for optimal stability and synchronization.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('9. Academic Fair-Use & Copyright'),
              _buildSectionBody(
                'All course syllabi, lecture slides, and academic resources shared on UniGrid are designated strictly for internal non-commercial educational study in accordance with institutional academic fair-use guidelines.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('10. Account Suspension & Termination'),
              _buildSectionBody(
                'UniGrid administrators reserve the right to restrict or terminate access for any user account that engages in abusive conduct, automated scraping, vulnerability exploitation, or unauthorized privilege escalation.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Privacy Policy Pane
  Widget _buildPrivacyPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Privacy Policy',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Effective Date: August 20, 2026',
            style:
                TextStyle(color: AppColors.textPrimary.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('1. Information We Collect'),
              _buildSectionBody(
                'When you sign up or configure your workspace, we collect your Full Name, University Email, Student ID, Contact Number, Department, Batch, and profile pictures. We also store academic files uploaded by you (materials, PDFs, announcements).',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('2. How We Use Information'),
              _buildSectionBody(
                'Your information is used solely to configure your UniGrid workspace, verify your registration (for CR and student scopes), enable classroom collaboration/chat, and deliver push notifications via FCM.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('3. Data Sharing & Security'),
              _buildSectionBody(
                'We do not sell, trade, or share your personal data with third parties. Your details are accessible only to authorized root administrators and CRs within your department for workspace moderation.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('4. Storage & Processing'),
              _buildSectionBody(
                'Your personal details and files are securely stored on Google Firebase Firestore/Authentication and Supabase Cloud Storage. We utilize encryption protocols to protect your transactions and stored items.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('5. Cookies & Local Storage'),
              _buildSectionBody(
                'We use local browser storage and app preferences (like SharedPreferences) to maintain your login session, notification preferences, and visual theme configurations.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('6. User Rights'),
              _buildSectionBody(
                'You can edit your profile details, update your password, or change notification preferences inside the settings at any time. For complete account deletion, you can contact your Master Admin.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('7. Diagnostic & Crash Analytics'),
              _buildSectionBody(
                'We may collect anonymized application performance metrics and crash telemetry (e.g. Flutter rendering latency and network error logs) to identify software bugs and enhance platform reliability without profiling individual users.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('8. Semester Data Archiving & Purging'),
              _buildSectionBody(
                'To prevent cloud clutter and protect student privacy, temporary class discussion histories and outdated announcements may be archived or safely purged during official semester transitions by authorized Class Representatives.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('9. Contact & Grievance Assistance'),
              _buildSectionBody(
                'For privacy inquiries, account data verification requests, or security vulnerability reports, please reach out to the UniGrid engineering team through the GitHub repository or your department\'s designated Master Administrator.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Community Guidelines Pane
  Widget _buildCommunityGuidelinesPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Community Guidelines',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Effective Date: August 20, 2026',
            style:
                TextStyle(color: AppColors.textPrimary.withOpacity(0.5), fontSize: 12)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.textPrimary.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('1. Mutual Respect & Civility'),
              _buildSectionBody(
                'UniGrid is a shared academic sanctuary for university students, Class Representatives, and educators. Treat all peers with respect, courtesy, and dignity. Harassment, personal attacks, hate speech, derogatory remarks, bullying, or discrimination based on race, gender, religion, or background will not be tolerated.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('2. Academic Integrity & Honest Collaboration'),
              _buildSectionBody(
                'Share genuine, helpful, and verified academic resources such as lecture slides, study guides, and assignment prompts. Do not upload or distribute unreleased exam papers, unauthorized test answer keys, or facilitate academic dishonesty.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('3. Clean & Purposeful Classroom Discussions'),
              _buildSectionBody(
                'Keep department and batch communication channels constructive and relevant to campus life and studies. Do not flood chat rooms with spam, commercial promotions, unauthorized advertisements, chain messages, or political/religious solicitation.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('4. Respecting Student Privacy & Consent'),
              _buildSectionBody(
                'Never publicly share or disseminate private information belonging to fellow students or faculty (such as personal phone numbers, home addresses, private photos, or confidential exam marks) without their clear and explicit permission.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('5. Class Representative (CR) Ethical Standards'),
              _buildSectionBody(
                'Class Representatives hold positions of trust. CRs must ensure timely, truthful publication of class schedules, notices, and test dates. Abuse of administrative powers, targeted removal of peer resources, or bias in member approval is strictly prohibited.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('6. Safe Media & Content Sharing'),
              _buildSectionBody(
                'Ensure all uploaded study materials, PDF attachments, and avatar images are appropriate, virus-free, and relevant to educational activities. Obscene, violent, suggestive, or copyrighted third-party material without fair use is prohibited.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('7. Platform Integrity & Fair Use'),
              _buildSectionBody(
                'Users must not attempt to exploit application vulnerabilities, deploy scraping bots, bypass authentication or approval guards, impersonate other university members, or disrupt cloud database operations.',
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('8. Reporting & Violation Enforcement'),
              _buildSectionBody(
                'If you witness misconduct or harmful content, report it directly to your Class Representative or Master Administrator. Disciplinary actions include formal warnings, message removal, temporary chat suspensions, CR credential revocation, or permanent account banning.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSectionBody(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textPrimary.withOpacity(0.7),
        fontSize: 12,
        height: 1.6,
      ),
    );
  }
}
