import 'package:flutter/material.dart';

class AppColors {
  // Sky Sapphire Theme Colors (Matches Logo)
  static Color primary = const Color(0xFF3B82F6); // Sky Sapphire Blue
  static Color secondary = const Color(0xFF93C5FD); // Light Sapphire Blue

  // Background Colors
  static Color backgroundTop = const Color(0xFF030710); // Dark Blue / Black (Solid)
  static Color backgroundBottom = const Color(0xFF030710); // Dark Blue / Black (Solid)

  // Card & Surface Colors
  static Color glassCardColor =
      const Color(0xFF0D1B2A); // Deep Navy Glass Base
  static Color glassCardBorder = const Color(0xFF1B263B); // Navy Border

  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8); // Slate Gray
  static Color get onPrimary => primary.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  // Badges
  static const Color urgent = Color(0xFFEF4444); // Red
  static const Color notice = Color(0xFFF59E0B); // Amber
  static const Color material = Color(0xFF3B82F6); // Blue
}

class AppGradients {
  static LinearGradient get mainBackground => LinearGradient(
        colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class AppStyles {
  static const TextStyle heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );
  static const TextStyle heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: AppColors.textPrimary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );

  static List<BoxShadow> get emeraldGlow => [
        BoxShadow(
          color: AppColors.primary.withOpacity(0.2),
          blurRadius: 15,
          spreadRadius: 0,
          offset: const Offset(0, 0),
        ),
      ];
}

class AppConstants {
  static const String fileServerBase = 'http://localhost:23012/';
}
