import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/platform/tv_platform.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/include_exclude_filter_chip.dart';
import '../../../core/widgets/media_poster_card.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/tv_directional_focus.dart';
import '../../../core/widgets/tv_text_field_focus.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../catalog/application/catalog_repository.dart';
import '../../catalog/presentation/catalog_offline_banner.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/data/tmdb_metadata_provider.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../profile/application/anilist_profile_provider.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/presentation/anilist_entry_editor.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';

enum _AniListDiscoveryKind {
  anime('Anime', 'anime'),
  manga('Manga', 'manga');

  const _AniListDiscoveryKind(this.label, this.key);
  final String label;
  final String key;
}

const List<_AniListDiscoveryKind> _kVisibleAniListDiscoveryKinds =
    <_AniListDiscoveryKind>[
      _AniListDiscoveryKind.anime,
      _AniListDiscoveryKind.manga,
    ];

class _AniListDiscoveryFilter {
  const _AniListDiscoveryFilter({
    this.formatIn = const <String>[],
    this.formatNotIn = const <String>[],
    this.statusIn = const <String>[],
    this.statusNotIn = const <String>[],
    this.sourceIn = const <String>[],
    this.sourceNotIn = const <String>[],
    this.season,
    this.yearFrom,
    this.yearTo,
    this.countryOfOrigin,
    this.genreIn = const <String>[],
    this.genreNotIn = const <String>[],
    this.tagIn = const <String>[],
    this.tagNotIn = const <String>[],
    this.isAdult,
    this.isLicensed,
    this.onList,
  });

  final List<String> formatIn;
  final List<String> formatNotIn;
  final List<String> statusIn;
  final List<String> statusNotIn;
  final List<String> sourceIn;
  final List<String> sourceNotIn;
  final String? season;
  final int? yearFrom;
  final int? yearTo;
  final String? countryOfOrigin;
  final List<String> genreIn;
  final List<String> genreNotIn;
  final List<String> tagIn;
  final List<String> tagNotIn;
  final bool? isAdult;
  final bool? isLicensed;
  final bool? onList;

  bool get hasAnyFilter =>
      formatIn.isNotEmpty ||
      formatNotIn.isNotEmpty ||
      statusIn.isNotEmpty ||
      statusNotIn.isNotEmpty ||
      sourceIn.isNotEmpty ||
      sourceNotIn.isNotEmpty ||
      season != null ||
      yearFrom != null ||
      yearTo != null ||
      countryOfOrigin != null ||
      genreIn.isNotEmpty ||
      genreNotIn.isNotEmpty ||
      tagIn.isNotEmpty ||
      tagNotIn.isNotEmpty ||
      isAdult != null ||
      isLicensed != null ||
      onList != null;

  _AniListDiscoveryFilter copyWith({
    List<String>? formatIn,
    List<String>? formatNotIn,
    List<String>? statusIn,
    List<String>? statusNotIn,
    List<String>? sourceIn,
    List<String>? sourceNotIn,
    Object? season = _sentinel,
    Object? yearFrom = _sentinel,
    Object? yearTo = _sentinel,
    Object? countryOfOrigin = _sentinel,
    List<String>? genreIn,
    List<String>? genreNotIn,
    List<String>? tagIn,
    List<String>? tagNotIn,
    Object? isAdult = _sentinel,
    Object? isLicensed = _sentinel,
    Object? onList = _sentinel,
  }) {
    return _AniListDiscoveryFilter(
      formatIn: formatIn ?? this.formatIn,
      formatNotIn: formatNotIn ?? this.formatNotIn,
      statusIn: statusIn ?? this.statusIn,
      statusNotIn: statusNotIn ?? this.statusNotIn,
      sourceIn: sourceIn ?? this.sourceIn,
      sourceNotIn: sourceNotIn ?? this.sourceNotIn,
      season: season == _sentinel ? this.season : season as String?,
      yearFrom: yearFrom == _sentinel ? this.yearFrom : yearFrom as int?,
      yearTo: yearTo == _sentinel ? this.yearTo : yearTo as int?,
      countryOfOrigin: countryOfOrigin == _sentinel
          ? this.countryOfOrigin
          : countryOfOrigin as String?,
      genreIn: genreIn ?? this.genreIn,
      genreNotIn: genreNotIn ?? this.genreNotIn,
      tagIn: tagIn ?? this.tagIn,
      tagNotIn: tagNotIn ?? this.tagNotIn,
      isAdult: isAdult == _sentinel ? this.isAdult : isAdult as bool?,
      isLicensed: isLicensed == _sentinel
          ? this.isLicensed
          : isLicensed as bool?,
      onList: onList == _sentinel ? this.onList : onList as bool?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _AniListDiscoveryFilter &&
      _listEq(other.formatIn, formatIn) &&
      _listEq(other.formatNotIn, formatNotIn) &&
      _listEq(other.statusIn, statusIn) &&
      _listEq(other.statusNotIn, statusNotIn) &&
      _listEq(other.sourceIn, sourceIn) &&
      _listEq(other.sourceNotIn, sourceNotIn) &&
      other.season == season &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.countryOfOrigin == countryOfOrigin &&
      _listEq(other.genreIn, genreIn) &&
      _listEq(other.genreNotIn, genreNotIn) &&
      _listEq(other.tagIn, tagIn) &&
      _listEq(other.tagNotIn, tagNotIn) &&
      other.isAdult == isAdult &&
      other.isLicensed == isLicensed &&
      other.onList == onList;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    Object.hashAll(formatIn),
    Object.hashAll(formatNotIn),
    Object.hashAll(statusIn),
    Object.hashAll(statusNotIn),
    Object.hashAll(sourceIn),
    Object.hashAll(sourceNotIn),
    season,
    yearFrom,
    yearTo,
    countryOfOrigin,
    Object.hashAll(genreIn),
    Object.hashAll(genreNotIn),
    Object.hashAll(tagIn),
    Object.hashAll(tagNotIn),
    isAdult,
    isLicensed,
    onList,
  ]);

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

const Object _sentinel = Object();

class _TmdbDiscoveryFilter {
  const _TmdbDiscoveryFilter({
    this.genreIds = const <int>[],
    this.genreNotIds = const <int>[],
    this.yearFrom,
    this.yearTo,
    this.minRating,
    this.originalLanguage,
    this.includeAdult,
  });

  final List<int> genreIds;
  final List<int> genreNotIds;
  final int? yearFrom;
  final int? yearTo;
  final double? minRating;
  final String? originalLanguage;
  final bool? includeAdult;

  bool get hasAnyFilter =>
      genreIds.isNotEmpty ||
      genreNotIds.isNotEmpty ||
      yearFrom != null ||
      yearTo != null ||
      minRating != null ||
      originalLanguage != null ||
      includeAdult != null;

  _TmdbDiscoveryFilter copyWith({
    List<int>? genreIds,
    List<int>? genreNotIds,
    Object? yearFrom = _sentinel,
    Object? yearTo = _sentinel,
    Object? minRating = _sentinel,
    Object? originalLanguage = _sentinel,
    Object? includeAdult = _sentinel,
  }) {
    return _TmdbDiscoveryFilter(
      genreIds: genreIds ?? this.genreIds,
      genreNotIds: genreNotIds ?? this.genreNotIds,
      yearFrom: yearFrom == _sentinel ? this.yearFrom : yearFrom as int?,
      yearTo: yearTo == _sentinel ? this.yearTo : yearTo as int?,
      minRating: minRating == _sentinel ? this.minRating : minRating as double?,
      originalLanguage: originalLanguage == _sentinel
          ? this.originalLanguage
          : originalLanguage as String?,
      includeAdult: includeAdult == _sentinel
          ? this.includeAdult
          : includeAdult as bool?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _TmdbDiscoveryFilter &&
      _intListEq(other.genreIds, genreIds) &&
      _intListEq(other.genreNotIds, genreNotIds) &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.minRating == minRating &&
      other.originalLanguage == originalLanguage &&
      other.includeAdult == includeAdult;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    Object.hashAll(genreIds),
    Object.hashAll(genreNotIds),
    yearFrom,
    yearTo,
    minRating,
    originalLanguage,
    includeAdult,
  ]);

  static bool _intListEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class DiscoveryPage extends ConsumerStatefulWidget {
  const DiscoveryPage({
    this.initialType,
    this.initialFilter,
    this.initialAniListKind,
    super.key,
  });

  final MediaType? initialType;
  final String? initialFilter;
  final String? initialAniListKind;

  @override
  ConsumerState<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends ConsumerState<DiscoveryPage> {
  late final ScrollController _scrollController;
  Timer? _searchDebounce;
  MediaType? _selectedType;
  _AniListDiscoveryKind _selectedAniListKind = _AniListDiscoveryKind.anime;
  String _query = '';
  String _filter = 'Trending';
  final List<MediaItem> _items = <MediaItem>[];
  int _page = 0;
  bool _loadingInitial = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _settingsSignature;
  int _requestSerial = 0;

  _AniListDiscoveryFilter _advancedFilter = const _AniListDiscoveryFilter();
  List<String> _cachedGenres = <String>[];
  List<AniListMediaTagInfo> _cachedTags = <AniListMediaTagInfo>[];
  _TmdbDiscoveryFilter _tmdbAdvancedFilter = const _TmdbDiscoveryFilter();

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _selectedAniListKind = _aniListKindFromKey(widget.initialAniListKind);
    final String initialFilter = widget.initialFilter?.trim() ?? '';
    _filter = initialFilter.isEmpty
        ? _defaultFilterForKind(_selectedAniListKind)
        : initialFilter;
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingInitial || _loadingMore) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 900) {
      unawaited(_loadMore());
    }
  }

  String _settingsKey(SettingsState settings, CatalogMode mode) {
    return Object.hash(
      mode,
      settings.effectiveTmdbReadAccessToken,
      settings.effectiveTmdbLanguage,
      settings.anilistAccessToken,
      settings.anilistViewerId,
    ).toString();
  }

  List<MediaItem> _visibleItems() => List<MediaItem>.of(_items);

  void _setQuery(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 360),
      () => unawaited(_reload()),
    );
  }

  void _setType(MediaType? type) {
    if (_selectedType == type) return;
    setState(() {
      _selectedType = type;
      _tmdbAdvancedFilter = const _TmdbDiscoveryFilter();
    });
    unawaited(_reload());
  }

  void _setAniListKind(_AniListDiscoveryKind kind) {
    if (_selectedAniListKind == kind) return;
    setState(() {
      _selectedAniListKind = kind;
      _filter = _defaultFilterForKind(kind);
      _advancedFilter = const _AniListDiscoveryFilter();
    });
    unawaited(_reload());
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    unawaited(_reload());
  }

  void _clearAdvancedFilter() {
    setState(() => _advancedFilter = const _AniListDiscoveryFilter());
    unawaited(_reload());
  }

  void _clearTmdbAdvancedFilter() {
    setState(() => _tmdbAdvancedFilter = const _TmdbDiscoveryFilter());
    unawaited(_reload());
  }

  Future<void> _openTmdbFilterSheet() async {
    if (!mounted) return;
    final _TmdbDiscoveryFilter? result =
        await showModalBottomSheet<_TmdbDiscoveryFilter>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) => _TmdbDiscoveryFilterSheet(
            initial: _tmdbAdvancedFilter,
            selectedType: _selectedType,
          ),
        );
    if (result != null && mounted) {
      setState(() => _tmdbAdvancedFilter = result);
      unawaited(_reload());
    }
  }

  Future<void> _openFilterSheet() async {
    if (_cachedGenres.isEmpty || _cachedTags.isEmpty) {
      try {
        final client = ref.read(aniListProfileClientProvider);
        _cachedGenres = await client.fetchGenres();
        _cachedTags = await client.fetchMediaTags();
      } catch (_) {
        _cachedGenres = const <String>[];
        _cachedTags = const <AniListMediaTagInfo>[];
      }
    }
    if (!mounted) return;

    final _AniListDiscoveryFilter? result =
        await showModalBottomSheet<_AniListDiscoveryFilter>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (BuildContext context) => _DiscoveryAdvancedFilterSheet(
            initial: _advancedFilter,
            genres: _cachedGenres,
            tags: _cachedTags,
            kind: _selectedAniListKind,
          ),
        );

    if (result != null && mounted) {
      setState(() => _advancedFilter = result);
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final int requestId = ++_requestSerial;
    setState(() {
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
      _error = null;
      _page = 0;
      _items.clear();
    });
    final List<MediaItem> firstPage = await _fetchPage(1);
    if (!mounted || requestId != _requestSerial) return;
    setState(() {
      _items
        ..clear()
        ..addAll(_dedupe(firstPage));
      _page = firstPage.isEmpty ? 0 : 1;
      _hasMore = firstPage.isNotEmpty;
      _loadingInitial = false;
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loadingInitial) return;
    final int requestId = _requestSerial;
    setState(() => _loadingMore = true);
    final int nextPage = _page + 1;
    final List<MediaItem> nextItems = await _fetchPage(nextPage);
    if (!mounted || requestId != _requestSerial) return;
    setState(() {
      final List<MediaItem> merged = _dedupe(<MediaItem>[
        ..._items,
        ...nextItems,
      ]);
      _items
        ..clear()
        ..addAll(merged);
      _page = nextItems.isEmpty ? _page : nextPage;
      _hasMore = nextItems.isNotEmpty;
      _loadingMore = false;
    });
  }

  Future<List<MediaItem>> _fetchPage(int page) async {
    try {
      final String search = _query.trim();
      final CatalogMode mode = ref.read(catalogModeProvider);

      if (mode == CatalogMode.tmdb &&
          _tmdbAdvancedFilter.hasAnyFilter &&
          search.isEmpty) {
        final TmdbMetadataProvider? tmdb = ref.read(tmdbProviderProvider);
        if (tmdb == null) return const <MediaItem>[];
        return tmdb.discoverPageAdvanced(
          filter: _filter,
          type: _selectedType,
          page: page,
          genreIds: _tmdbAdvancedFilter.genreIds.isEmpty
              ? null
              : _tmdbAdvancedFilter.genreIds,
          withoutGenreIds: _tmdbAdvancedFilter.genreNotIds.isEmpty
              ? null
              : _tmdbAdvancedFilter.genreNotIds,
          yearFrom: _tmdbAdvancedFilter.yearFrom,
          yearTo: _tmdbAdvancedFilter.yearTo,
          minRating: _tmdbAdvancedFilter.minRating,
          originalLanguage: _tmdbAdvancedFilter.originalLanguage,
          includeAdult: _tmdbAdvancedFilter.includeAdult,
        );
      }

      if (mode == CatalogMode.anilist &&
          _advancedFilter.hasAnyFilter &&
          search.isEmpty) {
        final String type = _selectedAniListKind == _AniListDiscoveryKind.manga
            ? 'MANGA'
            : 'ANIME';
        final List<String> sourceIn = _effectiveAniListSourceIn(
          _advancedFilter,
        );
        if (_aniListSourceFilterHasNoMatches(_advancedFilter)) {
          return const <MediaItem>[];
        }
        return ref
            .read(aniListProfileClientProvider)
            .getAdvancedFilteredCatalog(
              type: type,
              sort: _sortStringForFilter(_filter),
              formatIn: _advancedFilter.formatIn.isEmpty
                  ? null
                  : _advancedFilter.formatIn,
              formatNotIn: _advancedFilter.formatNotIn.isEmpty
                  ? null
                  : _advancedFilter.formatNotIn,
              statusIn: _advancedFilter.statusIn.isEmpty
                  ? null
                  : _advancedFilter.statusIn,
              statusNotIn: _advancedFilter.statusNotIn.isEmpty
                  ? null
                  : _advancedFilter.statusNotIn,
              sourceIn: sourceIn.isEmpty ? null : sourceIn,
              season: _advancedFilter.season,
              startDateGreater: _advancedFilter.yearFrom != null
                  ? int.parse('${_advancedFilter.yearFrom}0101')
                  : null,
              startDateLesser: _advancedFilter.yearTo != null
                  ? int.parse('${_advancedFilter.yearTo}1231')
                  : null,
              countryOfOrigin: _advancedFilter.countryOfOrigin,
              genreIn: _advancedFilter.genreIn.isEmpty
                  ? null
                  : _advancedFilter.genreIn,
              genreNotIn: _advancedFilter.genreNotIn.isEmpty
                  ? null
                  : _advancedFilter.genreNotIn,
              tagIn: _advancedFilter.tagIn.isEmpty
                  ? null
                  : _advancedFilter.tagIn,
              tagNotIn: _advancedFilter.tagNotIn.isEmpty
                  ? null
                  : _advancedFilter.tagNotIn,
              isAdult: _advancedFilter.isAdult,
              isLicensed: _advancedFilter.isLicensed,
              onList: _advancedFilter.onList,
              page: page,
            );
      }

      final CatalogRepository? repository = ref.read(
        activeCatalogRepositoryProvider,
      );
      if (repository == null) return const <MediaItem>[];
      return repository.discover(
        search: search,
        filter: _filter,
        type: mode == CatalogMode.tmdb ? _selectedType : null,
        page: page,
        anilistKind: mode == CatalogMode.anilist
            ? _selectedAniListKind.key
            : null,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
      return <MediaItem>[];
    }
  }

  static String _sortStringForFilter(String filter) {
    return switch (filter.trim().toLowerCase()) {
      'trending' => 'TRENDING_DESC',
      'popular' => 'POPULARITY_DESC',
      'top rated' => 'SCORE_DESC',
      'favorites' => 'FAVOURITES_DESC',
      'newest' => 'START_DATE_DESC',
      'airing' => 'TRENDING_DESC',
      'upcoming' => 'START_DATE',
      'finished' => 'POPULARITY_DESC',
      'recently updated' => 'UPDATED_AT_DESC',
      _ => 'POPULARITY_DESC',
    };
  }

  static _AniListDiscoveryKind _aniListKindFromKey(String? key) {
    for (final _AniListDiscoveryKind kind in _AniListDiscoveryKind.values) {
      if (kind.key == key) {
        return kind;
      }
    }
    return _AniListDiscoveryKind.anime;
  }

  static String _defaultFilterForKind(_AniListDiscoveryKind kind) {
    return kind == _AniListDiscoveryKind.manga ? 'Popular' : 'Trending';
  }

  List<MediaItem> _dedupe(List<MediaItem> items) {
    final Map<String, MediaItem> byId = <String, MediaItem>{};
    for (final MediaItem item in items) {
      byId.putIfAbsent(item.id, () => item);
    }
    return byId.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = ref.watch(settingsProvider);
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final String settingsKey = _settingsKey(settings, mode);
    if (_settingsSignature != settingsKey) {
      _settingsSignature = settingsKey;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
    final List<MediaItem> items = _visibleItems();
    final AsyncValue<List<AniListAnimeListFolder>> badgeFoldersAsync =
        mode == CatalogMode.anilist
        ? (_selectedAniListKind == _AniListDiscoveryKind.manga
              ? ref.watch(anilistMangaListProvider)
              : ref.watch(anilistAnimeListProvider))
        : const AsyncValue<List<AniListAnimeListFolder>>.data(
            <AniListAnimeListFolder>[],
          );
    final Map<String, String> statusBadges = mode == CatalogMode.anilist
        ? _anilistStatusBadges(
            badgeFoldersAsync.maybeWhen(
              skipLoadingOnReload: true,
              data: (List<AniListAnimeListFolder> folders) => folders,
              orElse: () => const <AniListAnimeListFolder>[],
            ),
            context,
          )
        : const <String, String>{};
    final Map<String, AniListAnimeListEntry> anilistEntryMap =
        mode == CatalogMode.anilist
        ? _anilistEntryMap(
            badgeFoldersAsync.maybeWhen(
              skipLoadingOnReload: true,
              data: (List<AniListAnimeListFolder> folders) => folders,
              orElse: () => const <AniListAnimeListFolder>[],
            ),
          )
        : const <String, AniListAnimeListEntry>{};
    final Widget page = AdaptivePage(
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CatalogOfflineBanner(),
            SectionHeader(
              title: context.t('Discovery'),
              subtitle: context.t('Search media, genres, people, moods'),
            ),
            const SizedBox(height: AppSpacing.md),
            GlassCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TvTextFieldFocus(
                    releaseHorizontal: true,
                    child: TextField(
                      onChanged: _setQuery,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.t(
                          'Search media, genres, people, moods',
                        ),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _TypeTabs(
                    mode: mode,
                    selectedType: _selectedType,
                    selectedAniListKind: _selectedAniListKind,
                    onTypeChanged: _setType,
                    onAniListKindChanged: _setAniListKind,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FilterBar(
                    mode: mode,
                    selected: _filter,
                    onSelected: _setFilter,
                  ),
                  if (mode == CatalogMode.anilist) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (_advancedFilter.hasAnyFilter)
                          TextButton.icon(
                            onPressed: _clearAdvancedFilter,
                            icon: const Icon(
                              Icons.filter_list_off_rounded,
                              size: 18,
                            ),
                            label: Text(context.t('Clear filters')),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _openFilterSheet,
                          icon: Icon(
                            _advancedFilter.hasAnyFilter
                                ? Icons.filter_alt_rounded
                                : Icons.filter_alt_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _advancedFilter.hasAnyFilter
                                ? context.t('Filters (active)')
                                : context.t('Filters'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (mode == CatalogMode.tmdb) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (_tmdbAdvancedFilter.hasAnyFilter)
                          TextButton.icon(
                            onPressed: _clearTmdbAdvancedFilter,
                            icon: const Icon(
                              Icons.filter_list_off_rounded,
                              size: 18,
                            ),
                            label: Text(context.t('Clear filters')),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _openTmdbFilterSheet,
                          icon: Icon(
                            _tmdbAdvancedFilter.hasAnyFilter
                                ? Icons.filter_alt_rounded
                                : Icons.filter_alt_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _tmdbAdvancedFilter.hasAnyFilter
                                ? context.t('Filters (active)')
                                : context.t('Filters'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_loadingInitial)
              const _DiscoverySkeletonGrid()
            else if (_error != null && items.isEmpty)
              NeutralPlaceholder(
                icon: Icons.cloud_off_rounded,
                title: context.t('Discovery is offline'),
                message: _error!,
                height: 320,
              )
            else if (items.isEmpty)
              NeutralPlaceholder(
                icon: Icons.manage_search_rounded,
                title: context.t('No Results Yet'),
                message: context.t(
                  'Configure a metadata source in Settings to browse content.',
                ),
                height: 320,
              )
            else ...<Widget>[
              ResponsiveGrid(
                itemCount: items.length,
                maxColumns: 6,
                itemBuilder: (BuildContext context, int index) {
                  final MediaItem item = items[index];
                  final AniListAnimeListEntry? entry = anilistEntryMap[item.id];
                  final VoidCallback? editAniListEntry =
                      mode == CatalogMode.anilist
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
                    statusBadgeLabel: statusBadges[item.id],
                    onTap: () => context.push(
                      AppRoutes.mediaDetailsPath(item.id),
                      extra: item,
                    ),
                    onLongPress: editAniListEntry,
                    onSecondaryTap: editAniListEntry,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              _DiscoveryFooter(
                loadingMore: _loadingMore,
                hasMore: _hasMore,
                onLoadMore: _loadMore,
              ),
            ],
          ],
        ),
      ),
    );
    return TvPlatform.isAndroidTv ? TvDirectionalFocus(child: page) : page;
  }
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

List<String> _effectiveAniListSourceIn(_AniListDiscoveryFilter filter) {
  final Set<String> included = filter.sourceIn.toSet();
  final Set<String> excluded = filter.sourceNotIn.toSet();
  if (included.isEmpty && excluded.isEmpty) return const <String>[];
  final Set<String> sourceValues = included.isEmpty
      ? _DiscoveryAdvancedFilterSheetState._sources
            .map((source) => source.value)
            .toSet()
      : included;
  sourceValues.removeAll(excluded);
  return sourceValues.toList()..sort();
}

bool _aniListSourceFilterHasNoMatches(_AniListDiscoveryFilter filter) {
  if (filter.sourceIn.isEmpty && filter.sourceNotIn.isEmpty) return false;
  return _effectiveAniListSourceIn(filter).isEmpty;
}

String _displayTagCategory(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Other';
  final List<String> parts = trimmed
      .split('-')
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? trimmed : parts.last;
}

class _DiscoveryFooter extends StatelessWidget {
  const _DiscoveryFooter({
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: loadingMore
            ? const SizedBox(
                key: ValueKey<String>('loading-more'),
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : hasMore
            ? OutlinedButton.icon(
                key: const ValueKey<String>('load-more'),
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(context.t('Load more')),
              )
            : Text(
                key: const ValueKey<String>('end'),
                context.t('All caught up'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
      ),
    );
  }
}

class _TypeTabs extends StatelessWidget {
  const _TypeTabs({
    required this.mode,
    required this.selectedType,
    required this.selectedAniListKind,
    required this.onTypeChanged,
    required this.onAniListKindChanged,
  });

  final CatalogMode mode;
  final MediaType? selectedType;
  final _AniListDiscoveryKind selectedAniListKind;
  final ValueChanged<MediaType?> onTypeChanged;
  final ValueChanged<_AniListDiscoveryKind> onAniListKindChanged;

  @override
  Widget build(BuildContext context) {
    if (mode == CatalogMode.anilist) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: _kVisibleAniListDiscoveryKinds
            .map(
              (_AniListDiscoveryKind kind) => ChoiceChip(
                label: Text(context.t(kind.label)),
                selected: selectedAniListKind == kind,
                onSelected: (_) => onAniListKindChanged(kind),
              ),
            )
            .toList(),
      );
    }

    final List<({String label, MediaType? type})> tabs =
        <({String label, MediaType? type})>[
          (label: 'All', type: null),
          (label: 'Movies', type: MediaType.movie),
          (label: 'Series', type: MediaType.series),
          (label: 'Anime', type: MediaType.anime),
        ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: tabs
          .map(
            (({String label, MediaType? type}) tab) => ChoiceChip(
              label: Text(context.t(tab.label)),
              selected: selectedType == tab.type,
              onSelected: (_) => onTypeChanged(tab.type),
            ),
          )
          .toList(),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.mode,
    required this.selected,
    required this.onSelected,
  });

  final CatalogMode mode;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<String> filters = mode == CatalogMode.anilist
        ? _anilistFilters()
        : const <String>[
            'Trending',
            'Popular',
            'Top Rated',
            'New Releases',
            'Coming Soon',
          ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: filters
          .map(
            (String filter) => FilterChip(
              label: Text(context.t(filter)),
              selected: selected == filter,
              onSelected: (_) => onSelected(filter),
            ),
          )
          .toList(),
    );
  }

  List<String> _anilistFilters() {
    return const <String>[
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
  }
}

class _DiscoverySkeletonGrid extends StatelessWidget {
  const _DiscoverySkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      itemCount: 8,
      maxColumns: 6,
      itemBuilder: (BuildContext context, int index) =>
          const SkeletonBox(radius: 18),
    );
  }
}

// ── Advanced filter sheet ────────────────────────────────────────────────────

class _DiscoveryAdvancedFilterSheet extends StatefulWidget {
  const _DiscoveryAdvancedFilterSheet({
    required this.initial,
    required this.genres,
    required this.tags,
    required this.kind,
  });

  final _AniListDiscoveryFilter initial;
  final List<String> genres;
  final List<AniListMediaTagInfo> tags;
  final _AniListDiscoveryKind kind;

  @override
  State<_DiscoveryAdvancedFilterSheet> createState() =>
      _DiscoveryAdvancedFilterSheetState();
}

class _DiscoveryAdvancedFilterSheetState
    extends State<_DiscoveryAdvancedFilterSheet> {
  late _AniListDiscoveryFilter _draft;
  final TextEditingController _tagSearch = TextEditingController();

  static const List<({String value, String label})> _animeFormats =
      <({String value, String label})>[
        (value: 'TV', label: 'TV'),
        (value: 'MOVIE', label: 'Movie'),
        (value: 'TV_SHORT', label: 'TV Short'),
        (value: 'OVA', label: 'OVA'),
        (value: 'ONA', label: 'ONA'),
        (value: 'SPECIAL', label: 'Special'),
        (value: 'MUSIC', label: 'Music'),
      ];

  static const List<({String value, String label})> _mangaFormats =
      <({String value, String label})>[
        (value: 'MANGA', label: 'Manga'),
        (value: 'ONE_SHOT', label: 'One Shot'),
        (value: 'NOVEL', label: 'Novel'),
      ];

  static const List<({String value, String label})> _statuses =
      <({String value, String label})>[
        (value: 'RELEASING', label: 'Releasing'),
        (value: 'FINISHED', label: 'Finished'),
        (value: 'NOT_YET_RELEASED', label: 'Not Yet Released'),
        (value: 'CANCELLED', label: 'Cancelled'),
        (value: 'HIATUS', label: 'Hiatus'),
      ];

  static const List<({String value, String label})> _sources =
      <({String value, String label})>[
        (value: 'ORIGINAL', label: 'Original'),
        (value: 'ANIME', label: 'Anime'),
        (value: 'MANGA', label: 'Manga'),
        (value: 'LIGHT_NOVEL', label: 'Light Novel'),
        (value: 'NOVEL', label: 'Novel'),
        (value: 'WEB_NOVEL', label: 'Web Novel'),
        (value: 'VISUAL_NOVEL', label: 'Visual Novel'),
        (value: 'VIDEO_GAME', label: 'Video Game'),
        (value: 'GAME', label: 'Game'),
        (value: 'COMIC', label: 'Comic'),
        (value: 'DOUJINSHI', label: 'Doujinshi'),
        (value: 'LIVE_ACTION', label: 'Live Action'),
        (value: 'MULTIMEDIA_PROJECT', label: 'Multimedia Project'),
        (value: 'PICTURE_BOOK', label: 'Picture Book'),
        (value: 'OTHER', label: 'Other'),
      ];

  static const List<({String value, String label})> _seasons =
      <({String value, String label})>[
        (value: 'WINTER', label: 'Winter'),
        (value: 'SPRING', label: 'Spring'),
        (value: 'SUMMER', label: 'Summer'),
        (value: 'FALL', label: 'Fall'),
      ];

  static const List<({String value, String label})> _countries =
      <({String value, String label})>[
        (value: 'JP', label: 'Japan'),
        (value: 'CN', label: 'China'),
        (value: 'KR', label: 'Korea'),
        (value: 'TW', label: 'Taiwan'),
      ];

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  @override
  void dispose() {
    _tagSearch.dispose();
    super.dispose();
  }

  IncludeExcludeState _boolState(bool? value) {
    return switch (value) {
      true => IncludeExcludeState.included,
      false => IncludeExcludeState.excluded,
      null => IncludeExcludeState.neutral,
    };
  }

  Map<String, List<AniListMediaTagInfo>> _tagsByCategory() {
    final String query = _tagSearch.text.trim().toLowerCase();
    final Set<String> selectedTags = <String>{
      ..._draft.tagIn,
      ..._draft.tagNotIn,
    };
    final List<AniListMediaTagInfo> tags = widget.tags
        .where((AniListMediaTagInfo tag) {
          if (selectedTags.contains(tag.name)) return true;
          if (query.isEmpty) return true;
          return tag.name.toLowerCase().contains(query) ||
              tag.category.toLowerCase().contains(query) ||
              _displayTagCategory(tag.category).toLowerCase().contains(query);
        })
        .toList(growable: false);
    final Map<String, List<AniListMediaTagInfo>> grouped =
        <String, List<AniListMediaTagInfo>>{};
    for (final AniListMediaTagInfo tag in tags) {
      final String category = tag.category.trim().isEmpty
          ? 'Other'
          : tag.category.trim();
      grouped.putIfAbsent(category, () => <AniListMediaTagInfo>[]).add(tag);
    }
    for (final List<AniListMediaTagInfo> group in grouped.values) {
      group.sort(
        (AniListMediaTagInfo a, AniListMediaTagInfo b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return Map<String, List<AniListMediaTagInfo>>.fromEntries(
      grouped.entries.toList()..sort(
        (
          MapEntry<String, List<AniListMediaTagInfo>> a,
          MapEntry<String, List<AniListMediaTagInfo>> b,
        ) => _displayTagCategory(
          a.key,
        ).toLowerCase().compareTo(_displayTagCategory(b.key).toLowerCase()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAnime = widget.kind == _AniListDiscoveryKind.anime;
    final List<({String value, String label})> formats = isAnime
        ? _animeFormats
        : _mangaFormats;
    final int currentYear = DateTime.now().year;
    final List<int?> years = <int?>[
      null,
      ...List<int>.generate(
        currentYear + 2 - 1960 + 1,
        (int i) => currentYear + 2 - i,
      ),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: <Widget>[
            // Format
            _FilterSectionHeader(context.t('Format')),
            _IncludeExcludeChips<String>(
              options: formats,
              included: _draft.formatIn.toSet(),
              excluded: _draft.formatNotIn.toSet(),
              onChanged: (Set<String> included, Set<String> excluded) {
                setState(() {
                  _draft = _draft.copyWith(
                    formatIn: included.toList()..sort(),
                    formatNotIn: excluded.toList()..sort(),
                  );
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Status
            _FilterSectionHeader(context.t('Status')),
            _IncludeExcludeChips<String>(
              options: _statuses,
              included: _draft.statusIn.toSet(),
              excluded: _draft.statusNotIn.toSet(),
              onChanged: (Set<String> included, Set<String> excluded) {
                setState(() {
                  _draft = _draft.copyWith(
                    statusIn: included.toList()..sort(),
                    statusNotIn: excluded.toList()..sort(),
                  );
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Source
            _FilterSectionHeader(context.t('Source')),
            _IncludeExcludeChips<String>(
              options: _sources,
              included: _draft.sourceIn.toSet(),
              excluded: _draft.sourceNotIn.toSet(),
              onChanged: (Set<String> included, Set<String> excluded) {
                setState(() {
                  _draft = _draft.copyWith(
                    sourceIn: included.toList()..sort(),
                    sourceNotIn: excluded.toList()..sort(),
                  );
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // Season (anime only)
            if (isAnime) ...<Widget>[
              _FilterSectionHeader(context.t('Season')),
              _SingleSelectChips(
                options: _seasons,
                selected: _draft.season,
                onChanged: (String? val) =>
                    setState(() => _draft = _draft.copyWith(season: val)),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Year range
            _FilterSectionHeader(context.t('Year Range')),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('From'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      DropdownButton<int?>(
                        isExpanded: true,
                        value: _draft.yearFrom,
                        items: years
                            .map(
                              (int? y) => DropdownMenuItem<int?>(
                                value: y,
                                child: Text(y?.toString() ?? context.t('Any')),
                              ),
                            )
                            .toList(),
                        onChanged: (int? val) => setState(
                          () => _draft = _draft.copyWith(yearFrom: val),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('To'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      DropdownButton<int?>(
                        isExpanded: true,
                        value: _draft.yearTo,
                        items: years
                            .map(
                              (int? y) => DropdownMenuItem<int?>(
                                value: y,
                                child: Text(y?.toString() ?? context.t('Any')),
                              ),
                            )
                            .toList(),
                        onChanged: (int? val) => setState(
                          () => _draft = _draft.copyWith(yearTo: val),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Country
            _FilterSectionHeader(context.t('Country of Origin')),
            _SingleSelectChips(
              options: _countries,
              selected: _draft.countryOfOrigin,
              onChanged: (String? val) => setState(
                () => _draft = _draft.copyWith(countryOfOrigin: val),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Genres
            if (widget.genres.isNotEmpty) ...<Widget>[
              _FilterSectionHeader(context.t('Genres')),
              _IncludeExcludeChips<String>(
                options: widget.genres
                    .map((String g) => (value: g, label: g))
                    .toList(),
                included: _draft.genreIn.toSet(),
                excluded: _draft.genreNotIn.toSet(),
                onChanged: (Set<String> included, Set<String> excluded) {
                  setState(() {
                    _draft = _draft.copyWith(
                      genreIn: included.toList()..sort(),
                      genreNotIn: excluded.toList()..sort(),
                    );
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Flags
            _FilterSectionHeader(context.t('Flags')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                IncludeExcludeFilterChip(
                  label: context.t('Adult'),
                  state: _boolState(_draft.isAdult),
                  onInclude: () =>
                      setState(() => _draft = _draft.copyWith(isAdult: true)),
                  onExclude: () =>
                      setState(() => _draft = _draft.copyWith(isAdult: false)),
                  onClear: () =>
                      setState(() => _draft = _draft.copyWith(isAdult: null)),
                ),
                IncludeExcludeFilterChip(
                  label: context.t('Licensed'),
                  state: _boolState(_draft.isLicensed),
                  onInclude: () => setState(
                    () => _draft = _draft.copyWith(isLicensed: true),
                  ),
                  onExclude: () => setState(
                    () => _draft = _draft.copyWith(isLicensed: false),
                  ),
                  onClear: () => setState(
                    () => _draft = _draft.copyWith(isLicensed: null),
                  ),
                ),
                IncludeExcludeFilterChip(
                  label: context.t('In my list'),
                  state: _boolState(_draft.onList),
                  onInclude: () =>
                      setState(() => _draft = _draft.copyWith(onList: true)),
                  onExclude: () =>
                      setState(() => _draft = _draft.copyWith(onList: false)),
                  onClear: () =>
                      setState(() => _draft = _draft.copyWith(onList: null)),
                ),
              ],
            ),

            // Tags stay at the bottom because this can be the longest section.
            if (widget.tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _FilterSectionHeader(context.t('Tags')),
              TextField(
                controller: _tagSearch,
                decoration: InputDecoration(
                  hintText: context.t('Search tags'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_tagsByCategory().isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(context.t('No tags found')),
                )
              else
                ..._tagsByCategory().entries.map((
                  MapEntry<String, List<AniListMediaTagInfo>> entry,
                ) {
                  final bool hasSelected = entry.value.any(
                    (AniListMediaTagInfo tag) =>
                        _draft.tagIn.contains(tag.name) ||
                        _draft.tagNotIn.contains(tag.name),
                  );
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded:
                        hasSelected || _tagSearch.text.trim().isNotEmpty,
                    title: Text(context.t(_displayTagCategory(entry.key))),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _IncludeExcludeChips<String>(
                          options: entry.value
                              .map(
                                (AniListMediaTagInfo tag) => (
                                  value: tag.name,
                                  label: tag.isAdult
                                      ? '${tag.name}  18+'
                                      : tag.name,
                                ),
                              )
                              .toList(),
                          included: _draft.tagIn.toSet(),
                          excluded: _draft.tagNotIn.toSet(),
                          onChanged:
                              (Set<String> included, Set<String> excluded) {
                                setState(() {
                                  _draft = _draft.copyWith(
                                    tagIn: included.toList()..sort(),
                                    tagNotIn: excluded.toList()..sort(),
                                  );
                                });
                              },
                        ),
                      ),
                    ],
                  );
                }),
            ],
            const SizedBox(height: AppSpacing.xl),

            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const _AniListDiscoveryFilter()),
                    child: Text(context.t('Reset')),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: Text(context.t('Apply')),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FilterSectionHeader extends StatelessWidget {
  const _FilterSectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _IncludeExcludeChips<T> extends StatelessWidget {
  const _IncludeExcludeChips({
    required this.options,
    required this.included,
    required this.excluded,
    required this.onChanged,
  });

  final List<({T value, String label})> options;
  final Set<T> included;
  final Set<T> excluded;
  final void Function(Set<T> included, Set<T> excluded) onChanged;

  void _update(T value, IncludeExcludeState state) {
    final Set<T> nextIncluded = Set<T>.from(included);
    final Set<T> nextExcluded = Set<T>.from(excluded);
    setIncludeExcludeSelection<T>(
      included: nextIncluded,
      excluded: nextExcluded,
      value: value,
      state: state,
    );
    onChanged(nextIncluded, nextExcluded);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: options
          .map(
            (({T value, String label}) opt) => IncludeExcludeFilterChip(
              label: opt.label,
              state: includeExcludeStateOf<T>(opt.value, included, excluded),
              onInclude: () => _update(opt.value, IncludeExcludeState.included),
              onExclude: () => _update(opt.value, IncludeExcludeState.excluded),
              onClear: () => _update(opt.value, IncludeExcludeState.neutral),
            ),
          )
          .toList(),
    );
  }
}

class _SingleSelectChips extends StatelessWidget {
  const _SingleSelectChips({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<({String value, String label})> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: options
          .map(
            (({String value, String label}) opt) => ChoiceChip(
              label: Text(opt.label),
              selected: selected == opt.value,
              onSelected: (bool on) => onChanged(on ? opt.value : null),
            ),
          )
          .toList(),
    );
  }
}

// ── TMDB advanced filter sheet ───────────────────────────────────────────────

class _TmdbDiscoveryFilterSheet extends StatefulWidget {
  const _TmdbDiscoveryFilterSheet({
    required this.initial,
    required this.selectedType,
  });

  final _TmdbDiscoveryFilter initial;
  final MediaType? selectedType;

  @override
  State<_TmdbDiscoveryFilterSheet> createState() =>
      _TmdbDiscoveryFilterSheetState();
}

class _TmdbDiscoveryFilterSheetState extends State<_TmdbDiscoveryFilterSheet> {
  late _TmdbDiscoveryFilter _draft;

  static const List<({int id, String label})> _movieGenres =
      <({int id, String label})>[
        (id: 28, label: 'Action'),
        (id: 12, label: 'Adventure'),
        (id: 16, label: 'Animation'),
        (id: 35, label: 'Comedy'),
        (id: 80, label: 'Crime'),
        (id: 99, label: 'Documentary'),
        (id: 18, label: 'Drama'),
        (id: 10751, label: 'Family'),
        (id: 14, label: 'Fantasy'),
        (id: 27, label: 'Horror'),
        (id: 9648, label: 'Mystery'),
        (id: 10749, label: 'Romance'),
        (id: 878, label: 'Science Fiction'),
        (id: 53, label: 'Thriller'),
        (id: 10752, label: 'War'),
        (id: 37, label: 'Western'),
      ];

  static const List<({int id, String label})> _tvGenres =
      <({int id, String label})>[
        (id: 10759, label: 'Action & Adventure'),
        (id: 16, label: 'Animation'),
        (id: 35, label: 'Comedy'),
        (id: 80, label: 'Crime'),
        (id: 99, label: 'Documentary'),
        (id: 18, label: 'Drama'),
        (id: 10751, label: 'Family'),
        (id: 10762, label: 'Kids'),
        (id: 9648, label: 'Mystery'),
        (id: 10765, label: 'Sci-Fi & Fantasy'),
        (id: 10768, label: 'War & Politics'),
        (id: 37, label: 'Western'),
      ];

  static const List<({String value, String label})> _languages =
      <({String value, String label})>[
        (value: 'en', label: 'English'),
        (value: 'ja', label: 'Japanese'),
        (value: 'ko', label: 'Korean'),
        (value: 'zh', label: 'Chinese'),
        (value: 'fr', label: 'French'),
        (value: 'de', label: 'German'),
        (value: 'es', label: 'Spanish'),
        (value: 'it', label: 'Italian'),
        (value: 'pt', label: 'Portuguese'),
        (value: 'ru', label: 'Russian'),
        (value: 'hi', label: 'Hindi'),
      ];

  static const List<({double? value, String label})> _ratingOptions =
      <({double? value, String label})>[
        (value: null, label: 'Any'),
        (value: 5.0, label: '5+'),
        (value: 6.0, label: '6+'),
        (value: 7.0, label: '7+'),
        (value: 7.5, label: '7.5+'),
        (value: 8.0, label: '8+'),
        (value: 9.0, label: '9+'),
      ];

  List<({int id, String label})> _genresForType(MediaType? type) {
    return switch (type) {
      MediaType.movie => _movieGenres,
      MediaType.anime =>
        _tvGenres.where((({int id, String label}) g) => g.id != 16).toList(),
      MediaType.series => _tvGenres,
      null => <({int id, String label})>[
        ..._movieGenres,
        ..._tvGenres.where(
          (({int id, String label}) g) =>
              _movieGenres.every((({int id, String label}) m) => m.id != g.id),
        ),
      ],
    };
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  IncludeExcludeState _adultState() {
    return switch (_draft.includeAdult) {
      true => IncludeExcludeState.included,
      false => IncludeExcludeState.excluded,
      null => IncludeExcludeState.neutral,
    };
  }

  @override
  Widget build(BuildContext context) {
    final List<({int id, String label})> genres = _genresForType(
      widget.selectedType,
    );
    final bool showLanguage = widget.selectedType != MediaType.anime;
    final int currentYear = DateTime.now().year;
    final List<int?> years = <int?>[
      null,
      ...List<int>.generate(
        currentYear + 1 - 1900 + 1,
        (int i) => currentYear + 1 - i,
      ),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: <Widget>[
            // Genres
            _FilterSectionHeader(context.t('Genres')),
            _IncludeExcludeChips<int>(
              options: genres
                  .map(
                    (({int id, String label}) g) =>
                        (value: g.id, label: g.label),
                  )
                  .toList(),
              included: _draft.genreIds.toSet(),
              excluded: _draft.genreNotIds.toSet(),
              onChanged: (Set<int> included, Set<int> excluded) {
                setState(() {
                  _draft = _draft.copyWith(
                    genreIds: included.toList()..sort(),
                    genreNotIds: excluded.toList()..sort(),
                  );
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            _FilterSectionHeader(context.t('Age restriction')),
            IncludeExcludeFilterChip(
              label: context.t('Adult'),
              state: _adultState(),
              onInclude: () =>
                  setState(() => _draft = _draft.copyWith(includeAdult: true)),
              onExclude: () =>
                  setState(() => _draft = _draft.copyWith(includeAdult: false)),
              onClear: () =>
                  setState(() => _draft = _draft.copyWith(includeAdult: null)),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Min Rating
            _FilterSectionHeader(context.t('Min Rating')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: _ratingOptions
                  .map(
                    (({double? value, String label}) opt) => ChoiceChip(
                      label: Text(opt.label),
                      selected: _draft.minRating == opt.value,
                      onSelected: (bool on) => setState(
                        () => _draft = _draft.copyWith(
                          minRating: on ? opt.value : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Year range
            _FilterSectionHeader(context.t('Year Range')),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('From'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      DropdownButton<int?>(
                        isExpanded: true,
                        value: _draft.yearFrom,
                        items: years
                            .map(
                              (int? y) => DropdownMenuItem<int?>(
                                value: y,
                                child: Text(y?.toString() ?? context.t('Any')),
                              ),
                            )
                            .toList(),
                        onChanged: (int? val) => setState(
                          () => _draft = _draft.copyWith(yearFrom: val),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t('To'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      DropdownButton<int?>(
                        isExpanded: true,
                        value: _draft.yearTo,
                        items: years
                            .map(
                              (int? y) => DropdownMenuItem<int?>(
                                value: y,
                                child: Text(y?.toString() ?? context.t('Any')),
                              ),
                            )
                            .toList(),
                        onChanged: (int? val) => setState(
                          () => _draft = _draft.copyWith(yearTo: val),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Language (not for anime type)
            if (showLanguage) ...<Widget>[
              _FilterSectionHeader(context.t('Original Language')),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: _languages
                    .map(
                      (({String value, String label}) lang) => ChoiceChip(
                        label: Text(lang.label),
                        selected: _draft.originalLanguage == lang.value,
                        onSelected: (bool on) => setState(
                          () => _draft = _draft.copyWith(
                            originalLanguage: on ? lang.value : null,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const _TmdbDiscoveryFilter()),
                    child: Text(context.t('Reset')),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: Text(context.t('Apply')),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
