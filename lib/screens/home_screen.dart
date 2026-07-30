import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/glass_card.dart';
import '../services/supabase_storage_service.dart';
import '../widgets/unigrid_loader.dart';
import '../widgets/floating_app_bar.dart';
import 'file_viewer_screen.dart';
import '../notifications/in_app_notification.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final hasScope = user != null && user.hasDeptScope;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FloatingAppBar(
              title: 'Announcements',
              subtitle: hasScope
                  ? '${deptFullName(user.department)} — Batch ${user.batch}'
                  : null,
              actions: [
                IconButton(
                  icon: Icon(Icons.logout_rounded, color: AppColors.textSecondary),
                  onPressed: () => context.read<AuthService>().signOut(),
                  tooltip: 'Logout',
                ),
              ],
            ),
            Expanded(
              child: _buildBody(context, user),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppUser? user) {
    // Show setup prompt if user has no dept/batch
    if (user == null || !user.hasDeptScope) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                height: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'Department not set',
                style: AppStyles.heading2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please complete your profile to see announcements for your department and batch.',
                style: AppStyles.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final announcementsPath =
        deptBatchCol(user.department, user.batch, 'announcements');

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(announcementsPath)
                .orderBy('timestamp', descending: true)
                .limit(30)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Something went wrong'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const UniGridLoader(
                  title: 'Loading Announcements',
                  subtitle: 'Fetching latest notices...',
                  showBackground: false,
                );
              }

              final announcements = snapshot.data!.docs
                  .map((doc) => Announcement.fromMap(
                      doc.data() as Map<String, dynamic>, doc.id))
                  .toList();

              if (announcements.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withOpacity(0.05),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.15),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.1),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.notifications_paused_rounded,
                          size: 44,
                          color: AppColors.primary.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'No announcements yet.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 96,
                ),
                itemCount: announcements.length,
                itemBuilder: (context, index) {
                  final ann = announcements[index];
                  return _AnnouncementCard(
                    announcement: ann,
                    collectionPath: announcementsPath,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final String collectionPath;

  const _AnnouncementCard({
    required this.announcement,
    required this.collectionPath,
  });

  Color _getMainColor(String type) {
    switch (type) {
      case 'Urgent':
        return const Color(0xFFEF4444); // Bright warning red for accents
      case 'Material':
        return const Color(0xFF3B82F6); // Bright blue for material accents
      default:
        return AppColors.primary; // Accent color from current theme
    }
  }

  IconData _getBadgeIcon(String type) {
    switch (type) {
      case 'Urgent':
        return Icons.warning_amber_rounded;
      case 'Material':
        return Icons.menu_book_rounded;
      default:
        return Icons.hourglass_bottom;
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    return name.trim()[0].toUpperCase();
  }

  Future<void> _deleteAnnouncement(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundTop,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.glassCardBorder)),
        title: Text('Delete Announcement?',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('This action cannot be undone.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final fileUrl = announcement.fileUrl;
      
      // Delete Firestore document instantly (optimistic UI)
      FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(announcement.id)
          .delete()
          .catchError((e) {
        debugPrint('Failed to delete announcement doc: $e');
      });

      // Clean up Supabase file in background
      if (fileUrl != null && fileUrl.isNotEmpty) {
        SupabaseStorageService.deleteFileByUrl(fileUrl).catchError((e) {
          debugPrint('[AnnouncementDelete] Error cleaning up file: $e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AppUser?>(context);
    final canDelete = user != null && (user.isCR || user.isAdmin);

    final mainColor = _getMainColor(announcement.type);
    final badgeIcon = _getBadgeIcon(announcement.type);

    const isCardLight = false;
    const isPocketLight = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - 32;

    // Dynamically measure the exact width of the poster name text in pixels
    final textPainter = TextPainter(
      text: TextSpan(
        text: announcement.postedBy,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final nameWidth = textPainter.width;

    // Minimum pocket width is 120, maximum is nameWidth + 66, capped by available card width (leaving 130px on left)
    final maxAllowedCutoff = (cardWidth - 130).clamp(120.0, 240.0);
    final cutoffWidth = (nameWidth + 66.0).clamp(120.0, maxAllowedCutoff);
    final nameMaxWidth = cutoffWidth - 51.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          // Background layer containing poster details
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.glassCardBorder.withOpacity(0.85), // Premium glass navy pocket
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: mainColor.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 5),
                ],
              ),
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(top: 10, right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mainColor,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _getInitials(announcement.postedBy),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: nameMaxWidth),
                    child: Text(
                      announcement.postedBy,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Foreground layer containing the announcement card
          ClipPath(
            clipper: HiglightsCard(cutoffWidth: cutoffWidth),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.glassCardColor, // Premium glass navy card
                borderRadius: BorderRadius.circular(15.0),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: mainColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: mainColor.withOpacity(0.25),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  badgeIcon,
                                  size: 12,
                                  color: mainColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  announcement.type,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: mainColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canDelete) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _deleteAnnouncement(context),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: isCardLight ? Colors.black.withOpacity(0.6) : AppColors.textSecondary,
                                size: 20,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    announcement.title,
                    style: TextStyle(
                      color: isCardLight ? Colors.black : AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (announcement.details != null &&
                      announcement.details!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      announcement.details!,
                      style: TextStyle(
                        color: isCardLight ? Colors.black.withOpacity(0.6) : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (announcement.content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      announcement.content,
                      style: TextStyle(
                        color: isCardLight ? Colors.black.withOpacity(0.85) : AppColors.textPrimary.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  Divider(
                    color: isCardLight
                        ? Colors.black.withOpacity(0.12)
                        : AppColors.textSecondary.withOpacity(0.3),
                    height: 20,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _buildBottomAction(context, isCardLight),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM dd, hh:mm a')
                            .format(announcement.timestamp),
                        style: TextStyle(
                          color: isCardLight ? Colors.black.withOpacity(0.6) : AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction(BuildContext context, bool isCardLight) {
    if (announcement.fileUrl != null || announcement.fileName != null) {
      return GestureDetector(
        onTap: () {
          if (announcement.fileUrl == null) {
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
                fileName: announcement.fileName ?? 'attachment',
                fileUrl: announcement.fileUrl,
              ),
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file_rounded,
              color: isCardLight ? Colors.black.withOpacity(0.7) : AppColors.textPrimary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                announcement.fileName ?? 'Tap to view attachment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCardLight ? Colors.black.withOpacity(0.8) : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (announcement.fileUrl != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new_rounded,
                color: isCardLight ? Colors.black.withOpacity(0.5) : AppColors.textSecondary,
                size: 12,
              ),
            ],
          ],
        ),
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: isCardLight ? Colors.black.withOpacity(0.5) : AppColors.textSecondary,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Tap to view details',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCardLight ? Colors.black.withOpacity(0.6) : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }
  }
}

class HiglightsCard extends CustomClipper<Path> {
  final double cutoffWidth;

  const HiglightsCard({this.cutoffWidth = 120.0});

  @override
  Path getClip(Size size) {
    Path path = Path();
    double w = size.width;
    double h = size.height;
    double r = 15.0;
    double cutoffDepth = 45.0;
    double curveStart = w - cutoffWidth - 40;

    path.moveTo(r, 0);
    path.lineTo(curveStart, 0);
    path.cubicTo(
      curveStart + 15,
      0,
      curveStart + 25,
      cutoffDepth,
      curveStart + 55,
      cutoffDepth,
    );
    path.lineTo(w - r, cutoffDepth);
    path.quadraticBezierTo(w, cutoffDepth, w, cutoffDepth + r);
    path.lineTo(w, h - r);
    path.quadraticBezierTo(w, h, w - r, h);
    path.lineTo(r, h);
    path.quadraticBezierTo(0, h, 0, h - r);
    path.lineTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
