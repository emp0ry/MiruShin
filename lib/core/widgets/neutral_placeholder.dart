import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme_extension.dart';

class NeutralPlaceholder extends StatelessWidget {
  const NeutralPlaceholder({
    required this.title,
    required this.message,
    this.icon = Icons.cloud_off_rounded,
    this.height = 220,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final double height;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surfaceSoftColor.withValues(alpha: 0.68),
        borderRadius: AppRadius.all(AppRadius.xl),
        border: Border.all(color: palette.borderColor),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final EdgeInsets padding = EdgeInsets.all(
            constraints.maxHeight < 180 ? AppSpacing.lg : AppSpacing.xl,
          );
          final double minHeight = constraints.maxHeight > padding.vertical
              ? constraints.maxHeight - padding.vertical
              : 0;

          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, color: palette.textMutedColor, size: 42),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.t(title),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        context.t(message),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMutedColor,
                        ),
                      ),
                      if (action != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        action!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
