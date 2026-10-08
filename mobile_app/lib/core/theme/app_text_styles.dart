import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Centralized typography: Readex Pro, a clean modern face designed for
/// reading on screens, whose Latin letters match its Arabic ones so mixed
/// text looks like one family. (IBM Plex Sans Arabic was tried first, but it
/// draws the name "محمد" as a single calligraphic symbol.)
/// Bundled (assets/fonts, declared in pubspec.yaml), so text renders in it
/// from the first frame, offline included.
class AppTextStyles {
  static const fontFamily = 'ReadexPro';

  static TextStyle get displayLarge => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get displayMedium => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get titleLarge => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get titleMedium => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyLarge => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
      );

  static TextStyle get labelSmall => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textMuted,
      );

  static TextStyle get buttonText => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      );
}
