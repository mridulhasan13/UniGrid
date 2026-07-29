import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/constants.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final double opacity;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = const EdgeInsets.only(bottom: 16.0),
    this.borderRadius = 24.0,
    this.opacity = 0.2,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool useBlur = !kIsWeb;

    // Solid opaque base — gradient cannot override a separate Stack layer
    Widget cardContainer = Stack(
      children: [
        // Layer 1: fully solid dark base (no transparency so bg never bleeds through)
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.glassCardColor, // fully opaque
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: AppColors.glassCardBorder,
              width: 1.5,
            ),
            boxShadow: AppStyles.emeraldGlow,
          ),
          // Wrap in transparent Material so ListTile (and other ink-based widgets)
          // can paint their splash/highlight effects correctly, instead of being
          // hidden by this Container's BoxDecoration background.
          child: Material(
            color: Colors.transparent,
            child: child,
          ),
        ),
        // Layer 2: subtle shimmer gradient overlay on top (purely decorative, does not affect opacity)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.textPrimary.withOpacity(0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: useBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: cardContainer,
            )
          : cardContainer,
    );

    if (onTap != null) {
      return Padding(
        padding: margin,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: onTap,
            splashColor: AppColors.primary.withOpacity(0.3),
            highlightColor: Colors.transparent,
            child: cardContent,
          ),
        ),
      );
    }

    return Padding(
      padding: margin,
      child: cardContent,
    );
  }

  static Future<T?> showGlassDialog<T>({
    required BuildContext context,
    required Widget child,
  }) {
    return showDialog<T>(
      barrierColor: Colors.black.withOpacity(0.75),
      context: context,
      builder: (context) => Center(
        child: SingleChildScrollView(
          child: GlassCard(
            margin: const EdgeInsets.all(24),
            borderRadius: 28,
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
