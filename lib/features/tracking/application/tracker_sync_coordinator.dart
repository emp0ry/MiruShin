import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../library/application/canonical_library_repository.dart';
import '../../library/application/google_drive_sync_controller.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/application/settings_state.dart';
import '../data/anilist_api_client.dart';
import '../data/canonical_tracking_sync_store.dart';
import '../data/mal_api_client.dart';
import '../data/shikimori_api_client.dart';
import '../data/tracking_sync_store.dart';
import '../domain/provider_field_projection.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';
import 'local_first_sync_engine.dart';

final trackingSyncStoreProvider = Provider<TrackingSyncStore>((Ref ref) {
  final accounts = ref.watch(
    settingsProvider.select(
      (settings) => (
        settings.anilistViewerId,
        settings.malViewerId,
        settings.shikimoriViewerId,
      ),
    ),
  );
  return CanonicalTrackingSyncStore(
    repository: ref.watch(canonicalLibraryRepositoryProvider),
    healthAccountIds: {
      if (accounts.$1 != null) TrackerSource.anilist: '${accounts.$1}',
      if (accounts.$2 != null) TrackerSource.mal: '${accounts.$2}',
      if (accounts.$3 != null) TrackerSource.shikimori: '${accounts.$3}',
    },
  );
});

final trackerProviderHealthProvider =
    FutureProvider<Map<TrackerSource, TrackerProviderHealth>>((Ref ref) {
      return ref.watch(trackingSyncStoreProvider).loadHealth();
    });

/// Includes coordinators from accounts switched out while work was in flight.
/// Their queues must drain before any of their workspace databases are closed.
class TrackerSyncCoordinatorRegistry {
  final Set<TrackerSyncCoordinator> _coordinators = {};
  Future<void>? _shutdown;

  void register(TrackerSyncCoordinator coordinator) {
    if (_shutdown != null) {
      throw StateError('Cannot start tracker work during shutdown.');
    }
    _coordinators.add(coordinator);
  }

  Future<void> prepareForExit() => _shutdown ??= Future.wait<void>(
    _coordinators.map((coordinator) => coordinator.prepareForExit()),
    eagerError: false,
  ).then((_) {});
}

final trackerSyncCoordinatorRegistryProvider =
    Provider<TrackerSyncCoordinatorRegistry>(
      (Ref ref) => TrackerSyncCoordinatorRegistry(),
    );

final trackerSyncCoordinatorProvider = Provider<TrackerSyncCoordinator>((
  Ref ref,
) {
  // Give every AniList workspace its own mutation/network queues and pin all
  // storage dependencies to that workspace. An operation started for account
  // A must never resume after a switch and resolve its store as account B.
  ref.watch(
    settingsProvider.select(
      (SettingsState settings) => (
        anilistViewerId: settings.anilistViewerId,
        anilistAccessToken: settings.anilistAccessToken,
        malViewerId: settings.malViewerId,
        hasMalSession: settings.hasMalSession,
        shikimoriViewerId: settings.shikimoriViewerId,
        hasShikimoriSession: settings.hasShikimoriSession,
        primary: settings.primaryTrackerSource,
      ),
    ),
  );
  final SettingsState settings = ref.read(settingsProvider);
  final CanonicalLibraryRepository repository = ref.watch(
    canonicalLibraryRepositoryProvider,
  );
  final coordinator = TrackerSyncCoordinator(
    ref,
    store: ref.watch(trackingSyncStoreProvider),
    settings: settings,
    settingsController: ref.read(settingsProvider.notifier),
    repository: repository,
    effectiveTitleLanguage: settings.anilistTitleLanguage,
    beforeTrackerNetwork: () async {
      final GoogleDriveSyncState drive = await ref.read(
        googleDriveSyncControllerProvider.future,
      );
      if (!ref.mounted) return false;
      if (!drive.configured) return true;
      return ref
          .read(googleDriveSyncControllerProvider.notifier)
          .ensureWorkspaceReadyForTrackerDelivery(repository.replicaNamespace);
    },
  );
  ref.read(trackerSyncCoordinatorRegistryProvider).register(coordinator);
  ref.onDispose(() => unawaited(coordinator.prepareForExit()));
  return coordinator;
});

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

/// Application facade over the provider-neutral local-first engine. It decides
/// which authenticated adapters are available, while the engine owns local
/// state, identity reconciliation, conflict policy and journal replay.
class TrackerSyncCoordinator {
  TrackerSyncCoordinator(
    this._ref, {
    TrackingSyncStore? store,
    SettingsState? settings,
    SettingsController? settingsController,
    CanonicalLibraryRepository? repository,
    String? effectiveTitleLanguage,
    Future<bool> Function()? beforeTrackerNetwork,
    Future<TrackerProviderAdapter?> Function(TrackerSource)? adapterFactory,
  }) : _boundStore = store,
       _boundSettings = settings,
       _boundSettingsController = settingsController,
       _boundRepository = repository,
       _boundTitleLanguage = effectiveTitleLanguage,
       _beforeTrackerNetwork = beforeTrackerNetwork,
       _adapterFactory = adapterFactory;

  final Ref _ref;
  final TrackingSyncStore? _boundStore;
  final SettingsState? _boundSettings;
  final SettingsController? _boundSettingsController;
  final CanonicalLibraryRepository? _boundRepository;
  final String? _boundTitleLanguage;
  final Future<bool> Function()? _beforeTrackerNetwork;
  final Future<TrackerProviderAdapter?> Function(TrackerSource)?
  _adapterFactory;
  // User mutations and remote work deliberately have separate lanes. A slow
  // tracker refresh/flush must never keep Add/Edit/Delete waiting before its
  // canonical SQLite transaction can commit.
  Future<void> _mutationTail = Future<void>.value();
  final Map<TrackerSource, Future<void>> _providerTails = {};
  final Set<Future<void>> _networkWork = {};
  final Set<TrackerSource> _initializedProviders = {};
  final Map<TrackerSource, Timer> _retryTimers = {};
  final Map<TrackerSource, String> _authBlockedCredentials = {};
  Timer? _deliveryDebounce;
  Future<bool>? _driveGate;
  final CancelToken _networkCancellation = CancelToken();
  bool _shuttingDown = false;
  Future<void>? _shutdown;

  Future<void> prepareForExit() {
    if (_shutdown != null) return _shutdown!;
    _shuttingDown = true;
    _deliveryDebounce?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _networkCancellation.cancel('MiruShin is closing.');
    // Tail futures are completion barriers, not the results of requests. A
    // failed/cancelled request still releases its lane and leaves its outbox.
    return _shutdown = Future.wait<void>([
      _mutationTail,
      ..._networkWork,
      ..._providerTails.values,
    ], eagerError: false).then((_) {});
  }

  SettingsState get _settings => _boundSettings ?? _ref.read(settingsProvider);
  SettingsController get _controller =>
      _boundSettingsController ?? _ref.read(settingsProvider.notifier);
  TrackingSyncStore get _store =>
      _boundStore ?? _ref.read(trackingSyncStoreProvider);
  CanonicalLibraryRepository get _repository =>
      _boundRepository ?? _ref.read(canonicalLibraryRepositoryProvider);

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
    int? canonicalTotal = mediaItem?.episodeCount;
    if (canonicalTotal == null && status == AniListListStatus.completed) {
      for (final UserMediaState state in await _store.loadStates()) {
        if (state.identity.matches(identity)) {
          canonicalTotal = state.mediaItem.episodeCount;
          break;
        }
      }
    }
    final bool completesAnime =
        status == AniListListStatus.completed && identity.mediaKind == 'anime';
    if (completesAnime && (canonicalTotal == null || canonicalTotal <= 0)) {
      throw StateError(
        'Enter the final episode count before marking Completed.',
      );
    }
    final int? safeProgress =
        completesAnime && canonicalTotal != null && canonicalTotal > 0
        ? canonicalTotal
        : progress == null
        ? null
        : canonicalEpisodeProgress(progress, canonicalTotal);
    final DateTime? safeCompletedAt = status == AniListListStatus.completed
        ? completedAt ?? DateTime.now().toUtc()
        : completedAt;
    final Set<UserMediaField>? effectiveFields = fields == null
        ? null
        : <UserMediaField>{
            ...fields,
            if (completesAnime && safeProgress != null) UserMediaField.progress,
            if (status == AniListListStatus.completed)
              UserMediaField.completedAt,
          };
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
        completedAt: safeCompletedAt,
        priority: priority,
        private: private,
        hiddenFromStatusLists: hiddenFromStatusLists,
        customLists: customLists,
        advancedScores: advancedScores,
        scoreFormat: scoreFormat,
        malPriority: malPriority,
        malRewatchValue: malRewatchValue,
        malTags: malTags,
        fields: effectiveFields,
      ),
      targets: resolvedTargets,
      mediaItem: mediaItem,
      mediaTitle: mediaTitle,
      providerEntryIds: providerEntryIds,
      backgroundDelivery: true,
      episodeCheckpoint: episodeCheckpoint,
    );
    if (result.pendingTargets.isNotEmpty) _scheduleDelivery();
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
    if (result.pendingTargets.isNotEmpty) _scheduleDelivery();
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
    if (result.pendingTargets.isNotEmpty) _scheduleDelivery();
    _invalidateHealth();
    return result;
  });

  Future<void> flushPending() async {
    if (_shuttingDown) return;
    try {
      await Future.wait(
        _accountIds.keys.map(
          (source) =>
              _serialProvider(source, () async {
                if (!await _canContactTrackers()) {
                  _retryTimers[source]?.cancel();
                  _retryTimers[source] = Timer(
                    const Duration(seconds: 5),
                    () => unawaited(flushPending()),
                  );
                  return;
                }
                if (await _providerDeferred(source)) {
                  await _scheduleRetry(source);
                  return;
                }
                final engine = await _engine(source: source);
                if (!_initializedProviders.contains(source)) {
                  final anime = await engine.refreshAllProviderSnapshots(
                    providerOrder: [source],
                    deliverAfterRefresh: false,
                  );
                  if (anime.fromCache || anime.requiresAccountApproval) {
                    await _scheduleRetry(source);
                    return;
                  }
                  final manga = await engine.refreshAllProviderSnapshots(
                    providerOrder: [source],
                    mediaKind: 'manga',
                    deliverAfterRefresh: false,
                  );
                  if (anime.fromCache ||
                      manga.fromCache ||
                      anime.requiresAccountApproval ||
                      manga.requiresAccountApproval) {
                    await _scheduleRetry(source);
                    return;
                  }
                  _initializedProviders.add(source);
                }
                await engine.flush();
                await _scheduleRetry(source);
                _invalidateHealth();
              }).catchError((Object error) {
                // Failure is recorded by this provider's lane; other lanes continue.
              }),
        ),
      );
    } on TrackerSyncStoppedException {
      // Shutdown cancels queued background work, not persisted user actions.
    }
  }

  Future<TrackerLibrarySnapshot> refreshAnimeLibrary({
    required TrackerSource preferred,
    Set<TrackerSource> excluded = const <TrackerSource>{},
  }) => _refreshPreferred(preferred, excluded, 'anime');

  Future<TrackerLibrarySnapshot> refreshMangaLibrary({
    required TrackerSource preferred,
    Set<TrackerSource> excluded = const <TrackerSource>{},
  }) => _refreshPreferred(preferred, excluded, 'manga');

  Future<TrackerLibrarySnapshot> _refreshPreferred(
    TrackerSource preferred,
    Set<TrackerSource> excluded,
    String kind,
  ) async {
    if (!await _canContactTrackers()) return _cachedSnapshot(kind);
    for (final source in {preferred, ...TrackerSource.values}) {
      if (excluded.contains(source) || !_accountIds.containsKey(source)) {
        continue;
      }
      final result = await _refreshSource(source, kind);
      if (!result.fromCache) {
        return TrackerLibrarySnapshot(
          folders: foldersFromUserMediaStates(
            result.states.where((s) => s.identity.mediaKind == kind).toList(),
          ),
          remoteSource: source,
          fromCache: false,
        );
      }
    }
    return _cachedSnapshot(kind);
  }

  Future<LocalFirstLibraryResult> _refreshSource(
    TrackerSource source,
    String kind, {
    bool force = false,
  }) =>
      _serialProvider(source, () async {
        if (await _providerDeferred(source, force: force)) {
          await _scheduleRetry(source);
          return LocalFirstLibraryResult(
            states: await _store.loadStates(),
            fromCache: true,
          );
        }
        final engine = await _engine(source: source);
        final result = await engine.refreshAllProviderSnapshots(
          providerOrder: [source],
          mediaKind: kind,
          deliverAfterRefresh: false,
        );
        if (!result.fromCache && !result.requiresAccountApproval) {
          // Reconcile the other kind before the first replay of this account.
          if (!_initializedProviders.contains(source)) {
            final other = await engine.refreshAllProviderSnapshots(
              providerOrder: [source],
              mediaKind: kind == 'anime' ? 'manga' : 'anime',
              deliverAfterRefresh: false,
            );
            if (!other.fromCache && !other.requiresAccountApproval) {
              _initializedProviders.add(source);
            }
          }
          if (_initializedProviders.contains(source)) await engine.flush();
        }
        await _scheduleRetry(source);
        _invalidateHealth();
        return result;
      }).onError(
        (Object error, StackTrace stack) async => LocalFirstLibraryResult(
          states: await _store.loadStates(),
          fromCache: true,
        ),
      );

  /// Reconciles a complete authenticated snapshot from every connected
  /// tracker instead of stopping after the first provider that responds.
  Future<TrackerLibrarySnapshot> refreshAllConnectedLibraries({
    String mediaKind = 'anime',
    Set<TrackerSource> excluded = const <TrackerSource>{},
    bool force = false,
  }) => _serialNetwork<TrackerLibrarySnapshot>(() async {
    if (!await _canContactTrackers()) return _cachedSnapshot(mediaKind);
    final List<TrackerSource> order =
        <TrackerSource>[
              TrackerSource.anilist,
              TrackerSource.mal,
              TrackerSource.shikimori,
            ]
            .where((TrackerSource source) => !excluded.contains(source))
            .toSet()
            .toList();
    final results = await Future.wait(
      order
          .where(_accountIds.containsKey)
          .map((source) => _refreshSource(source, mediaKind, force: force)),
    );
    final success = results.where((result) => !result.fromCache).firstOrNull;
    _invalidateHealth();
    final List<UserMediaState> states = (await _store.loadStates())
        .where((UserMediaState state) => state.identity.mediaKind == mediaKind)
        .toList(growable: false);
    return TrackerLibrarySnapshot(
      folders: foldersFromUserMediaStates(states),
      remoteSource: success?.remoteSource,
      fromCache: success == null,
    );
  });

  Future<List<AniListAnimeListFolder>> ingestAnimeLibrary({
    required TrackerSource source,
    required List<AniListAnimeListFolder> folders,
    required bool liveSnapshot,
    required bool completeSnapshot,
    String mediaKind = 'anime',
  }) => _serialNetwork<List<AniListAnimeListFolder>>(() async {
    if (!await _canContactTrackers()) {
      final List<UserMediaState> local = await _store.loadStates();
      return foldersFromUserMediaStates(
        local.where((state) => state.identity.mediaKind == mediaKind).toList(),
      );
    }
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
                propagationAccountIds: <TrackerSource, String>{
                  if (settings.hasAniListSession &&
                      settings.anilistViewerId != null)
                    TrackerSource.anilist: '${settings.anilistViewerId}',
                  if (settings.hasMalSession && settings.malViewerId != null)
                    TrackerSource.mal: '${settings.malViewerId}',
                  if (settings.hasShikimoriSession &&
                      settings.shikimoriViewerId != null)
                    TrackerSource.shikimori: '${settings.shikimoriViewerId}',
                },
                completeSnapshot: true,
              );
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

  Future<bool> _canContactTrackers() async {
    if (_shuttingDown) return false;
    final gate = _driveGate ??=
        (_beforeTrackerNetwork?.call() ?? Future<bool>.value(true));
    final allowed = await gate;
    if (identical(_driveGate, gate)) _driveGate = null;
    return !_shuttingDown && allowed;
  }

  Future<TrackerLibrarySnapshot> _cachedSnapshot(String mediaKind) async {
    final List<UserMediaState> states = await _store.loadStates();
    return TrackerLibrarySnapshot(
      folders: foldersFromUserMediaStates(
        states.where((state) => state.identity.mediaKind == mediaKind).toList(),
      ),
      fromCache: true,
    );
  }

  Future<void> recordProviderFailure(TrackerSource source, Object error) =>
      _serialNetwork<void>(() async {
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: _store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          targetAccountIds: _accountIds,
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
          targetAccountIds: _accountIds,
          primary: _settings.effectivePrimaryTrackerSource,
        );
        await engine.recordSuccess(source);
        _invalidateHealth();
      });

  Set<TrackerSource> _connectedTargets(MediaIdentity identity) {
    final SettingsState settings = _settings;
    return <TrackerSource>{
      if (settings.anilistAccessToken.trim().isNotEmpty) TrackerSource.anilist,
      if (settings.hasMalSession) TrackerSource.mal,
      if (settings.hasShikimoriSession) TrackerSource.shikimori,
    };
  }

  Future<LocalFirstSyncEngine> _engine({TrackerSource? source}) async {
    return LocalFirstSyncEngine(
      store: _store,
      adapters: await _adapters(only: source),
      targetAccountIds: _accountIds,
      primary: _settings.effectivePrimaryTrackerSource,
      blockedOperationIds: await _repository
          .unresolvedConflictLocalOperationIds(),
      loadProviderBlocks: () =>
          _repository.unresolvedProviderDeliveryBlocks(_accountIds),
      isStopping: () => _shuttingDown,
    );
  }

  LocalFirstSyncEngine _localEngine() => LocalFirstSyncEngine(
    store: _store,
    adapters: const <TrackerSource, TrackerProviderAdapter>{},
    targetAccountIds: <TrackerSource, String>{
      if (_settings.hasAniListSession && _settings.anilistViewerId != null)
        TrackerSource.anilist: '${_settings.anilistViewerId}',
      if (_settings.hasMalSession && _settings.malViewerId != null)
        TrackerSource.mal: '${_settings.malViewerId}',
      if (_settings.hasShikimoriSession && _settings.shikimoriViewerId != null)
        TrackerSource.shikimori: '${_settings.shikimoriViewerId}',
    },
    primary: _settings.effectivePrimaryTrackerSource,
  );

  Future<Map<TrackerSource, TrackerProviderAdapter>> _adapters({
    TrackerSource? only,
  }) async {
    if (_adapterFactory != null && only != null) {
      final adapter = await _adapterFactory(only);
      return {only: ?adapter};
    }
    if (_shuttingDown || (_boundSettings != null && !_ref.mounted)) {
      // This coordinator belongs to an account that has been switched out.
      // Keep its pending outbox in that account's database for a later retry;
      // never deliver it with the newly active account's credentials.
      return const <TrackerSource, TrackerProviderAdapter>{};
    }
    final SettingsState settings = _settings;
    final Map<TrackerSource, TrackerProviderAdapter> adapters =
        <TrackerSource, TrackerProviderAdapter>{};
    MalApiClient? malMetadataClient;

    final String aniListToken = settings.anilistAccessToken.trim();
    if (aniListToken.isNotEmpty &&
        (only == null || only == TrackerSource.anilist)) {
      final String fallbackTitleLanguage = _ref.read(
        aniListEffectiveTitleLanguageProvider,
      );
      final String titleLanguage =
          (_boundTitleLanguage ?? fallbackTitleLanguage).trim();
      adapters[TrackerSource.anilist] = _AniListAdapter(
        client: AniListApiClient(
          accessToken: aniListToken,
          cancelToken: _networkCancellation,
          titleLanguage: titleLanguage == 'RUSSIAN' ? 'ENGLISH' : titleLanguage,
        ),
        viewerId: settings.anilistViewerId,
        advancedScoreOrder: _ref
            .read(aniListUserSettingsProvider)
            .value
            ?.advancedScores,
        onResolvedIdentity: (identity, id) =>
            _repository.attachVerifiedProviderBinding(
              identity: identity,
              provider: TrackerSource.anilist,
              externalMediaId: id,
              evidence: 'exact_mal_id_lookup',
            ),
      );
    }

    if (settings.hasMalSession && (only == null || only == TrackerSource.mal)) {
      final String? token = await _controller.validMalAccessToken();
      if (_shuttingDown || (_boundSettings != null && !_ref.mounted)) {
        return adapters;
      }
      if (token != null && token.trim().isNotEmpty) {
        malMetadataClient = MalApiClient(
          accessToken: token,
          cancelToken: _networkCancellation,
          readListStatusCache: (kind) => _repository.loadProviderFieldCache(
            'mal',
            '${settings.malViewerId}',
            kind,
          ),
          writeListStatusCache: (kind, values) =>
              _repository.saveProviderFieldCache(
                'mal',
                '${settings.malViewerId}',
                kind,
                values,
              ),
          priorityListStatusIds: (kind) async => {
            for (final job in await _store.loadJournal())
              if (job.identity.mediaKind == kind &&
                  job.tracks(TrackerSource.mal) &&
                  job.patch.touches(UserMediaField.notes) &&
                  (job.targetAccountIds[TrackerSource.mal] == null ||
                      job.targetAccountIds[TrackerSource.mal] ==
                          '${settings.malViewerId}') &&
                  job.identity.malId != null)
                job.identity.malId!,
          },
          onRefreshToken: () => _ref.mounted
              ? _controller.refreshMalToken()
              : Future<String?>.value(),
        );
        adapters[TrackerSource.mal] = _MalAdapter(
          malMetadataClient,
          settings.malViewerId!,
        );
      }
    }

    final int? shikimoriViewerId = settings.shikimoriViewerId;
    if (settings.hasShikimoriSession &&
        shikimoriViewerId != null &&
        (only == null || only == TrackerSource.shikimori)) {
      final String? token = await _controller.validShikimoriAccessToken();
      if (_shuttingDown || (_boundSettings != null && !_ref.mounted)) {
        return adapters;
      }
      if (token != null && token.trim().isNotEmpty) {
        adapters[TrackerSource.shikimori] = _ShikimoriAdapter(
          ShikimoriApiClient(
            accessToken: token,
            cancelToken: _networkCancellation,
            userId: shikimoriViewerId,
            onRefreshToken: () => _ref.mounted
                ? _controller.refreshShikimoriToken()
                : Future<String?>.value(),
          ),
          shikimoriViewerId,
          onResolvedIdentity: (MediaIdentity identity, int shikimoriId) {
            return _repository.attachVerifiedProviderBinding(
              identity: identity,
              provider: TrackerSource.shikimori,
              externalMediaId: shikimoriId,
              evidence: 'exact_mal_id_lookup',
            );
          },
        );
      }
    }
    if (only != null && !adapters.containsKey(only) && !_shuttingDown) {
      throw TrackerAuthenticationException(only);
    }
    return adapters;
  }

  void _invalidateHealth() {
    if (_ref.mounted) {
      _ref.invalidate(trackerProviderHealthProvider);
    }
  }

  Future<T> _serialMutation<T>(Future<T> Function() action) =>
      _serialOn<T>(action, mutation: true);

  Map<TrackerSource, String> get _accountIds => {
    if (_settings.hasAniListSession && _settings.anilistViewerId != null)
      TrackerSource.anilist: '${_settings.anilistViewerId}',
    if (_settings.hasMalSession && _settings.malViewerId != null)
      TrackerSource.mal: '${_settings.malViewerId}',
    if (_settings.hasShikimoriSession && _settings.shikimoriViewerId != null)
      TrackerSource.shikimori: '${_settings.shikimoriViewerId}',
  };

  void _scheduleDelivery() {
    _deliveryDebounce?.cancel();
    _deliveryDebounce = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(flushPending()),
    );
  }

  String _credentials(TrackerSource source) {
    final settings = _ref.mounted ? _ref.read(settingsProvider) : _settings;
    return switch (source) {
      TrackerSource.anilist => settings.anilistAccessToken,
      TrackerSource.mal => settings.malAccessToken,
      TrackerSource.shikimori => settings.shikimoriAccessToken,
    };
  }

  Future<bool> _providerDeferred(
    TrackerSource source, {
    bool force = false,
  }) async {
    final blocked = _authBlockedCredentials[source];
    if (blocked != null && blocked == _credentials(source)) return true;
    if (blocked != null) {
      _authBlockedCredentials.remove(source);
      _initializedProviders.remove(source);
    }
    final health = (await _store.loadHealth())[source];
    if (health?.nextRetryAt?.isAfter(DateTime.now().toUtc()) != true) {
      return false;
    }
    return !force || health?.lastError?.startsWith('Rate limited;') == true;
  }

  Future<void> _scheduleRetry(TrackerSource source) async {
    _retryTimers.remove(source)?.cancel();
    if (_shuttingDown) return;
    final health = (await _store.loadHealth())[source];
    if (health?.availability == TrackerProviderAvailability.authRequired) {
      _authBlockedCredentials[source] = _credentials(source);
      return;
    }
    if (health?.consecutiveFailures != 0 &&
        health?.consecutiveFailures != null) {
      _initializedProviders.remove(
        source,
      ); // Pull before replay after recovery.
    }
    final journal = await _store.loadJournal();
    if (!journal.any((job) => job.tracks(source))) return;
    final retryAt = health?.nextRetryAt;
    final delay = retryAt == null
        ? (journal.any((job) => job.awaitingRemoteTargets.contains(source))
              ? const Duration(seconds: 2)
              : const Duration(minutes: 1))
        : retryAt.difference(DateTime.now().toUtc());
    _retryTimers[source] = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!_shuttingDown) unawaited(flushPending());
    });
  }

  Future<T> _serialProvider<T>(
    TrackerSource source,
    Future<T> Function() action,
  ) {
    final release = Completer<void>();
    final previous = _providerTails[source] ?? Future<void>.value();
    _providerTails[source] = release.future;
    return previous
        .then((_) {
          if (_shuttingDown) throw const TrackerSyncStoppedException();
          return action();
        })
        .onError((Object error, StackTrace stack) async {
          if (!_shuttingDown && error is! TrackerSyncStoppedException) {
            await LocalFirstSyncEngine(
              store: _store,
              adapters: const {},
              targetAccountIds: _accountIds,
            ).recordFailure(source, error);
            await _scheduleRetry(source);
          }
          Error.throwWithStackTrace(error, stack);
        })
        .whenComplete(release.complete);
  }

  Future<T> _serialNetwork<T>(Future<T> Function() action) {
    if (_shuttingDown) return Future.error(const TrackerSyncStoppedException());
    final release = Completer<void>();
    _networkWork.add(release.future);
    return Future<T>.sync(action).whenComplete(() {
      _networkWork.remove(release.future);
      release.complete();
    });
  }

  Future<T> _serialOn<T>(
    Future<T> Function() action, {
    required bool mutation,
  }) {
    if (_shuttingDown) {
      return Future<T>.error(const TrackerSyncStoppedException());
    }
    final Completer<void> release = Completer<void>();
    final Future<void> previous = _mutationTail;
    _mutationTail = release.future;
    return previous
        .then((_) {
          if (!mutation && _shuttingDown) {
            throw const TrackerSyncStoppedException();
          }
          return action();
        })
        .whenComplete(release.complete);
  }
}

class TrackerSyncStoppedException implements Exception {
  const TrackerSyncStoppedException();
}

abstract class _AcknowledgingAdapter
    implements
        TrackerProviderAdapter,
        AcknowledgingTrackerProviderAdapter,
        SnapshotTrackerProviderAdapter {
  Map<String, dynamic>? mutationResponse;
  @override
  Future<TrackerProviderSnapshot> fetchSnapshot(String kind) async =>
      TrackerProviderSnapshot(
        source: source,
        accountId: accountId,
        mediaKind: kind,
        entries: await (kind == 'manga' ? fetchMangaList() : fetchAnimeList()),
        complete: true,
        fetchedAt: DateTime.now().toUtc(),
      );
  @override
  Future<bool> applyAndConfirm(SyncJournalEntry mutation) async {
    mutationResponse = null;
    await applyMutation(mutation);
    if (mutation.patch.touches(UserMediaField.favorite) &&
        this is TrackerFavoriteReadbackAdapter) {
      if (await (this as TrackerFavoriteReadbackAdapter).readFavorite(
            mutation.identity,
          ) !=
          (mutation.patch.favorite ?? false)) {
        return false;
      }
    }
    if (mutation.patch.delete) return true;
    if (!mutation.patch.fields.any(
      providerEntryFields(
        source,
        mediaKind: mutation.identity.mediaKind,
      ).contains,
    )) {
      return true;
    }
    return providerResponseConfirmsPatch(
      mutationResponse,
      mutation.patch,
      source,
      mutation.identity.mediaKind,
    );
  }
}

class _AniListAdapter extends _AcknowledgingAdapter
    implements TrackerFavoriteReadbackAdapter {
  _AniListAdapter({
    required this.client,
    required this.viewerId,
    required this.onResolvedIdentity,
    this.advancedScoreOrder,
  });

  final AniListApiClient client;
  final int? viewerId;
  List<String>? advancedScoreOrder;
  final Future<bool> Function(MediaIdentity, int) onResolvedIdentity;

  @override
  TrackerSource get source => TrackerSource.anilist;

  @override
  String get accountId => '${viewerId ?? 'unknown'}';

  @override
  Future<bool?> readFavorite(MediaIdentity identity) async {
    try {
      int? mediaId = identity.anilistId;
      final int? malId = identity.malId;
      if (mediaId == null && malId != null) {
        final MediaItem? resolved = identity.mediaKind == 'manga'
            ? await client.resolveMangaByMalId(malId)
            : await client.resolveAnimeByMalId(malId);
        mediaId = int.tryParse(resolved?.externalIds['anilist'] ?? '');
      }
      if (mediaId == null) return null;
      return await client.fetchMediaFavouriteStatus(mediaId);
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }

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
        if (mediaId != null &&
            !await onResolvedIdentity(mutation.identity, mediaId)) {
          throw const UnresolvedProviderIdentityException(
            TrackerSource.anilist,
          );
        }
      }
      if (mediaId == null) {
        throw const UnresolvedProviderIdentityException(TrackerSource.anilist);
      }
      if (mutation.patch.touches(UserMediaField.favorite)) {
        final bool desired = mutation.patch.favorite ?? false;
        final bool? current = await client.fetchMediaFavouriteStatus(mediaId);
        if (current == null) {
          throw TrackerMutationRejectedException(
            'AniList did not return the favorite state for media $mediaId; no toggle was sent.',
          );
        }
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
      if (!mutation.patch.fields.any(
        providerEntryFields(
          source,
          mediaKind: mutation.identity.mediaKind,
        ).contains,
      )) {
        return;
      }
      List<double>? advanced;
      if (mutation.patch.touches(UserMediaField.advancedScores)) {
        advancedScoreOrder ??=
            (await client.fetchUserSettings()).advancedScores;
        advanced = [
          for (final name in advancedScoreOrder!)
            mutation.patch.advancedScores?[name] ?? 0,
        ];
      }
      mutationResponse = await client.updateListEntry(
        mediaId: mediaId,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        progress: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress ?? 0
            : null,
        progressVolumes: mutation.patch.touches(UserMediaField.progressVolumes)
            ? mutation.patch.progressVolumes ?? 0
            : null,
        scoreRaw: mutation.patch.touches(UserMediaField.score)
            ? aniListDisplayScoreToRaw(mutation.patch.score ?? 0)
            : null,
        notes: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes ?? ''
            : null,
        repeat: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat ?? 0
            : null,
        priority: mutation.patch.touches(UserMediaField.priority)
            ? mutation.patch.priority ?? 0
            : null,
        private: mutation.patch.touches(UserMediaField.private)
            ? mutation.patch.private ?? false
            : null,
        hiddenFromStatusLists:
            mutation.patch.touches(UserMediaField.hiddenFromStatusLists)
            ? mutation.patch.hiddenFromStatusLists ?? false
            : null,
        customLists: mutation.patch.touches(UserMediaField.customLists)
            ? (mutation.patch.customLists ?? const <String, bool>{}).entries
                  .where((MapEntry<String, bool> entry) => entry.value)
                  .map((MapEntry<String, bool> entry) => entry.key)
                  .toList(growable: false)
            : null,
        advancedScores: advanced,
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

class _MalAdapter extends _AcknowledgingAdapter {
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
      if (!mutation.patch.fields.any(
        providerEntryFields(
          source,
          mediaKind: mutation.identity.mediaKind,
        ).contains,
      )) {
        return;
      }
      mutationResponse = await client.updateStatus(
        malId: malId,
        mediaKind: mutation.identity.mediaKind,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        episodesWatched: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress ?? 0
            : null,
        volumesRead: mutation.patch.touches(UserMediaField.progressVolumes)
            ? mutation.patch.progressVolumes ?? 0
            : null,
        score: mutation.patch.touches(UserMediaField.score)
            ? mutation.patch.score ?? 0
            : null,
        isRewatching: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status == AniListListStatus.repeating
            : null,
        numTimesRewatched: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat ?? 0
            : null,
        rewatchValue: mutation.patch.touches(UserMediaField.malRewatchValue)
            ? mutation.patch.malRewatchValue ?? 0
            : null,
        priority: mutation.patch.touches(UserMediaField.malPriority)
            ? mutation.patch.malPriority ?? 0
            : null,
        tags: mutation.patch.touches(UserMediaField.malTags)
            ? mutation.patch.malTags ?? const <String>[]
            : null,
        comments: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes ?? ''
            : null,
        startDate: mutation.patch.touches(UserMediaField.startedAt)
            ? mutation.patch.startedAt
            : null,
        finishDate: mutation.patch.touches(UserMediaField.completedAt)
            ? mutation.patch.completedAt
            : null,
        clearStartDate:
            mutation.patch.touches(UserMediaField.startedAt) &&
            mutation.patch.startedAt == null,
        clearFinishDate:
            mutation.patch.touches(UserMediaField.completedAt) &&
            mutation.patch.completedAt == null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

class _ShikimoriAdapter extends _AcknowledgingAdapter {
  _ShikimoriAdapter(
    this.client,
    this.viewerId, {
    required this.onResolvedIdentity,
  });

  final ShikimoriApiClient client;
  final int viewerId;
  final Future<bool> Function(MediaIdentity identity, int shikimoriId)
  onResolvedIdentity;

  @override
  TrackerSource get source => TrackerSource.shikimori;

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
    // Shikimori's target_id is its own internal media id. Older MiruShin
    // versions sent the MAL id directly because the ids are commonly aligned.
    // Keep that working, but verify the candidate through Shikimori's own
    // `malId` field and persist the binding before any write.
    try {
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
        throw const UnresolvedProviderIdentityException(
          TrackerSource.shikimori,
        );
      }
      if (mutation.patch.delete) {
        await client.deleteUserRate(
          targetId,
          mediaKind: mutation.identity.mediaKind,
        );
        return;
      }
      if (!mutation.patch.fields.any(
        providerEntryFields(
          source,
          mediaKind: mutation.identity.mediaKind,
        ).contains,
      )) {
        return;
      }
      mutationResponse = await client.updateUserRate(
        targetId: targetId,
        mediaKind: mutation.identity.mediaKind,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        episodes: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress ?? 0
            : null,
        chapters:
            mutation.identity.mediaKind == 'manga' &&
                mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress ?? 0
            : null,
        volumes: mutation.patch.touches(UserMediaField.progressVolumes)
            ? mutation.patch.progressVolumes ?? 0
            : null,
        score: mutation.patch.touches(UserMediaField.score)
            ? mutation.patch.score ?? 0
            : null,
        rewatches: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat ?? 0
            : null,
        text: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes ?? ''
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
  if (error.response?.statusCode == 429) {
    final value = error.response?.headers.value('retry-after');
    final seconds = int.tryParse(value ?? '');
    DateTime? deadline = DateTime.tryParse(value ?? '')?.toUtc();
    if (seconds == null && deadline == null && value != null) {
      try {
        deadline = parseHttpDate(value);
      } on FormatException {
        /* Use bounded default. */
      }
    }
    throw TrackerRateLimitException(
      deadline ??
          DateTime.now().toUtc().add(
            Duration(seconds: (seconds ?? 60).clamp(0, 86400)),
          ),
    );
  }
  if ({400, 404, 422}.contains(error.response?.statusCode)) {
    throw TrackerMutationRejectedException(
      '${source.label}: request rejected (${error.response?.statusCode}). Review this title’s values or catalog ID.',
    );
  }
  throw error;
}
