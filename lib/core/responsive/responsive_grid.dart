import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/theme/app_spacing.dart';

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 168,
    this.maxColumns = 6,
    this.spacing = AppSpacing.lg,
    this.childAspectRatio = 0.62,
    this.physics = const NeverScrollableScrollPhysics(),
    this.shrinkWrap = true,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double childAspectRatio;
  final ScrollPhysics physics;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = math.max(
          1,
          math.min(maxColumns, (constraints.maxWidth / minItemWidth).floor()),
        );

        return GridView.builder(
          itemCount: itemCount,
          physics: physics,
          shrinkWrap: shrinkWrap,
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
