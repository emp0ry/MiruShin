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

      for (final TrackerSource target in <TrackerSource>{
        ...entry.pendingTargets,
      }) {
        final TrackerProviderAdapter? adapter = _adapters[target];
        if (adapter == null) continue;
        try {
          await adapter.applyMutation(entry);
          entry = entry.deliveredTo(target);
          journal[index] = entry;
          await _recordSuccessLocked(target);
          await _store.saveJournal(
            journal
                .where(
                  (SyncJournalEntry value) => value.pendingTargets.isNotEmpty,
                )
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
        .where((SyncJournalEntry entry) => entry.pendingTargets.isNotEmpty)
        .toList();
    await _store.saveJournal(journal);
  }

  Future<LocalFirstLibraryResult> refreshAnimeList({
    required List<TrackerSource> providerOrder,
  }) async {
    await flush();
    final LocalFirstLibraryResult result = await _serial(() async {
      List<UserMediaState> local = await _store.loadStates();
      final List<SyncJournalEntry> journal = await _store.loadJournal();
      for (final TrackerSource source in providerOrder) {
        final TrackerProviderAdapter? adapter = _adapters[source];
        if (adapter == null) continue;
        try {
          final List<UserMediaState> remote = await adapter.fetchAnimeList();
          local = _mergeRemote(local, remote, journal);
          await _store.saveStates(local);
          await _recordSuccessLocked(source);
          return LocalFirstLibraryResult(
            states: local,
            remoteSource: source,
            fromCache: false,
          );
        } on TrackerAuthenticationException catch (error) {
          await _recordFailureLocked(source, error, authentication: true);
        } catch (error) {
          await _recordFailureLocked(source, error);
        }
      }
      return LocalFirstLibraryResult(states: local, fromCache: true);
    });
    // A successful refresh can discover an id that was missing while the
    // mutation was recorded. Replay once more after persisting that mapping.
    await flush();
    return result;
  }

  Future<List<UserMediaState>> ingestRemoteStates(List<UserMediaState> remote) {
    return _serial<List<UserMediaState>>(() async {
      final List<UserMediaState> local = await _store.loadStates();
      final List<SyncJournalEntry> journal = await _store.loadJournal();
      final List<UserMediaState> merged = _mergeRemote(local, remote, journal);
      await _store.saveStates(merged);
      return merged;
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
    List<SyncJournalEntry> journal,
  ) {
    final List<UserMediaState> result = <UserMediaState>[...local];
    for (final UserMediaState incoming in remote) {
      final int index = result.indexWhere(
        (UserMediaState state) => state.identity.matches(incoming.identity),
      );
      final UserMediaPatch? pending = _pendingPatch(journal, incoming.identity);
      if (index < 0) {
        if (pending?.delete == true) {
          continue;
        }
        result.add(
          pending == null ? incoming : incoming.apply(pending, _now().toUtc()),
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
      );
    }
    return result;
  }

  UserMediaPatch? _pendingPatch(
    List<SyncJournalEntry> journal,
    MediaIdentity identity,
  ) {
    for (final SyncJournalEntry entry in journal.reversed) {
      if (entry.identity.matches(identity)) return entry.patch;
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
