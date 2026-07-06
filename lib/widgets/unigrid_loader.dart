import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/constants.dart';

class UniGridLoader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showBackground;

  const UniGridLoader({
    super.key,
    this.title = 'Loading...',
    this.subtitle = 'Please wait a moment',
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final loaderBody = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withOpacity(0.03),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.12),
                  blurRadius: 25,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing outer halo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.15),
                      width: 1.5,
                    ),
                  ),
                )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1500.ms, curve: Curves.easeInOut)
                .fadeIn(duration: 1500.ms),

                // Core spinner ring
                SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                    backgroundColor: AppColors.glassCardBorder,
                  ),
                ),

                // Pulsing Logo
                Image.asset(
                  'assets/images/logo.png',
                  width: 36,
                  height: 36,
                )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1000.ms, curve: Curves.easeInOut),
              ],
            ),
          )
          .animate()
          .fadeIn(duration: 500.ms)
          .scale(begin: const Offset(0.85, 0.85), end: const Offset(1.0, 1.0), curve: Curves.easeOutBack, duration: 500.ms),

          const SizedBox(height: 24),

          if (title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            )
            .animate()
            .fadeIn(delay: 150.ms, duration: 500.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),

          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            )
            .animate()
            .fadeIn(delay: 300.ms, duration: 500.ms)
            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
          ],
        ],
      ),
    );

    if (showBackground) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: AppGradients.mainBackground),
        child: loaderBody,
      );
    }

    return loaderBody;
  }
}
