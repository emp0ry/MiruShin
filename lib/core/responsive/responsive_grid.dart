import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/theme/app_spacing.dart';

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 168,
    this.maxColumns = 6,
    this.maxColumnsForWidth,
    this.spacing = AppSpacing.lg,
    this.childAspectRatio = 0.62,
    this.physics = const NeverScrollableScrollPhysics(),
    this.shrinkWrap = true,
    this.clipBehavior = Clip.hardEdge,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final int maxColumns;
  final int Function(double availableWidth)? maxColumnsForWidth;
  final double spacing;
  final double childAspectRatio;
  final ScrollPhysics physics;
  final bool shrinkWrap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int effectiveMaxColumns = math.max(
          1,
          math.min(
            maxColumns,
            maxColumnsForWidth?.call(constraints.maxWidth) ?? maxColumns,
          ),
        );
        final int columns = math.max(
          1,
          math.min(
            effectiveMaxColumns,
            (constraints.maxWidth / minItemWidth).floor(),
          ),
        );

        return GridView.builder(
          itemCount: itemCount,
          physics: physics,
          shrinkWrap: shrinkWrap,
          clipBehavior: clipBehavior,
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
