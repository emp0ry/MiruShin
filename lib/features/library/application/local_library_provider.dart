import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../tracking/application/tracker_library_provider.dart';
import '../../tracking/application/tracker_sync_coordinator.dart';
import '../../watch/domain/normalized_models.dart';
import '../domain/canonical_library_models.dart';
import 'canonical_library_repository.dart';

final localLibraryProvider =
    NotifierProvider<LocalLibraryController, List<LibraryItem>>(
      LocalLibraryController.new,
    );

class LocalLibraryController extends Notifier<List<LibraryItem>> {
  static const String _baseStorageKey = 'library.localItems';
  static const String _baseEpisodeProgressKey = 'library.episodeProgress';
  SharedPreferences? _preferences;
  LibraryWorkspaceScope? _workspace;
  int _workspaceGeneration = 0;
  bool _loading = false;
  bool _episodeProgressLoaded = false;
  Future<void>? _episodeProgressLoadFuture;
  Map<String, EpisodeProgress> _episodeProgress = <String, EpisodeProgress>{};

  @override
  List<LibraryItem> build() {
    final LibraryWorkspaceScope workspace = ref.watch(
      libraryWorkspaceScopeProvider,
    );
    if (_workspace?.workspaceId != workspace.workspaceId) {
      _workspace = workspace;
      _workspaceGeneration += 1;
      _loading = false;
      _episodeProgressLoaded = false;
      _episodeProgressLoadFuture = null;
      _episodeProgress = <String, EpisodeProgress>{};
    }
    if (!_loading) {
      _loading = true;
      unawaited(_load());
      unawaited(_ensureEpisodeProgressLoaded());
    }
    return const <LibraryItem>[];
  }

  String get _storageKey => _scopedKey(_baseStorageKey);

  String get _episodeProgressKey => _scopedKey(_baseEpisodeProgressKey);

  String _scopedKey(String base) {
    final LibraryWorkspaceScope? workspace = _workspace;
    return workspace == null ? base : '$base.${workspace.replicaNamespace}';
  }

  EpisodeProgress? episodeProgress(String mediaId, int season, double episode) {
    return _episodeProgress[_episodeKey(mediaId, season, episode)];
  }

  Future<EpisodeProgress?> loadEpisodeProgress(
    String mediaId,
    int season,
    double episode,
  ) async {
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    await _ensureEpisodeProgressLoaded();
    CanonicalEpisodeProgress? canonical;
    try {
      canonical = await repository.loadEpisodeProgress(
        mediaId: mediaId,
        season: season,
        episode: episode,
      );
    } on Object {
      // A failed/opening migration must never block playback. The legacy
      // SharedPreferences checkpoint remains the safe-mode source.
    }
    if (canonical != null) {
      return EpisodeProgress(
        positionSeconds: canonical.positionSeconds,
        durationSeconds: canonical.durationSeconds,
        updatedAt: canonical.updatedAt,
        completed: canonical.completed,
      );
    }
    return episodeProgress(mediaId, season, episode);
  }

  Future<void> saveEpisodeProgress({
    required String mediaId,
    required int season,
    required double episode,
    required int positionSeconds,
    int? durationSeconds,
    bool completed = false,
    MediaItem? mediaItem,
    bool persistCanonical = true,
  }) async {
    // Capture the workspace repository before the first async gap. Reading
    // through `ref` after playback/navigation has disposed this notifier is
    // unsafe and used to surface as an unhandled Riverpod exception while the
    // app was closing or switching accounts.
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    final int generation = _workspaceGeneration;
    final MediaItem? canonicalMedia = mediaItem ?? find(mediaId)?.mediaItem;
    await _ensureEpisodeProgressLoaded();
    final bool canonical = canonicalMedia == null
        ? !mediaId.startsWith('tmdb:')
        : _isCanonicalMedia(canonicalMedia);
    if (persistCanonical && canonical) {
      try {
        await repository.saveEpisodeProgress(
          mediaId: mediaId,
          season: season,
          episode: episode,
          positionSeconds: positionSeconds,
          durationSeconds: durationSeconds,
          completed: completed,
          mediaItem: canonicalMedia,
        );
      } on Object {
        // Persist the legacy checkpoint below. A later app launch retries the
        // verified migration without losing the user's current position.
      }
    }
    if (!ref.mounted || generation != _workspaceGeneration) return;
    final String key = _episodeKey(mediaId, season, episode);
    _episodeProgress = Map<String, EpisodeProgress>.from(_episodeProgress)
      ..[key] = EpisodeProgress(
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        updatedAt: DateTime.now(),
        completed: completed,
      );
    await _persistEpisodeProgress(repository);
  }

  String _episodeKey(String mediaId, int season, double episode) =>
      '$mediaId|S${season}E$episode';

  Future<void> _ensureEpisodeProgressLoaded() {
    if (_episodeProgressLoaded) {
      return Future<void>.value();
    }
    return _episodeProgressLoadFuture ??= _loadEpisodeProgress();
  }

  Future<void> _loadEpisodeProgress() async {
    final int generation = _workspaceGeneration;
    final String storageKey = _episodeProgressKey;
    final bool importsLegacyData = _workspace?.importsLegacyData == true;
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    final SharedPreferences preferences = await _prefs();
    final Map<String, EpisodeProgress> persisted = _decodeEpisodeProgressValue(
      await repository.loadLocalEpisodeProgress(),
    );
    final Map<String, EpisodeProgress> scoped = _decodeEpisodeProgressValue(
      preferences.getString(storageKey),
    );
    final Map<String, EpisodeProgress> loaded = persisted.isNotEmpty
        ? persisted
        : scoped.isNotEmpty
        ? scoped
        : importsLegacyData
        ? _decodeEpisodeProgressValue(
            preferences.getString(_baseEpisodeProgressKey),
          )
        : <String, EpisodeProgress>{};
    if (loaded.isEmpty) {
      if (generation == _workspaceGeneration) _episodeProgressLoaded = true;
      return;
    }
    try {
      if (generation != _workspaceGeneration) return;
      _episodeProgress = loaded;
      for (final MapEntry<String, EpisodeProgress> entry in loaded.entries) {
        final RegExpMatch? match = RegExp(
          r'^(.*)\|S(-?\d+)E(.+)$',
        ).firstMatch(entry.key);
        if (match == null) continue;
        final int? season = int.tryParse(match.group(2) ?? '');
        final double? episode = double.tryParse(match.group(3) ?? '');
        if (season == null || episode == null) continue;
        final String mediaId = match.group(1)!;
        if (!_isMigratableEpisodeMediaId(mediaId)) continue;
        final EpisodeProgress value = entry.value;
        await repository.saveEpisodeProgress(
          mediaId: mediaId,
          season: season,
          episode: episode,
          positionSeconds: value.positionSeconds,
          durationSeconds: value.durationSeconds,
          completed: value.completed,
          recordActivity: false,
        );
      }
      await repository.saveLocalEpisodeProgress(_episodeProgressJson(loaded));
      await _removeMigratedPreferenceKeys(
        preferences,
        scopedKey: storageKey,
        legacyKey: _baseEpisodeProgressKey,
        removeLegacy: importsLegacyData,
      );
    } catch (_) {
      // Ignore corrupt progress cache and start fresh instead of blocking playback.
    } finally {
      if (generation == _workspaceGeneration) _episodeProgressLoaded = true;
    }
  }

  Future<void> _persistEpisodeProgress(
    CanonicalLibraryRepository repository,
  ) async {
    try {
      await repository.saveLocalEpisodeProgress(
        _episodeProgressJson(_episodeProgress),
      );
    } on Object {
      // A container can close while a final playback checkpoint is in flight.
      // The canonical checkpoint above already owns durable progress; teardown
      // must never turn this best-effort compatibility cache into a crash.
    }
  }

  Map<String, EpisodeProgress> _decodeEpisodeProgressValue(Object? raw) {
    if (raw == null || raw == '') return <String, EpisodeProgress>{};
    try {
      final Object? decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return <String, EpisodeProgress>{};
      final Map<String, EpisodeProgress> result = <String, EpisodeProgress>{};
      for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final EpisodeProgress value = EpisodeProgress.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        final String key = _compactEpisodeProgressKey(entry.key as String);
        final EpisodeProgress? existing = result[key];
        if (existing == null || value.updatedAt.isAfter(existing.updatedAt)) {
          result[key] = value;
        }
      }
      return result;
    } on Object {
      return <String, EpisodeProgress>{};
    }
  }

  Map<String, dynamic> _episodeProgressJson(
    Map<String, EpisodeProgress> values,
  ) => values.map(
    (String itemKey, EpisodeProgress value) =>
        MapEntry<String, dynamic>(itemKey, value.toJson()),
  );

  String _compactEpisodeProgressKey(String key) {
    final RegExpMatch? match = RegExp(r'^(.*)\|S(-?\d+)E(.+)$').firstMatch(key);
    if (match == null) return key;
    final String mediaId = compactSoraEpisodeProgressMediaId(match.group(1)!);
    return '$mediaId|S${match.group(2)}E${match.group(3)}';
  }

  LibraryItem? find(String mediaId) {
    for (final LibraryItem item in state) {
      if (item.mediaItem.id == mediaId) {
        return item;
      }
    }
    return null;
  }

  Future<void> addToLibrary(
    MediaItem media, {
    LibraryStatus status = LibraryStatus.planned,
    double progress = 0,
  }) async {
    final int generation = _workspaceGeneration;
    final TrackerSyncCoordinator coordinator = ref.read(
      trackerSyncCoordinatorProvider,
    );
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    final DateTime now = DateTime.now();
    final LibraryItem? existing = find(media.id);
    if (_isCanonicalMedia(media)) {
      final int total = media.episodeCount ?? 0;
      final int canonicalProgress = total > 0
          ? (progress.clamp(0.0, 1.0) * total).round()
          : (progress >= 1 ? 1 : 0);
      await coordinator.pushEntryEdit(
        externalIds: media.externalIds,
        mediaId: media.id,
        mediaTitle: media.title,
        mediaItem: media,
        status: _trackerStatus(status),
        progress: canonicalProgress,
      );
      if (!ref.mounted || generation != _workspaceGeneration) return;
      ref.invalidate(
        _isManga(media)
            ? trackerLocalMangaLibraryProvider
            : trackerLocalAnimeLibraryProvider,
      );
    }
    final LibraryItem item = LibraryItem(
      id: existing?.id ?? 'local:${media.id}',
      mediaItem: media,
      status: status,
      progress: progress,
      addedAt: existing?.addedAt ?? now,
      updatedAt: now,
      trackingSyncState: 'Local',
    );

    state = <LibraryItem>[
      item,
      ...state.where((LibraryItem current) => current.mediaItem.id != media.id),
    ];
    await _persist(repository);
  }

  Future<void> markWatched(MediaItem media) {
    return addToLibrary(media, status: LibraryStatus.completed, progress: 1);
  }

  /// Updates a local item's progress to reflect the furthest episode reached
  /// (cumulative episode index across seasons / total episodes). Progress is
  /// monotonic, so jumping back to an earlier episode never lowers it. For movies
  /// the playback [positionFraction] is used instead. No-op when the media is
  /// not in the local library (we never auto-add items here).
  Future<void> updateWatchProgress({
    required String mediaId,
    required int seasonNumber,
    required double episodeNumber,
    double? positionFraction,
  }) async {
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    final LibraryItem? existing = find(mediaId);
    if (existing == null) return;

    final double fraction = _furthestProgressFraction(
      media: existing.mediaItem,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      positionFraction: positionFraction,
    );
    if (fraction <= existing.progress) return;

    final LibraryItem updated = LibraryItem(
      id: existing.id,
      mediaItem: existing.mediaItem,
      status: existing.status,
      progress: fraction,
      addedAt: existing.addedAt,
      updatedAt: DateTime.now(),
      trackingSyncState: existing.trackingSyncState,
    );
    // Replace in place so playback doesn't reorder the library list.
    state = <LibraryItem>[
      for (final LibraryItem item in state)
        if (item.mediaItem.id == mediaId) updated else item,
    ];
    await _persist(repository);
  }

  double _furthestProgressFraction({
    required MediaItem media,
    required int seasonNumber,
    required double episodeNumber,
    double? positionFraction,
  }) {
    final List<MediaSeason> seasons = media.seasons
        .where((MediaSeason s) => !s.isSpecials && s.episodeCount > 0)
        .toList(growable: false);

    int total = seasons.fold<int>(
      0,
      (int sum, MediaSeason s) => sum + s.episodeCount,
    );
    if (total <= 0) total = media.episodeCount ?? 0;

    // Movies / items without a real episode structure: use playback position.
    if (media.type == MediaType.movie || total <= 1) {
      return (positionFraction ?? 0).clamp(0.0, 1.0);
    }

    int episodesBefore = 0;
    for (final MediaSeason s in seasons) {
      if (s.seasonNumber < seasonNumber) {
        episodesBefore += s.episodeCount;
      }
    }

    final int reached = episodesBefore + episodeNumber.round();
    return (reached / total).clamp(0.0, 1.0);
  }

  Future<void> remove(String mediaId) async {
    final int generation = _workspaceGeneration;
    final TrackerSyncCoordinator coordinator = ref.read(
      trackerSyncCoordinatorProvider,
    );
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    final LibraryItem? existing = find(mediaId);
    if (existing != null && _isCanonicalMedia(existing.mediaItem)) {
      await coordinator.deleteEntry(
        externalIds: existing.mediaItem.externalIds,
        mediaId: existing.mediaItem.id,
        mediaTitle: existing.mediaItem.title,
      );
      if (!ref.mounted || generation != _workspaceGeneration) return;
      ref.invalidate(
        _isManga(existing.mediaItem)
            ? trackerLocalMangaLibraryProvider
            : trackerLocalAnimeLibraryProvider,
      );
    }
    state = state
        .where((LibraryItem item) => item.mediaItem.id != mediaId)
        .toList(growable: false);
    await _persist(repository);
  }

  bool _isCanonicalMedia(MediaItem media) {
    final bool hasTrackerIdentity =
        media.externalIds['anilist_type'] == 'MANGA' ||
        media.externalIds.containsKey('anilist') ||
        media.externalIds.containsKey('mal') ||
        media.externalIds.containsKey('shikimori');
    if (hasTrackerIdentity) return true;

    // TMDB movies/series, including the anime-flavoured TMDB catalog, keep
    // using the existing shared local storage. Only anime/manga owned by the
    // canonical tracker library is isolated per AniList workspace.
    if (media.id.startsWith('tmdb:')) return false;
    return media.type == MediaType.anime;
  }

  bool _isManga(MediaItem media) =>
      media.externalIds['anilist_type']?.toUpperCase() == 'MANGA' ||
      media.id.contains(':manga:');

  bool _isMigratableEpisodeMediaId(String mediaId) =>
      mediaId.startsWith('anilist:') ||
      mediaId.startsWith('mal:') ||
      mediaId.startsWith('shikimori:');

  AniListListStatus _trackerStatus(LibraryStatus status) => switch (status) {
    LibraryStatus.watching => AniListListStatus.current,
    LibraryStatus.completed => AniListListStatus.completed,
    LibraryStatus.dropped => AniListListStatus.dropped,
    LibraryStatus.planned ||
    LibraryStatus.favorite ||
    LibraryStatus.local => AniListListStatus.planning,
  };

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<void> _load() async {
    final int generation = _workspaceGeneration;
    final String storageKey = _storageKey;
    final bool importsLegacyData = _workspace?.importsLegacyData == true;
    final CanonicalLibraryRepository repository = ref.read(
      canonicalLibraryRepositoryProvider,
    );
    final SharedPreferences preferences = await _prefs();
    final List<LibraryItem> persisted = await repository
        .loadLocalLibraryItems();
    final List<LibraryItem> scoped = _decodeLibraryItems(
      preferences.getString(storageKey),
    );
    final List<LibraryItem> loaded = persisted.isNotEmpty
        ? persisted
        : scoped.isNotEmpty
        ? scoped
        : importsLegacyData
        ? _decodeLibraryItems(preferences.getString(_baseStorageKey))
        : const <LibraryItem>[];
    if (loaded.isEmpty) {
      return;
    }

    try {
      await repository.importLegacyLocalLibrary(loaded);
      await repository.saveLocalLibraryItems(loaded);
      await _removeMigratedPreferenceKeys(
        preferences,
        scopedKey: storageKey,
        legacyKey: _baseStorageKey,
        removeLegacy: importsLegacyData,
      );
      if (!ref.mounted || generation != _workspaceGeneration) return;
      if (state.isEmpty) {
        state = loaded;
        return;
      }

      final Set<String> currentIds = state
          .map((LibraryItem item) => item.mediaItem.id)
          .toSet();
      state = <LibraryItem>[
        ...state,
        ...loaded.where(
          (LibraryItem item) => !currentIds.contains(item.mediaItem.id),
        ),
      ];
      await _persist(repository);
    } catch (_) {
      if (ref.mounted && generation == _workspaceGeneration) {
        state = const <LibraryItem>[];
      }
    }
  }

  Future<void> _persist(CanonicalLibraryRepository repository) =>
      repository.saveLocalLibraryItems(state);

  List<LibraryItem> _decodeLibraryItems(String? raw) {
    if (raw == null || raw.isEmpty) return <LibraryItem>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <LibraryItem>[];
      return decoded
          .whereType<Map>()
          .map(
            (Map<dynamic, dynamic> value) =>
                LibraryItem.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((LibraryItem item) => item.mediaItem.id.isNotEmpty)
          .toList(growable: false);
    } on Object {
      return <LibraryItem>[];
    }
  }

  Future<void> _removeMigratedPreferenceKeys(
    SharedPreferences preferences, {
    required String scopedKey,
    required String legacyKey,
    required bool removeLegacy,
  }) async {
    await preferences.remove(scopedKey);
    if (removeLegacy && scopedKey != legacyKey) {
      await preferences.remove(legacyKey);
    }
  }
}
