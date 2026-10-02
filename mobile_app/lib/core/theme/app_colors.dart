import 'package:flutter/material.dart';

/// Centralized Design Palette — Unified (Glass + Brand)
class AppColors {
  // Backgrounds
  static const Color background = Color(0xFFF8FAFC);
  static const Color backgroundPure = Color(0xFFFFFFFF);
  static const Color backgroundSecondary = Color(0xFFF1F5F9);
  static const Color surface = Colors.white;

  // Brand Primary (Navy & Teal — used in Theme)
  static const Color primary = Color(0xFF1E3A8A); // Deep Navy Blue
  static const Color primaryDark = Color(0xFF17384A);
  static const Color secondary = Color(0xFF0D9488); // Teal
  static const Color accent = Color(0xFFF59E0B); // Amber / Gold
  static const Color teal = Color(0xFF00658D);
  static const Color ink = Color(0xFF17384A);
  static const Color canvas = Color(0xFFEAF5FA);

  // Baby Blue Accents (Glass)
  static const Color babyBlue = Color(0xFF7EC8E3);
  static const Color babyBlueLight = Color(0xFFA8D8F0);
  static const Color babyBlueUltraLight = Color(0xFFE0F2FE);
  static const Color babyBlueDark = Color(0xFF4FA8C7);

  // Text Colors (Dark slate, never pure black)
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);

  // Status & Feedback Colors
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);

  // Glassmorphic Properties
  static Color glassBackground = Colors.white.withOpacity(0.70);
  static Color glassBackgroundSubtle = Colors.white.withOpacity(0.50);
  static Color glassBorder = Colors.white.withOpacity(0.40);
  static Color glassBorderAccent = const Color(0xFF7EC8E3).withOpacity(0.35);

  // Blue-Tinted Soft Shadows (never flat gray)
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

  static List<BoxShadow> get floatingBarShadow => [
        BoxShadow(
          color: const Color(0xFF7EC8E3).withOpacity(0.18),
          blurRadius: 28,
          spreadRadius: 2,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        const BoxShadow(
            color: Color(0x0A16384A), blurRadius: 14, offset: Offset(0, 5)),
      ];
}
