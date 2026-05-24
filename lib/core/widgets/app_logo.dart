import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_gradients.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    this.compact = false,
    this.taglineOverride,
    this.onPressed,
    super.key,
  });

  final bool compact;
  final String? taglineOverride;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final Widget logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppGradients.accent(accent),
            borderRadius: AppRadius.all(AppRadius.md),
          ),
          child: Center(
            child: Text(
              '新',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
        if (!compact) ...<Widget>[
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.t('app_name'),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  taglineOverride ?? context.t('app_tagline'),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ],
    );
    if (onPressed == null) return logo;
    return Tooltip(
      message: 'Switch catalog mode',
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.md),
        onTap: onPressed,
        child: Padding(padding: const EdgeInsets.all(2), child: logo),
      ),
    );
  }
}
