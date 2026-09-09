import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/platform/url_opener.dart';
import '../../../../core/widgets/glass_card.dart';

class SupportMiruShinCard extends StatelessWidget {
  const SupportMiruShinCard({this.openUrl, super.key});

  final Future<bool> Function(String url)? openUrl;

  Future<void> _openSupport(BuildContext context) async {
    final bool opened = await (openUrl ?? openExternalUrl)(
      AppConstants.supportUrl,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('Could not open the support page.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget icon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.accentAmber, AppColors.accentRose],
        ),
        borderRadius: AppRadius.all(AppRadius.md),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.accentAmber.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.local_cafe_rounded,
        color: Color(0xFF2B1B08),
        size: 27,
      ),
    );
    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          context.t('Support MiruShin'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.t(
            'Support development and help MiruShin keep getting better.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
    final Widget button = FilledButton.icon(
      key: const ValueKey<String>('support-mirushin-button'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accentAmber,
        foregroundColor: const Color(0xFF2B1B08),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
      onPressed: () => _openSupport(context),
      icon: const Icon(Icons.favorite_rounded, size: 19),
      label: Text(context.t('Buy me a coffee')),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 560;
        return GlassCard(
          padding: EdgeInsets.zero,
          borderColor: AppColors.accentAmber.withValues(alpha: 0.42),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.all(AppRadius.lg),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  AppColors.accentAmber.withValues(alpha: 0.14),
                  AppColors.accentRose.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            icon,
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: copy),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        button,
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        icon,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: copy),
                        const SizedBox(width: AppSpacing.lg),
                        button,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
