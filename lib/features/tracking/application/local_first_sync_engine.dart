import 'dart:async';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../data/tracking_sync_store.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';

abstract class TrackerProviderAdapter {
  TrackerSource get source;

  Future<List<UserMediaState>> fetchAnimeList();

  Future<void> applyMutation(SyncJournalEntry mutation);
}

class UnresolvedProviderIdentityException implements Exception {
  const UnresolvedProviderIdentityException(this.provider);

  final TrackerSource provider;

  @override
  String toString() => 'No ${provider.label} id is known for this media.';
}

class TrackerAuthenticationException implements Exception {
  const TrackerAuthenticationException(this.provider, [this.message]);

  final TrackerSource provider;
  final String? message;

  @override
  String toString() => message ?? '${provider.label} authentication required.';
}

class SyncDispatchResult {
  const SyncDispatchResult({required this.pendingTargets});

  final Set<TrackerSource> pendingTargets;

  bool isPending(TrackerSource provider) => pendingTargets.contains(provider);
}

class LocalFirstLibraryResult {
  const LocalFirstLibraryResult({
    required this.states,
    this.remoteSource,
    required this.fromCache,
  });

  final List<UserMediaState> states;
  final TrackerSource? remoteSource;
  final bool fromCache;
}

/// Provider-neutral orchestration. Providers only communicate with this engine;
/// no adapter ever reads from or writes to another adapter.
class LocalFirstSyncEngine {
  LocalFirstSyncEngine({
    required TrackingSyncStore store,
    required Map<TrackerSource, TrackerProviderAdapter> adapters,
    this.primary = TrackerSource.anilist,
    DateTime Function()? now,
  }) : _store = store,
       _adapters = adapters,
       _now = now ?? DateTime.now;

  final TrackingSyncStore _store;
  final Map<TrackerSource, TrackerProviderAdapter> _adapters;
  final TrackerSource primary;
  final DateTime Function() _now;
  final UserMediaConflictResolver _resolver = const UserMediaConflictResolver();

  Future<void> _tail = Future<void>.value();
  Future<void>? _activeFlush;

  Future<SyncDispatchResult> recordMutation({
    required MediaIdentity identity,
    required UserMediaPatch patch,
    required Set<TrackerSource> targets,
    MediaItem? mediaItem,
    String? mediaTitle,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
  }) async {
    final MediaIdentity resolved = await _serial<MediaIdentity>(() async {
      final List<UserMediaState> states = await _store.loadStates();
      final int stateIndex = states.indexWhere(
        (UserMediaState state) => state.identity.matches(identity),
      );
      final List<LocalMediaFavoriteState> favorites = await _store
          .loadFavorites();
      final int favoriteIndex = favorites.indexWhere(
        (LocalMediaFavoriteState favorite) =>
            favorite.identity.matches(identity),
      );
      final MediaIdentity nextIdentity = stateIndex >= 0
          ? states[stateIndex].identity.merge(identity)
          : favoriteIndex >= 0
          ? favorites[favoriteIndex].identity.merge(identity)
          : identity;

      final DateTime timestamp = _now().toUtc();
      if (stateIndex >= 0) {
        if (patch.delete) {
          states.removeAt(stateIndex);
        } else if (patch.touchesLibraryState) {
          states[stateIndex] = states[stateIndex]
              .withIdentity(nextIdentity)
              .apply(patch, timestamp);
        } else {
          states[stateIndex] = states[stateIndex].withIdentity(nextIdentity);
        }
        await _store.saveStates(states);
      } else if (!patch.delete && patch.touchesLibraryState) {
        final MediaItem localMedia = _localMediaItem(
          nextIdentity,
          mediaItem: mediaItem,
          title: mediaTitle,
        );
        states.add(
          UserMediaState(
            identity: nextIdentity,
            mediaItem: localMedia,
            status: AniListListStatus.planning,
            progress: 0,
            createdAt: timestamp,
            updatedAt: timestamp,
            nextEpisode: _positiveExternalInt(
              localMedia.externalIds[anilistNextAiringEpisodeKey],
            ),
            airingAt: _externalEpochDate(
              localMedia.externalIds[anilistNextAiringAtKey],
            ),
            avgScore: localMedia.rating > 0
                ? (localMedia.rating * 10).round().clamp(1, 100)
                : null,
            format: _localFormat(localMedia),
            source: primary,
          ).apply(patch, timestamp),
        );
        await _store.saveStates(states);
      }

      if (patch.touches(UserMediaField.favorite) && patch.favorite != null) {
        final LocalMediaFavoriteState favorite = LocalMediaFavoriteState(
          identity: nextIdentity,
          favorite: patch.favorite!,
          updatedAt: timestamp,
        );
        if (favoriteIndex < 0) {
          favorites.add(favorite);
        } else {
          favorites[favoriteIndex] = favorite;
        }
        await _store.saveFavorites(favorites);
      }

      final SyncJournalEntry incoming = SyncJournalEntry(
        identity: nextIdentity,
        patch: patch,
        pendingTargets: targets,
        createdAt: timestamp,
        updatedAt: timestamp,
        mediaTitle: mediaTitle,
        providerEntryIds: providerEntryIds,
      );
      final List<SyncJournalEntry> journal = await _store.loadJournal();
      final int index = journal.indexWhere(
        (SyncJournalEntry current) => current.identity.matches(nextIdentity),
      );
      if (index < 0) {
        journal.add(incoming);
      } else {
        journal[index] = journal[index].mergedWith(incoming);
      }
      await _store.saveJournal(journal);
      return nextIdentity;
    });

    await flush();
    final Set<TrackerSource> pending = await _serial<Set<TrackerSource>>(
      () async {
        final List<SyncJournalEntry> journal = await _store.loadJournal();
        for (final SyncJournalEntry entry in journal) {
          if (entry.identity.matches(resolved)) return entry.pendingTargets;
        }
        return <TrackerSource>{};
      },
    );
    return SyncDispatchResult(pendingTargets: pending);
  }

  MediaItem _localMediaItem(
    MediaIdentity identity, {
    MediaItem? mediaItem,
    String? title,
  }) {
    if (mediaItem != null) {
      return mediaItem.copyWith(
        externalIds: identity.mergeExternalIds(mediaItem.externalIds),
      );
    }
    final String id = identity.anilistId != null
        ? identity.mediaKind == 'manga'
              ? 'anilist:manga:${identity.anilistId}'
              : 'anilist:${identity.anilistId}'
        : identity.malId != null
        ? 'mal:${identity.malId}'
        : 'shikimori:${identity.shikimoriId}';
    return MediaItem(
      id: id,
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'Saved media',
      originalTitle: title?.trim() ?? '',
      overview: '',
      type: MediaType.anime,
      year: 0,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: 'MiruShin Local',
      externalIds: identity.mergeExternalIds(const <String, String>{}),
      statusLabel: '',
    );
  }

  int? _positiveExternalInt(String? value) {
    final int parsed = int.tryParse(value?.trim() ?? '') ?? 0;
    return parsed > 0 ? parsed : null;
  }

  DateTime? _externalEpochDate(String? value) {
    final int? seconds = _positiveExternalInt(value);
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  String? _localFormat(MediaItem media) {
    final String raw =
        (media.externalIds['anilist_format'] ??
                media.externalIds['mal_media_type'] ??
                '')
            .trim()
            .toUpperCase();
    return switch (raw) {
      'TV' => 'TV',
      'TV_SHORT' => 'TV Short',
      'TV_SPECIAL' => 'TV Special',
      'MOVIE' => 'Movie',
      'OVA' => 'OVA',
      'ONA' => 'ONA',
      'SPECIAL' => 'Special',
      'MUSIC' => 'Music',
      _ => raw.isEmpty ? null : raw,
    };
  }

  Future<void> flush() {
    final Future<void>? active = _activeFlush;
    if (active != null) return active;
    final Future<void> next = _serial<void>(_flushLocked);
    _activeFlush = next;
    return next.whenComplete(() {
      if (identical(_activeFlush, next)) _activeFlush = null;
    });
  }

  Future<void> _flushLocked() async {
    List<SyncJournalEntry> journal = await _store.loadJournal();
    if (journal.isEmpty) return;
    final List<UserMediaState> states = await _store.loadStates();

    for (int index = 0; index < journal.length; index += 1) {
      SyncJournalEntry entry = journal[index];
      final int stateIndex = states.indexWhere(
        (UserMediaState state) => state.identity.matches(entry.identity),
      );
      if (stateIndex >= 0) {
        final MediaIdentity resolved = states[stateIndex].identity.merge(
          entry.identity,
        );
        entry = entry.withIdentity(resolved);
        journal[index] = entry;
      }

      final List<TrackerSource> orderedTargets = <TrackerSource>[
        if (entry.pendingTargets.contains(primary)) primary,
        ...TrackerSource.values.where(
          (TrackerSource target) =>
              target != primary && entry.pendingTargets.contains(target),
        ),
      ];
      for (final TrackerSource target in orderedTargets) {
        final TrackerProviderAdapter? adapter = _adapters[target];
        if (adapter == null) continue;
        try {
          await adapter.applyMutation(entry);
          entry = entry.deliveredTo(
            target,
            awaitRemoteConfirmation:
                entry.patch.delete || entry.patch.touchesLibraryState,
          );
          journal[index] = entry;
          await _recordSuccessLocked(target);
          await _store.saveJournal(
            journal
                .where((SyncJournalEntry value) => !value.isSettled)
                .toList(),
          );
        } on UnresolvedProviderIdentityException {
          // Mapping may be learned from a later provider refresh. This is not
          // a provider outage and the mutation remains queued.
        } on TrackerAuthenticationException catch (error) {
          await _recordFailureLocked(target, error, authentication: true);
        } catch (error) {
          await _recordFailureLocked(target, error);
        }
      }
    }
    journal = journal
        .where((SyncJournalEntry entry) => !entry.isSettled)
        .toList();
    await _store.saveJournal(journal);
  }

  Future<LocalFirstLibraryResult> refreshAnimeList({
    required List<TrackerSource> providerOrder,
    TrackerSource? cacheSource,
  }) async {
    await flush();
    final LocalFirstLibraryResult result = await _serial(() async {
      List<UserMediaState> local = await _store.loadStates();
      List<SyncJournalEntry> journal = await _store.loadJournal();
      for (final TrackerSource source in providerOrder) {
        final TrackerProviderAdapter? adapter = _adapters[source];
        if (adapter == null) continue;
        try {
          final List<UserMediaState> remote = await adapter.fetchAnimeList();
          journal = _confirmRemoteSnapshot(journal, remote, source);
          await _store.saveJournal(journal);
          local = _mergeRemote(
            local,
            remote,
            journal,
            incomingProviderIsAuthoritative: true,
            incomingAiringIsAuthoritative: source == TrackerSource.anilist,
          );
          await _store.saveStates(local);
          await _recordSuccessLocked(source);
          return LocalFirstLibraryResult(
            states: _statesForProviderSnapshot(local, remote, journal, source),
            remoteSource: source,
            fromCache: false,
          );
        } on TrackerAuthenticationException catch (error) {
          await _recordFailureLocked(source, error, authentication: true);
        } catch (error) {
          await _recordFailureLocked(source, error);
        }
      }
      final TrackerSource? selectedCacheSource =
          cacheSource ?? (providerOrder.isEmpty ? null : providerOrder.first);
      return LocalFirstLibraryResult(
        states: selectedCacheSource == null
            ? const <UserMediaState>[]
            : _statesForCachedProvider(local, journal, selectedCacheSource),
        fromCache: true,
      );
    });
    // A successful refresh can discover an id that was missing while the
    // mutation was recorded. Replay once more after persisting that mapping.
    await flush();
    return result;
  }

  Future<List<UserMediaState>> ingestRemoteStates(
    List<UserMediaState> remote, {
    TrackerSource? snapshotSource,
    bool confirmRemoteMutations = true,
    bool incomingProviderIsAuthoritative = false,
    bool incomingAiringIsAuthoritative = false,
  }) {
    return _serial<List<UserMediaState>>(() async {
      final List<UserMediaState> local = await _store.loadStates();
      List<SyncJournalEntry> journal = await _store.loadJournal();
      // A status-filtered preview is not an authoritative provider snapshot.
      // It may contain a just-created Watching entry while the already-loaded
      // full Library is still stale. Settling the journal from that preview
      // removes the local overlay too early and makes the entry disappear
      // until the user manually reloads the full list.
      if (snapshotSource != null && confirmRemoteMutations) {
        journal = _confirmRemoteSnapshot(journal, remote, snapshotSource);
        await _store.saveJournal(journal);
      }
      final List<UserMediaState> merged = _mergeRemote(
        local,
        remote,
        journal,
        incomingProviderIsAuthoritative: incomingProviderIsAuthoritative,
        incomingAiringIsAuthoritative: incomingAiringIsAuthoritative,
      );
      await _store.saveStates(merged);
      return snapshotSource == null
          ? merged
          : _statesForProviderSnapshot(merged, remote, journal, snapshotSource);
    });
  }

  Future<List<UserMediaState>> loadCachedStates() => _store.loadStates();

  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth() =>
      _store.loadHealth();

  Future<void> recordSuccess(TrackerSource provider) =>
      _serial<void>(() => _recordSuccessLocked(provider));

  Future<void> recordFailure(TrackerSource provider, Object error) =>
      _serial<void>(() => _recordFailureLocked(provider, error));

  List<UserMediaState> _mergeRemote(
    List<UserMediaState> local,
    List<UserMediaState> remote,
    List<SyncJournalEntry> journal, {
    bool incomingProviderIsAuthoritative = false,
    bool incomingAiringIsAuthoritative = false,
  }) {
    final List<UserMediaState> result = <UserMediaState>[...local];
    for (final UserMediaState incoming in remote) {
      final int index = result.indexWhere(
        (UserMediaState state) => state.identity.matches(incoming.identity),
      );
      final SyncJournalEntry? mutation = _pendingMutation(
        journal,
        incoming.identity,
        incoming.source,
      );
      final UserMediaPatch? pending = mutation?.patch;
      if (index < 0) {
        if (pending?.delete == true) {
          continue;
        }
        result.add(
          pending == null
              ? incoming
              : incoming.apply(pending, mutation!.updatedAt),
        );
        continue;
      }
      if (pending?.delete == true) {
        result.removeAt(index);
        continue;
      }
      result[index] = _resolver.merge(
        existing: result[index],
        incoming: incoming,
        primary: primary,
        pendingLocal: pending,
        pendingLocalUpdatedAt: mutation?.updatedAt,
        incomingProviderIsAuthoritative: incomingProviderIsAuthoritative,
        incomingAiringIsAuthoritative:
            incomingAiringIsAuthoritative &&
            incoming.source == TrackerSource.anilist,
      );
    }
    return result;
  }

  /// A provider page is a view of that provider's list, not the union of every
  /// connected account. The canonical store intentionally keeps identities and
  /// raw snapshots from all trackers, but returning that entire store here made
  /// MAL/Shikimori-only titles appear as seemingly random AniList additions.
  List<UserMediaState> _statesForProviderSnapshot(
    List<UserMediaState> merged,
    List<UserMediaState> remote,
    List<SyncJournalEntry> journal,
    TrackerSource source,
  ) {
    bool belongsToSnapshot(UserMediaState state) {
      if (remote.any(
        (UserMediaState item) => item.identity.matches(state.identity),
      )) {
        return true;
      }
      for (final SyncJournalEntry mutation in journal) {
        if (!mutation.identity.matches(state.identity) ||
            !mutation.tracks(source)) {
          continue;
        }
        return !mutation.patch.delete;
      }
      return false;
    }

    return merged.where(belongsToSnapshot).toList(growable: false);
  }

  List<UserMediaState> _statesForCachedProvider(
    List<UserMediaState> states,
    List<SyncJournalEntry> journal,
    TrackerSource source,
  ) {
    return states
        .where((UserMediaState state) {
          if (state.providerStates.containsKey(source)) return true;
          return journal.any(
            (SyncJournalEntry mutation) =>
                mutation.identity.matches(state.identity) &&
                mutation.tracks(source) &&
                !mutation.patch.delete,
          );
        })
        .toList(growable: false);
  }

  /// Successful creates and deletes remain in the durable journal until the
  /// provider's list endpoint confirms them. Mutation endpoints and list
  /// endpoints are not always read-after-write consistent; dropping the entry
  /// immediately made a newly added anime disappear until manual refresh.
  List<SyncJournalEntry> _confirmRemoteSnapshot(
    List<SyncJournalEntry> journal,
    List<UserMediaState> remote,
    TrackerSource source,
  ) {
    return journal
        .map((SyncJournalEntry mutation) {
          if (!mutation.awaitingRemoteTargets.contains(source)) {
            return mutation;
          }
          UserMediaState? matching;
          for (final UserMediaState state in remote) {
            if (state.identity.matches(mutation.identity)) {
              matching = state;
              break;
            }
          }
          final bool confirmed = mutation.patch.delete
              ? matching == null
              : matching != null &&
                    _providerSnapshotConfirms(mutation.patch, matching, source);
          return confirmed ? mutation.confirmedBy(source) : mutation;
        })
        .where((SyncJournalEntry mutation) => !mutation.isSettled)
        .toList(growable: false);
  }

  bool _providerSnapshotConfirms(
    UserMediaPatch patch,
    UserMediaState remote,
    TrackerSource source,
  ) {
    if (patch.touches(UserMediaField.status) &&
        patch.status != null &&
        remote.status != patch.status) {
      return false;
    }
    if (patch.touches(UserMediaField.progress) &&
        patch.progress != null &&
        remote.progress != patch.progress) {
      return false;
    }
    if (patch.touches(UserMediaField.score)) {
      final double remoteScore = normalizeCanonicalScore(remote.score) ?? 0;
      final double desiredScore = normalizeCanonicalScore(patch.score) ?? 0;
      if ((remoteScore - desiredScore).abs() > 0.001) return false;
    }
    // MAL and Shikimori adapters do not expose notes/repeat. Those fields are
    // still canonical locally, but only AniList can confirm their delivery.
    if (source == TrackerSource.anilist) {
      if (patch.touches(UserMediaField.notes) &&
          remote.notes != (patch.notes ?? '')) {
        return false;
      }
      if (patch.touches(UserMediaField.repeat) &&
          remote.repeat != (patch.repeat ?? 0)) {
        return false;
      }
    }
    return true;
  }

  SyncJournalEntry? _pendingMutation(
    List<SyncJournalEntry> journal,
    MediaIdentity identity,
    TrackerSource source,
  ) {
    for (final SyncJournalEntry entry in journal.reversed) {
      if (entry.identity.matches(identity) && entry.tracks(source)) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _recordSuccessLocked(TrackerSource provider) async {
    final Map<TrackerSource, TrackerProviderHealth> health = await _store
        .loadHealth();
    final TrackerProviderHealth current =
        health[provider] ?? TrackerProviderHealth(provider: provider);
    health[provider] = current.success(_now().toUtc());
    await _store.saveHealth(health);
  }

  Future<void> _recordFailureLocked(
    TrackerSource provider,
    Object error, {
    bool authentication = false,
  }) async {
    final Map<TrackerSource, TrackerProviderHealth> health = await _store
        .loadHealth();
    final TrackerProviderHealth current =
        health[provider] ?? TrackerProviderHealth(provider: provider);
    health[provider] = current.failure(
      _now().toUtc(),
      error,
      authentication: authentication,
    );
    await _store.saveHealth(health);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final Completer<void> release = Completer<void>();
    final Future<void> previous = _tail;
    _tail = release.future;
    return previous.then((_) => action()).whenComplete(release.complete);
  }
}
