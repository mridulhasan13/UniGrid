import 'package:flutter/material.dart';

class AppColors {
  // Sky Sapphire Theme Colors (Matches Logo)
  static Color primary = const Color(0xFF3B82F6); // Sky Sapphire Blue
  static Color secondary = const Color(0xFF93C5FD); // Light Sapphire Blue

  // Background Colors
  static Color backgroundTop = const Color(0xFF030710); // Dark Blue / Black (Solid)
  static Color backgroundBottom = const Color(0xFF0A0F1D); // Deep Space Navy Blue

  // Card & Surface Colors
  static Color glassCardColor =
      const Color(0xFF0D1B2A); // Deep Navy Glass Base
  static Color glassCardBorder = const Color(0xFF1B263B); // Navy Border

  // Text Colors
  static Color textPrimary = Colors.white;
  static Color textSecondary = const Color(0xFF94A3B8); // Slate Gray
  static Color get onPrimary => primary.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  static bool isLight = false;

  // Badges & Dynamic Contrast Accents
  static const Color urgent = Color(0xFFEF4444); // Red
  static const Color notice = Color(0xFFF59E0B); // Amber
  static const Color material = Color(0xFF3B82F6); // Blue

  static Color get emerald => isLight ? const Color(0xFF15803D) : const Color(0xFF10B981);
  static Color get amber => isLight ? const Color(0xFFB45309) : const Color(0xFFF59E0B);
  static Color get cyan => isLight ? const Color(0xFF0284C7) : const Color(0xFF06B6D4);
  static Color get crimson => isLight ? const Color(0xFFDC2626) : const Color(0xFFEF4444);
  static Color get purple => isLight ? const Color(0xFF7E22CE) : const Color(0xFFA855F7);
}

class AppGradients {
  static LinearGradient get mainBackground => LinearGradient(
        colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class AppStyles {
  static TextStyle get heading1 => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );
  static TextStyle get heading2 => TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static TextStyle get body => TextStyle(
    fontSize: 16,
    color: AppColors.textPrimary,
  );
  static TextStyle get caption => TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );

  static List<BoxShadow> get emeraldGlow => [
        BoxShadow(
          color: AppColors.isLight
              ? Colors.black.withOpacity(0.06)
              : AppColors.primary.withOpacity(0.2),
          blurRadius: AppColors.isLight ? 10 : 15,
          spreadRadius: 0,
          offset: AppColors.isLight ? const Offset(0, 4) : const Offset(0, 0),
        ),
      ];
}

class AppConstants {
  static const String fileServerBase = 'http://localhost:23012/';
}
