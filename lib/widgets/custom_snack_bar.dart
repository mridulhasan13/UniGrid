import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../notifications/in_app_notification.dart';

class CustomSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color? iconColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    InAppNotification.show(
      context,
      title: 'Notice',
      message: message,
      icon: icon,
      accentColor: iconColor ?? AppColors.primary,
      duration: duration,
    );
  }
}
