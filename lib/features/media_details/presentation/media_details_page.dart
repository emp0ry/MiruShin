import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation_helpers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/page_back_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../../shared/utils/media_status_formatter.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../catalog/presentation/catalog_offline_banner.dart';
import '../../library/application/local_library_provider.dart';
import '../../library/presentation/local_library_editor.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/data/shikimori_client.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../../tracking/presentation/anilist_entry_editor.dart';
import '../../tracking/presentation/anilist_favorite_button.dart';

class MediaDetailsPage extends ConsumerWidget {
  const MediaDetailsPage({required this.id, this.initialItem, super.key});

  final String id;
  final MediaItem? initialItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MediaItem?> asyncDetails = ref.watch(
      mediaDetailsProvider(id),
    );
    final MediaItem? details = asyncDetails.maybeWhen(
      data: (MediaItem? item) => item,
      orElse: () => null,
    );
    final MediaItem? item = details ?? initialItem;

    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CatalogOfflineBanner(),
            if (item == null && asyncDetails.isLoading)
              const SkeletonBox(height: 520, radius: AppRadius.xxl)
            else if (item == null)
              NeutralPlaceholder(
                title: context.t('Details unavailable'),
                message: context.t(
                  'Metadata details could not be loaded. Check your settings.',
                ),
                height: 420,
                icon: Icons.info_outline_rounded,
                action: OutlinedButton.icon(
                  onPressed: () => context.go(AppRoutes.discovery),
                  icon: const Icon(Icons.explore_rounded),
                  label: Text(context.t('Discovery')),
                ),
              )
            else ...<Widget>[
              _DetailsHero(item: item),
              const SizedBox(height: AppSpacing.xxl),
              _DetailsBody(item: item),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final bool hasAniListInfo =
        mode == CatalogMode.anilist &&
        (item.externalIds['anilist_source'] != null ||
            item.externalIds['anilist_studios'] != null ||
            item.externalIds['anilist_tags'] != null ||
            item.externalIds['anilist_format'] != null ||
            item.externalIds['anilist_relation_type'] != null ||
            item.externalIds['anilist_popularity'] != null ||
            item.episodeCount != null ||
            item.genres.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ActionPanel(item: item),
        const SizedBox(height: AppSpacing.xxl),
        _OverviewPanel(item: item),
        if (hasAniListInfo) ...<Widget>[
          const SizedBox(height: AppSpacing.xxl),
          _AniListInfoPanel(item: item),
        ],
        if (item.seasons.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xxl),
          _SeasonsPanel(item: item),
        ],
      ],
    );
  }
}

AniListAnimeListEntry? _findAniListEntry(WidgetRef ref, MediaItem item) {
  final int? anilistId = _aniListId(item);
  if (anilistId == null) return null;

  final bool isManga = _isAniListManga(item);
  final List<AniListAnimeListFolder> fullFolders = ref
      .watch(isManga ? anilistMangaListProvider : anilistAnimeListProvider)
      .maybeWhen(
        skipLoadingOnReload: true,
        data: (List<AniListAnimeListFolder> folders) => folders,
        orElse: () => const <AniListAnimeListFolder>[],
      );
  final AniListAnimeListEntry? fullEntry = _findAniListEntryInFolders(
    anilistId,
    fullFolders,
  );
  if (fullEntry != null) return fullEntry;

  final List<AniListAnimeListFolder> previewFolders = ref
      .watch(
        isManga
            ? anilistMangaPreviewListProvider
            : anilistAnimePreviewListProvider,
      )
      .maybeWhen(
        skipLoadingOnReload: true,
        data: (List<AniListAnimeListFolder> folders) => folders,
        orElse: () => const <AniListAnimeListFolder>[],
      );
  return _findAniListEntryInFolders(anilistId, previewFolders);
}

AniListAnimeListEntry? _findAniListEntryInFolders(
  int anilistId,
  List<AniListAnimeListFolder> folders,
) {
  for (final AniListAnimeListFolder folder in folders) {
    for (final AniListAnimeListEntry entry in folder.entries) {
      if (entryAniListId(entry) == anilistId) {
        return entry;
      }
    }
  }
  return null;
}

int? _aniListId(MediaItem item) {
  final String? anilistId = item.externalIds['anilist'];
  return anilistId == null ? null : int.tryParse(anilistId);
}

bool _isAniListManga(MediaItem item) {
  return item.externalIds['anilist_type'] == 'MANGA' ||
      item.id.toLowerCase().startsWith('anilist:manga:');
}

bool _isAniListAnime(MediaItem item) {
  return item.externalIds['anilist_type'] == 'ANIME' ||
      RegExp(r'^anilist:\d+$').hasMatch(item.id);
}

String _aniListStatusLabel(AniListListStatus status, MediaItem item) {
  final bool isManga = _isAniListManga(item);
  return switch (status) {
    AniListListStatus.current => isManga ? 'Reading' : 'Watching',
    AniListListStatus.planning => 'Planning',
    AniListListStatus.completed => 'Finished',
    AniListListStatus.dropped => 'Dropped',
    AniListListStatus.paused => 'Paused',
    AniListListStatus.repeating => isManga ? 'Rereading' : 'Rewatching',
  };
}

String _personalStatusLabel(WidgetRef ref, MediaItem item, CatalogMode mode) {
  if (mode == CatalogMode.anilist) {
    final AniListAnimeListEntry? entry = _findAniListEntry(ref, item);
    return entry == null ? '' : _aniListStatusLabel(entry.status, item);
  }

  final List<LibraryItem> library = ref.watch(localLibraryProvider);
  for (final LibraryItem current in library) {
    if (current.mediaItem.id == item.id) {
      return current.status.label;
    }
  }
  return '';
}

String _formatMediaFormat(String raw) {
  final String value = raw.trim();
  if (value.isEmpty) return '';
  return switch (value.toUpperCase()) {
    'TV' => 'TV',
    'TV_SHORT' => 'TV Short',
    'MOVIE' => 'Movie',
    'SPECIAL' => 'Special',
    'OVA' => 'OVA',
    'ONA' => 'ONA',
    'MUSIC' => 'Music',
    'MANGA' => 'Manga',
    'NOVEL' => 'Novel',
    'ONE_SHOT' => 'One Shot',
    _ => _titleCaseToken(value),
  };
}

String _mediaKindLabel(MediaItem item, {String? fallbackFormat}) {
  final String format = _formatMediaFormat(
    item.externalIds['anilist_format'] ?? fallbackFormat ?? '',
  );
  final String relation = _formatRelationType(
    item.externalIds['anilist_relation_type'] ?? '',
  );
  if (format.isNotEmpty && relation.isNotEmpty) {
    return '$format · $relation';
  }
  return format.isNotEmpty ? format : relation;
}

String _formatRelationType(String raw) {
  final String value = raw.trim();
  if (value.isEmpty) return '';
  return switch (value.toUpperCase()) {
    'SIDE_STORY' => 'Side Story',
    'SPIN_OFF' => 'Spin-off',
    'PREQUEL' => 'Prequel',
    'SEQUEL' => 'Sequel',
    'ADAPTATION' => 'Adaptation',
    'ALTERNATIVE' => 'Alternative',
    'SUMMARY' => 'Summary',
    'OTHER' => 'Other',
    _ => _titleCaseToken(value),
  };
}

String _titleCaseToken(String value) {
  return value
      .split(RegExp(r'[_\s]+'))
      .where((String part) => part.isNotEmpty)
      .map((String part) {
        if (part.length <= 3 && part.toUpperCase() == part) return part;
        final String lower = part.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

String _episodeCountLabel(MediaItem item) {
  final int? count = item.episodeCount;
  if (count == null || count <= 0) return '';
  return '$count';
}

class _OverviewPanel extends ConsumerWidget {
  const _OverviewPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final List<Widget> chips = <Widget>[
      if (mode != CatalogMode.anilist && item.sourceProvider.isNotEmpty)
        MetadataChip(label: item.sourceProvider),
      if (mode != CatalogMode.anilist && item.externalIds['tmdb'] != null)
        MetadataChip(label: 'TMDB ${item.externalIds['tmdb']}'),
      if (mode != CatalogMode.anilist)
        MetadataChip(label: context.t(item.type.labelKey)),
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('Overview'),
            subtitle: context.t(
              'Metadata, progress, and library actions only.',
            ),
          ),
          Text(item.overview, style: Theme.of(context).textTheme.bodyLarge),
          if (chips.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: chips,
            ),
          ],
          if (mode != CatalogMode.anilist &&
              item.genres.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.t('Genres'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final String genre in item.genres.take(12))
                  MetadataChip(label: genre),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── AniList info panel ───────────────────────────────────────────────────────

class _AniListInfoPanel extends StatefulWidget {
  const _AniListInfoPanel({required this.item});

  final MediaItem item;

  @override
  State<_AniListInfoPanel> createState() => _AniListInfoPanelState();
}

class _AniListInfoPanelState extends State<_AniListInfoPanel> {
  bool _spoilersRevealed = false;

  Map<String, String> get _ext => widget.item.externalIds;

  static String _fmtSource(String s) => switch (s.toUpperCase()) {
    'ORIGINAL' => 'Original',
    'MANGA' => 'Manga',
    'LIGHT_NOVEL' => 'Light Novel',
    'VISUAL_NOVEL' => 'Visual Novel',
    'VIDEO_GAME' => 'Video Game',
    'NOVEL' => 'Novel',
    'DOUJINSHI' => 'Doujinshi',
    'ANIME' => 'Anime',
    'WEB_NOVEL' => 'Web Novel',
    'LIVE_ACTION' => 'Live Action',
    'GAME' => 'Game',
    'COMIC' => 'Comic',
    'MULTIMEDIA_PROJECT' => 'Multimedia',
    'OTHER' => 'Other',
    _ => s,
  };

  static String _fmtSeason(String s) => switch (s.toUpperCase()) {
    'WINTER' => 'Winter',
    'SPRING' => 'Spring',
    'SUMMER' => 'Summer',
    'FALL' => 'Fall',
    _ => s,
  };

  static String _fmtStatus(String s) => mediaStatusOrFallback(s);

  static String _fmtCountry(String c) => switch (c.toUpperCase()) {
    'JP' => 'Japan',
    'CN' => 'China',
    'KR' => 'South Korea',
    'TW' => 'Taiwan',
    _ => c,
  };

  static String _fmtNum(String raw) {
    final int? n = int.tryParse(raw);
    if (n == null) return raw;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextTheme tt = Theme.of(context).textTheme;
    final Color spoilerTextColor = Colors.red.shade200;
    final String episodeLabel = _episodeCountLabel(widget.item);

    // Info rows
    final List<({IconData icon, String label, String value})> infoRows =
        <({IconData icon, String label, String value})>[
          if (episodeLabel.isNotEmpty)
            (
              icon: Icons.format_list_numbered_rounded,
              label: _isAniListManga(widget.item) ? 'Chapters' : 'Episodes',
              value: episodeLabel,
            ),
          if (_ext['anilist_country'] != null)
            (
              icon: Icons.flag_outlined,
              label: 'Origin',
              value: _fmtCountry(_ext['anilist_country']!),
            ),
          if (_ext['anilist_source'] != null)
            (
              icon: Icons.auto_stories_outlined,
              label: 'Source',
              value: _fmtSource(_ext['anilist_source']!),
            ),
          if (_ext['anilist_season'] != null)
            (
              icon: Icons.wb_sunny_outlined,
              label: 'Season',
              value: [
                _fmtSeason(_ext['anilist_season']!),
                if (_ext['anilist_season_year'] != null)
                  _ext['anilist_season_year']!,
              ].join(' '),
            ),
          if (widget.item.statusLabel.isNotEmpty &&
              widget.item.statusLabel != 'AniList')
            (
              icon: Icons.live_tv_outlined,
              label: 'Status',
              value: _fmtStatus(widget.item.statusLabel),
            ),
          if (_ext['anilist_start_date'] != null)
            (
              icon: Icons.calendar_month_outlined,
              label: 'Released',
              value: _ext['anilist_start_date']!,
            ),
          if (_ext['anilist_end_date'] != null)
            (
              icon: Icons.event_available_outlined,
              label: 'Ended',
              value: _ext['anilist_end_date']!,
            ),
        ];

    // Studios / producers
    final List<({String name, bool isStudio})> studios =
        <({String name, bool isStudio})>[];
    final String? studiosRaw = _ext['anilist_studios'];
    if (studiosRaw != null) {
      for (final String entry in studiosRaw.split('|')) {
        final List<String> parts = entry.split(':');
        if (parts.length < 2) continue;
        final String name = parts.sublist(0, parts.length - 1).join(':');
        studios.add((name: name, isStudio: parts.last == '1'));
      }
    }
    final List<String> animationStudios = studios
        .where((s) => s.isStudio)
        .map((s) => s.name)
        .toList(growable: false);
    final List<String> producers = studios
        .where((s) => !s.isStudio)
        .map((s) => s.name)
        .toList(growable: false);

    // Tags
    final List<({String name, int rank, bool spoiler})> tags =
        <({String name, int rank, bool spoiler})>[];
    final String? tagsRaw = _ext['anilist_tags'];
    if (tagsRaw != null) {
      for (final String entry in tagsRaw.split('|')) {
        final List<String> parts = entry.split(':');
        if (parts.length < 4) continue;
        final String name = parts.sublist(0, parts.length - 3).join(':');
        final int rank = int.tryParse(parts[parts.length - 3]) ?? 0;
        final bool isSpoiler =
            parts[parts.length - 2] == '1' || parts[parts.length - 1] == '1';
        tags.add((name: name, rank: rank, spoiler: isSpoiler));
      }
      tags.sort((a, b) => b.rank.compareTo(a.rank));
    }
    final List<({String name, int rank, bool spoiler})> visibleTags = tags
        .where((t) => !t.spoiler)
        .toList(growable: false);
    final List<({String name, int rank, bool spoiler})> spoilerTags = tags
        .where((t) => t.spoiler)
        .toList(growable: false);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('Details')),

          // Stats row: popularity + favorites
          if (_ext['anilist_popularity'] != null ||
              _ext['anilist_favourites'] != null) ...<Widget>[
            Row(
              children: <Widget>[
                if (_ext['anilist_popularity'] != null) ...<Widget>[
                  Icon(
                    Icons.people_outline_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _fmtNum(_ext['anilist_popularity']!),
                    style: tt.titleMedium,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(context.t('watching'), style: tt.bodySmall),
                ],
                if (_ext['anilist_popularity'] != null &&
                    _ext['anilist_favourites'] != null)
                  const SizedBox(width: AppSpacing.xl),
                if (_ext['anilist_favourites'] != null) ...<Widget>[
                  Icon(
                    Icons.favorite_outline_rounded,
                    size: 18,
                    color: cs.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _fmtNum(_ext['anilist_favourites']!),
                    style: tt.titleMedium,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(context.t('favorites'), style: tt.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Info rows
          if (infoRows.isNotEmpty) ...<Widget>[
            ...infoRows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Icon(row.icon, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${context.t(row.label)}: ',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.value,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Genres
          if (widget.item.genres.isNotEmpty) ...<Widget>[
            Text(context.t('Genres'), style: tt.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final String genre in widget.item.genres.take(12))
                  Chip(
                    label: Text(genre),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Tags
          if (tags.isNotEmpty) ...<Widget>[
            Text(context.t('Tags'), style: tt.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                ...visibleTags.map(
                  (t) => Chip(
                    label: Text('${t.rank}% ${t.name}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (spoilerTags.isNotEmpty)
                  ..._spoilersRevealed
                      ? spoilerTags.map(
                          (t) => Chip(
                            label: Text('${t.rank}% ${t.name}'),
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(color: spoilerTextColor),
                          ),
                        )
                      : <Widget>[
                          ActionChip(
                            avatar: Icon(
                              Icons.visibility_off_outlined,
                              size: 14,
                              color: spoilerTextColor,
                            ),
                            label: Text(
                              '${spoilerTags.length} ${context.t('spoiler tags')}',
                            ),
                            onPressed: () =>
                                setState(() => _spoilersRevealed = true),
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(color: spoilerTextColor),
                          ),
                        ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Animation studios
          if (animationStudios.isNotEmpty) ...<Widget>[
            Text(context.t('Studios'), style: tt.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: animationStudios
                  .map(
                    (s) => Chip(
                      avatar: const Icon(
                        Icons.movie_creation_outlined,
                        size: 14,
                      ),
                      label: Text(s),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Producers
          if (producers.isNotEmpty) ...<Widget>[
            Text(context.t('Producers'), style: tt.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: producers
                  .map(
                    (p) => Chip(
                      label: Text(p),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Details hero ─────────────────────────────────────────────────────────────

class _DetailsHero extends ConsumerWidget {
  const _DetailsHero({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool forceCompact = ref.watch(
      settingsProvider.select((SettingsState settings) => settings.compactMode),
    );
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
            child: ColoredBox(
              color:
                  palette.surfaceColor, // use your page/background color here
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

                    // This hides the scrolling hairline inside the bottom edge.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: palette.heroOverlayGradient,
                        ),
                      ),
                    ),

                    Positioned(
                      top: AppSpacing.md,
                      left: AppSpacing.md,
                      child: PageBackButton(
                        onPressed: () => _goBackFromDetails(context),
                      ),
                    ),
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.34),
                          borderRadius: AppRadius.all(AppRadius.lg),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: AniListFavoriteButton(item: item, onImage: true),
                      ),
                    ),

                    Positioned(
                      left: compact ? AppSpacing.lg : AppSpacing.xxl,
                      right: compact ? AppSpacing.lg : AppSpacing.xxl,
                      bottom: compact ? AppSpacing.xl : AppSpacing.xxl,
                      child: compact
                          ? _HeroCopy(item: item, compact: true)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                _PosterPreview(item: item),
                                const SizedBox(width: AppSpacing.xxl),
                                Expanded(child: _HeroCopy(item: item)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

void _goBackFromDetails(BuildContext context) {
  goBackOrGo(context, AppRoutes.discovery);
}

class _PosterPreview extends StatelessWidget {
  const _PosterPreview({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.xl),
      child: SizedBox(
        width: 188,
        height: 282,
        child: item.posterUrl.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: palette.posterFallbackGradient,
                ),
              )
            : CachedNetworkImage(
                imageUrl: item.posterUrl,
                fit: BoxFit.cover,
                placeholder: (BuildContext context, String url) =>
                    const SkeletonBox(),
                errorWidget: (BuildContext context, String url, Object error) =>
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: palette.posterFallbackGradient,
                      ),
                    ),
              ),
      ),
    );
  }
}

class _HeroCopy extends ConsumerWidget {
  const _HeroCopy({required this.item, this.compact = false});

  final MediaItem item;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final String formatLabel = _mediaKindLabel(item);
    final String personalStatusLabel = _personalStatusLabel(ref, item, mode);
    final String aniListTitleLanguage = ref.watch(
      aniListEffectiveTitleLanguageProvider,
    );
    final String? secondaryTitle = _secondaryHeroTitle(
      item,
      aniListTitleLanguage: aniListTitleLanguage,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              if (mode != CatalogMode.anilist)
                MetadataChip(
                  label: context.t(item.type.labelKey),
                  onImage: true,
                ),
              MetadataChip(label: item.year.toString(), onImage: true),
              if (item.rating > 0 && item.rating <= 10)
                MetadataChip(
                  icon: Icons.star_rounded,
                  label: item.rating.toStringAsFixed(1),
                  color: AppColors.accentAmber,
                  onImage: true,
                ),
              if (mode == CatalogMode.anilist && formatLabel.isNotEmpty)
                MetadataChip(label: formatLabel, onImage: true),
              if (personalStatusLabel.isNotEmpty)
                MetadataChip(label: personalStatusLabel, onImage: true),
              if (mode != CatalogMode.anilist)
                MetadataChip(label: item.durationLabel, onImage: true),
              if (mode != CatalogMode.anilist)
                MetadataChip(label: item.sourceProvider, onImage: true),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: item.title));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.t('Title copied'))),
              );
            },
            child: Text(
              item.title,
              maxLines: compact ? 4 : 3,
              overflow: TextOverflow.ellipsis,
              style:
                  (compact
                          ? Theme.of(context).textTheme.headlineLarge
                          : Theme.of(context).textTheme.displayLarge)
                      ?.copyWith(color: Colors.white),
            ),
          ),
          if (secondaryTitle != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              secondaryTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            item.overview,
            maxLines: compact ? 4 : 5,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

String? _secondaryHeroTitle(
  MediaItem item, {
  required String aniListTitleLanguage,
}) {
  final String primaryTitle = item.title.trim();
  final String originalTitle = item.originalTitle.trim();
  final String nativeTitle = _firstDistinctTitle(primaryTitle, <String>[
    item.externalIds['anilist_title_native'] ?? '',
    originalTitle,
  ]);
  final String romajiTitle = _firstDistinctTitle(
    primaryTitle,
    <String>[item.externalIds['anilist_title_romaji'] ?? '', ...item.aliases],
    requireLatin: true,
    rejectJapanese: true,
  );

  if (item.type == MediaType.anime) {
    if (aniListTitleLanguage == 'NATIVE') {
      if (romajiTitle.isNotEmpty) return romajiTitle;
      if (nativeTitle.isNotEmpty) return nativeTitle;
    } else if (aniListTitleLanguage == 'ROMAJI') {
      if (nativeTitle.isNotEmpty) return nativeTitle;
      if (romajiTitle.isNotEmpty) return romajiTitle;
    } else {
      if (romajiTitle.isNotEmpty) return romajiTitle;
      if (nativeTitle.isNotEmpty) return nativeTitle;
    }
  }

  if (originalTitle.isNotEmpty && !_sameTitle(originalTitle, primaryTitle)) {
    return originalTitle;
  }
  return null;
}

String _firstDistinctTitle(
  String primaryTitle,
  List<String> candidates, {
  bool requireLatin = false,
  bool rejectJapanese = false,
}) {
  final String normalizedPrimary = primaryTitle.trim();
  for (final String candidate in candidates) {
    final String trimmed = candidate.trim();
    if (trimmed.isEmpty || _sameTitle(trimmed, normalizedPrimary)) {
      continue;
    }
    if (requireLatin && !_containsLatin(trimmed)) {
      continue;
    }
    if (rejectJapanese && _containsJapanese(trimmed)) {
      continue;
    }
    return trimmed;
  }
  return '';
}

bool _sameTitle(String a, String b) {
  return a.toLowerCase() == b.toLowerCase();
}

bool _containsLatin(String text) {
  return RegExp(r'[A-Za-z]').hasMatch(text);
}

bool _containsJapanese(String text) {
  return RegExp(r'[぀-ゟ゠-ヿ一-鿿]').hasMatch(text);
}

class _ActionPanel extends ConsumerWidget {
  const _ActionPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final SettingsState settings = ref.watch(settingsProvider);
    final String anilistToken = settings.anilistAccessToken.trim();

    LibraryItem? libraryItem;
    if (mode == CatalogMode.tmdb) {
      final List<LibraryItem> library = ref.watch(localLibraryProvider);
      for (final LibraryItem current in library) {
        if (current.mediaItem.id == item.id) {
          libraryItem = current;
          break;
        }
      }
    }
    final LocalLibraryController controller = ref.read(
      localLibraryProvider.notifier,
    );
    final bool inLibrary = libraryItem != null;

    final bool hasAnilist = anilistToken.isNotEmpty;
    final int? anilistId = _aniListId(item);
    final bool isAniListManga = _isAniListManga(item);
    final bool isAniListAnime = _isAniListAnime(item);
    final bool canWatch =
        mode == CatalogMode.tmdb ||
        (mode == CatalogMode.anilist && isAniListAnime);
    final bool canAddToAniList =
        mode == CatalogMode.anilist && hasAnilist && anilistId != null;
    final AniListAnimeListEntry? anilistEntry = canAddToAniList
        ? _findAniListEntry(ref, item)
        : null;

    final List<Widget> actions = <Widget>[
      if (canWatch)
        FilledButton.icon(
          onPressed: () =>
              context.push(AppRoutes.watchPath(item.id), extra: item),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(context.t('Watch')),
        ),
      if (mode == CatalogMode.anilist)
        FilledButton.icon(
          onPressed: canAddToAniList
              ? anilistEntry != null
                    ? () => _editAniListEntry(context, ref, anilistEntry)
                    : () => _addToAniList(
                        context,
                        ref,
                        anilistToken,
                        anilistId,
                        isManga: isAniListManga,
                      )
              : null,
          icon: Icon(
            anilistEntry != null
                ? Icons.tune_rounded
                : Icons.playlist_add_rounded,
          ),
          label: Text(
            anilistEntry != null
                ? context.t('Edit')
                : context.t('Add to Library'),
          ),
        ),
      if (mode == CatalogMode.tmdb)
        FilledButton.icon(
          onPressed: () async {
            final LocalLibraryEditResult? result = await showLocalLibraryEditor(
              context,
              item: item,
              current: libraryItem?.status,
            );
            if (result == null || !context.mounted) return;
            if (result.remove) {
              await controller.remove(item.id);
              if (context.mounted) {
                _showSnack(context, context.t('Removed from Library'));
              }
            } else {
              await controller.addToLibrary(
                item,
                status: result.status,
                progress: libraryItem?.progress ?? 0,
              );
              if (context.mounted) {
                _showSnack(context, context.t('Library updated'));
              }
            }
          },
          icon: Icon(
            inLibrary ? Icons.tune_rounded : Icons.playlist_add_rounded,
          ),
          label: Text(
            inLibrary ? context.t('Edit') : context.t('Add to Library'),
          ),
        ),
    ];

    return GlassCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth >= 980
              ? 4
              : constraints.maxWidth >= 640
              ? 3
              : constraints.maxWidth >= 430
              ? 2
              : 1;
          final double width =
              (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final Widget action in actions)
                SizedBox(width: width, height: 46, child: action),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editAniListEntry(
    BuildContext context,
    WidgetRef ref,
    AniListAnimeListEntry entry,
  ) async {
    final String scoreFormat = ref.read(aniListEffectiveScoreFormatProvider);
    final AniListEntryEditDraft? draft = await showAniListEntryEditor(
      context,
      ref: ref,
      entry: entry,
      status: entry.status,
      progress: entry.progress,
      score: entry.score,
      notes: entry.notes,
      repeat: entry.repeat,
      scoreFormat: scoreFormat,
    );
    if (draft == null || !context.mounted) return;
    if (draft.remove) {
      await deleteAniListEntry(context: context, ref: ref, entry: entry);
      return;
    }
    await saveAniListEntryEdit(
      context: context,
      ref: ref,
      entry: entry,
      draft: draft,
    );
  }

  Future<void> _addToAniList(
    BuildContext context,
    WidgetRef ref,
    String token,
    int? anilistId, {
    bool isManga = false,
  }) async {
    if (anilistId == null) return;
    try {
      final AniListApiClient client = AniListApiClient(accessToken: token);
      await client.addToList(anilistId, AniListListStatus.current);
      try {
        final AniListAnimeListEntry? entry = await client.fetchMediaListEntry(
          userId: ref.read(settingsProvider).anilistViewerId,
          mediaId: anilistId,
        );
        if (entry != null) {
          if (isManga) {
            invalidateAniListMangaLibraryProviders(ref.invalidate);
          } else {
            ref
                .read(anilistAnimeListProvider.notifier)
                .replaceEntry(mediaId: anilistId, entry: entry);
            invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
          }
        }
      } catch (_) {}
      if (context.mounted) _showSnack(context, context.t('Added to Library'));
    } catch (_) {
      await ref
          .read(anilistEditQueueProvider)
          .queueAdd(mediaId: anilistId, status: AniListListStatus.current);
      if (context.mounted) _showSnack(context, context.t('Added to Library'));
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

// ─── Seasons panel ────────────────────────────────────────────────────────────

MediaItem _seasonAsItem(MediaItem parent, MediaSeason season) {
  final String? anilistId = season.externalIds['anilist'];
  final String? anilistType = season.externalIds['anilist_type'];
  final Map<String, String> externalIds = <String, String>{
    ...parent.externalIds,
  };
  if (anilistId != null) {
    externalIds['anilist'] = anilistId;
  }
  if (anilistType != null) {
    externalIds['anilist_type'] = anilistType;
  }
  if (season.format.isNotEmpty) {
    externalIds['anilist_format'] = season.format;
  }
  if (season.relationType.isNotEmpty) {
    externalIds['anilist_relation_type'] = season.relationType;
  }
  return MediaItem(
    id: anilistId != null
        ? 'anilist:$anilistId'
        : '${parent.id}:s${season.seasonNumber}',
    title: season.name,
    originalTitle: season.originalName.isNotEmpty
        ? season.originalName
        : season.name,
    overview: season.overview.isNotEmpty ? season.overview : parent.overview,
    type: parent.type,
    year: parent.year,
    posterUrl: season.posterUrl.isNotEmpty
        ? season.posterUrl
        : parent.posterUrl,
    backdropUrl: parent.backdropUrl,
    rating: parent.rating,
    genres: parent.genres,
    sourceProvider: parent.sourceProvider,
    externalIds: externalIds,
    runtimeMinutes: parent.runtimeMinutes,
    episodeCount: season.episodeCount > 0
        ? season.episodeCount
        : parent.episodeCount,
    seasons: const <MediaSeason>[],
    statusLabel: parent.statusLabel,
    aliases: season.aliases,
    originalLanguage: parent.originalLanguage,
  );
}

final _shikimoriForDetailsProvider = Provider<ShikiMoriClient>(
  (Ref ref) => ShikiMoriClient(),
);

final _shikimoriRussianTitleProvider = FutureProvider.autoDispose
    .family<String?, int>((Ref ref, int malId) {
      return ref
          .watch(_shikimoriForDetailsProvider)
          .findRussianTitleByMalId(malId);
    });

/// Interleaves side-content (OVA/Special/Movie/SideStory/SpinOff) near the
/// main-story entry (Prequel/Sequel) whose air year is closest and prior.
List<MediaSeason> _buildWatchOrder(List<MediaSeason> all) {
  bool isMain(MediaSeason s) =>
      s.relationType == 'PREQUEL' || s.relationType == 'SEQUEL';

  final List<MediaSeason> main = all.where(isMain).toList()
    ..sort((MediaSeason a, MediaSeason b) {
      if (a.year == 0 && b.year == 0) return 0;
      if (a.year == 0) return 1;
      if (b.year == 0) return -1;
      return a.year.compareTo(b.year);
    });

  final List<MediaSeason> side =
      all.where((MediaSeason s) => !isMain(s)).toList()
        ..sort((MediaSeason a, MediaSeason b) {
          if (a.year == 0 && b.year == 0) return 0;
          if (a.year == 0) return 1;
          if (b.year == 0) return -1;
          return a.year.compareTo(b.year);
        });

  if (main.isEmpty) return side;

  final List<MediaSeason> result = <MediaSeason>[];
  int si = 0;
  for (int mi = 0; mi < main.length; mi++) {
    result.add(main[mi]);
    final int nextYear = mi + 1 < main.length && main[mi + 1].year > 0
        ? main[mi + 1].year
        : 999999;
    while (si < side.length) {
      final int sy = side[si].year;
      if (sy == 0 || sy <= nextYear) {
        result.add(side[si++]);
      } else {
        break;
      }
    }
  }
  while (si < side.length) {
    result.add(side[si++]);
  }
  return result;
}

String _seasonTypeLabel(MediaSeason s) {
  return switch (s.format.toUpperCase()) {
    'MOVIE' => 'Movie',
    'OVA' => 'OVA',
    'SPECIAL' => 'Special',
    'ONA' => 'ONA',
    'MUSIC' => 'Music',
    _ => switch (s.relationType) {
      'SIDE_STORY' => 'Side Story',
      'SPIN_OFF' => 'Spin-off',
      'PREQUEL' => 'Prequel',
      'SEQUEL' => 'Sequel',
      _ => '',
    },
  };
}

class _SeasonsPanel extends ConsumerWidget {
  const _SeasonsPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final SettingsState settings = ref.watch(settingsProvider);
    final String anilistToken = settings.anilistAccessToken.trim();
    final LocalLibraryController controller = ref.read(
      localLibraryProvider.notifier,
    );
    final List<String> libraryIds = ref
        .watch(localLibraryProvider)
        .map((LibraryItem i) => i.mediaItem.id)
        .toList(growable: false);

    final List<AniListAnimeListFolder> anilistFolders = ref
        .watch(anilistAnimeListProvider)
        .maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> d) => d,
          orElse: () => const <AniListAnimeListFolder>[],
        );
    final List<AniListAnimeListFolder> anilistPreviewFolders = ref
        .watch(anilistAnimePreviewListProvider)
        .maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> d) => d,
          orElse: () => const <AniListAnimeListFolder>[],
        );

    final bool showRussian =
        settings.metadataLocale?.languageCode == 'ru' ||
        (settings.metadataLocale == null &&
            WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
                'ru');

    final List<MediaSeason> sorted = _buildWatchOrder(
      item.seasons
          .where((MediaSeason s) => s.externalIds['anilist_type'] != 'MANGA')
          .toList(growable: false),
    );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t(
              mode == CatalogMode.anilist ? 'Watch Order' : 'Seasons',
            ),
          ),
          ...sorted.map((MediaSeason season) {
            final MediaItem seasonItem = _seasonAsItem(item, season);
            final bool inLibrary = libraryIds.contains(seasonItem.id);
            final String? alIdStr = seasonItem.externalIds['anilist'];
            final int? alId = alIdStr != null ? int.tryParse(alIdStr) : null;
            final bool canUseAniList =
                mode == CatalogMode.anilist &&
                anilistToken.isNotEmpty &&
                alId != null;

            AniListAnimeListEntry? anilistEntry;
            if (canUseAniList) {
              outer:
              for (final AniListAnimeListFolder folder in anilistFolders) {
                for (final AniListAnimeListEntry entry in folder.entries) {
                  if (entryAniListId(entry) == alId) {
                    anilistEntry = entry;
                    break outer;
                  }
                }
              }
              if (anilistEntry == null) {
                outerPreview:
                for (final AniListAnimeListFolder folder
                    in anilistPreviewFolders) {
                  for (final AniListAnimeListEntry entry in folder.entries) {
                    if (entryAniListId(entry) == alId) {
                      anilistEntry = entry;
                      break outerPreview;
                    }
                  }
                }
              }
            }

            Future<void> openAniListDialog() async {
              final AniListAnimeListEntry entry =
                  anilistEntry ??
                  AniListAnimeListEntry(
                    id: 0,
                    status: AniListListStatus.planning,
                    progress: 0,
                    mediaItem: seasonItem,
                  );
              final String scoreFormat = ref.read(
                aniListEffectiveScoreFormatProvider,
              );
              final AniListEntryEditDraft? draft = await showAniListEntryEditor(
                context,
                ref: ref,
                entry: entry,
                status: entry.status,
                progress: entry.progress,
                score: entry.score,
                notes: entry.notes,
                repeat: entry.repeat,
                scoreFormat: scoreFormat,
              );
              if (draft == null || !context.mounted) return;
              if (draft.remove && anilistEntry != null) {
                await deleteAniListEntry(
                  context: context,
                  ref: ref,
                  entry: anilistEntry,
                );
                return;
              }
              await saveAniListEntryEdit(
                context: context,
                ref: ref,
                entry: entry,
                draft: draft,
              );
            }

            return _SeasonTile(
              season: season,
              seasonItem: seasonItem,
              inLibrary: inLibrary,
              useAniList: canUseAniList,
              showRussian: showRussian,
              anilistEntry: anilistEntry,
              onTap: () => context.push(
                AppRoutes.mediaDetailsPath(seasonItem.id),
                extra: seasonItem,
              ),
              onWatch: () => context.push(
                AppRoutes.watchPath(seasonItem.id),
                extra: seasonItem,
              ),
              onAniListOpen: openAniListDialog,
              onLocalAdd: () async {
                await controller.addToLibrary(seasonItem);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t('Added to Library'))),
                  );
                }
              },
            );
          }),
        ],
      ),
    );
  }
}

class _SeasonTile extends ConsumerWidget {
  const _SeasonTile({
    required this.season,
    required this.seasonItem,
    required this.inLibrary,
    required this.useAniList,
    required this.showRussian,
    required this.onTap,
    required this.onWatch,
    required this.onAniListOpen,
    required this.onLocalAdd,
    this.anilistEntry,
  });

  final MediaSeason season;
  final MediaItem seasonItem;
  final bool inLibrary;
  final bool useAniList;
  final bool showRussian;
  final AniListAnimeListEntry? anilistEntry;
  final VoidCallback onTap;
  final VoidCallback onWatch;
  final Future<void> Function() onAniListOpen;
  final Future<void> Function() onLocalAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme tt = Theme.of(context).textTheme;

    final String? malIdStr = season.externalIds['mal'];
    final int malId = malIdStr != null ? (int.tryParse(malIdStr) ?? 0) : 0;
    final String? russianTitle = (showRussian && malId > 0)
        ? ref
              .watch(_shikimoriRussianTitleProvider(malId))
              .maybeWhen(data: (String? v) => v, orElse: () => null)
        : null;

    final String displayTitle = russianTitle?.isNotEmpty == true
        ? russianTitle!
        : season.name;
    final String typeLabel = _seasonTypeLabel(season);
    final String yearLabel = season.year > 0 ? '${season.year}' : '';
    final String ratingLabel = season.rating > 0
        ? season.rating.toStringAsFixed(1)
        : '';
    final String epLabel = season.episodeCount > 0
        ? '${season.episodeCount} ep.'
        : '';

    final List<String> subtitleParts = <String>[
      if (typeLabel.isNotEmpty) typeLabel,
      if (yearLabel.isNotEmpty) yearLabel,
      if (ratingLabel.isNotEmpty) '★ $ratingLabel',
      if (epLabel.isNotEmpty) epLabel,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        onLongPress: useAniList ? onAniListOpen : null,
        borderRadius: AppRadius.all(AppRadius.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (season.posterUrl.isNotEmpty)
              ClipRRect(
                borderRadius: AppRadius.all(AppRadius.sm),
                child: CachedNetworkImage(
                  imageUrl: season.posterUrl,
                  width: 48,
                  height: 68,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _PosterFallback(season.name),
                ),
              )
            else
              _PosterFallback(season.name, width: 48, height: 68),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayTitle,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' · '),
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: onWatch,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(56, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 16),
            ),
            const SizedBox(width: AppSpacing.xs),
            OutlinedButton(
              onPressed: useAniList ? onAniListOpen : onLocalAdd,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(56, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Icon(
                useAniList
                    ? Icons.tune_rounded
                    : inLibrary
                    ? Icons.library_add_check_rounded
                    : Icons.playlist_add_rounded,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback(this.title, {this.width = 48, this.height = 68});

  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.all(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
