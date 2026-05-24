import '../../../shared/models/media_item.dart';
import 'anilist_anime_client.dart';
import 'shikimori_client.dart';

class AnimeResolver {
  AnimeResolver({
    required AniListAnimeClient anilist,
    required ShikiMoriClient shikimori,
    required this.language,
  }) : _anilist = anilist,
       _shikimori = shikimori;

  final AniListAnimeClient _anilist;
  final ShikiMoriClient _shikimori;

  // language is TMDB-style: 'ru-RU', 'en-US', 'ja-JP'
  final String language;

  bool get _wantsRussian => language.startsWith('ru');
  bool get _wantsJapanese => language.startsWith('ja');

  final Map<String, _CacheEntry> _enrichCache = <String, _CacheEntry>{};

  static const Duration _cacheTtl = Duration(hours: 4);
  static const int _maxCacheSize = 100;

  // Direct lookup by AniList ID — skips title search, used for anilist:* items.
  // Does NOT build franchise seasons because the item IS a specific season.
  Future<MediaItem> enrichByAniListId(int anilistId, MediaItem baseItem) async {
    final String cacheKey = 'al:$anilistId:$language';
    final _CacheEntry? cached = _enrichCache[cacheKey];
    if (cached != null && cached.expiry.isAfter(DateTime.now())) {
      return cached.value;
    }

    try {
      final AniListAnimeDetails? aniEntry = await _anilist.getById(anilistId);
      if (aniEntry == null) return baseItem;
      return _applyAniListEntry(
        baseItem,
        aniEntry,
        cacheKey,
        includeFranchiseSeasons: false,
      );
    } catch (_) {
      return baseItem;
    }
  }

  Future<MediaItem> enrich(MediaItem tmdbItem) async {
    final String cacheKey = '${tmdbItem.id}:$language';
    final _CacheEntry? cached = _enrichCache[cacheKey];
    if (cached != null && cached.expiry.isAfter(DateTime.now())) {
      return cached.value;
    }

    try {
      final AniListAnimeDetails? aniEntry = await _findAniListEntry(tmdbItem);
      if (aniEntry == null) return tmdbItem;
      return _applyAniListEntry(tmdbItem, aniEntry, cacheKey);
    } catch (_) {
      return tmdbItem;
    }
  }

  Future<MediaItem> _applyAniListEntry(
    MediaItem base,
    AniListAnimeDetails aniEntry,
    String cacheKey, {
    bool includeFranchiseSeasons = true,
  }) async {
    final String title = await _resolveTitle(base, aniEntry);
    final List<MediaSeason> seasons = includeFranchiseSeasons
        ? _buildFranchiseSeasons(aniEntry)
        : const <MediaSeason>[];

    final Map<String, String> externalIds = <String, String>{
      ...base.externalIds,
      'anilist': aniEntry.id.toString(),
      if (aniEntry.titleRomaji.isNotEmpty)
        'anilist_title_romaji': aniEntry.titleRomaji,
      if (aniEntry.titleEnglish.isNotEmpty)
        'anilist_title_english': aniEntry.titleEnglish,
      if (aniEntry.titleNative.isNotEmpty)
        'anilist_title_native': aniEntry.titleNative,
      if (aniEntry.malId != null) 'mal': aniEntry.malId.toString(),
    };

    final String originalTitle = aniEntry.titleNative.isNotEmpty
        ? aniEntry.titleNative
        : base.originalTitle;

    final int episodeCount =
        aniEntry.episodes ??
        base.episodeCount ??
        seasons.fold<int>(0, (int sum, MediaSeason s) => sum + s.episodeCount);

    final MediaItem enriched = MediaItem(
      id: base.id,
      title: title,
      originalTitle: originalTitle,
      overview: base.overview,
      type: MediaType.anime,
      year: base.year,
      posterUrl: base.posterUrl,
      backdropUrl: base.backdropUrl.isNotEmpty
          ? base.backdropUrl
          : (aniEntry.bannerImage ?? ''),
      rating: base.rating > 0
          ? base.rating
          : (aniEntry.averageScore != null
                ? (aniEntry.averageScore! / 10.0).clamp(0.0, 10.0)
                : 0.0),
      genres: base.genres,
      sourceProvider: base.sourceProvider,
      externalIds: externalIds,
      runtimeMinutes: base.runtimeMinutes,
      episodeCount: episodeCount == 0 ? null : episodeCount,
      seasons: seasons.isNotEmpty ? seasons : base.seasons,
      statusLabel: base.statusLabel,
      aliases: <String>{
        if (aniEntry.titleRomaji.isNotEmpty && aniEntry.titleRomaji != title)
          aniEntry.titleRomaji,
        if (aniEntry.titleEnglish.isNotEmpty && aniEntry.titleEnglish != title)
          aniEntry.titleEnglish,
        if (aniEntry.titleNative.isNotEmpty && aniEntry.titleNative != title)
          aniEntry.titleNative,
        ...base.aliases,
      }.toList(growable: false),
      originalLanguage: base.originalLanguage,
    );

    _putCache(cacheKey, enriched);
    return enriched;
  }

  Future<AniListAnimeDetails?> _findAniListEntry(MediaItem tmdbItem) async {
    // Try original title (Japanese) first — most reliable for anime
    final String originalTitle = tmdbItem.originalTitle.trim();
    final String displayTitle = tmdbItem.title.trim();

    for (final String query in <String>[
      if (originalTitle.isNotEmpty) originalTitle,
      if (displayTitle.isNotEmpty && displayTitle != originalTitle)
        displayTitle,
    ]) {
      try {
        final List<AniListAnimeDetails> results = await _anilist.search(query);
        final AniListAnimeDetails? match = _bestMatch(results, tmdbItem);
        if (match != null) return match;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  AniListAnimeDetails? _bestMatch(
    List<AniListAnimeDetails> results,
    MediaItem tmdbItem,
  ) {
    if (results.isEmpty) return null;
    // Score by year proximity and title similarity
    final int tmdbYear = tmdbItem.year;
    AniListAnimeDetails? best;
    int bestScore = -1;

    for (final AniListAnimeDetails entry in results) {
      int score = 0;
      // Year match
      if (tmdbYear > 0 && entry.startYear > 0) {
        final int diff = (entry.startYear - tmdbYear).abs();
        if (diff == 0) {
          score += 20;
        } else if (diff == 1) {
          score += 10;
        } else if (diff <= 2) {
          score += 5;
        }
      }
      // Title match
      final String entryTitle = entry.displayTitle.toLowerCase();
      final String tmdbTitle = tmdbItem.title.toLowerCase();
      final String origTitle = tmdbItem.originalTitle.toLowerCase();
      if (entryTitle == tmdbTitle || entryTitle == origTitle) {
        score += 30;
      } else if (entryTitle.contains(tmdbTitle) ||
          tmdbTitle.contains(entryTitle)) {
        score += 10;
      }

      // Prefer TV format for series
      if (entry.format == 'TV') {
        score += 5;
      }

      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    // If best score is too low (no meaningful match), return null
    return bestScore >= 5 ? best : results.first;
  }

  Future<String> _resolveTitle(
    MediaItem tmdbItem,
    AniListAnimeDetails aniEntry,
  ) async {
    if (_wantsRussian) {
      // MAL ID direct lookup — most reliable (no redirect)
      if (aniEntry.malId != null) {
        final String? russian = await _shikimori.findRussianTitleByMalId(
          aniEntry.malId!,
        );
        if (russian != null && russian.isNotEmpty) return russian;
      }
      // Fall back to title search
      final String searchQuery = aniEntry.titleRomaji.isNotEmpty
          ? aniEntry.titleRomaji
          : aniEntry.titleEnglish;
      if (searchQuery.isNotEmpty) {
        final String? russian = await _shikimori.findRussianTitle(searchQuery);
        if (russian != null && russian.isNotEmpty) return russian;
      }
      // Fall back to TMDB title (already in Russian from ru-RU query)
      return tmdbItem.title;
    }

    if (_wantsJapanese) {
      // Prefer native Japanese, then romaji
      if (aniEntry.titleNative.isNotEmpty) return aniEntry.titleNative;
      if (aniEntry.titleRomaji.isNotEmpty) return aniEntry.titleRomaji;
      return tmdbItem.title;
    }

    // English: prefer AniList English, fall back to TMDB
    if (aniEntry.titleEnglish.isNotEmpty) return aniEntry.titleEnglish;
    return tmdbItem.title;
  }

  List<MediaSeason> _buildFranchiseSeasons(AniListAnimeDetails root) {
    // Collect all relevant entries: root + sequel/prequel relations
    final List<_SeasonEntry> entries = <_SeasonEntry>[];

    entries.add(
      _SeasonEntry(
        id: root.id,
        titleEnglish: root.titleEnglish,
        titleRomaji: root.titleRomaji,
        relationType: 'ROOT',
        format: root.format,
        episodes: root.episodes ?? 0,
        startYear: root.startYear,
        coverImage: root.coverImage,
      ),
    );

    for (final AniListRelation rel in root.relations) {
      final String type = rel.relationType;
      if (type == 'SEQUEL' ||
          type == 'PREQUEL' ||
          type == 'SIDE_STORY' ||
          type == 'ALTERNATIVE') {
        entries.add(
          _SeasonEntry(
            id: rel.nodeId,
            titleEnglish: rel.titleEnglish,
            titleRomaji: rel.titleRomaji,
            relationType: type,
            format: rel.format,
            episodes: rel.episodes ?? 0,
            startYear: rel.startYear,
            coverImage: rel.coverImage,
          ),
        );
      }
    }

    if (entries.length <= 1) return const <MediaSeason>[];

    entries.sort(_compareSeasonEntries);

    // Remove duplicates by id
    final Set<int> seen = <int>{};
    final List<_SeasonEntry> unique = entries
        .where((e) => seen.add(e.id))
        .toList(growable: false);

    int counter = 0;
    final List<MediaSeason> seasons = <MediaSeason>[];

    for (final _SeasonEntry entry in unique) {
      counter++;
      final bool isSpecial =
          entry.format == 'OVA' ||
          entry.format == 'ONA' ||
          entry.format == 'SPECIAL' ||
          entry.format == 'MUSIC';
      final bool isMovie = entry.format == 'MOVIE';

      final String name = entry.displayTitle;
      seasons.add(
        MediaSeason(
          seasonNumber: counter,
          name: name,
          episodeCount: entry.episodes,
          posterUrl: entry.coverImage ?? '',
          overview: '',
          isSpecials: isSpecial || isMovie,
          externalIds: <String, String>{'anilist': entry.id.toString()},
        ),
      );
    }

    return seasons;
  }

  int _compareSeasonEntries(_SeasonEntry a, _SeasonEntry b) {
    final bool aHasYear = a.startYear > 0;
    final bool bHasYear = b.startYear > 0;
    if (aHasYear && bHasYear) {
      final int yearOrder = a.startYear.compareTo(b.startYear);
      if (yearOrder != 0) {
        return yearOrder;
      }
    }
    final int relationOrder = _relationRank(
      a.relationType,
    ).compareTo(_relationRank(b.relationType));
    if (relationOrder != 0) {
      return relationOrder;
    }
    if (aHasYear != bHasYear) {
      return aHasYear ? -1 : 1;
    }
    return a.displayTitle.compareTo(b.displayTitle);
  }

  int _relationRank(String relationType) {
    return switch (relationType) {
      'PREQUEL' => 0,
      'ROOT' => 1,
      'SEQUEL' => 2,
      'SIDE_STORY' => 3,
      'ALTERNATIVE' => 4,
      _ => 5,
    };
  }

  void _putCache(String key, MediaItem value) {
    if (_enrichCache.length >= _maxCacheSize) {
      _enrichCache.remove(_enrichCache.keys.first);
    }
    _enrichCache[key] = _CacheEntry(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }
}

class _SeasonEntry {
  const _SeasonEntry({
    required this.id,
    required this.titleEnglish,
    required this.titleRomaji,
    required this.relationType,
    required this.format,
    required this.episodes,
    required this.startYear,
    this.coverImage,
  });

  final int id;
  final String titleEnglish;
  final String titleRomaji;
  final String relationType;
  final String format;
  final int episodes;
  final int startYear;
  final String? coverImage;

  String get displayTitle =>
      titleEnglish.isNotEmpty ? titleEnglish : titleRomaji;
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiry});
  final MediaItem value;
  final DateTime expiry;
}
