import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../library/application/canonical_library_repository.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/application/settings_state.dart';
import '../data/anilist_api_client.dart';
import '../data/canonical_tracking_sync_store.dart';
import '../data/mal_api_client.dart';
import '../data/shikimori_api_client.dart';
import '../data/tracking_sync_store.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';
import 'local_first_sync_engine.dart';

final trackingSyncStoreProvider = Provider<TrackingSyncStore>(
  (Ref ref) => CanonicalTrackingSyncStore(
    repository: ref.watch(canonicalLibraryRepositoryProvider),
  ),
);

final trackerProviderHealthProvider =
    FutureProvider<Map<TrackerSource, TrackerProviderHealth>>((Ref ref) {
      return ref.watch(trackingSyncStoreProvider).loadHealth();
    });

final trackerSyncCoordinatorProvider = Provider<TrackerSyncCoordinator>(
  (Ref ref) => TrackerSyncCoordinator(ref),
);

class TrackerLibrarySnapshot {
  const TrackerLibrarySnapshot({
    required this.folders,
    this.remoteSource,
    required this.fromCache,
  });

  final List<AniListAnimeListFolder> folders;
  final TrackerSource? remoteSource;
  final bool fromCache;
}

class TrackerEpisodeProgress {
  const TrackerEpisodeProgress({required this.progress, required this.status});

  final int progress;
  final AniListListStatus status;
}

/// Converts an addon's watched episode into a tracker-safe update. Extra addon
/// videos may be numbered beyond the AniList/MAL episode count, but tracker
/// progress must remain within the canonical total.
TrackerEpisodeProgress normalizeTrackerEpisodeProgress({
  required int episode,
  required int? total,
  AniListListStatus? currentStatus,
  String? mediaStatus,
}) {
  final int progress = canonicalEpisodeProgress(episode, total);
  final String normalizedMediaStatus = (mediaStatus ?? '').trim().toUpperCase();
  final bool explicitlyStillReleasing = <String>{
    'RELEASING',
    'NOT_YET_RELEASED',
    'CURRENTLY_AIRING',
    'NOT_YET_AIRED',
  }.contains(normalizedMediaStatus);
  final bool reachedKnownEnd =
      total != null &&
      total > 0 &&
      episode >= total &&
      !explicitlyStillReleasing;
  final AniListListStatus status = currentStatus == AniListListStatus.repeating
      ? AniListListStatus.repeating
      : reachedKnownEnd
      ? AniListListStatus.completed
      : AniListListStatus.current;
  return TrackerEpisodeProgress(progress: progress, status: status);
}

bool trackerEpisodeUpdateNeeded({
  required UserMediaState? current,
  required TrackerEpisodeProgress update,
  required int? total,
}) {
  if (current == null) return true;
  final bool repairsOverflow =
      total != null && total > 0 && current.progress > total;
  final bool completesCurrent =
      update.status == AniListListStatus.completed &&
      current.status != AniListListStatus.completed;
  final bool advancesProgress = update.progress > current.progress;
  if (current.status == AniListListStatus.completed && !repairsOverflow) {
    return false;
  }
  return repairsOverflow || completesCurrent || advancesProgress;
}

const Set<UserMediaField> _aniListEntryFields = <UserMediaField>{
  UserMediaField.status,
  UserMediaField.progress,
  UserMediaField.progressVolumes,
  UserMediaField.score,
  UserMediaField.notes,
  UserMediaField.repeat,
  UserMediaField.startedAt,
  UserMediaField.completedAt,
  UserMediaField.priority,
  UserMediaField.private,
  UserMediaField.hiddenFromStatusLists,
  UserMediaField.customLists,
  UserMediaField.advancedScores,
};

const Set<UserMediaField> _malEntryFields = <UserMediaField>{
  UserMediaField.status,
  UserMediaField.progress,
  UserMediaField.progressVolumes,
  UserMediaField.score,
  UserMediaField.notes,
  UserMediaField.repeat,
  UserMediaField.startedAt,
  UserMediaField.completedAt,
  UserMediaField.malPriority,
  UserMediaField.malRewatchValue,
  UserMediaField.malTags,
};

const Set<UserMediaField> _shikimoriEntryFields = <UserMediaField>{
  UserMediaField.status,
  UserMediaField.progress,
  UserMediaField.progressVolumes,
  UserMediaField.score,
  UserMediaField.notes,
  UserMediaField.repeat,
};

/// Application facade over the provider-neutral local-first engine. It decides
/// which authenticated adapters are available, while the engine owns local
/// state, identity reconciliation, conflict policy and journal replay.
class TrackerSyncCoordinator {
  TrackerSyncCoordinator(this._ref);

  final Ref _ref;
  // User mutations and remote work deliberately have separate lanes. A slow
  // tracker refresh/flush must never keep Add/Edit/Delete waiting before its
  // canonical SQLite transaction can commit.
  Future<void> _mutationTail = Future<void>.value();
  Future<void> _networkTail = Future<void>.value();

  SettingsState get _settings => _ref.read(settingsProvider);
  SettingsController get _controller => _ref.read(settingsProvider.notifier);
  TrackingSyncStore get _store => _ref.read(trackingSyncStoreProvider);

  Future<SyncDispatchResult> pushEpisodeProgress({
    required Map<String, String> externalIds,
    required int episode,
    int? total,
    String? mediaId,
    String? mediaTitle,
    MediaItem? mediaItem,
    Set<TrackerSource>? targets,
    TrackingEpisodeCheckpoint? episodeCheckpoint,
  }) async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      externalIds,
      mediaId: mediaId,
    );
    final List<UserMediaState> cached = await _store.loadStates();
    UserMediaState? matched;
    for (final UserMediaState state in cached) {
      if (!state.identity.matches(identity)) continue;
      matched = state;
      break;
    }
    final int? canonicalTotal = mediaItem?.episodeCount ?? total;
    final TrackerEpisodeProgress update = normalizeTrackerEpisodeProgress(
      episode: episode,
      total: canonicalTotal,
      currentStatus: matched?.status,
      mediaStatus: mediaItem?.statusLabel,
    );
    if (!trackerEpisodeUpdateNeeded(
      current: matched,
      update: update,
      total: canonicalTotal,
    )) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }
    return pushEntryEdit(
      externalIds: externalIds,
      mediaId: mediaId,
      mediaTitle: mediaTitle,
      mediaItem: mediaItem,
      status: update.status,
      progress: update.progress,
      startedAt: matched?.startedAt == null && update.progress > 0
          ? DateTime.now().toUtc()
          : null,
      completedAt:
          update.status == AniListListStatus.completed &&
              matched?.completedAt == null
          ? DateTime.now().toUtc()
          : null,
      targets: targets,
      episodeCheckpoint: episodeCheckpoint,
    );
  }

  Future<SyncDispatchResult> pushEntryEdit({
    required Map<String, String> externalIds,
    String? mediaId,
    String? mediaTitle,
    MediaItem? mediaItem,
    AniListListStatus? status,
    int? progress,
    int? progressVolumes,
    double? score,
    String? notes,
    int? repeat,
    DateTime? startedAt,
    DateTime? completedAt,
    int? priority,
    bool? private,
    bool? hiddenFromStatusLists,
    Map<String, bool>? customLists,
    Map<String, double>? advancedScores,
    String? scoreFormat,
    int? malPriority,
    int? malRewatchValue,
    List<String>? malTags,
    Set<UserMediaField>? fields,
    Set<TrackerSource>? targets,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
    TrackingEpisodeCheckpoint? episodeCheckpoint,
  }) => _serialMutation<SyncDispatchResult>(() async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      externalIds,
      mediaId: mediaId,
    );
    final Set<TrackerSource> resolvedTargets =
        targets ?? _connectedTargets(identity);
    final int? canonicalTotal = mediaItem?.episodeCount;
    final int? safeProgress = progress == null
        ? null
        : canonicalEpisodeProgress(progress, canonicalTotal);
    final LocalFirstSyncEngine engine = _localEngine();
    final SyncDispatchResult result = await engine.recordMutation(
      identity: identity,
      patch: UserMediaPatch(
        status: status,
        progress: safeProgress,
        progressVolumes: progressVolumes,
        score: score,
        notes: notes,
        repeat: repeat,
        startedAt: startedAt,
        completedAt: completedAt,
        priority: priority,
        private: private,
        hiddenFromStatusLists: hiddenFromStatusLists,
        customLists: customLists,
        advancedScores: advancedScores,
        scoreFormat: scoreFormat,
        malPriority: malPriority,
        malRewatchValue: malRewatchValue,
        malTags: malTags,
        fields: fields,
      ),
      targets: resolvedTargets,
      mediaItem: mediaItem,
      mediaTitle: mediaTitle,
      providerEntryIds: providerEntryIds,
      backgroundDelivery: true,
      episodeCheckpoint: episodeCheckpoint,
    );
    unawaited(flushPending());
    _invalidateHealth();
    return result;
  });

  Future<SyncDispatchResult> pushFavorite({
    required MediaItem mediaItem,
    required bool favorite,
  }) => _serialMutation<SyncDispatchResult>(() async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      mediaItem.externalIds,
      mediaId: mediaItem.id,
    );
    final bool canSyncAniList =
        (identity.anilistId != null || identity.malId != null) &&
        _settings.anilistAccessToken.trim().isNotEmpty;
    final LocalFirstSyncEngine engine = _localEngine();
    final SyncDispatchResult result = await engine.recordMutation(
      identity: identity,
      patch: UserMediaPatch(favorite: favorite),
      targets: <TrackerSource>{if (canSyncAniList) TrackerSource.anilist},
      mediaItem: mediaItem,
      mediaTitle: mediaItem.title,
      backgroundDelivery: true,
    );
    unawaited(flushPending());
    _invalidateHealth();
    return result;
  });

  Future<SyncDispatchResult> deleteEntry({
    required Map<String, String> externalIds,
    String? mediaId,
    String? mediaTitle,
    Set<TrackerSource>? targets,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
  }) => _serialMutation<SyncDispatchResult>(() async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      externalIds,
      mediaId: mediaId,
    );
    final LocalFirstSyncEngine engine = _localEngine();
    final SyncDispatchResult result = await engine.recordMutation(
      identity: identity,
      patch: UserMediaPatch(delete: true),
      targets: targets ?? _connectedTargets(identity),
      mediaTitle: mediaTitle,
      providerEntryIds: providerEntryIds,
      backgroundDelivery: true,
    );
    unawaited(flushPending());
    _invalidateHealth();
    return result;
  });

  Future<void> flushPending() => _serialNetwork<void>(() async {
    final LocalFirstSyncEngine engine = await _engine();
    await engine.flush();
    _invalidateHealth();
  });

  Future<TrackerLibrarySnapshot> refreshAnimeLibrary({
    required TrackerSource preferred,
    Set<TrackerSource> excluded = const <TrackerSource>{},
  }) => _serialNetwork<TrackerLibrarySnapshot>(() async {
    final LocalFirstSyncEngine engine = await _engine();
    final List<TrackerSource> order =
        <TrackerSource>[
              preferred,
              TrackerSource.anilist,
              TrackerSource.mal,
              TrackerSource.shikimori,
            ]
            .where((TrackerSource source) => !excluded.contains(source))
            .toSet()
            .toList();
    final LocalFirstLibraryResult result = await engine.refreshAnimeList(
      providerOrder: order,
      cacheSource: preferred,
    );
    _invalidateHealth();
    return TrackerLibrarySnapshot(
      folders: foldersFromUserMediaStates(result.states),
      remoteSource: result.remoteSource,
      fromCache: result.fromCache,
    );
  });

  Future<TrackerLibrarySnapshot> refreshMangaLibrary({
    required TrackerSource preferred,
    Set<TrackerSource> excluded = const <TrackerSource>{},
  }) => _serialNetwork<TrackerLibrarySnapshot>(() async {
    final LocalFirstSyncEngine engine = await _engine();
    final List<TrackerSource> order =
        <TrackerSource>[
              preferred,
              TrackerSource.anilist,
              TrackerSource.mal,
              TrackerSource.shikimori,
            ]
            .where((TrackerSource source) => !excluded.contains(source))
            .toSet()
            .toList();
    final LocalFirstLibraryResult result = await engine.refreshAnimeList(
      providerOrder: order,
      cacheSource: preferred,
      mediaKind: 'manga',
    );
    _invalidateHealth();
    return TrackerLibrarySnapshot(
      folders: foldersFromUserMediaStates(
        result.states
            .where(
              (UserMediaState state) => state.identity.mediaKind == 'manga',
            )
            .toList(growable: false),
      ),
      remoteSource: result.remoteSource,
      fromCache: result.fromCache,
    );
  });

  /// Reconciles a complete authenticated snapshot from every connected
  /// tracker instead of stopping after the first provider that responds.
  Future<TrackerLibrarySnapshot> refreshAllConnectedLibraries({
    String mediaKind = 'anime',
    Set<TrackerSource> excluded = const <TrackerSource>{},
  }) => _serialNetwork<TrackerLibrarySnapshot>(() async {
    final LocalFirstSyncEngine engine = await _engine();
    final List<TrackerSource> order =
        <TrackerSource>[
              TrackerSource.anilist,
              TrackerSource.mal,
              TrackerSource.shikimori,
            ]
            .where((TrackerSource source) => !excluded.contains(source))
            .toSet()
            .toList();
    final LocalFirstLibraryResult result = await engine
        .refreshAllProviderSnapshots(
          providerOrder: order,
          mediaKind: mediaKind,
        );
    _invalidateHealth();
    final List<UserMediaState> states = result.states
        .where((UserMediaState state) => state.identity.mediaKind == mediaKind)
        .toList(growable: false);
    return TrackerLibrarySnapshot(
      folders: foldersFromUserMediaStates(states),
      remoteSource: result.remoteSource,
      fromCache: result.fromCache,
    );
  });

  Future<List<AniListAnimeListFolder>> ingestAnimeLibrary({
    required TrackerSource source,
    required List<AniListAnimeListFolder> folders,
    required bool liveSnapshot,
    required bool completeSnapshot,
    String mediaKind = 'anime',
  }) => _serialNetwork<List<AniListAnimeListFolder>>(() async {
    final List<UserMediaState> remote = userMediaStatesFromFolders(
      folders,
      source: source,
    );
    final TrackingSyncStore store = _store;
    if (liveSnapshot &&
        completeSnapshot &&
        store is ReconciliationTrackingSyncStore) {
      final SettingsState settings = _settings;
      final String accountId = switch (source) {
        TrackerSource.anilist => '${settings.anilistViewerId ?? 'unknown'}',
        TrackerSource.mal => '${settings.malViewerId ?? 'unknown'}',
        TrackerSource.shikimori => '${settings.shikimoriViewerId ?? 'unknown'}',
      };
      final Set<TrackerSource> propagationTargets = <TrackerSource>{
        if (settings.hasAniListSession) TrackerSource.anilist,
        if (settings.hasMalSession) TrackerSource.mal,
        if (settings.hasShikimoriSession) TrackerSource.shikimori,
      }..remove(source);
      final ProviderReconciliationResult result =
          await (store as ReconciliationTrackingSyncStore)
              .reconcileProviderSnapshot(
                source: source,
                accountId: accountId,
                mediaKind: mediaKind,
                remote: remote,
                journal: await store.loadJournal(),
                propagationTargets: propagationTargets,
                completeSnapshot: true,
              );
      await store.saveJournal(result.journal);
      _invalidateHealth();
      return foldersFromUserMediaStates(
        result.states
            .where(
              (UserMediaState state) => state.identity.mediaKind == mediaKind,
            )
            .toList(growable: false),
      );
    }
    final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
      store: _store,
      adapters: const <TrackerSource, TrackerProviderAdapter>{},
      primary: _settings.effectivePrimaryTrackerSource,
    );
    final List<UserMediaState> merged = await engine.ingestRemoteStates(
      remote,
      snapshotSource: source,
      confirmRemoteMutations: liveSnapshot && completeSnapshot,
      incomingProviderIsAuthoritative: liveSnapshot,
      incomingAiringIsAuthoritative:
          liveSnapshot && source == TrackerSource.anilist,
    );
    await engine.recordSuccess(source);
    _invalidateHealth();
    return foldersFromUserMediaStates(
      merged
          .where(
            (UserMediaState state) => state.identity.mediaKind == mediaKind,
          )
          .toList(growable: false),
    );
  });

  Future<List<AniListAnimeListFolder>> cachedAnimeLibrary() async {
    return foldersFromUserMediaStates(await _store.loadStates());
  }

  Future<void> recordProviderFailure(TrackerSource source, Object error) =>
      _serialNetwork<void>(() async {
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: _store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          primary: _settings.effectivePrimaryTrackerSource,
        );
        await engine.recordFailure(source, error);
        _invalidateHealth();
      });

  Future<void> recordProviderSuccess(TrackerSource source) =>
      _serialNetwork<void>(() async {
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: _store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          primary: _settings.effectivePrimaryTrackerSource,
        );
        await engine.recordSuccess(source);
        _invalidateHealth();
      });

  Set<TrackerSource> _connectedTargets(MediaIdentity identity) {
    final SettingsState settings = _settings;
    return <TrackerSource>{
      if (settings.anilistAccessToken.trim().isNotEmpty &&
          (identity.anilistId != null || identity.malId != null))
        TrackerSource.anilist,
      if (settings.hasMalSession && identity.malId != null) TrackerSource.mal,
      if (settings.hasShikimoriSession) TrackerSource.shikimori,
    };
  }

  Future<LocalFirstSyncEngine> _engine() async {
    return LocalFirstSyncEngine(
      store: _store,
      adapters: await _adapters(),
      primary: _settings.effectivePrimaryTrackerSource,
    );
  }

  LocalFirstSyncEngine _localEngine() => LocalFirstSyncEngine(
    store: _store,
    adapters: const <TrackerSource, TrackerProviderAdapter>{},
    primary: _settings.effectivePrimaryTrackerSource,
  );

  Future<Map<TrackerSource, TrackerProviderAdapter>> _adapters() async {
    final SettingsState settings = _settings;
    final Map<TrackerSource, TrackerProviderAdapter> adapters =
        <TrackerSource, TrackerProviderAdapter>{};
    MalApiClient? malMetadataClient;

    final String aniListToken = settings.anilistAccessToken.trim();
    if (aniListToken.isNotEmpty) {
      final String titleLanguage = _ref
          .read(aniListEffectiveTitleLanguageProvider)
          .trim();
      adapters[TrackerSource.anilist] = _AniListAdapter(
        client: AniListApiClient(
          accessToken: aniListToken,
          titleLanguage: titleLanguage == 'RUSSIAN' ? 'ENGLISH' : titleLanguage,
        ),
        viewerId: settings.anilistViewerId,
      );
    }

    if (settings.hasMalSession) {
      final String? token = await _controller.validMalAccessToken();
      if (token != null && token.trim().isNotEmpty) {
        malMetadataClient = MalApiClient(
          accessToken: token,
          onRefreshToken: _controller.refreshMalToken,
        );
        adapters[TrackerSource.mal] = _MalAdapter(
          malMetadataClient,
          settings.malViewerId!,
        );
      }
    }

    final int? shikimoriViewerId = settings.shikimoriViewerId;
    if (settings.hasShikimoriSession && shikimoriViewerId != null) {
      final String? token = await _controller.validShikimoriAccessToken();
      if (token != null && token.trim().isNotEmpty) {
        adapters[TrackerSource.shikimori] = _ShikimoriAdapter(
          ShikimoriApiClient(
            accessToken: token,
            userId: shikimoriViewerId,
            onRefreshToken: _controller.refreshShikimoriToken,
          ),
          shikimoriViewerId,
          enrichFromMal: malMetadataClient == null
              ? null
              : (int malId, String mediaKind) => mediaKind == 'manga'
                    ? malMetadataClient!.fetchMangaDetails(malId)
                    : malMetadataClient!.fetchAnimeDetails(malId),
          onResolvedIdentity: (MediaIdentity identity, int shikimoriId) {
            return _ref
                .read(canonicalLibraryRepositoryProvider)
                .attachVerifiedProviderBinding(
                  identity: identity,
                  provider: TrackerSource.shikimori,
                  externalMediaId: shikimoriId,
                  evidence: 'exact_mal_id_lookup',
                );
          },
        );
      }
    }
    return adapters;
  }

  void _invalidateHealth() {
    _ref.invalidate(trackerProviderHealthProvider);
  }

  Future<T> _serialMutation<T>(Future<T> Function() action) =>
      _serialOn<T>(action, mutation: true);

  Future<T> _serialNetwork<T>(Future<T> Function() action) =>
      _serialOn<T>(action, mutation: false);

  Future<T> _serialOn<T>(
    Future<T> Function() action, {
    required bool mutation,
  }) {
    final Completer<void> release = Completer<void>();
    final Future<void> previous = mutation ? _mutationTail : _networkTail;
    if (mutation) {
      _mutationTail = release.future;
    } else {
      _networkTail = release.future;
    }
    return previous.then((_) => action()).whenComplete(release.complete);
  }
}

class _AniListAdapter implements TrackerProviderAdapter {
  _AniListAdapter({required this.client, required this.viewerId});

  final AniListApiClient client;
  final int? viewerId;

  @override
  TrackerSource get source => TrackerSource.anilist;

  @override
  String get accountId => '${viewerId ?? 'unknown'}';

  @override
  Future<List<UserMediaState>> fetchAnimeList() async {
    try {
      final List<AniListAnimeListFolder> folders = await client
          .fetchMediaListCollection(userId: viewerId, type: 'ANIME');
      return userMediaStatesFromFolders(folders, source: source);
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

  @override
  Future<List<UserMediaState>> fetchMangaList() async {
    try {
      final List<AniListAnimeListFolder> folders = await client
          .fetchMediaListCollection(userId: viewerId, type: 'MANGA');
      return userMediaStatesFromFolders(folders, source: source);
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

  @override
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    try {
      int? mediaId = mutation.identity.anilistId;
      final int? malId = mutation.identity.malId;
      if (mediaId == null && malId != null) {
        final MediaItem? resolved = mutation.identity.mediaKind == 'manga'
            ? await client.resolveMangaByMalId(malId)
            : await client.resolveAnimeByMalId(malId);
        mediaId = int.tryParse(resolved?.externalIds['anilist'] ?? '');
      }
      if (mediaId == null) {
        throw const UnresolvedProviderIdentityException(TrackerSource.anilist);
      }
      if (mutation.patch.touches(UserMediaField.favorite)) {
        final bool desired = mutation.patch.favorite ?? false;
        final bool? current = await client.fetchMediaFavouriteStatus(mediaId);
        if (current != desired) {
          await client.toggleFavouriteMedia(
            mediaId: mediaId,
            isManga: mutation.identity.mediaKind == 'manga',
          );
        }
      }
      if (mutation.patch.delete) {
        int? entryId = mutation.providerEntryIds[source];
        entryId ??= (await client.fetchMediaListEntry(
          userId: viewerId,
          mediaId: mediaId,
        ))?.id;
        if (entryId == null) return;
        await client.deleteListEntry(entryId);
        return;
      }
      if (!mutation.patch.fields.any(_aniListEntryFields.contains)) return;
      await client.updateListEntry(
        mediaId: mediaId,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        progress: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        progressVolumes: mutation.patch.touches(UserMediaField.progressVolumes)
            ? mutation.patch.progressVolumes
            : null,
        scoreRaw: mutation.patch.touches(UserMediaField.score)
            ? aniListDisplayScoreToRaw(mutation.patch.score ?? 0)
            : null,
        notes: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes
            : null,
        repeat: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat
            : null,
        priority: mutation.patch.touches(UserMediaField.malPriority)
            ? mutation.patch.malPriority
            : null,
        private: mutation.patch.touches(UserMediaField.private)
            ? mutation.patch.private
            : null,
        hiddenFromStatusLists:
            mutation.patch.touches(UserMediaField.hiddenFromStatusLists)
            ? mutation.patch.hiddenFromStatusLists
            : null,
        customLists: mutation.patch.touches(UserMediaField.customLists)
            ? mutation.patch.customLists?.entries
                  .where((MapEntry<String, bool> entry) => entry.value)
                  .map((MapEntry<String, bool> entry) => entry.key)
                  .toList(growable: false)
            : null,
        advancedScores: mutation.patch.touches(UserMediaField.advancedScores)
            ? mutation.patch.advancedScores?.values.toList(growable: false)
            : null,
        startedAt: mutation.patch.touches(UserMediaField.startedAt)
            ? _fuzzyDateInput(mutation.patch.startedAt)
            : null,
        completedAt: mutation.patch.touches(UserMediaField.completedAt)
            ? _fuzzyDateInput(mutation.patch.completedAt)
            : null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

class _MalAdapter implements TrackerProviderAdapter {
  _MalAdapter(this.client, this.viewerId);

  final MalApiClient client;
  final int viewerId;

  @override
  TrackerSource get source => TrackerSource.mal;

  @override
  String get accountId => '$viewerId';

  @override
  Future<List<UserMediaState>> fetchAnimeList() async {
    try {
      return userMediaStatesFromFolders(
        await client.fetchAnimeList(),
        source: source,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

  @override
  Future<List<UserMediaState>> fetchMangaList() async {
    try {
      return userMediaStatesFromFolders(
        await client.fetchMangaList(),
        source: source,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

  @override
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    final int? malId = mutation.identity.malId;
    if (malId == null) {
      throw const UnresolvedProviderIdentityException(TrackerSource.mal);
    }
    try {
      if (mutation.patch.delete) {
        await client.deleteEntry(malId, mediaKind: mutation.identity.mediaKind);
        return;
      }
      if (!mutation.patch.fields.any(_malEntryFields.contains)) return;
      await client.updateStatus(
        malId: malId,
        mediaKind: mutation.identity.mediaKind,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        episodesWatched: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        volumesRead: mutation.patch.touches(UserMediaField.progressVolumes)
            ? mutation.patch.progressVolumes
            : null,
        score: mutation.patch.touches(UserMediaField.score)
            ? mutation.patch.score ?? 0
            : null,
        isRewatching: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status == AniListListStatus.repeating
            : null,
        numTimesRewatched: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat
            : null,
        rewatchValue: mutation.patch.touches(UserMediaField.malRewatchValue)
            ? mutation.patch.malRewatchValue
            : null,
        priority: mutation.patch.touches(UserMediaField.priority)
            ? mutation.patch.priority
            : null,
        tags: mutation.patch.touches(UserMediaField.malTags)
            ? mutation.patch.malTags
            : null,
        comments: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes
            : null,
        startDate: mutation.patch.touches(UserMediaField.startedAt)
            ? mutation.patch.startedAt
            : null,
        finishDate: mutation.patch.touches(UserMediaField.completedAt)
            ? mutation.patch.completedAt
            : null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

class _ShikimoriAdapter implements TrackerProviderAdapter {
  _ShikimoriAdapter(
    this.client,
    this.viewerId, {
    required this.onResolvedIdentity,
    this.enrichFromMal,
  });

  final ShikimoriApiClient client;
  final int viewerId;
  final Future<bool> Function(MediaIdentity identity, int shikimoriId)
  onResolvedIdentity;
  final Future<MediaItem?> Function(int malId, String mediaKind)? enrichFromMal;

  @override
  TrackerSource get source => TrackerSource.shikimori;

  @override
  String get accountId => '$viewerId';

  @override
  Future<List<UserMediaState>> fetchAnimeList() async {
    try {
      return _enrichStatesFromMal(
        userMediaStatesFromFolders(
          await client.fetchAnimeList(),
          source: source,
        ),
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

  @override
  Future<List<UserMediaState>> fetchMangaList() async {
    try {
      return _enrichStatesFromMal(
        userMediaStatesFromFolders(
          await client.fetchMangaList(),
          source: source,
        ),
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

  Future<List<UserMediaState>> _enrichStatesFromMal(
    List<UserMediaState> states,
  ) async {
    final Future<MediaItem?> Function(int, String)? enrich = enrichFromMal;
    if (enrich == null) return states;
    final List<UserMediaState> result = <UserMediaState>[];
    for (final UserMediaState state in states) {
      final int? malId = state.identity.malId;
      final MediaItem media = state.mediaItem;
      final bool incomplete =
          _isTechnicalTitle(media.title) ||
          media.posterUrl.trim().isEmpty ||
          media.overview.trim().isEmpty;
      if (malId == null || malId <= 0 || !incomplete) {
        result.add(state);
        continue;
      }
      try {
        final MediaItem? enriched = await enrich(
          malId,
          state.identity.mediaKind,
        );
        result.add(enriched == null ? state : state.withMediaItem(enriched));
      } on Object {
        result.add(state);
      }
    }
    return result;
  }

  bool _isTechnicalTitle(String title) => RegExp(
    r'^(saved media|(anime|manga)\s*#\d+)$',
    caseSensitive: false,
  ).hasMatch(title.trim());

  @override
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    // Shikimori's target_id is its own internal media id. Older MiruShin
    // versions sent the MAL id directly because the ids are commonly aligned.
    // Keep that working, but verify the candidate through Shikimori's own
    // `malId` field and persist the binding before any write.
    int? targetId = mutation.identity.shikimoriId;
    final int? malId = mutation.identity.malId;
    if (targetId == null && malId != null) {
      final int? resolved = await client.resolveMediaIdByMalId(
        malId: malId,
        mediaKind: mutation.identity.mediaKind,
        title: mutation.mediaTitle,
      );
      if (resolved != null &&
          await onResolvedIdentity(mutation.identity, resolved)) {
        targetId = resolved;
      }
    }
    if (targetId == null) {
      throw const UnresolvedProviderIdentityException(TrackerSource.shikimori);
    }
    try {
      if (mutation.patch.delete) {
        await client.deleteUserRate(
          targetId,
          mediaKind: mutation.identity.mediaKind,
        );
        return;
      }
      if (!mutation.patch.fields.any(_shikimoriEntryFields.contains)) return;
      await client.updateUserRate(
        targetId: targetId,
        mediaKind: mutation.identity.mediaKind,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        episodes: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        chapters:
            mutation.identity.mediaKind == 'manga' &&
                mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        volumes: mutation.patch.touches(UserMediaField.progressVolumes)
            ? mutation.patch.progressVolumes
            : null,
        score: mutation.patch.touches(UserMediaField.score)
            ? mutation.patch.score ?? 0
            : null,
        rewatches: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat
            : null,
        text: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes
            : null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

Map<String, int?> _fuzzyDateInput(DateTime? value) => <String, int?>{
  'year': value?.year,
  'month': value?.month,
  'day': value?.day,
};

Never _throwAuthentication(TrackerSource source, DioException error) {
  if (error.response?.statusCode == 401) {
    throw TrackerAuthenticationException(source);
  }
  throw error;
}
