import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/linkified_text.dart';

/// Global navigator key to trigger notifications from anywhere (e.g. FCM background listeners).
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

/// Premium glassmorphic in-app notification banner overlay.
///
/// Usage:
/// ```dart
/// InAppNotification.show(
///   context,
///   title: 'New Announcement',
///   message: 'Class has been rescheduled to Room 302',
///   icon: Icons.campaign_rounded,
///   onTap: () => print('Notification tapped!'),
/// );
/// ```
class InAppNotification {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext? context, {
    required String title,
    required String message,
    IconData? icon,
    String? photoUrl,
    Color? accentColor,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    dismiss();

    final targetContext = context ?? globalNavigatorKey.currentContext;
    if (targetContext == null) return;

    final overlay = Overlay.maybeOf(targetContext, rootOverlay: true);
    if (overlay == null) return;

    _currentEntry = OverlayEntry(
      builder: (ctx) => _InAppNotificationWidget(
        title: title,
        message: message,
        icon: icon ?? Icons.notifications_active_rounded,
        photoUrl: photoUrl,
        accentColor: accentColor ?? AppColors.primary,
        onTap: () {
          dismiss();
          onTap?.call();
        },
        onDismiss: dismiss,
        duration: duration,
      ),
    );

    overlay.insert(_currentEntry!);

    _dismissTimer = Timer(duration, () {
      dismiss();
    });
  }

  static void showGlobal({
    required String title,
    required String message,
    IconData? icon,
    String? photoUrl,
    Color? accentColor,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      null,
      title: title,
      message: message,
      icon: icon,
      photoUrl: photoUrl,
      accentColor: accentColor,
      onTap: onTap,
      duration: duration,
    );
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _InAppNotificationWidget extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final String? photoUrl;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final Duration duration;

  const _InAppNotificationWidget({
    required this.title,
    required this.message,
    required this.icon,
    this.photoUrl,
    required this.accentColor,
    required this.onTap,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_InAppNotificationWidget> createState() =>
      _InAppNotificationWidgetState();
}

class _InAppNotificationWidgetState extends State<_InAppNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _animController.forward();
  }

  void _dismissWithAnim() async {
    await _animController.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 8.0;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragUpdate: (details) {
              if (details.delta.dy < -3) {
                _dismissWithAnim();
              }
            },
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassCardColor.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.accentColor.withOpacity(0.45),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.accentColor.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          // Colored left indicator strip
                          Container(
                            width: 5,
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                bottomLeft: Radius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Leading Avatar / Icon
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: widget.photoUrl != null &&
                                    widget.photoUrl!.isNotEmpty
                                ? CircleAvatar(
                                    radius: 20,
                                    backgroundImage:
                                        NetworkImage(widget.photoUrl!),
                                  )
                                : Container(
                                    width: 40,
                                    height: 40,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color:
                                          widget.accentColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: widget.accentColor
                                            .withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.asset(
                                        'assets/images/logo.png',
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.contain,
                                        errorBuilder: (ctx, err, stack) => Icon(
                                          widget.icon,
                                          color: widget.accentColor,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),

                          // Title and Subtitle text area
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: LinkifiedText(
                                          widget.title,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        'Now',
                                        style: TextStyle(
                                          color: AppColors.textSecondary
                                              .withOpacity(0.7),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  LinkifiedText(
                                    widget.message,
                                    style: TextStyle(
                                      color: AppColors.textSecondary
                                          .withOpacity(0.9),
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Close Button
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color:
                                    AppColors.textSecondary.withOpacity(0.6),
                                size: 18,
                              ),
                              onPressed: _dismissWithAnim,
                              tooltip: 'Dismiss',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
