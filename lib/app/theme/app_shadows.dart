import 'package:flutter/material.dart';

abstract final class AppShadows {
  static List<BoxShadow> soft(Color color) => <BoxShadow>[
    BoxShadow(
      color: color.withValues(alpha: 0.18),
      blurRadius: 28,
      offset: const Offset(0, 18),
    ),
  ];

  static List<BoxShadow> glow(Color color) => <BoxShadow>[
    BoxShadow(
      color: color.withValues(alpha: 0.22),
      blurRadius: 36,
      offset: const Offset(0, 18),
    ),
  ];
}
