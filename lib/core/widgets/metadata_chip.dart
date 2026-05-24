import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme_extension.dart';

class MetadataChip extends StatelessWidget {
  const MetadataChip({
    required this.label,
    this.icon,
    this.color,
    this.onImage = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final Color chipColor =
        color ??
        (onImage ? Colors.white : Theme.of(context).colorScheme.primary);
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final Color textColor = onImage ? Colors.white : palette.textPrimaryColor;
    final Color fillColor = onImage
        ? Colors.black.withValues(alpha: 0.34)
        : chipColor.withValues(alpha: 0.12);
    final Color borderColor = onImage
        ? chipColor.withValues(alpha: color == null ? 0.24 : 0.38)
        : chipColor.withValues(alpha: 0.24);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: AppRadius.all(AppRadius.md),
        border: Border.all(color: borderColor),
        boxShadow: onImage
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: chipColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
