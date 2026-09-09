import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/application/settings_state.dart';
import '../data/anilist_api_client.dart';
import '../data/mal_api_client.dart';
import '../data/shikimori_api_client.dart';
import '../data/tracking_sync_store.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';
import 'local_first_sync_engine.dart';

final trackingSyncStoreProvider = Provider<TrackingSyncStore>(
  (Ref ref) => const SharedPreferencesTrackingSyncStore(),
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

/// Application facade over the provider-neutral local-first engine. It decides
/// which authenticated adapters are available, while the engine owns local
/// state, identity reconciliation, conflict policy and journal replay.
class TrackerSyncCoordinator {
  TrackerSyncCoordinator(this._ref);

  final Ref _ref;
  Future<void> _tail = Future<void>.value();

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
  }) async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      externalIds,
      mediaId: mediaId,
    );
    if (!identity.hasProviderId) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }

    final List<UserMediaState> cached = await _store.loadStates();
    UserMediaState? matched;
    for (final UserMediaState state in cached) {
      if (!state.identity.matches(identity)) continue;
      matched = state;
      break;
    }
    if (matched != null &&
        (matched.status == AniListListStatus.completed ||
            matched.progress >= episode)) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }

    final AniListListStatus status =
        (total != null && total > 0 && episode >= total)
        ? AniListListStatus.completed
        : matched?.status == AniListListStatus.repeating
        ? AniListListStatus.repeating
        : AniListListStatus.current;
    return pushEntryEdit(
      externalIds: externalIds,
      mediaId: mediaId,
      mediaTitle: mediaTitle,
      mediaItem: mediaItem,
      status: status,
      progress: episode,
      targets: targets,
    );
  }

  Future<SyncDispatchResult> pushEntryEdit({
    required Map<String, String> externalIds,
    String? mediaId,
    String? mediaTitle,
    MediaItem? mediaItem,
    AniListListStatus? status,
    int? progress,
    double? score,
    String? notes,
    int? repeat,
    Set<UserMediaField>? fields,
    Set<TrackerSource>? targets,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
  }) => _serial<SyncDispatchResult>(() async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      externalIds,
      mediaId: mediaId,
    );
    if (!identity.hasProviderId) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }
    final Set<TrackerSource> resolvedTargets =
        targets ?? _connectedTargets(identity);
    if (resolvedTargets.isEmpty) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }
    final LocalFirstSyncEngine engine = await _engine();
    final SyncDispatchResult result = await engine.recordMutation(
      identity: identity,
      patch: UserMediaPatch(
        status: status,
        progress: progress,
        score: score,
        notes: notes,
        repeat: repeat,
        fields: fields,
      ),
      targets: resolvedTargets,
      mediaItem: mediaItem,
      mediaTitle: mediaTitle,
      providerEntryIds: providerEntryIds,
    );
    _invalidateHealth();
    return result;
  });

  Future<SyncDispatchResult> pushFavorite({
    required MediaItem mediaItem,
    required bool favorite,
  }) => _serial<SyncDispatchResult>(() async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      mediaItem.externalIds,
      mediaId: mediaItem.id,
    );
    if ((identity.anilistId == null && identity.malId == null) ||
        _settings.anilistAccessToken.trim().isEmpty) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }
    final LocalFirstSyncEngine engine = await _engine();
    final SyncDispatchResult result = await engine.recordMutation(
      identity: identity,
      patch: UserMediaPatch(favorite: favorite),
      targets: const <TrackerSource>{TrackerSource.anilist},
      mediaItem: mediaItem,
      mediaTitle: mediaItem.title,
    );
    _invalidateHealth();
    return result;
  });

  Future<SyncDispatchResult> deleteEntry({
    required Map<String, String> externalIds,
    String? mediaId,
    String? mediaTitle,
    Set<TrackerSource>? targets,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
  }) => _serial<SyncDispatchResult>(() async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      externalIds,
      mediaId: mediaId,
    );
    if (!identity.hasProviderId) {
      return const SyncDispatchResult(pendingTargets: <TrackerSource>{});
    }
    final LocalFirstSyncEngine engine = await _engine();
    final SyncDispatchResult result = await engine.recordMutation(
      identity: identity,
      patch: UserMediaPatch(delete: true),
      targets: targets ?? _connectedTargets(identity),
      mediaTitle: mediaTitle,
      providerEntryIds: providerEntryIds,
    );
    _invalidateHealth();
    return result;
  });

  Future<void> flushPending() => _serial<void>(() async {
    final LocalFirstSyncEngine engine = await _engine();
    await engine.flush();
    _invalidateHealth();
  });

  Future<TrackerLibrarySnapshot> refreshAnimeLibrary({
    required TrackerSource preferred,
    Set<TrackerSource> excluded = const <TrackerSource>{},
  }) => _serial<TrackerLibrarySnapshot>(() async {
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
    );
    _invalidateHealth();
    return TrackerLibrarySnapshot(
      folders: foldersFromUserMediaStates(result.states),
      remoteSource: result.remoteSource,
      fromCache: result.fromCache,
    );
  });

  Future<List<AniListAnimeListFolder>> ingestAnimeLibrary({
    required TrackerSource source,
    required List<AniListAnimeListFolder> folders,
  }) => _serial<List<AniListAnimeListFolder>>(() async {
    final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
      store: _store,
      adapters: const <TrackerSource, TrackerProviderAdapter>{},
      primary: _settings.primaryTrackerSource,
    );
    final List<UserMediaState> merged = await engine.ingestRemoteStates(
      userMediaStatesFromFolders(folders, source: source),
    );
    await engine.recordSuccess(source);
    _invalidateHealth();
    return foldersFromUserMediaStates(merged);
  });

  Future<List<AniListAnimeListFolder>> cachedAnimeLibrary() async {
    return foldersFromUserMediaStates(await _store.loadStates());
  }

  Future<void> recordProviderFailure(TrackerSource source, Object error) =>
      _serial<void>(() async {
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: _store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          primary: _settings.primaryTrackerSource,
        );
        await engine.recordFailure(source, error);
        _invalidateHealth();
      });

  Future<void> recordProviderSuccess(TrackerSource source) =>
      _serial<void>(() async {
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: _store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          primary: _settings.primaryTrackerSource,
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
      if (settings.hasShikimoriSession &&
          (identity.shikimoriId != null || identity.malId != null))
        TrackerSource.shikimori,
    };
  }

  Future<LocalFirstSyncEngine> _engine() async {
    return LocalFirstSyncEngine(
      store: _store,
      adapters: await _adapters(),
      primary: _settings.primaryTrackerSource,
    );
  }

  Future<Map<TrackerSource, TrackerProviderAdapter>> _adapters() async {
    final SettingsState settings = _settings;
    final Map<TrackerSource, TrackerProviderAdapter> adapters =
        <TrackerSource, TrackerProviderAdapter>{};

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
        adapters[TrackerSource.mal] = _MalAdapter(
          MalApiClient(
            accessToken: token,
            onRefreshToken: _controller.refreshMalToken,
          ),
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
        );
      }
    }
    return adapters;
  }

  void _invalidateHealth() {
    _ref.invalidate(trackerProviderHealthProvider);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final Completer<void> release = Completer<void>();
    final Future<void> previous = _tail;
    _tail = release.future;
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
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    try {
      int? mediaId = mutation.identity.anilistId;
      final int? malId = mutation.identity.malId;
      if (mediaId == null && malId != null) {
        final MediaItem? resolved = await client.resolveAnimeByMalId(malId);
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
      if (!mutation.patch.touchesLibraryState) return;
      await client.updateListEntry(
        mediaId: mediaId,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        progress: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        scoreRaw:
            mutation.patch.touches(UserMediaField.score) &&
                mutation.patch.score != null
            ? aniListDisplayScoreToRaw(mutation.patch.score!)
            : null,
        notes: mutation.patch.touches(UserMediaField.notes)
            ? mutation.patch.notes
            : null,
        repeat: mutation.patch.touches(UserMediaField.repeat)
            ? mutation.patch.repeat
            : null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

class _MalAdapter implements TrackerProviderAdapter {
  _MalAdapter(this.client);

  final MalApiClient client;

  @override
  TrackerSource get source => TrackerSource.mal;

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
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    final int? malId = mutation.identity.malId;
    if (malId == null) {
      throw const UnresolvedProviderIdentityException(TrackerSource.mal);
    }
    try {
      if (mutation.patch.delete) {
        await client.deleteEntry(malId);
        return;
      }
      await client.updateStatus(
        malId: malId,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        episodesWatched: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        score: mutation.patch.touches(UserMediaField.score)
            ? mutation.patch.score
            : null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

class _ShikimoriAdapter implements TrackerProviderAdapter {
  _ShikimoriAdapter(this.client);

  final ShikimoriApiClient client;

  @override
  TrackerSource get source => TrackerSource.shikimori;

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
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    // Preserve MiruShin's established Shikimori contract: anime target_id is
    // the MAL id. The explicit Shikimori id remains a fallback for records
    // returned without malId and for future identity reconciliation.
    final int? targetId =
        mutation.identity.malId ?? mutation.identity.shikimoriId;
    if (targetId == null) {
      throw const UnresolvedProviderIdentityException(TrackerSource.shikimori);
    }
    try {
      if (mutation.patch.delete) {
        await client.deleteUserRate(targetId);
        return;
      }
      await client.updateUserRate(
        malId: targetId,
        status: mutation.patch.touches(UserMediaField.status)
            ? mutation.patch.status
            : null,
        episodes: mutation.patch.touches(UserMediaField.progress)
            ? mutation.patch.progress
            : null,
        score: mutation.patch.touches(UserMediaField.score)
            ? mutation.patch.score
            : null,
      );
    } on DioException catch (error) {
      _throwAuthentication(source, error);
    }
  }
}

Never _throwAuthentication(TrackerSource source, DioException error) {
  if (error.response?.statusCode == 401) {
    throw TrackerAuthenticationException(source);
  }
  throw error;
}
