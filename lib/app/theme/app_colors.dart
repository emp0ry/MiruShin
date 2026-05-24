import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color background = Color(0xFF070A12);
  static const Color backgroundElevated = Color(0xFF0B1020);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceSoft = Color(0xFF172033);
  static const Color surfaceGlass = Color(0xB31A2338);
  static const Color border = Color(0x26FFFFFF);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFB8C2D6);
  static const Color textMuted = Color(0xFF7F8AA3);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentAqua = Color(0xFF64D8FF);
  static const Color accentViolet = Color(0xFF9B8CFF);
  static const Color accentRose = Color(0xFFFF7DAF);
  static const Color accentAmber = Color(0xFFFFC46B);
  static const Color success = Color(0xFF6FE3B1);
  static const Color warning = Color(0xFFFFD166);
  static const Color danger = Color(0xFFFF6B7A);

  static const List<Color> accentOptions = <Color>[
    accentPurple,
    accentViolet,
    accentAqua,
    accentRose,
    accentAmber,
  ];
}
