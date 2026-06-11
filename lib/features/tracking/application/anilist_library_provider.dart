import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/cache/metadata_cache_store.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../profile/domain/anilist_profile_models.dart';
import '../../settings/presentation/settings_state.dart';
import '../data/anilist_api_client.dart';
import '../../metadata/data/shikimori_client.dart';
import '../../notifications/airing_notification_scheduler.dart';

final anilistEditQueueProvider = Provider<AniListEditQueue>(
  (Ref ref) => const AniListEditQueue(),
);

enum AniListLibraryLoadPhase { idle, loading, success, failed }

class AniListLibraryLoadStatus {
  const AniListLibraryLoadStatus({
    this.phase = AniListLibraryLoadPhase.idle,
    this.usingCache = false,
  });

  final AniListLibraryLoadPhase phase;
  final bool usingCache;

  bool get isFailed => phase == AniListLibraryLoadPhase.failed;
}

final _aniListLibraryLoadStatusProvider =
    NotifierProvider<
      _AniListLibraryLoadStatusController,
      Map<String, AniListLibraryLoadStatus>
    >(_AniListLibraryLoadStatusController.new);

class _AniListLibraryLoadStatusController
    extends Notifier<Map<String, AniListLibraryLoadStatus>> {
  @override
  Map<String, AniListLibraryLoadStatus> build() =>
      <String, AniListLibraryLoadStatus>{};

  void setStatus(String key, AniListLibraryLoadStatus status) {
    state = <String, AniListLibraryLoadStatus>{...state, key: status};
  }
}

AniListLibraryLoadStatus watchAniListLibraryLoadStatus(
  WidgetRef ref, {
  required String mediaType,
  List<AniListListStatus>? statuses,
}) {
  final String key = _aniListLibraryLoadStatusKey(
    mediaType: mediaType,
    statuses: statuses,
  );
  return ref.watch(
    _aniListLibraryLoadStatusProvider.select(
      (Map<String, AniListLibraryLoadStatus> state) =>
          state[key] ?? const AniListLibraryLoadStatus(),
    ),
  );
}

String _aniListLibraryLoadStatusKey({
  required String mediaType,
  List<AniListListStatus>? statuses,
}) {
  return '$mediaType:${_collectionScope(statuses)}';
}

void _setAniListLibraryLoadStatus(
  Ref ref, {
  required String mediaType,
  List<AniListListStatus>? statuses,
  required AniListLibraryLoadPhase phase,
  bool usingCache = false,
}) {
  ref
      .read(_aniListLibraryLoadStatusProvider.notifier)
      .setStatus(
        _aniListLibraryLoadStatusKey(mediaType: mediaType, statuses: statuses),
        AniListLibraryLoadStatus(phase: phase, usingCache: usingCache),
      );
}

final anilistAnimeListProvider =
    AsyncNotifierProvider<AniListLibraryNotifier, List<AniListAnimeListFolder>>(
      AniListLibraryNotifier.new,
    );

const List<AniListListStatus> _previewStatuses = <AniListListStatus>[
  AniListListStatus.current,
  AniListListStatus.repeating,
];

final anilistAnimePreviewListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
      return _fetchCollection(
        ref,
        mediaType: 'ANIME',
        statuses: _previewStatuses,
        flushQueue: false,
      );
    });

final anilistAnimeRussianListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
      final List<AniListAnimeListFolder> folders = await ref.watch(
        anilistAnimeListProvider.future,
      );
      return _maybeEnrichAnimeFoldersWithRussian(ref, folders: folders);
    });

final anilistAnimePreviewRussianListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
      final List<AniListAnimeListFolder> folders = await ref.watch(
        anilistAnimePreviewListProvider.future,
      );
      return _maybeEnrichAnimeFoldersWithRussian(
        ref,
        folders: folders,
        statuses: _previewStatuses,
      );
    });

final anilistMangaRussianListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
      final List<AniListAnimeListFolder> folders = await ref.watch(
        anilistMangaListProvider.future,
      );
      return _maybeEnrichAnimeFoldersWithRussian(
        ref,
        folders: folders,
        mediaType: 'MANGA',
      );
    });

final anilistMangaPreviewRussianListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
      final List<AniListAnimeListFolder> folders = await ref.watch(
        anilistMangaPreviewListProvider.future,
      );
      return _maybeEnrichAnimeFoldersWithRussian(
        ref,
        folders: folders,
        statuses: _previewStatuses,
        mediaType: 'MANGA',
      );
    });

final anilistRussianAliasProvider =
    AsyncNotifierProvider.family<
      AniListRussianAliasController,
      Map<int, String>,
      AniListRussianAliasRequest
    >(AniListRussianAliasController.new);

final anilistMangaPreviewListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
      return _fetchCollection(
        ref,
        mediaType: 'MANGA',
        statuses: _previewStatuses,
        flushQueue: false,
      );
    });

const Duration _russianAliasCacheTtl = Duration(days: 30);
const List<String> _russianAliasStatusKeys = <String>[
  'current',
  'planning',
  'completed',
  'dropped',
  'paused',
  'repeating',
];

class AniListRussianAliasRequest {
  AniListRussianAliasRequest({
    required this.viewerId,
    required this.mediaType,
    required this.statusKey,
    required Iterable<int> malIds,
    this.loadNetwork = false,
  }) : malIds = _sortedUniqueIds(malIds);

  final int? viewerId;
  final String mediaType;
  final String statusKey;
  final List<int> malIds;
  final bool loadNetwork;

  @override
  bool operator ==(Object other) {
    if (other is! AniListRussianAliasRequest) return false;
    if (other.viewerId != viewerId ||
        other.mediaType != mediaType ||
        other.statusKey != statusKey ||
        other.loadNetwork != loadNetwork ||
        other.malIds.length != malIds.length) {
      return false;
    }
    for (int index = 0; index < malIds.length; index += 1) {
      if (other.malIds[index] != malIds[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    viewerId,
    mediaType,
    statusKey,
    loadNetwork,
    Object.hashAll(malIds),
  );

  static List<int> _sortedUniqueIds(Iterable<int> ids) {
    final List<int> result = ids.where((int id) => id > 0).toSet().toList();
    result.sort();
    return result;
  }
}

class AniListRussianAliasController extends AsyncNotifier<Map<int, String>> {
  AniListRussianAliasController(this.request);

  final AniListRussianAliasRequest request;

  @override
  Future<Map<int, String>> build() async {
    if (request.mediaType != 'ANIME' || request.malIds.isEmpty) {
      return const <int, String>{};
    }

    bool disposed = false;
    ref.onDispose(() => disposed = true);

    final MetadataCacheStore cache = ref.watch(metadataCacheStoreProvider);
    final _RussianAliasCacheEntry cached = await _readRussianAliasCache(
      cache,
      request,
    );

    if (request.loadNetwork) {
      unawaited(
        _refreshRussianAliasCache(cache, cached, isDisposed: () => disposed),
      );
    }

    return cached.titlesByMalId;
  }

  Future<void> _refreshRussianAliasCache(
    MetadataCacheStore cache,
    _RussianAliasCacheEntry cached, {
    required bool Function() isDisposed,
  }) async {
    final DateTime now = DateTime.now();
    final List<int> pendingIds = <int>[];
    for (final int malId in request.malIds) {
      final DateTime? fetchedAt = cached.fetchedAtByMalId[malId];
      if (fetchedAt == null ||
          now.difference(fetchedAt) >= _russianAliasCacheTtl) {
        pendingIds.add(malId);
      }
    }
    if (pendingIds.isEmpty) return;

    final Map<int, String> fetched = await ShikiMoriClient().batchRussianTitles(
      pendingIds,
    );
    final Map<int, String> nextTitles = <int, String>{...cached.titlesByMalId};
    final Map<int, DateTime> nextFetchedAt = <int, DateTime>{
      ...cached.fetchedAtByMalId,
    };
    for (final int malId in pendingIds) {
      nextFetchedAt[malId] = now;
      final String? title = fetched[malId]?.trim();
      if (title != null && title.isNotEmpty) {
        nextTitles[malId] = title;
      }
    }

    final _RussianAliasCacheEntry updated = _RussianAliasCacheEntry(
      titlesByMalId: nextTitles,
      fetchedAtByMalId: nextFetchedAt,
    );
    await cache.write(
      _russianAliasCacheKey(request),
      _encodeRussianAliases(updated),
    );
    if (!isDisposed()) {
      state = AsyncData<Map<int, String>>(updated.titlesByMalId);
    }
  }
}

class _RussianAliasCacheEntry {
  const _RussianAliasCacheEntry({
    required this.titlesByMalId,
    required this.fetchedAtByMalId,
  });

  final Map<int, String> titlesByMalId;
  final Map<int, DateTime> fetchedAtByMalId;
}

Future<_RussianAliasCacheEntry> _readRussianAliasCache(
  MetadataCacheStore cache,
  AniListRussianAliasRequest request,
) async {
  if (request.statusKey == 'all') {
    _RussianAliasCacheEntry result = const _RussianAliasCacheEntry(
      titlesByMalId: <int, String>{},
      fetchedAtByMalId: <int, DateTime>{},
    );
    for (final String statusKey in <String>[
      'all',
      ..._russianAliasStatusKeys,
    ]) {
      final Map<String, dynamic>? json = await cache.read(
        _russianAliasCacheKey(request, statusKeyOverride: statusKey),
      );
      if (json == null) continue;
      result = _mergeRussianAliasCaches(result, _decodeRussianAliases(json));
    }
    return result;
  }

  final Map<String, dynamic>? json = await cache.read(
    _russianAliasCacheKey(request),
  );
  if (json == null) {
    return const _RussianAliasCacheEntry(
      titlesByMalId: <int, String>{},
      fetchedAtByMalId: <int, DateTime>{},
    );
  }
  return _decodeRussianAliases(json);
}

_RussianAliasCacheEntry _mergeRussianAliasCaches(
  _RussianAliasCacheEntry left,
  _RussianAliasCacheEntry right,
) {
  final Map<int, String> titles = <int, String>{...left.titlesByMalId};
  for (final MapEntry<int, String> entry in right.titlesByMalId.entries) {
    if (entry.value.trim().isNotEmpty) {
      titles[entry.key] = entry.value;
    }
  }

  final Map<int, DateTime> fetchedAt = <int, DateTime>{
    ...left.fetchedAtByMalId,
  };
  for (final MapEntry<int, DateTime> entry in right.fetchedAtByMalId.entries) {
    final DateTime? previous = fetchedAt[entry.key];
    if (previous == null || entry.value.isAfter(previous)) {
      fetchedAt[entry.key] = entry.value;
    }
  }
  return _RussianAliasCacheEntry(
    titlesByMalId: titles,
    fetchedAtByMalId: fetchedAt,
  );
}

String _russianAliasCacheKey(
  AniListRussianAliasRequest request, {
  String? statusKeyOverride,
}) {
  return 'anilist.russianAliases.'
      '${request.viewerId ?? 'viewer'}.'
      '${request.mediaType}.'
      '${statusKeyOverride ?? request.statusKey}';
}

Map<String, dynamic> _encodeRussianAliases(_RussianAliasCacheEntry entry) {
  return <String, dynamic>{
    'titlesByMalId': entry.titlesByMalId.map(
      (int key, String value) => MapEntry<String, String>('$key', value),
    ),
    'fetchedAtByMalId': entry.fetchedAtByMalId.map(
      (int key, DateTime value) =>
          MapEntry<String, String>('$key', value.toIso8601String()),
    ),
  };
}

_RussianAliasCacheEntry _decodeRussianAliases(Map<String, dynamic> json) {
  final Object? titlesRaw = json['titlesByMalId'];
  final Object? fetchedRaw = json['fetchedAtByMalId'];
  final Map<int, String> titles = <int, String>{};
  if (titlesRaw is Map) {
    for (final MapEntry<dynamic, dynamic> entry in titlesRaw.entries) {
      final int? key = int.tryParse(entry.key.toString());
      final String value = entry.value.toString().trim();
      if (key != null && key > 0 && value.isNotEmpty) {
        titles[key] = value;
      }
    }
  }

  final Map<int, DateTime> fetchedAt = <int, DateTime>{};
  if (fetchedRaw is Map) {
    for (final MapEntry<dynamic, dynamic> entry in fetchedRaw.entries) {
      final int? key = int.tryParse(entry.key.toString());
      final DateTime? value = DateTime.tryParse(entry.value.toString());
      if (key != null && key > 0 && value != null) {
        fetchedAt[key] = value;
      }
    }
  }
  return _RussianAliasCacheEntry(
    titlesByMalId: titles,
    fetchedAtByMalId: fetchedAt,
  );
}

void invalidateAniListAnimeLibraryProviders(dynamic invalidate) {
  invalidate(anilistAnimeListProvider);
  invalidate(anilistAnimePreviewListProvider);
  invalidate(anilistAnimeRussianListProvider);
  invalidate(anilistAnimePreviewRussianListProvider);
}

void invalidateAniListAnimePreviewLibraryProvider(dynamic invalidate) {
  invalidate(anilistAnimePreviewListProvider);
  invalidate(anilistAnimePreviewRussianListProvider);
}

void invalidateAniListMangaLibraryProviders(dynamic invalidate) {
  invalidate(anilistMangaListProvider);
  invalidate(anilistMangaPreviewListProvider);
  invalidate(anilistMangaRussianListProvider);
  invalidate(anilistMangaPreviewRussianListProvider);
}

void invalidateAniListMangaPreviewLibraryProvider(dynamic invalidate) {
  invalidate(anilistMangaPreviewListProvider);
  invalidate(anilistMangaPreviewRussianListProvider);
}

void invalidateAniListLibraryProviders(dynamic invalidate) {
  invalidateAniListAnimeLibraryProviders(invalidate);
  invalidateAniListMangaLibraryProviders(invalidate);
}

void invalidateAniListLibraryProvidersForMediaType(
  dynamic invalidate,
  String mediaType,
) {
  if (mediaType == 'MANGA') {
    invalidateAniListMangaLibraryProviders(invalidate);
    return;
  }
  invalidateAniListAnimeLibraryProviders(invalidate);
}

Future<void> refreshAniListLibraryForMediaType(
  WidgetRef ref, {
  required String mediaType,
}) async {
  invalidateAniListLibraryProvidersForMediaType(ref.invalidate, mediaType);
  await _awaitAniListLibraryLoadsForMediaType(ref, mediaType: mediaType);
}

Future<void> retryAniListFullListForMediaType(
  WidgetRef ref, {
  required String mediaType,
}) async {
  if (mediaType == 'MANGA') {
    ref.invalidate(anilistMangaListProvider);
    final bool wantsRussian =
        ref.read(aniListEffectiveTitleLanguageProvider) == 'RUSSIAN';
    ref.invalidate(anilistMangaRussianListProvider);
    ref.invalidate(anilistMangaPreviewRussianListProvider);
    await ref.read(anilistMangaListProvider.future);
    if (wantsRussian) {
      await ref.read(anilistMangaRussianListProvider.future);
    }
    return;
  }

  ref.invalidate(anilistAnimeListProvider);
  final bool wantsRussian =
      ref.read(aniListEffectiveTitleLanguageProvider) == 'RUSSIAN';
  if (wantsRussian) {
    ref.invalidate(anilistAnimeRussianListProvider);
  } else {
    ref.invalidate(anilistAnimeRussianListProvider);
    ref.invalidate(anilistAnimePreviewRussianListProvider);
  }

  await ref.read(anilistAnimeListProvider.future);
  if (wantsRussian) {
    await ref.read(anilistAnimeRussianListProvider.future);
  }
}

Future<void> _awaitAniListLibraryLoadsForMediaType(
  WidgetRef ref, {
  required String mediaType,
}) async {
  if (mediaType == 'MANGA') {
    final bool wantsRussianManga =
        ref.read(aniListEffectiveTitleLanguageProvider) == 'RUSSIAN';
    await ref.read(anilistMangaPreviewListProvider.future);
    if (wantsRussianManga) {
      await Future.wait<List<AniListAnimeListFolder>>(
        <Future<List<AniListAnimeListFolder>>>[
          ref.read(anilistMangaPreviewRussianListProvider.future),
          ref.read(anilistMangaListProvider.future),
        ],
      );
      await ref.read(anilistMangaRussianListProvider.future);
    } else {
      ref.invalidate(anilistMangaPreviewRussianListProvider);
      ref.invalidate(anilistMangaRussianListProvider);
      await ref.read(anilistMangaListProvider.future);
    }
    return;
  }

  final bool wantsRussian =
      ref.read(aniListEffectiveTitleLanguageProvider) == 'RUSSIAN';
  await ref.read(anilistAnimePreviewListProvider.future);
  if (wantsRussian) {
    await Future.wait<List<AniListAnimeListFolder>>(
      <Future<List<AniListAnimeListFolder>>>[
        ref.read(anilistAnimePreviewRussianListProvider.future),
        ref.read(anilistAnimeListProvider.future),
      ],
    );
    await ref.read(anilistAnimeRussianListProvider.future);
  } else {
    ref.invalidate(anilistAnimePreviewRussianListProvider);
    ref.invalidate(anilistAnimeRussianListProvider);
    await ref.read(anilistAnimeListProvider.future);
  }
}

class AniListLibraryNotifier
    extends AsyncNotifier<List<AniListAnimeListFolder>> {
  @override
  Future<List<AniListAnimeListFolder>> build() =>
      _fetchCollection(ref, mediaType: 'ANIME', flushQueue: false);

  void updateEntryProgress(
    int mediaId,
    int newProgress, {
    AniListListStatus? status,
  }) {
    final AniListAnimeListEntry? current = _entryForMediaId(mediaId);
    if (current == null) return;
    replaceEntry(
      mediaId: mediaId,
      entry: current.copyWith(progress: newProgress, status: status),
    );
  }

  void updateEntry({
    required int mediaId,
    required int progress,
    AniListListStatus? status,
    double? score,
    required String notes,
    required int repeat,
  }) {
    final AniListAnimeListEntry? current = _entryForMediaId(mediaId);
    if (current == null) return;

    replaceEntry(
      mediaId: mediaId,
      entry: AniListAnimeListEntry(
        id: current.id,
        status: status ?? current.status,
        progress: progress,
        score: score,
        mediaItem: current.mediaItem,
        notes: notes,
        repeat: repeat,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
        startedAt: current.startedAt,
        completedAt: current.completedAt,
        nextEpisode: current.nextEpisode,
        airingAt: current.airingAt,
        avgScore: current.avgScore,
        format: current.format,
      ),
    );
  }

  void replaceEntry({
    required int mediaId,
    required AniListAnimeListEntry entry,
  }) {
    final AniListAnimeListEntry? current = _entryForMediaId(mediaId);
    final AniListAnimeListEntry merged = current == null
        ? entry
        : AniListAnimeListEntry(
            id: entry.id,
            status: entry.status,
            progress: entry.progress,
            score: entry.score,
            mediaItem: current.mediaItem,
            notes: entry.notes,
            repeat: entry.repeat,
            createdAt: entry.createdAt ?? current.createdAt,
            updatedAt: entry.updatedAt ?? current.updatedAt,
            startedAt: entry.startedAt ?? current.startedAt,
            completedAt: entry.completedAt ?? current.completedAt,
            nextEpisode: entry.nextEpisode ?? current.nextEpisode,
            airingAt: entry.airingAt ?? current.airingAt,
            avgScore: entry.avgScore ?? current.avgScore,
            format: entry.format ?? current.format,
          );
    _upsertEntry(mediaId, merged);
  }

  void removeEntry(int mediaId) {
    final List<AniListAnimeListFolder>? folders = state.asData?.value;
    if (folders == null) return;
    state = AsyncValue.data(<AniListAnimeListFolder>[
      for (final AniListAnimeListFolder folder in folders)
        if (folder.entries.any(
          (AniListAnimeListEntry entry) => !_entryMatchesId(entry, mediaId),
        ))
          AniListAnimeListFolder(
            name: folder.name,
            status: folder.status,
            entries: <AniListAnimeListEntry>[
              for (final AniListAnimeListEntry entry in folder.entries)
                if (!_entryMatchesId(entry, mediaId)) entry,
            ],
          ),
    ]);
  }

  AniListAnimeListEntry? _entryForMediaId(int mediaId) {
    final List<AniListAnimeListFolder>? folders = state.asData?.value;
    if (folders == null) return null;
    for (final AniListAnimeListFolder folder in folders) {
      for (final AniListAnimeListEntry entry in folder.entries) {
        if (_entryMatchesId(entry, mediaId)) return entry;
      }
    }
    return null;
  }

  void _upsertEntry(int mediaId, AniListAnimeListEntry entry) {
    final List<AniListAnimeListFolder>? folders = state.asData?.value;
    if (folders == null) return;

    bool foundTargetFolder = false;
    final List<AniListAnimeListFolder> next = <AniListAnimeListFolder>[];
    for (final AniListAnimeListFolder folder in folders) {
      final List<AniListAnimeListEntry> entries = <AniListAnimeListEntry>[
        for (final AniListAnimeListEntry current in folder.entries)
          if (!_entryMatchesId(current, mediaId)) current,
      ];
      if (folder.status == entry.status) {
        foundTargetFolder = true;
        entries.add(entry);
      }
      if (entries.isNotEmpty) {
        next.add(
          AniListAnimeListFolder(
            name: folder.name,
            status: folder.status,
            entries: entries,
          ),
        );
      }
    }

    if (!foundTargetFolder) {
      next.add(
        AniListAnimeListFolder(
          name: entry.status.label,
          status: entry.status,
          entries: <AniListAnimeListEntry>[entry],
        ),
      );
    }

    state = AsyncValue.data(next);
  }
}

Future<List<AniListAnimeListFolder>> _enrichFoldersWithRussian(
  List<AniListAnimeListFolder> folders,
  AniListApiClient client,
) async {
  final List<MediaItem> mediaItems = <MediaItem>[];
  for (final AniListAnimeListFolder folder in folders) {
    for (final AniListAnimeListEntry entry in folder.entries) {
      mediaItems.add(entry.mediaItem);
    }
  }
  if (mediaItems.isEmpty) return folders;
  final List<MediaItem> enrichedItems = await client.enrichWithRussian(
    mediaItems,
  );
  return _replaceMediaItems(folders, <String, MediaItem>{
    for (final MediaItem item in enrichedItems) item.id: item,
  });
}

Map<String, MediaItem> _mediaItemsById(List<AniListAnimeListFolder> folders) {
  final Map<String, MediaItem> items = <String, MediaItem>{};
  for (final AniListAnimeListFolder folder in folders) {
    for (final AniListAnimeListEntry entry in folder.entries) {
      items[entry.mediaItem.id] = entry.mediaItem;
    }
  }
  return items;
}

List<AniListAnimeListFolder> _replaceMediaItems(
  List<AniListAnimeListFolder> folders,
  Map<String, MediaItem> enrichedById,
) {
  return folders
      .map((AniListAnimeListFolder folder) {
        return AniListAnimeListFolder(
          name: folder.name,
          status: folder.status,
          entries: folder.entries
              .map((AniListAnimeListEntry entry) {
                final MediaItem? enriched = enrichedById[entry.mediaItem.id];
                if (enriched == null ||
                    enriched.title == entry.mediaItem.title) {
                  return entry;
                }
                return AniListAnimeListEntry(
                  id: entry.id,
                  status: entry.status,
                  progress: entry.progress,
                  score: entry.score,
                  mediaItem: enriched,
                  notes: entry.notes,
                  repeat: entry.repeat,
                  createdAt: entry.createdAt,
                  updatedAt: entry.updatedAt,
                  startedAt: entry.startedAt,
                  completedAt: entry.completedAt,
                  nextEpisode: entry.nextEpisode,
                  airingAt: entry.airingAt,
                  avgScore: entry.avgScore,
                  format: entry.format,
                );
              })
              .toList(growable: false),
        );
      })
      .toList(growable: false);
}

String _collectionScope(List<AniListListStatus>? statuses) {
  return statuses == null || statuses.isEmpty
      ? 'all'
      : statuses
            .map((AniListListStatus status) => status.graphQlValue)
            .join('_');
}

String _resolvedAniListTitleLanguage(String mediaType, String titleLanguage) {
  // AniList has no "Russian" option, so fetch the base list in English and let
  // Shikimori supply the Russian titles afterwards — for manga as well as anime.
  if ((mediaType == 'ANIME' || mediaType == 'MANGA') &&
      titleLanguage == 'RUSSIAN') {
    return 'ENGLISH';
  }
  return titleLanguage;
}

bool _entryMatchesId(AniListAnimeListEntry entry, int mediaId) {
  final int? external = int.tryParse(
    entry.mediaItem.externalIds['anilist'] ?? '',
  );
  if (external == mediaId) return true;
  final List<String> parts = entry.mediaItem.id.split(':');
  return parts.length >= 2 &&
      parts.first == 'anilist' &&
      int.tryParse(parts.last) == mediaId;
}

final anilistMangaListProvider = FutureProvider<List<AniListAnimeListFolder>>((
  Ref ref,
) async {
  return _fetchCollection(ref, mediaType: 'MANGA', flushQueue: false);
});

Future<List<AniListAnimeListFolder>> _maybeEnrichAnimeFoldersWithRussian(
  Ref ref, {
  required List<AniListAnimeListFolder> folders,
  List<AniListListStatus>? statuses,
  String mediaType = 'ANIME',
}) async {
  if (folders.isEmpty) return folders;

  final String titleLanguage = ref.watch(aniListEffectiveTitleLanguageProvider);
  if (titleLanguage != 'RUSSIAN') {
    return folders;
  }

  final SettingsState settings = ref.watch(settingsProvider);
  final String token = settings.anilistAccessToken.trim();
  final int? viewerId = settings.anilistViewerId;
  final MetadataCacheStore cache = ref.watch(metadataCacheStoreProvider);
  final String cacheKey =
      'anilist.library.$mediaType.${_collectionScope(statuses)}.RUSSIAN.${viewerId ?? 'viewer'}';

  Future<List<AniListAnimeListFolder>> cachedOrBase() async {
    final Map<String, dynamic>? cached = await cache.read(cacheKey);
    if (cached == null) {
      return folders;
    }
    return _replaceMediaItems(folders, _mediaItemsById(_decode(cached)));
  }

  if (token.isEmpty || viewerId == null) {
    return cachedOrBase();
  }

  final AniListApiClient client = AniListApiClient(
    accessToken: token,
    titleLanguage: titleLanguage,
    shikimori: ShikiMoriClient(),
  );
  try {
    final List<AniListAnimeListFolder> enriched =
        await _enrichFoldersWithRussian(folders, client);
    await cache.write(cacheKey, _encode(enriched));
    if (statuses == null && mediaType == 'ANIME') {
      final bool airingEnabled = ref
          .read(aniListUserSettingsProvider)
          .maybeWhen(
            data: (AniListUserSettings s) => s.airingNotifications,
            orElse: () => true,
          );
      unawaited(
        AiringNotificationScheduler.syncAnimeList(
          enriched,
          enabled: airingEnabled,
          titleLanguage: 'RUSSIAN',
        ),
      );
    }
    return enriched;
  } catch (_) {
    return cachedOrBase();
  }
}

Future<List<AniListAnimeListFolder>> _fetchCollection(
  Ref ref, {
  required String mediaType,
  List<AniListListStatus>? statuses,
  bool flushQueue = true,
}) async {
  final SettingsState settings = ref.watch(settingsProvider);
  final String token = settings.anilistAccessToken.trim();
  final int? viewerId = settings.anilistViewerId;
  final MetadataCacheStore cache = ref.watch(metadataCacheStoreProvider);
  final String requestedTitleLanguage = ref.watch(
    aniListEffectiveTitleLanguageProvider,
  );
  final String titleLanguage = _resolvedAniListTitleLanguage(
    mediaType,
    requestedTitleLanguage,
  );
  final bool airingNotificationsEnabled = ref
      .watch(aniListUserSettingsProvider)
      .maybeWhen(
        data: (AniListUserSettings settings) => settings.airingNotifications,
        orElse: () => true,
      );
  if (mediaType == 'ANIME' && statuses == null && !airingNotificationsEnabled) {
    unawaited(AiringNotificationScheduler.cancelAll());
  }
  final String scope = _collectionScope(statuses);
  final String cacheKey =
      'anilist.library.$mediaType.$scope.$titleLanguage.${viewerId ?? 'viewer'}';
  if (token.isEmpty || viewerId == null) {
    if (mediaType == 'ANIME' && statuses == null) {
      unawaited(AiringNotificationScheduler.cancelAll());
    }
    final Map<String, dynamic>? cached = await cache.read(cacheKey);
    _setAniListLibraryLoadStatus(
      ref,
      mediaType: mediaType,
      statuses: statuses,
      phase: AniListLibraryLoadPhase.success,
      usingCache: cached != null,
    );
    return cached == null ? <AniListAnimeListFolder>[] : _decode(cached);
  }

  final AniListApiClient client = AniListApiClient(
    accessToken: token,
    titleLanguage: titleLanguage,
  );

  List<AniListAnimeListFolder>? fetchedFolders;
  Object? fetchError;
  try {
    if (flushQueue) {
      await ref.read(anilistEditQueueProvider).flush(token: token);
    }
    fetchedFolders = await client.fetchMediaListCollection(
      userId: viewerId,
      type: mediaType,
      statusIn: statuses
          ?.map((AniListListStatus status) => status.graphQlValue)
          .toList(growable: false),
    );
    await cache.write(cacheKey, _encode(fetchedFolders));
  } catch (error) {
    fetchError = error;
  }

  if (fetchError != null) {
    final Map<String, dynamic>? cached = await cache.read(cacheKey);
    _setAniListLibraryLoadStatus(
      ref,
      mediaType: mediaType,
      statuses: statuses,
      phase: AniListLibraryLoadPhase.failed,
      usingCache: cached != null,
    );
    return cached == null ? <AniListAnimeListFolder>[] : _decode(cached);
  }

  _setAniListLibraryLoadStatus(
    ref,
    mediaType: mediaType,
    statuses: statuses,
    phase: AniListLibraryLoadPhase.success,
  );
  if (mediaType == 'ANIME' && statuses == null) {
    unawaited(
      AiringNotificationScheduler.syncAnimeList(
        fetchedFolders!,
        enabled: airingNotificationsEnabled,
        titleLanguage: requestedTitleLanguage,
      ),
    );
  }
  return fetchedFolders!;
}

Map<String, dynamic> _encode(List<AniListAnimeListFolder> folders) {
  return <String, dynamic>{
    'folders': folders
        .map((AniListAnimeListFolder folder) => folder.toJson())
        .toList(growable: false),
  };
}

List<AniListAnimeListFolder> _decode(Map<String, dynamic> json) {
  final Object? folders = json['folders'];
  if (folders is! List<dynamic>) return const <AniListAnimeListFolder>[];
  return folders
      .whereType<Map<String, dynamic>>()
      .map(AniListAnimeListFolder.fromJson)
      .toList(growable: false);
}

class AniListEditQueue {
  const AniListEditQueue();

  static const String _key = 'anilist.pendingEdits';

  Future<void> queueAdd({
    required int mediaId,
    required AniListListStatus status,
  }) async {
    await _upsert(_QueuedAniListEdit.add(mediaId: mediaId, status: status));
  }

  Future<void> queueProgress({
    required int mediaId,
    required int progress,
    AniListListStatus? status,
  }) async {
    await _upsert(
      _QueuedAniListEdit.progress(
        mediaId: mediaId,
        progress: progress,
        status: status,
      ),
    );
  }

  Future<void> queueEntry({
    required int mediaId,
    AniListListStatus? status,
    required int progress,
    required double score,
    required String notes,
    required int repeat,
  }) async {
    await _upsert(
      _QueuedAniListEdit.entry(
        mediaId: mediaId,
        status: status,
        progress: progress,
        score: score,
        notes: notes,
        repeat: repeat,
      ),
    );
  }

  Future<void> queueDelete({required int entryId, required int mediaId}) async {
    await _upsert(
      _QueuedAniListEdit.delete(entryId: entryId, mediaId: mediaId),
    );
  }

  Future<void> flush({required String token}) async {
    if (token.trim().isEmpty) return;
    final List<_QueuedAniListEdit> edits = await _load();
    if (edits.isEmpty) return;
    final AniListApiClient client = AniListApiClient(accessToken: token);
    final List<_QueuedAniListEdit> remaining = <_QueuedAniListEdit>[];
    for (final _QueuedAniListEdit edit in edits) {
      try {
        switch (edit.kind) {
          case _QueuedAniListEditKind.add:
            await client.addToList(
              edit.mediaId,
              edit.status ?? AniListListStatus.current,
            );
          case _QueuedAniListEditKind.progress:
            await client.updateProgress(
              mediaId: edit.mediaId,
              progress: edit.progress,
              status: edit.status,
            );
          case _QueuedAniListEditKind.entry:
            await client.updateListEntry(
              mediaId: edit.mediaId,
              status: edit.status,
              progress: edit.progress,
              scoreRaw: edit.score == null
                  ? null
                  : aniListDisplayScoreToRaw(edit.score!),
              notes: edit.notes,
              repeat: edit.repeat,
            );
          case _QueuedAniListEditKind.delete:
            if (edit.entryId == null) {
              throw StateError('Queued AniList delete is missing entry id.');
            }
            await client.deleteListEntry(edit.entryId!);
        }
      } catch (_) {
        remaining.add(edit);
      }
    }
    await _save(remaining);
  }

  Future<void> _upsert(_QueuedAniListEdit edit) async {
    final List<_QueuedAniListEdit> edits = await _load();
    edits.removeWhere(
      (_QueuedAniListEdit current) =>
          current.key == edit.key ||
          (edit.kind == _QueuedAniListEditKind.delete &&
              current.mediaId == edit.mediaId),
    );
    edits.add(edit);
    await _save(edits);
  }

  Future<List<_QueuedAniListEdit>> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_key) ?? const <String>[];
    return raw
        .map((String value) {
          try {
            final Object? decoded = jsonDecode(value);
            return decoded is Map<String, dynamic>
                ? _QueuedAniListEdit.fromJson(decoded)
                : null;
          } catch (_) {
            return null;
          }
        })
        .whereType<_QueuedAniListEdit>()
        .where((_QueuedAniListEdit edit) => edit.mediaId > 0)
        .toList();
  }

  Future<void> _save(List<_QueuedAniListEdit> edits) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      edits
          .map((_QueuedAniListEdit edit) => jsonEncode(edit.toJson()))
          .toList(growable: false),
    );
  }
}

enum _QueuedAniListEditKind { add, progress, entry, delete }

class _QueuedAniListEdit {
  const _QueuedAniListEdit({
    required this.kind,
    required this.mediaId,
    required this.status,
    required this.progress,
    this.entryId,
    this.score,
    this.notes,
    this.repeat,
  });

  factory _QueuedAniListEdit.add({
    required int mediaId,
    required AniListListStatus status,
  }) {
    return _QueuedAniListEdit(
      kind: _QueuedAniListEditKind.add,
      mediaId: mediaId,
      status: status,
      progress: 0,
    );
  }

  factory _QueuedAniListEdit.progress({
    required int mediaId,
    required int progress,
    AniListListStatus? status,
  }) {
    return _QueuedAniListEdit(
      kind: _QueuedAniListEditKind.progress,
      mediaId: mediaId,
      status: status,
      progress: progress,
    );
  }

  factory _QueuedAniListEdit.entry({
    required int mediaId,
    AniListListStatus? status,
    required int progress,
    required double score,
    required String notes,
    required int repeat,
  }) {
    return _QueuedAniListEdit(
      kind: _QueuedAniListEditKind.entry,
      mediaId: mediaId,
      status: status,
      progress: progress,
      score: score,
      notes: notes,
      repeat: repeat,
    );
  }

  factory _QueuedAniListEdit.delete({
    required int entryId,
    required int mediaId,
  }) {
    return _QueuedAniListEdit(
      kind: _QueuedAniListEditKind.delete,
      entryId: entryId,
      mediaId: mediaId,
      status: AniListListStatus.planning,
      progress: 0,
    );
  }

  factory _QueuedAniListEdit.fromJson(Map<String, dynamic> json) {
    final String kindName = json['kind']?.toString() ?? 'progress';
    return _QueuedAniListEdit(
      kind: _QueuedAniListEditKind.values.firstWhere(
        (_QueuedAniListEditKind kind) => kind.name == kindName,
        orElse: () => _QueuedAniListEditKind.progress,
      ),
      entryId: int.tryParse(json['entryId']?.toString() ?? ''),
      mediaId: int.tryParse(json['mediaId']?.toString() ?? '') ?? 0,
      status: json['status'] == null
          ? null
          : AniListListStatusLabel.fromGraphQl(json['status']?.toString()),
      progress: int.tryParse(json['progress']?.toString() ?? '') ?? 0,
      score: double.tryParse(json['score']?.toString() ?? ''),
      notes: json['notes']?.toString(),
      repeat: int.tryParse(json['repeat']?.toString() ?? ''),
    );
  }

  final _QueuedAniListEditKind kind;
  final int? entryId;
  final int mediaId;
  final AniListListStatus? status;
  final int progress;
  final double? score;
  final String? notes;
  final int? repeat;

  String get key {
    if (kind == _QueuedAniListEditKind.add) {
      return '${kind.name}:$mediaId';
    }
    if (kind == _QueuedAniListEditKind.delete) {
      return '${kind.name}:${entryId ?? mediaId}';
    }
    return 'entry:$mediaId';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind.name,
      if (entryId != null) 'entryId': entryId,
      'mediaId': mediaId,
      if (status != null) 'status': status!.graphQlValue,
      'progress': progress,
      if (score != null) 'score': score,
      if (notes != null) 'notes': notes,
      if (repeat != null) 'repeat': repeat,
    };
  }
}
