import 'package:flutter/material.dart';

abstract final class AppAnimations {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration page = Duration(milliseconds: 340);
  static const Duration pageReverse = Duration(milliseconds: 260);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.16, 1, 0.3, 1);
  static const Curve exit = Curves.easeInCubic;

  /// Keeps motion in one place and respects the platform's reduced-motion
  /// accessibility settings. Callers can still render their final visual
  /// state; only the interpolation is removed.
  static bool reduceMotion(BuildContext context) {
    final MediaQueryData? mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
  }

  static Duration duration(BuildContext context, Duration preferred) {
    return reduceMotion(context) ? Duration.zero : preferred;
  }
}
