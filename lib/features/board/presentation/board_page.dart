import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/platform/tv_platform.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/media_poster_card.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/tv_directional_focus.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../catalog/application/catalog_repository.dart';
import '../../catalog/presentation/catalog_offline_banner.dart';
import '../../library/application/local_library_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/application/settings_state.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/presentation/anilist_entry_editor.dart';

const double _kBoardWidePosterWidth = 166;
const double _kPosterRowVerticalOverflow = AppSpacing.xxl + AppSpacing.sm;

int _boardMaxColumnsForWidth(double availableWidth) {
  const double spacing = AppSpacing.lg;
  const double sevenColumnsWidth = (7 * _kBoardWidePosterWidth) + (6 * spacing);
  const double eightColumnsWidth = (8 * _kBoardWidePosterWidth) + (7 * spacing);
  if (availableWidth >= eightColumnsWidth) return 8;
  if (availableWidth >= sevenColumnsWidth) return 7;
  return 6;
}

class BoardPage extends ConsumerStatefulWidget {
  const BoardPage({super.key});

  @override
  ConsumerState<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends ConsumerState<BoardPage> {
  late final int _heroSeed = Random().nextInt(1 << 31);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<BoardRails> asyncRails = ref.watch(boardRailsProvider);
    final BoardRails rails = asyncRails.maybeWhen(
      skipLoadingOnReload: true,
      data: (BoardRails value) => value,
      orElse: BoardRails.empty,
    );
    final bool loadingInitialBoard =
        asyncRails.isLoading && !asyncRails.hasValue;
    final CatalogMode mode = ref.watch(catalogModeProvider);
    if (loadingInitialBoard) {
      const Widget emptyPage = AdaptivePage(child: SizedBox.shrink());
      return TvPlatform.isAndroidTv
          ? const TvDirectionalFocus(child: emptyPage)
          : emptyPage;
    }
    final MediaItem? hero = rails.heroForSeed(
      _heroSeed,
      preferRecentMovies: mode == CatalogMode.tmdb,
    );
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
    final Map<String, String> statusBadges = mode == CatalogMode.anilist
        ? _anilistStatusBadges(anilistFolders, context)
        : const <String, String>{};
    final Map<String, AniListAnimeListEntry> anilistEntryMap =
        mode == CatalogMode.anilist
        ? _anilistEntryMap(anilistFolders)
        : const <String, AniListAnimeListEntry>{};
    final List<MediaItem> recentlyAdded = mode == CatalogMode.tmdb
        ? ref
              .watch(localLibraryProvider)
              .where(
                (LibraryItem item) => item.mediaItem.id.startsWith('tmdb:'),
              )
              .take(12)
              .map((LibraryItem item) => item.mediaItem)
              .toList(growable: false)
        : const <MediaItem>[];
    final Widget page = AdaptivePage(
      child: SingleChildScrollView(
        key: const ValueKey<String>('board-page-scroll-view'),
        clipBehavior: Clip.none,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CatalogOfflineBanner(),
            if (hero == null)
              NeutralPlaceholder(
                title: context.t('Could not load catalog'),
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
                statusBadgeMap: statusBadges,
                anilistEntryMap: anilistEntryMap,
                enableAniListEditing: mode == CatalogMode.anilist,
                loadMoreQuery: mode == CatalogMode.tmdb
                    ? const _BoardLoadMoreQuery(
                        type: MediaType.movie,
                        filter: 'New Releases',
                      )
                    : null,
              ),
            ],
            if (mode == CatalogMode.anilist) ...<Widget>[
              for (final String filter in _anilistBoardFilters)
                if (_anilistBoardItems(rails, filter).isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  _MediaSection(
                    title: context.t(filter),
                    items: _anilistBoardItems(rails, filter),
                    loadMoreQuery: _BoardLoadMoreQuery(
                      filter: filter,
                      anilistKind: 'anime',
                    ),
                    statusBadgeMap: statusBadges,
                    anilistEntryMap: anilistEntryMap,
                    enableAniListEditing: true,
                  ),
                ],
            ] else ...<Widget>[
              if (rails.recentSeries.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxl),
                _MediaSection(
                  title: context.t('Recently Aired Series'),
                  items: rails.recentSeries,
                  loadMoreQuery: const _BoardLoadMoreQuery(
                    type: MediaType.series,
                    filter: 'Popular',
                  ),
                ),
              ],
              if (rails.topAnime.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxl),
                _MediaSection(
                  title: context.t('Top Anime'),
                  items: rails.topAnime,
                  loadMoreQuery: const _BoardLoadMoreQuery(
                    type: MediaType.anime,
                    filter: 'Popular',
                  ),
                ),
              ],
              if (recentlyAdded.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxl),
                _MediaSection(
                  title: context.t('Recently Added to Library'),
                  items: recentlyAdded,
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
    return TvPlatform.isAndroidTv ? TvDirectionalFocus(child: page) : page;
  }
}

class _BoardLoadingAnimation extends StatelessWidget {
  const _BoardLoadingAnimation({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Center(
        child: Semantics(
          label: context.t('Loading...'),
          child: const SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

const List<String> _anilistBoardFilters = <String>[
  'Trending',
  'Popular',
  'Top Rated',
  'Favorites',
  'Airing',
  'Upcoming',
  'Finished',
  'Newest',
  'Recently Updated',
];

List<MediaItem> _anilistBoardItems(BoardRails rails, String filter) {
  return switch (filter) {
    'Trending' => rails.recentMovies,
    'Popular' => rails.recentSeries,
    'Top Rated' => rails.topAnime,
    _ => rails.additionalSection(filter),
  };
}

Map<String, String> _anilistStatusBadges(
  List<AniListAnimeListFolder> folders,
  BuildContext context,
) {
  final Map<String, String> badges = <String, String>{};
  for (final AniListAnimeListFolder folder in folders) {
    for (final AniListAnimeListEntry entry in folder.entries) {
      final String label = context.t(entry.status.label);
      badges[entry.mediaItem.id] = label;
      final String? anilistId = entry.mediaItem.externalIds['anilist'];
      if (anilistId != null && anilistId.isNotEmpty) {
        badges['anilist:$anilistId'] = label;
        badges['anilist:manga:$anilistId'] = label;
      }
    }
  }
  return badges;
}

Map<String, AniListAnimeListEntry> _anilistEntryMap(
  List<AniListAnimeListFolder> folders,
) {
  final Map<String, AniListAnimeListEntry> entries =
      <String, AniListAnimeListEntry>{};
  for (final AniListAnimeListFolder folder in folders) {
    for (final AniListAnimeListEntry entry in folder.entries) {
      entries[entry.mediaItem.id] = entry;
      final String? anilistId = entry.mediaItem.externalIds['anilist'];
      if (anilistId != null && anilistId.isNotEmpty) {
        entries['anilist:$anilistId'] = entry;
        entries['anilist:manga:$anilistId'] = entry;
      }
    }
  }
  return entries;
}

Future<void> _openAniListEntryEditor(
  BuildContext context,
  WidgetRef ref, {
  required MediaItem item,
  required AniListAnimeListEntry? entry,
}) async {
  final AniListAnimeListEntry editableEntry =
      entry ??
      AniListAnimeListEntry(
        id: 0,
        status: AniListListStatus.planning,
        progress: 0,
        mediaItem: item,
      );
  final AniListEntryEditDraft? draft = await showAniListEntryEditor(
    context,
    ref: ref,
    entry: editableEntry,
    status: entry?.status,
    progress: editableEntry.progress,
    score: editableEntry.score,
    notes: editableEntry.notes,
    repeat: editableEntry.repeat,
    scoreFormat: ref.read(aniListEffectiveScoreFormatProvider),
    allowRemove: entry != null,
  );
  if (draft == null || !context.mounted) return;
  if (draft.remove && entry != null) {
    await deleteAniListEntry(context: context, ref: ref, entry: entry);
    return;
  }
  await saveAniListEntryEdit(
    context: context,
    ref: ref,
    entry: editableEntry,
    draft: draft,
  );
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
            key: const ValueKey<String>('board-hero-clip'),
            borderRadius: AppRadius.all(AppRadius.xxl),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              height: compact ? 380 : 540,
              width: double.infinity,
              child: Stack(
                key: const ValueKey<String>('board-hero-stack'),
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
                    key: const ValueKey<String>('board-hero-bottom-hairline'),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 1,
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

class _BoardLoadMoreQuery {
  const _BoardLoadMoreQuery({
    required this.filter,
    this.type,
    this.anilistKind,
  });

  final String filter;
  final MediaType? type;
  final String? anilistKind;

  @override
  bool operator ==(Object other) {
    return other is _BoardLoadMoreQuery &&
        other.filter == filter &&
        other.type == type &&
        other.anilistKind == anilistKind;
  }

  @override
  int get hashCode => Object.hash(filter, type, anilistKind);
}

class _MediaSection extends ConsumerStatefulWidget {
  const _MediaSection({
    required this.title,
    required this.items,
    this.progressMap = const <String, double>{},
    this.statusBadgeMap = const <String, String>{},
    this.anilistEntryMap = const <String, AniListAnimeListEntry>{},
    this.enableAniListEditing = false,
    this.loadMoreQuery,
  });

  final String title;
  final List<MediaItem> items;
  final Map<String, double> progressMap;
  final Map<String, String> statusBadgeMap;
  final Map<String, AniListAnimeListEntry> anilistEntryMap;
  final bool enableAniListEditing;
  final _BoardLoadMoreQuery? loadMoreQuery;

  @override
  ConsumerState<_MediaSection> createState() => _MediaSectionState();
}

class _MediaSectionState extends ConsumerState<_MediaSection> {
  final List<MediaItem> _additionalItems = <MediaItem>[];
  late final ScrollController _compactScrollController;
  int _page = 1;
  int _requestSerial = 0;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageSize = 20;
  int? _pendingPageSize;

  @override
  void initState() {
    super.initState();
    _compactScrollController = ScrollController()
      ..addListener(_onCompactScroll);
  }

  @override
  void dispose() {
    _compactScrollController
      ..removeListener(_onCompactScroll)
      ..dispose();
    super.dispose();
  }

  void _onCompactScroll() {
    if (!_compactScrollController.hasClients ||
        _compactScrollController.position.pixels <= 0 ||
        _compactScrollController.position.extentAfter > 220) {
      return;
    }
    unawaited(_loadMore(pageSize: 20, compact: true));
  }

  @override
  void didUpdateWidget(covariant _MediaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadMoreQuery != widget.loadMoreQuery ||
        !identical(oldWidget.items, widget.items)) {
      _requestSerial += 1;
      _additionalItems.clear();
      _page = 1;
      _loadingMore = false;
      _hasMore = true;
    }
  }

  void _schedulePageSize(int pageSize) {
    if (_pageSize == pageSize || _pendingPageSize == pageSize) return;
    _pendingPageSize = pageSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingPageSize != pageSize) return;
      _pendingPageSize = null;
      if (_pageSize == pageSize) return;
      setState(() {
        _requestSerial += 1;
        _additionalItems.clear();
        _page = 1;
        _loadingMore = false;
        _hasMore = true;
        _pageSize = pageSize;
      });
    });
  }

  List<MediaItem> _visibleItems({
    required int pageSize,
    required bool compact,
  }) {
    final Set<String> seen = <String>{};
    final Iterable<MediaItem> initialItems =
        !compact && widget.loadMoreQuery != null
        ? widget.items.take(pageSize)
        : widget.items;
    return <MediaItem>[
      ...initialItems,
      ..._additionalItems,
    ].where((MediaItem item) => seen.add(item.id)).toList(growable: false);
  }

  Future<void> _loadMore({required int pageSize, required bool compact}) async {
    final _BoardLoadMoreQuery? query = widget.loadMoreQuery;
    if (query == null || _loadingMore || !_hasMore) return;

    final CatalogRepository? repository = ref.read(
      activeCatalogRepositoryProvider,
    );
    if (repository == null) {
      setState(() => _hasMore = false);
      return;
    }

    final int requestId = ++_requestSerial;
    final int nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      final List<MediaItem> nextItems = await repository.discover(
        search: '',
        type: query.type,
        filter: query.filter,
        page: nextPage,
        pageSize: pageSize,
        anilistKind: query.anilistKind,
      );
      if (!mounted || requestId != _requestSerial) return;

      final Set<String> seen = _visibleItems(
        pageSize: pageSize,
        compact: compact,
      ).map((MediaItem item) => item.id).toSet();
      setState(() {
        _additionalItems.addAll(
          nextItems.where((MediaItem item) => seen.add(item.id)),
        );
        if (nextItems.isNotEmpty) _page = nextPage;
        _hasMore = nextItems.length >= pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestSerial) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool forceCompact = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.compactCards,
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact =
            AppBreakpoints.classify(
              constraints.maxWidth,
              forceCompact: forceCompact,
            ) ==
            WindowSizeClass.compact;
        final int columns = responsiveGridColumnCount(
          availableWidth: constraints.maxWidth,
          minItemWidth: 168,
          maxColumns: 8,
          maxColumnsForWidth: _boardMaxColumnsForWidth,
        );
        final int pageSize = compact ? 20 : columns * 3;
        _schedulePageSize(pageSize);
        final List<MediaItem> items = _visibleItems(
          pageSize: pageSize,
          compact: compact,
        );
        final VoidCallback? onShowMore = widget.loadMoreQuery == null
            ? null
            : () => unawaited(_loadMore(pageSize: pageSize, compact: compact));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(title: widget.title),
            if (items.isEmpty)
              const _BoardLoadingAnimation(height: 240)
            else ...<Widget>[
              if (compact)
                SizedBox(
                  height: 300,
                  child: ClipRect(
                    key: const ValueKey<String>(
                      'media-section-horizontal-clip',
                    ),
                    clipper: const _HorizontalPosterRowClipper(),
                    child: ListView.separated(
                      key: const ValueKey<String>(
                        'media-section-horizontal-list',
                      ),
                      controller: _compactScrollController,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (BuildContext context, int index) {
                        if (index == items.length) {
                          return const SizedBox(
                            key: ValueKey<String>('compact-row-loading-more'),
                            width: 64,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final MediaItem item = items[index];
                        final AniListAnimeListEntry? entry =
                            widget.anilistEntryMap[item.id];
                        final VoidCallback? editAniListEntry =
                            widget.enableAniListEditing
                            ? () => unawaited(
                                _openAniListEntryEditor(
                                  context,
                                  ref,
                                  item: item,
                                  entry: entry,
                                ),
                              )
                            : null;
                        return SizedBox(
                          width: 172,
                          child: MediaPosterCard(
                            item: item,
                            compact: false,
                            watchProgress: widget.progressMap[item.id],
                            statusBadgeLabel: widget.statusBadgeMap[item.id],
                            onTap: () => context.push(
                              AppRoutes.mediaDetailsPath(item.id),
                              extra: item,
                            ),
                            onLongPress: editAniListEntry,
                            onSecondaryTap: editAniListEntry,
                          ),
                        );
                      },
                    ),
                  ),
                )
              else
                ResponsiveGrid(
                  itemCount: items.length,
                  maxColumns: 8,
                  maxColumnsForWidth: _boardMaxColumnsForWidth,
                  clipBehavior: Clip.none,
                  itemBuilder: (BuildContext context, int index) {
                    final MediaItem item = items[index];
                    final AniListAnimeListEntry? entry =
                        widget.anilistEntryMap[item.id];
                    final VoidCallback? editAniListEntry =
                        widget.enableAniListEditing
                        ? () => unawaited(
                            _openAniListEntryEditor(
                              context,
                              ref,
                              item: item,
                              entry: entry,
                            ),
                          )
                        : null;
                    return MediaPosterCard(
                      item: item,
                      watchProgress: widget.progressMap[item.id],
                      statusBadgeLabel: widget.statusBadgeMap[item.id],
                      onTap: () => context.push(
                        AppRoutes.mediaDetailsPath(item.id),
                        extra: item,
                      ),
                      onLongPress: editAniListEntry,
                      onSecondaryTap: editAniListEntry,
                    );
                  },
                ),
              if (!compact && onShowMore != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: _SectionLoadMoreButton(
                    onPressed: onShowMore,
                    loading: _loadingMore,
                    hasMore: _hasMore,
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _HorizontalPosterRowClipper extends CustomClipper<Rect> {
  const _HorizontalPosterRowClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    -_kPosterRowVerticalOverflow,
    size.width,
    size.height + _kPosterRowVerticalOverflow,
  );

  @override
  bool shouldReclip(_HorizontalPosterRowClipper oldClipper) => false;
}

class _SectionLoadMoreButton extends StatelessWidget {
  const _SectionLoadMoreButton({
    required this.onPressed,
    required this.loading,
    required this.hasMore,
  });

  final VoidCallback onPressed;
  final bool loading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) {
      return Text(
        context.t('All caught up'),
        style: Theme.of(context).textTheme.labelLarge,
      );
    }
    return OutlinedButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.expand_more_rounded),
      label: Text(context.t(loading ? 'Loading more' : 'Load more')),
    );
  }
}
