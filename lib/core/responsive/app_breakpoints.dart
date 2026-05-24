enum WindowSizeClass { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const double compact = 700;
  static const double expanded = 1100;

  static WindowSizeClass classify(double width, {bool forceCompact = false}) {
    if (forceCompact || width < compact) {
      return WindowSizeClass.compact;
    }
    if (width < expanded) {
      return WindowSizeClass.medium;
    }
    return WindowSizeClass.expanded;
  }
}
