import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../application/catalog_mode.dart';
import '../application/catalog_status.dart';

final Uri _aniListDiscordUri = Uri.parse('https://discord.com/invite/anilist');

class CatalogOfflineBanner extends ConsumerWidget {
  const CatalogOfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogOfflineNotice? notice = ref.watch(
      catalogOfflineNoticeProvider,
    );
    final CatalogMode mode = ref.watch(catalogModeProvider);
    if (notice == null || notice.mode != mode) {
      return const SizedBox.shrink();
    }

    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.64),
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.26)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                notice.usingCache
                    ? Icons.cloud_sync_rounded
                    : Icons.cloud_off_rounded,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      notice.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notice.message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondaryColor,
                      ),
                    ),
                    if (notice.detail != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        notice.detail!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: palette.textMutedColor,
                        ),
                      ),
                    ],
                    if (notice.isAniList) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => launchUrl(
                            _aniListDiscordUri,
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('AniList Discord'),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onErrorContainer,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
