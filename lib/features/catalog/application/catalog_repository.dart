import 'dart:async';

import '../../../core/cache/metadata_cache_store.dart';
import '../../../shared/models/calendar_item.dart';
import '../../../shared/models/media_item.dart';
import '../../metadata/application/media_catalog.dart';
import '../../metadata/data/tmdb_metadata_provider.dart';
import '../../tracking/data/anilist_api_client.dart';
import 'catalog_mode.dart';

typedef CatalogOfflineCallback =
    void Function(
      Object error, {
      required String operation,
      required bool usingCache,
    });

typedef CatalogOnlineCallback = void Function({required String operation});

abstract interface class CatalogRepository {
  CatalogMode get mode;

  Future<BoardRails> boardRails();

  Future<List<MediaItem>> discover({
    required String search,
    required MediaType? type,
    required String filter,
    required int page,
    String? anilistKind,
  });

  Future<MediaItem?> details(String id);

  Future<List<CalendarItem>> calendar({
    required DateTime from,
    required DateTime to,
  });
}

class TmdbCatalogRepository implements CatalogRepository {
  const TmdbCatalogRepository({
    required this.tmdb,
    required this.cache,
    required this.cacheScope,
    this.onOffline,
    this.onOnline,
  });

  final TmdbMetadataProvider tmdb;
  final MetadataCacheStore cache;
  final String cacheScope;
  final CatalogOfflineCallback? onOffline;
  final CatalogOnlineCallback? onOnline;

  @override
  CatalogMode get mode => CatalogMode.tmdb;

  @override
  Future<BoardRails> boardRails() {
    return _cachedBoardThenRefreshForNextLaunch(
      cache: cache,
      key: '$cacheScope.board',
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () async {
        final List<List<MediaItem>> results =
            await Future.wait(<Future<List<MediaItem>>>[
              tmdb.getRecentlyReleasedMovies(),
              tmdb.getPopular(MediaType.series),
              tmdb.getPopular(MediaType.anime),
            ]);
        return _limitBoardRails(
          BoardRails(
            recentMovies: results[0],
            recentSeries: results[1],
            topAnime: results[2],
          ),
        );
      },
    );
  }

  @override
  Future<List<MediaItem>> discover({
    required String search,
    required MediaType? type,
    required String filter,
    required int page,
    String? anilistKind,
  }) {
    final String normalizedSearch = search.trim();
    final String typeKey = type?.name ?? 'all';
    final String key =
        '$cacheScope.discovery.${_safe(normalizedSearch)}.$filter.$typeKey.$page';
    return _networkFirst(
      cache: cache,
      key: key,
      operation: 'discovery',
      fallback: const <MediaItem>[],
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () {
        if (normalizedSearch.isNotEmpty) {
          return tmdb
              .search(normalizedSearch, page: page)
              .then(
                (List<MediaItem> items) => type == null
                    ? items
                    : items
                          .where((MediaItem item) => item.type == type)
                          .toList(),
              );
        }
        return tmdb.discoverPage(filter: filter, type: type, page: page);
      },
      decode: _mediaListFromJson,
      encode: _mediaListToJson,
    );
  }

  @override
  Future<MediaItem?> details(String id) {
    return _cachedThenRefresh(
      cache: cache,
      key: '$cacheScope.details.${_safe(id)}',
      operation: 'details',
      fallback: null,
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () => tmdb.getDetails(id),
      decode: _mediaFromJsonOrNull,
      encode: _mediaToJsonOrNull,
    );
  }

  @override
  Future<List<CalendarItem>> calendar({
    required DateTime from,
    required DateTime to,
  }) {
    return _networkFirst(
      cache: cache,
      key: '$cacheScope.calendar.${_dateKey(from)}.${_dateKey(to)}',
      operation: 'calendar',
      fallback: const <CalendarItem>[],
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () => tmdb.getCalendarItems(from: from, to: to),
      decode: _calendarListFromJson,
      encode: _calendarListToJson,
    );
  }
}

class AniListCatalogRepository implements CatalogRepository {
  const AniListCatalogRepository({
    required this.client,
    required this.cache,
    required this.cacheScope,
    this.tmdb,
    this.viewerId,
    this.hasAccessToken = false,
    this.onOffline,
    this.onOnline,
  });

  final AniListApiClient client;
  final MetadataCacheStore cache;
  final String cacheScope;
  final TmdbMetadataProvider? tmdb;
  final int? viewerId;
  final bool hasAccessToken;
  final CatalogOfflineCallback? onOffline;
  final CatalogOnlineCallback? onOnline;

  @override
  CatalogMode get mode => CatalogMode.anilist;

  @override
  Future<BoardRails> boardRails() {
    return _cachedBoardThenRefreshForNextLaunch(
      cache: cache,
      key: '$cacheScope.board.${viewerId ?? 'public'}',
      isCachedSnapshotCurrent: (Map<String, dynamic> json) =>
          json['schemaVersion'] == _boardCacheSchemaVersion,
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () async {
        final List<List<MediaItem>> results =
            await Future.wait(<Future<List<MediaItem>>>[
              client.getTrendingCatalog(kind: 'anime'),
              client.getPopularCatalog(kind: 'anime'),
              client.getFilteredCatalog(kind: 'anime', filter: 'Top Rated'),
              for (final String filter in _additionalAniListBoardFilters)
                client.getFilteredCatalog(kind: 'anime', filter: filter),
            ]);
        List<MediaItem> recentMovies = results[0];
        if (recentMovies.isNotEmpty) {
          final MediaItem enriched = await client.enrichHeroOverview(
            recentMovies.first,
          );
          if (!identical(enriched, recentMovies.first)) {
            recentMovies = <MediaItem>[enriched, ...recentMovies.skip(1)];
          }
        }
        return _limitBoardRails(
          BoardRails(
            recentMovies: recentMovies,
            recentSeries: results[1],
            topAnime: results[2],
            additionalSections: <String, List<MediaItem>>{
              for (
                int index = 0;
                index < _additionalAniListBoardFilters.length;
                index += 1
              )
                _additionalAniListBoardFilters[index]: results[index + 3],
            },
          ),
        );
      },
    );
  }

  @override
  Future<List<MediaItem>> discover({
    required String search,
    required MediaType? type,
    required String filter,
    required int page,
    String? anilistKind,
  }) {
    final String requestedKind = (anilistKind?.trim().isNotEmpty ?? false)
        ? anilistKind!.trim()
        : 'anime';
    final String kind = requestedKind;
    final String normalizedSearch = search.trim();
    final String key =
        '$cacheScope.discovery.$kind.${_safe(normalizedSearch)}.$filter.$page';
    return _networkFirst(
      cache: cache,
      key: key,
      operation: 'discovery',
      fallback: const <MediaItem>[],
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () {
        if (normalizedSearch.isNotEmpty) {
          return client.searchCatalog(
            kind: kind,
            query: normalizedSearch,
            page: page,
          );
        }
        if (filter == 'Trending') {
          return client.getTrendingCatalog(kind: kind, page: page);
        }
        if (filter == 'Popular') {
          return client.getPopularCatalog(kind: kind, page: page);
        }
        return client.getFilteredCatalog(
          kind: kind,
          filter: filter,
          page: page,
        );
      },
      decode: _mediaListFromJson,
      encode: _mediaListToJson,
    );
  }

  @override
  Future<MediaItem?> details(String id) {
    return _cachedThenRefresh(
      cache: cache,
      key: '$cacheScope.details.${_safe(id)}',
      operation: 'details',
      fallback: null,
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () async {
        final MediaItem? item = await client.getCatalogDetails(id);
        if (item == null || item.trailer != null || tmdb == null) {
          return item;
        }
        final MediaTrailer? trailer = await tmdb!.findAnimeTrailer(item);
        return trailer == null ? item : item.copyWith(trailer: trailer);
      },
      decode: _mediaFromJsonOrNull,
      encode: _mediaToJsonOrNull,
    );
  }

  @override
  Future<List<CalendarItem>> calendar({
    required DateTime from,
    required DateTime to,
  }) {
    return _networkFirst(
      cache: cache,
      key: '$cacheScope.calendar.${_dateKey(from)}.${_dateKey(to)}',
      operation: 'calendar',
      fallback: const <CalendarItem>[],
      onOffline: onOffline,
      onOnline: onOnline,
      fetch: () => client.getAiringAnime(from: from, to: to),
      decode: _calendarListFromJson,
      encode: _calendarListToJson,
    );
  }
}

const List<String> _additionalAniListBoardFilters = <String>[
  'Favorites',
  'Airing',
  'Upcoming',
  'Finished',
  'Newest',
  'Recently Updated',
];

/// Returns the previous complete board snapshot immediately, then replaces the
/// stored snapshot in the background for the next app launch.
///
/// A cold cache remains network-first so first-time users still receive live
/// board data. Refresh failures are contained because this work is unawaited.
Future<BoardRails> _cachedBoardThenRefreshForNextLaunch({
  required MetadataCacheStore cache,
  required String key,
  required Future<BoardRails> Function() fetch,
  bool Function(Map<String, dynamic> json)? isCachedSnapshotCurrent,
  CatalogOfflineCallback? onOffline,
  CatalogOnlineCallback? onOnline,
}) async {
  final Map<String, dynamic>? cachedJson = await cache.read(key);
  if (cachedJson != null &&
      (isCachedSnapshotCurrent?.call(cachedJson) ?? true)) {
    try {
      final BoardRails cached = _limitBoardRails(_boardFromJson(cachedJson));
      unawaited(
        _refreshBoardCache(
          cache: cache,
          key: key,
          fetch: fetch,
          onOffline: onOffline,
          onOnline: onOnline,
        ),
      );
      return cached;
    } catch (_) {
      // Treat an invalid snapshot as a cold cache and replace it from network.
    }
  }

  return _networkFirst(
    cache: cache,
    key: key,
    operation: 'board',
    fallback: BoardRails.empty(),
    onOffline: onOffline,
    onOnline: onOnline,
    fetch: fetch,
    decode: (Map<String, dynamic> json) =>
        _limitBoardRails(_boardFromJson(json)),
    encode: (BoardRails value) => _boardToJson(_limitBoardRails(value)),
  );
}

Future<void> _refreshBoardCache({
  required MetadataCacheStore cache,
  required String key,
  required Future<BoardRails> Function() fetch,
  CatalogOfflineCallback? onOffline,
  CatalogOnlineCallback? onOnline,
}) async {
  try {
    final BoardRails fresh = _limitBoardRails(await fetch());
    await cache.write(key, _boardToJson(fresh));
    try {
      onOnline?.call(operation: 'board');
    } catch (_) {
      // The provider may have been disposed while this refresh was running.
    }
  } catch (error) {
    try {
      onOffline?.call(error, operation: 'board', usingCache: true);
    } catch (_) {
      // Keep background refresh errors from escaping as unhandled futures.
    }
  }
}

/// Returns a complete saved value first, then refreshes the persisted snapshot
/// in the background. This keeps detail pages instant across app restarts while
/// still allowing the provider to replace stale text and artwork URLs.
Future<T> _cachedThenRefresh<T>({
  required MetadataCacheStore cache,
  required String key,
  required String operation,
  required T fallback,
  required Future<T> Function() fetch,
  required T Function(Map<String, dynamic> json) decode,
  required Map<String, dynamic> Function(T value) encode,
  CatalogOfflineCallback? onOffline,
  CatalogOnlineCallback? onOnline,
}) async {
  final Map<String, dynamic>? cachedJson = await cache.read(key);
  if (cachedJson != null) {
    try {
      final T cached = decode(cachedJson);
      if (cached != null) {
        unawaited(
          _refreshCachedValue(
            cache: cache,
            key: key,
            operation: operation,
            fetch: fetch,
            encode: encode,
            onOffline: onOffline,
            onOnline: onOnline,
          ),
        );
        return cached;
      }
    } catch (_) {
      // Treat an invalid or incomplete snapshot as a cold cache.
    }
  }

  return _networkFirst(
    cache: cache,
    key: key,
    operation: operation,
    fallback: fallback,
    fetch: fetch,
    decode: decode,
    encode: encode,
    onOffline: onOffline,
    onOnline: onOnline,
  );
}

Future<void> _refreshCachedValue<T>({
  required MetadataCacheStore cache,
  required String key,
  required String operation,
  required Future<T> Function() fetch,
  required Map<String, dynamic> Function(T value) encode,
  CatalogOfflineCallback? onOffline,
  CatalogOnlineCallback? onOnline,
}) async {
  try {
    final T fresh = await fetch();
    await cache.write(key, encode(fresh));
    try {
      onOnline?.call(operation: operation);
    } catch (_) {
      // The provider may have been disposed while this refresh was running.
    }
  } catch (error) {
    try {
      onOffline?.call(error, operation: operation, usingCache: true);
    } catch (_) {
      // Keep background refresh errors from escaping as unhandled futures.
    }
  }
}

Future<T> _networkFirst<T>({
  required MetadataCacheStore cache,
  required String key,
  required String operation,
  required T fallback,
  required Future<T> Function() fetch,
  required T Function(Map<String, dynamic> json) decode,
  required Map<String, dynamic> Function(T value) encode,
  CatalogOfflineCallback? onOffline,
  CatalogOnlineCallback? onOnline,
}) async {
  try {
    final T value = await fetch();
    await cache.write(key, encode(value));
    onOnline?.call(operation: operation);
    return value;
  } catch (error) {
    final Map<String, dynamic>? cached = await cache.read(key);
    if (cached != null) {
      onOffline?.call(error, operation: operation, usingCache: true);
      return decode(cached);
    }
    onOffline?.call(error, operation: operation, usingCache: false);
    return fallback;
  }
}

Map<String, dynamic> _boardToJson(BoardRails rails) {
  final BoardRails limited = _limitBoardRails(rails);
  return <String, dynamic>{
    'schemaVersion': _boardCacheSchemaVersion,
    'recentMovies': limited.recentMovies
        .map((MediaItem item) => item.toJson())
        .toList(growable: false),
    'recentSeries': limited.recentSeries
        .map((MediaItem item) => item.toJson())
        .toList(growable: false),
    'topAnime': limited.topAnime
        .map((MediaItem item) => item.toJson())
        .toList(growable: false),
    'additionalSections': <String, dynamic>{
      for (final MapEntry<String, List<MediaItem>> section
          in limited.additionalSections.entries)
        section.key: section.value
            .map((MediaItem item) => item.toJson())
            .toList(growable: false),
    },
  };
}

BoardRails _boardFromJson(Map<String, dynamic> json) {
  return _limitBoardRails(
    BoardRails(
      recentMovies: _mediaList(json['recentMovies']),
      recentSeries: _mediaList(json['recentSeries']),
      topAnime: _mediaList(json['topAnime']),
      additionalSections: _mediaSectionMap(json['additionalSections']),
    ),
  );
}

const int _boardCacheSchemaVersion = 2;
const int _boardCacheItemLimit = 20;

BoardRails _limitBoardRails(BoardRails rails) {
  return BoardRails(
    recentMovies: rails.recentMovies
        .take(_boardCacheItemLimit)
        .toList(growable: false),
    recentSeries: rails.recentSeries
        .take(_boardCacheItemLimit)
        .toList(growable: false),
    topAnime: rails.topAnime.take(_boardCacheItemLimit).toList(growable: false),
    additionalSections: <String, List<MediaItem>>{
      for (final MapEntry<String, List<MediaItem>> section
          in rails.additionalSections.entries)
        section.key: section.value
            .take(_boardCacheItemLimit)
            .toList(growable: false),
    },
  );
}

Map<String, List<MediaItem>> _mediaSectionMap(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return const <String, List<MediaItem>>{};
  }
  return <String, List<MediaItem>>{
    for (final MapEntry<dynamic, dynamic> section in value.entries)
      if (section.key is String)
        section.key as String: _mediaList(section.value),
  };
}

Map<String, dynamic> _mediaListToJson(List<MediaItem> items) {
  return <String, dynamic>{
    'items': items
        .map((MediaItem item) => item.toJson())
        .toList(growable: false),
  };
}

List<MediaItem> _mediaListFromJson(Map<String, dynamic> json) {
  return _mediaList(json['items']);
}

Map<String, dynamic> _mediaToJsonOrNull(MediaItem? item) {
  return <String, dynamic>{if (item != null) 'item': item.toJson()};
}

MediaItem? _mediaFromJsonOrNull(Map<String, dynamic> json) {
  final Object? item = json['item'];
  return item is Map<String, dynamic> ? MediaItem.fromJson(item) : null;
}

List<MediaItem> _mediaList(Object? value) {
  if (value is! List<dynamic>) return const <MediaItem>[];
  return value
      .whereType<Map<String, dynamic>>()
      .map(MediaItem.fromJson)
      .toList(growable: false);
}

Map<String, dynamic> _calendarListToJson(List<CalendarItem> items) {
  return <String, dynamic>{
    'items': items.map(_calendarToJson).toList(growable: false),
  };
}

List<CalendarItem> _calendarListFromJson(Map<String, dynamic> json) {
  final Object? items = json['items'];
  if (items is! List<dynamic>) return const <CalendarItem>[];
  return items
      .whereType<Map<String, dynamic>>()
      .map(_calendarFromJson)
      .whereType<CalendarItem>()
      .toList(growable: false);
}

Map<String, dynamic> _calendarToJson(CalendarItem item) {
  return <String, dynamic>{
    'id': item.id,
    'mediaItem': item.mediaItem.toJson(),
    'date': item.date.toIso8601String(),
    'title': item.title,
    'description': item.description,
    'type': item.type.name,
    'isFromLibrary': item.isFromLibrary,
  };
}

CalendarItem? _calendarFromJson(Map<String, dynamic> json) {
  final Object? mediaItem = json['mediaItem'];
  final DateTime? date = DateTime.tryParse(json['date']?.toString() ?? '');
  if (mediaItem is! Map<String, dynamic> || date == null) return null;
  return CalendarItem(
    id: json['id']?.toString() ?? '',
    mediaItem: MediaItem.fromJson(mediaItem),
    date: date,
    title: json['title']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    type: CalendarItemType.values.firstWhere(
      (CalendarItemType type) => type.name == json['type'],
      orElse: () => CalendarItemType.reminder,
    ),
    isFromLibrary: json['isFromLibrary'] == true,
  );
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _safe(String value) {
  if (value.trim().isEmpty) return 'empty';
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
