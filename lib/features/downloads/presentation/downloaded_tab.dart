import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../catalog/application/catalog_mode.dart';
import '../application/download_episode_display.dart';
import '../application/downloads_provider.dart';
import '../domain/download_models.dart';
import 'downloaded_artwork_image.dart';

/// Grid of downloaded titles for one catalog, rendered as the Library
/// "Downloaded" tab. Tapping a title opens the offline title page.
class DownloadedTab extends ConsumerWidget {
  const DownloadedTab({required this.catalog, super.key});

  final CatalogMode catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(downloadsProvider);
    final List<DownloadedTitle> titles = ref
        .read(downloadsProvider.notifier)
        .titlesForCatalog(catalog);
    final String? rootPath = ref.read(downloadsProvider.notifier).rootPath;

    if (titles.isEmpty) {
      return NeutralPlaceholder(
        title: context.t('No downloads yet'),
        message: context.t(
          'Download episodes from a title to watch them offline.',
        ),
        icon: Icons.download_done_rounded,
        height: 300,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.65,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: titles.length,
      itemBuilder: (BuildContext context, int index) =>
          _DownloadedTitleCell(title: titles[index], rootPath: rootPath),
    );
  }
}

class _DownloadedTitleCell extends StatelessWidget {
  const _DownloadedTitleCell({required this.title, required this.rootPath});

  final DownloadedTitle title;
  final String? rootPath;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DownloadedEpisode artworkEpisode = title.episodes.firstWhere(
      (DownloadedEpisode episode) => episode.isComplete,
      orElse: () => title.episodes.first,
    );
    final String poster = downloadedMediaWithLocalArtwork(
      artworkEpisode,
      rootPath: rootPath,
    ).posterUrl;
    final int completed = title.completedCount;
    final bool active = title.hasActive;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.offlineTitlePath(title.mediaId)),
      child: ClipRRect(
        borderRadius: AppRadius.all(AppRadius.lg),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (poster.isEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: palette.posterFallbackGradient,
                ),
              )
            else
              DownloadedArtworkImage(
                imageUrl: poster,
                fit: BoxFit.cover,
                fallback: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: palette.posterFallbackGradient,
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black87,
                  ],
                  stops: <double>[0, 0.5, 1],
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: AppRadius.all(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      active
                          ? Icons.downloading_rounded
                          : Icons.download_done_rounded,
                      size: 13,
                      color: active ? scheme.primary : Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$completed',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Text(
                title.media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
