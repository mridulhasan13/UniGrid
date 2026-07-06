import 'package:flutter/material.dart';
import '../utils/constants.dart';

class CustomSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color? iconColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    final themeIconColor = iconColor ?? AppColors.primary;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: themeIconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.glassCardColor.withOpacity(0.95),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: themeIconColor.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      ),
    );
  }
}
