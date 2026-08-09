import 'package:flutter/material.dart';

/// Design tokens for LocalDrop (light theme, blueprint-driven).
abstract final class AppColors {
  static const Color primary = Color(0xFF2878F0);
  static const Color receive = Color(0xFF20B873);
  static const Color purple = Color(0xFF7B4DDB);
  static const Color orange = Color(0xFFF5A623);
  static const Color background = Color(0xFFF8F9FC);
  static const Color surface = Colors.white;
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF667085);
  static const Color border = Color(0xFFE6E8EC);
  static const Color error = Color(0xFFFF3B30);
}

abstract final class AppRadius {
  static const double largeCard = 18.0;
  static const double smallCard = 16.0;
  static const double button = 15.0;
  static const double small = 12.0;
}

abstract final class AppSpace {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 40.0;
}

abstract final class AppText {
  static const double logo = 28.0;
  static const double title = 24.0;
  static const double percentage = 58.0;
  static const double sectionHeading = 18.0;
  static const double button = 18.0;
  static const double body = 16.0;
  static const double secondary = 14.0;
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.receive,
      surface: AppColors.surface,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: AppText.title,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontSize: AppText.sectionHeading,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(
        fontSize: AppText.body,
        fontWeight: FontWeight.w500,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: AppText.secondary,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.secondaryText,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.secondaryText,
        ),
      ),
    ),
  );
}