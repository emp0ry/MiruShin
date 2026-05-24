import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/media_poster_card.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../catalog/presentation/catalog_offline_banner.dart';
import '../../library/application/local_library_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';

class BoardPage extends ConsumerWidget {
  const BoardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BoardRails rails = ref
        .watch(boardRailsProvider)
        .maybeWhen(data: (BoardRails value) => value, orElse: BoardRails.empty);
    final MediaItem? hero = rails.hero;
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final List<AniListAnimeListFolder> anilistFolders =
        mode == CatalogMode.anilist
        ? ref
              .watch(anilistAnimeListProvider)
              .maybeWhen(
                data: (List<AniListAnimeListFolder> f) => f,
                orElse: () => const <AniListAnimeListFolder>[],
              )
        : const <AniListAnimeListFolder>[];
    final List<AniListAnimeListEntry> watchingEntries =
        (anilistFolders
                .where(
                  (AniListAnimeListFolder f) =>
                      f.status == AniListListStatus.current,
                )
                .expand((AniListAnimeListFolder f) => f.entries)
                .where(
                  (AniListAnimeListEntry e) =>
                      e.mediaItem.statusLabel != 'NOT_YET_RELEASED',
                )
                .toList(growable: true)
              ..sort(
                (AniListAnimeListEntry a, AniListAnimeListEntry b) =>
                    b.progress.compareTo(a.progress),
              ))
            .take(12)
            .toList(growable: false);
    final List<MediaItem> continueWatching = watchingEntries
        .map((AniListAnimeListEntry e) => e.mediaItem)
        .toList(growable: false);
    final Map<String, double> continueWatchingProgress = <String, double>{
      for (final AniListAnimeListEntry e in watchingEntries)
        if (e.mediaItem.episodeCount != null && e.mediaItem.episodeCount! > 0)
          e.mediaItem.id: (e.progress / e.mediaItem.episodeCount!).clamp(
            0.0,
            1.0,
          ),
    };
    final List<MediaItem> recentlyAdded = mode == CatalogMode.tmdb
        ? ref
              .watch(localLibraryProvider)
              .where(
                (LibraryItem item) => item.mediaItem.id.startsWith('tmdb:'),
              )
              .take(12)
              .map((LibraryItem item) => item.mediaItem)
              .toList(growable: false)
        : anilistFolders
              .expand((AniListAnimeListFolder folder) => folder.entries)
              .map((AniListAnimeListEntry entry) => entry.mediaItem)
              .take(12)
              .toList(growable: false);
    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CatalogOfflineBanner(),
            if (hero == null)
              NeutralPlaceholder(
                title: context.t('No live metadata yet'),
                message: context.t(
                  'Configure a metadata source in Settings to populate the board.',
                ),
                height: 440,
                icon: Icons.movie_filter_rounded,
              )
            else
              _HeroSection(item: hero, mode: mode),
            if (mode == CatalogMode.tmdb
                ? rails.recentMovies.isNotEmpty
                : continueWatching.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              _MediaSection(
                title: context.t(
                  mode == CatalogMode.tmdb
                      ? 'Recently Aired Movies'
                      : 'Continue Watching',
                ),
                items: mode == CatalogMode.tmdb
                    ? rails.recentMovies
                    : continueWatching,
                progressMap: mode == CatalogMode.tmdb
                    ? const <String, double>{}
                    : continueWatchingProgress,
              ),
            ],
            if (rails.recentSeries.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              _MediaSection(
                title: context.t(
                  mode == CatalogMode.tmdb
                      ? 'Recently Aired Series'
                      : 'Popular Anime',
                ),
                items: rails.recentSeries,
                showMoreLocation: mode == CatalogMode.anilist
                    ? AppRoutes.discoveryPath(
                        filter: 'Popular',
                        anilistKind: 'anime',
                      )
                    : null,
              ),
            ],
            if (rails.topAnime.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              _MediaSection(
                title: context.t('Top Anime'),
                items: rails.topAnime,
                maxColumns: 6,
                showMoreLocation: AppRoutes.discoveryPath(
                  type: mode == CatalogMode.tmdb ? MediaType.anime : null,
                  filter: mode == CatalogMode.tmdb ? 'Popular' : 'Top Rated',
                  anilistKind: mode == CatalogMode.anilist ? 'anime' : null,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            _MediaSection(
              title: context.t(
                mode == CatalogMode.tmdb
                    ? 'Recently Added to Library'
                    : 'AniList Library',
              ),
              items: recentlyAdded,
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _HeroSection extends ConsumerWidget {
  const _HeroSection({required this.item, required this.mode});

  final MediaItem item;
  final CatalogMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool forceCompact = ref.watch(
          settingsProvider.select(
            (SettingsState settings) => settings.compactMode,
          ),
        );
        final bool compact =
            AppBreakpoints.classify(
              constraints.maxWidth,
              forceCompact: forceCompact,
            ) ==
            WindowSizeClass.compact;
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: AppRadius.all(AppRadius.xxl),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              height: compact ? 380 : 540,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  Positioned.fill(
                    child: item.backdropUrl.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: palette.posterFallbackGradient,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: item.backdropUrl,
                            fit: BoxFit.cover,
                            placeholder: (BuildContext context, String url) =>
                                const SkeletonBox(),
                            errorWidget:
                                (
                                  BuildContext context,
                                  String url,
                                  Object error,
                                ) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: palette.posterFallbackGradient,
                                  ),
                                ),
                          ),
                  ),

                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: palette.heroOverlayGradient,
                      ),
                    ),
                  ),

                  Positioned(
                    left: compact ? AppSpacing.lg : AppSpacing.xxl,
                    right: compact ? AppSpacing.lg : AppSpacing.xxl,
                    bottom: compact ? AppSpacing.xl : AppSpacing.xxl,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: <Widget>[
                              MetadataChip(
                                label: item.year.toString(),
                                onImage: true,
                              ),
                              if (item.rating > 0)
                                MetadataChip(
                                  icon: Icons.star_rounded,
                                  label: item.rating.toStringAsFixed(1),
                                  color: AppColors.accentAmber,
                                  onImage: true,
                                ),
                              if (mode != CatalogMode.anilist)
                                MetadataChip(
                                  label: context.t(item.type.labelKey),
                                  onImage: true,
                                ),
                              MetadataChip(
                                label: item.durationLabel,
                                onImage: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            item.title,
                            maxLines: compact ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: compact
                                ? Theme.of(context).textTheme.headlineLarge
                                      ?.copyWith(color: Colors.white)
                                : Theme.of(context).textTheme.displayLarge
                                      ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            item.overview,
                            maxLines: compact ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.md,
                            children: <Widget>[
                              FilledButton.icon(
                                style: _onImageFilledButtonStyle(context),
                                onPressed: () => context.push(
                                  AppRoutes.mediaDetailsPath(item.id),
                                  extra: item,
                                ),
                                icon: const Icon(Icons.info_outline_rounded),
                                label: Text(context.t('Details')),
                              ),
                              if (mode == CatalogMode.tmdb)
                                OutlinedButton.icon(
                                  style: _onImageOutlinedButtonStyle(),
                                  onPressed: () async {
                                    await ref
                                        .read(localLibraryProvider.notifier)
                                        .markWatched(item);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            context.t('Marked as watched'),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.check_circle_outline_rounded,
                                  ),
                                  label: Text(context.t('Mark as Watched')),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Covers the tiny scrolling hairline at the bottom edge.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

ButtonStyle _onImageFilledButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: Theme.of(context).colorScheme.primary,
    disabledForegroundColor: Colors.white54,
    disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
    shadowColor: Colors.black.withValues(alpha: 0.32),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
  );
}

ButtonStyle _onImageOutlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: Colors.black.withValues(alpha: 0.30),
    disabledForegroundColor: Colors.white54,
    side: BorderSide(color: Colors.white.withValues(alpha: 0.34)),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.pressed)) {
        return Colors.white.withValues(alpha: 0.18);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return Colors.white.withValues(alpha: 0.10);
      }
      return null;
    }),
  );
}

class _MediaSection extends ConsumerWidget {
  const _MediaSection({
    required this.title,
    required this.items,
    this.maxColumns = 5,
    this.progressMap = const <String, double>{},
    this.showMoreLocation,
  });

  final String title;
  final List<MediaItem> items;
  final int maxColumns;
  final Map<String, double> progressMap;
  final String? showMoreLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool forceCompact = ref.watch(
      settingsProvider.select((SettingsState settings) => settings.compactMode),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact =
            AppBreakpoints.classify(
              constraints.maxWidth,
              forceCompact: forceCompact,
            ) ==
            WindowSizeClass.compact;
        final VoidCallback? onShowMore = showMoreLocation == null
            ? null
            : () => context.go(showMoreLocation!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: title,
              trailing: compact && onShowMore != null
                  ? _SectionLoadMoreButton(onPressed: onShowMore, compact: true)
                  : null,
            ),
            if (items.isEmpty)
              NeutralPlaceholder(
                title: context.t('No live metadata yet'),
                message: context.t(
                  'Configure a metadata source in Settings to load live data.',
                ),
                height: 240,
                icon: Icons.grid_view_rounded,
              )
            else ...<Widget>[
              if (compact)
                SizedBox(
                  height: 300,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (BuildContext context, int index) => SizedBox(
                      width: 172,
                      child: MediaPosterCard(
                        item: items[index],
                        compact: false,
                        watchProgress: progressMap[items[index].id],
                        onTap: () => context.push(
                          AppRoutes.mediaDetailsPath(items[index].id),
                          extra: items[index],
                        ),
                      ),
                    ),
                  ),
                )
              else
                ResponsiveGrid(
                  itemCount: items.length,
                  maxColumns: maxColumns,
                  itemBuilder: (BuildContext context, int index) =>
                      MediaPosterCard(
                        item: items[index],
                        watchProgress: progressMap[items[index].id],
                        onTap: () => context.push(
                          AppRoutes.mediaDetailsPath(items[index].id),
                          extra: items[index],
                        ),
                      ),
                ),
              if (!compact && onShowMore != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Center(child: _SectionLoadMoreButton(onPressed: onShowMore)),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _SectionLoadMoreButton extends StatelessWidget {
  const _SectionLoadMoreButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: compact
          ? OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            )
          : null,
      icon: const Icon(Icons.expand_more_rounded),
      label: Text(context.t('Load more')),
    );
  }
}
