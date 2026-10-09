import 'package:flutter/material.dart';

import '../ui/tokens.dart';

/// The old palette's names, kept so screens that are not rebuilt yet still
/// compile. Each one now points at its successor in `core/ui/tokens.dart`;
/// the class goes away with the last screen that uses it.
@Deprecated('Read context.colors (core/ui/tokens.dart) instead')
class AppColors {
  // Backgrounds
  static const Color background = BasakPalette.ground;
  static const Color surface = BasakPalette.surface;

  // Navy and the second teal are not in the product; teal is the action colour.
  static const Color primary = BasakPalette.teal;
  static const Color secondary = BasakPalette.teal;
  static const Color teal = BasakPalette.teal;
  static const Color ink = BasakPalette.ink;

  // Baby blue leaves with the glass widgets that still draw with it.
  static const Color babyBlue = Color(0xFF7EC8E3);
  static const Color babyBlueLight = BasakPalette.sky;
  static const Color babyBlueUltraLight = Color(0xFFE0F2FE);
  static const Color babyBlueDark = Color(0xFF4FA8C7);

  static const Color textPrimary = BasakPalette.ink;
  static const Color textSecondary = BasakPalette.ink2;
  static const Color textMuted = BasakPalette.ink3;

  // Status: the text-safe tones
  static const Color success = BasakPalette.success;
  static const Color warning = BasakPalette.warning;
  static const Color error = BasakPalette.danger;
  static const Color errorLight = BasakPalette.dangerTint;

  static Color glassBorder = Colors.white.withOpacity(0.40);

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF7EC8E3).withOpacity(0.12),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 6,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get floatingBarShadow => BasakShadow.floating;
}
