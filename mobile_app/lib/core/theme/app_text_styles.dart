import 'package:flutter/material.dart';
import '../ui/tokens.dart';

/// The old six text styles, kept so screens that are not rebuilt yet lay out
/// exactly as before (their sizes are unchanged; their colours are the new
/// ink tones). New code reads the fifteen roles of `context.text`.
///
/// Centralized typography: Readex Pro, a clean modern face designed for
/// reading on screens, whose Latin letters match its Arabic ones so mixed
/// text looks like one family. (IBM Plex Sans Arabic was tried first, but it
/// draws the name "محمد" as a single calligraphic symbol.)
/// Bundled (assets/fonts, declared in pubspec.yaml), so text renders in it
/// from the first frame, offline included.
/// Line heights are generous on purpose: Arabic carries marks above and below
/// its letters, and lines set tight look glued together.
@Deprecated('Read context.text (core/ui/tokens.dart) instead')
class AppTextStyles {
  static const fontFamily = BasakText.fontFamily;

  static TextStyle get displayMedium => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: BasakPalette.ink,
        height: 1.3,
      );

  static TextStyle get titleLarge => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: BasakPalette.ink,
        height: 1.4,
      );

  static TextStyle get titleMedium => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: BasakPalette.ink,
        height: 1.45,
      );

  static TextStyle get bodyLarge => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.normal,
        color: BasakPalette.ink,
        height: 1.55,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.normal,
        color: BasakPalette.ink2,
        height: 1.55,
      );

  static TextStyle get labelSmall => const TextStyle(
        fontFamily: AppTextStyles.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: BasakPalette.ink3,
        height: 1.5,
      );
}
