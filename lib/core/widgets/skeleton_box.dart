import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_theme_extension.dart';

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    this.width,
    this.height,
    this.radius = AppRadius.md,
    super.key,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.35, end: 0.72),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (BuildContext context, double value, Widget? child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: AppRadius.all(radius),
            color: Color.lerp(
              palette.surfaceSoftColor,
              palette.surfaceColor,
              value,
            )?.withValues(alpha: 0.72),
          ),
        );
      },
    );
  }
}
