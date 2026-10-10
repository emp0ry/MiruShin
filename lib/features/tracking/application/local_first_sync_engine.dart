import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../data/tracking_sync_store.dart';
import '../domain/provider_field_projection.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';

abstract class TrackerProviderAdapter {
  TrackerSource get source;

  String get accountId => 'active';

  Future<List<UserMediaState>> fetchAnimeList();

  Future<List<UserMediaState>> fetchMangaList() async =>
      const <UserMediaState>[];

  Future<void> applyMutation(SyncJournalEntry mutation);
}

/// A favourite is not part of provider list snapshots, so only an adapter
/// with an independent read can confirm it after an uncertain delivery.
abstract interface class TrackerFavoriteReadbackAdapter {
  Future<bool?> readFavorite(MediaIdentity identity);
}

abstract interface class AcknowledgingTrackerProviderAdapter {
  /// True only when the response acknowledges every supported changed field.
  Future<bool> applyAndConfirm(SyncJournalEntry mutation);
}

class TrackerProviderSnapshot {
  const TrackerProviderSnapshot({
    required this.source,
    required this.accountId,
    required this.mediaKind,
    required this.entries,
    required this.complete,
    required this.fetchedAt,
  });
  final TrackerSource source;
  final String accountId;
  final String mediaKind;
  final List<UserMediaState> entries;
  final bool complete;
  final DateTime fetchedAt;
}

abstract interface class SnapshotTrackerProviderAdapter {
  Future<TrackerProviderSnapshot> fetchSnapshot(String mediaKind);
}

class TrackerRateLimitException implements Exception {
  const TrackerRateLimitException(this.retryAt);
  final DateTime retryAt;
  @override
  String toString() => 'Rate limited; retry at ${retryAt.toIso8601String()}';
}

class TrackerMutationRejectedException implements Exception {
  const TrackerMutationRejectedException(this.message);
  final String message;
  @override
  String toString() => message;
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
    this.requiresAccountApproval = false,
  });

  final List<UserMediaState> states;
  final TrackerSource? remoteSource;
  final bool fromCache;
  final bool requiresAccountApproval;
}

/// Provider-neutral orchestration. Providers only communicate with this engine;
/// no adapter ever reads from or writes to another adapter.
class LocalFirstSyncEngine {
  LocalFirstSyncEngine({
    required TrackingSyncStore store,
    required Map<TrackerSource, TrackerProviderAdapter> adapters,
    this.targetAccountIds = const <TrackerSource, String>{},
    this.primary = TrackerSource.anilist,
    this.blockedOperationIds = const <String>{},
    this.blockedProviderEntries = const <(String, TrackerSource)>{},
    this.loadProviderBlocks,
    this.isStopping,
    DateTime Function()? now,
  }) : _store = store,
       _adapters = adapters,
       _now = now ?? DateTime.now;

  final TrackingSyncStore _store;
  final Map<TrackerSource, TrackerProviderAdapter> _adapters;
  final Map<TrackerSource, String> targetAccountIds;
  final TrackerSource primary;
  final Set<String> blockedOperationIds;
  final Set<(String, TrackerSource)> blockedProviderEntries;
  final Future<Set<(String, TrackerSource)>> Function()? loadProviderBlocks;
  final bool Function()? isStopping;
  bool get _stopping => isStopping?.call() ?? false;
  final DateTime Function() _now;
  final UserMediaConflictResolver _resolver = const UserMediaConflictResolver();

  Future<void> _tail = Future<void>.value();
  Future<void>? _activeFlush;
  List<SyncJournalEntry> _journalBaseline = const [];
  final Map<(TrackerSource, String), Future<List<UserMediaState>>> _readbacks =
      {};

  Future<List<UserMediaState>> _fetchSnapshot(
    TrackerProviderAdapter adapter,
    String kind,
  ) async {
    if (adapter is SnapshotTrackerProviderAdapter) {
      final snapshot = await (adapter as SnapshotTrackerProviderAdapter)
          .fetchSnapshot(kind);
      if (!snapshot.complete ||
          snapshot.source != adapter.source ||
          snapshot.accountId != adapter.accountId ||
          snapshot.mediaKind != kind ||
          snapshot.entries.any((state) => state.identity.mediaKind != kind)) {
        throw const FormatException(
          'Incomplete or mismatched catalog snapshot.',
        );
      }
      return snapshot.entries;
    }
    return kind == 'manga'
        ? adapter.fetchMangaList()
        : adapter.fetchAnimeList();
  }

  Future<List<SyncJournalEntry>> _loadJournal() async {
    final entries = await _store.loadJournal();
    _journalBaseline = List.of(entries);
    return entries;
  }

  Future<void> _saveJournal(List<SyncJournalEntry> entries) async {
    final store = _store;
    if (store is ConcurrentJournalTrackingSyncStore) {
      await (store as ConcurrentJournalTrackingSyncStore).saveJournalChanges(
        _journalBaseline,
        entries,
      );
    } else {
      await store.saveJournal(entries);
    }
    _journalBaseline = List.of(entries);
  }

  Future<SyncDispatchResult> recordMutation({
    required MediaIdentity identity,
    required UserMediaPatch patch,
    required Set<TrackerSource> targets,
    MediaItem? mediaItem,
    String? mediaTitle,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
    bool backgroundDelivery = false,
    TrackingEpisodeCheckpoint? episodeCheckpoint,
  }) async {
    final eligibleTargets = targets
        .where(
          (source) =>
              patch.delete ||
              patch.fields.any(
                providerEntryFields(
                  source,
                  mediaKind: identity.mediaKind,
                ).contains,
              ) ||
              (source == TrackerSource.anilist &&
                  patch.touches(UserMediaField.favorite)),
        )
        .toSet();
    final String recordedOperationId = await _serial<String>(() async {
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
      final before = stateIndex >= 0 ? states[stateIndex] : null;

      final DateTime timestamp = _now().toUtc();
      final String operationId = const Uuid().v7();
      if (stateIndex >= 0) {
        if (patch.delete) {
          states.removeAt(stateIndex);
        } else if (patch.touchesLibraryState) {
          UserMediaState previous = states[stateIndex].withIdentity(
            nextIdentity,
          );
          // A user-supplied final episode count is trusted metadata. Preserve
          // it with the same atomic status/progress edit and its Drive record.
          if ((previous.mediaItem.episodeCount ?? 0) <= 0 &&
              (mediaItem?.episodeCount ?? 0) > 0) {
            previous = previous.withMediaItem(
              previous.mediaItem.copyWith(
                episodeCount: mediaItem!.episodeCount,
              ),
            );
          }
          states[stateIndex] = previous.apply(patch, timestamp);
        } else {
          states[stateIndex] = states[stateIndex].withIdentity(nextIdentity);
        }
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
      }

      final after = states
          .where((state) => state.identity.matches(nextIdentity))
          .firstOrNull;
      if (!patch.delete && after != null) {
        if (!patch.touches(UserMediaField.startedAt) &&
            after.startedAt != before?.startedAt &&
            after.startedAt != null) {
          patch = patch.mergedWith(UserMediaPatch(startedAt: after.startedAt));
        }
        if (!patch.touches(UserMediaField.completedAt) &&
            after.completedAt != before?.completedAt &&
            after.completedAt != null) {
          patch = patch.mergedWith(
            UserMediaPatch(completedAt: after.completedAt),
          );
        }
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
      }

      final SyncJournalEntry incoming = SyncJournalEntry(
        operationId: operationId,
        identity: nextIdentity,
        patch: patch,
        pendingTargets: eligibleTargets,
        createdAt: timestamp,
        updatedAt: timestamp,
        mediaTitle: mediaTitle,
        providerEntryIds: providerEntryIds,
        targetAccountIds: <TrackerSource, String>{
          for (final TrackerSource target in eligibleTargets)
            if (targetAccountIds[target] != null)
              target: targetAccountIds[target]!,
        },
      );
      final List<SyncJournalEntry> journal = await _store.loadJournal();
      // Every user action must retain its own provider delivery. In particular,
      // remove followed by add must never collapse into the final add patch.
      journal.add(incoming);
      final TrackingSyncStore store = _store;
      if (store is AtomicTrackingSyncStore) {
        await (store as AtomicTrackingSyncStore).commitMutation(
          operationId: operationId,
          states: states,
          journal: journal,
          favorites: favorites,
          identity: nextIdentity,
          patch: patch,
          targets: eligibleTargets,
          occurredAt: timestamp,
          mediaTitle: mediaTitle,
          episodeCheckpoint: episodeCheckpoint,
        );
      } else {
        await store.saveStates(states);
        await store.saveFavorites(favorites);
        await store.saveJournal(journal);
      }
      return operationId;
    });

    if (!backgroundDelivery) {
      await flush();
    }
    final Set<TrackerSource> pending = await _serial<Set<TrackerSource>>(
      () async {
        final List<SyncJournalEntry> journal = await _store.loadJournal();
        for (final SyncJournalEntry entry in journal) {
          if (entry.operationId == recordedOperationId) {
            return entry.pendingTargets;
          }
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
    _readbacks.clear();
    if (_stopping) return;
    if (await _isInMigrationSafeMode()) return;
    final providerBlocks =
        await loadProviderBlocks?.call() ?? blockedProviderEntries;
    if (_store is CompactDeliveryTrackingSyncStore) {
      for (final adapter in _adapters.values) {
        await (_store as CompactDeliveryTrackingSyncStore)
            .compactPendingDeliveries(adapter.source, adapter.accountId);
      }
    }
    List<SyncJournalEntry> journal = await _loadJournal();
    if (journal.isEmpty) return;
    final List<UserMediaState> states = await _store.loadStates();
    final Map<TrackerSource, TrackerProviderHealth> health = await _store
        .loadHealth();
    final Set<TrackerSource> providerBackoff = <TrackerSource>{
      for (final MapEntry<TrackerSource, TrackerProviderHealth> entry
          in health.entries)
        if ((entry.value.accountId == null ||
                entry.value.accountId ==
                    (_adapters[entry.key]?.accountId ??
                        targetAccountIds[entry.key])) &&
            _retryIsDeferred(entry.value, _now().toUtc()))
          entry.key,
    };
    final List<(MediaIdentity, TrackerSource)> blocked =
        <(MediaIdentity, TrackerSource)>[];
    bool isBlocked(MediaIdentity identity, TrackerSource target) =>
        providerBlocks.contains((identity.localId, target)) ||
        blocked.any(
          ((MediaIdentity, TrackerSource) value) =>
              value.$2 == target && value.$1.matches(identity),
        );

    for (int index = 0; index < journal.length; index += 1) {
      if (_stopping) break;
      SyncJournalEntry entry = journal[index];
      if (entry.operationId != null &&
          blockedOperationIds.contains(entry.operationId)) {
        for (final TrackerSource target in <TrackerSource>{
          ...entry.pendingTargets,
          ...entry.awaitingRemoteTargets,
        }) {
          blocked.add((entry.identity, target));
        }
        continue;
      }
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

      // A later action for the same title may only leave after the previous
      // one has actually reached this provider. This preserves remove/add and
      // rapid status transitions even across offline sessions.
      for (final TrackerSource target in entry.awaitingRemoteTargets.toList(
        growable: false,
      )) {
        if (_stopping) break;
        final TrackerProviderAdapter? adapter = _adapters[target];
        if (adapter == null ||
            providerBackoff.contains(target) ||
            isBlocked(entry.identity, target)) {
          continue;
        }
        if (!_targetsAccount(entry, adapter)) {
          blocked.add((entry.identity, target));
          await _updateDelivery(
            entry.identity,
            target,
            'blocked',
            operationId: entry.operationId,
            accountId: entry.targetAccountIds[target],
            error: 'Waiting for the original account to reconnect.',
          );
          continue;
        }
        if (_unsupported(entry, target)) {
          entry = entry.confirmedBy(target);
          journal[index] = entry;
          await _updateDelivery(
            entry.identity,
            target,
            'unsupported',
            operationId: entry.operationId,
            accountId: adapter.accountId,
            error:
                'These fields are local only; this catalog does not support them.',
          );
          continue;
        }
        try {
          if (await _readbackConfirms(adapter, entry)) {
            entry = entry.confirmedBy(target);
            journal[index] = entry;
            await _updateDelivery(
              entry.identity,
              target,
              'confirmed',
              operationId: entry.operationId,
              accountId: adapter.accountId,
            );
          } else {
            blocked.add((entry.identity, target));
          }
        } on Object catch (error) {
          await _recordFailureLocked(target, error);
          providerBackoff.add(target);
          await _updateDelivery(
            entry.identity,
            target,
            'retry',
            operationId: entry.operationId,
            accountId: adapter.accountId,
            error: 'Sent; confirmation unavailable: $error',
          );
          blocked.add((entry.identity, target));
        }
      }

      final List<TrackerSource> orderedTargets = <TrackerSource>[
        if (entry.pendingTargets.contains(primary)) primary,
        ...TrackerSource.values.where(
          (TrackerSource target) =>
              target != primary && entry.pendingTargets.contains(target),
        ),
      ];
      for (final TrackerSource target in orderedTargets) {
        if (_stopping) break;
        final TrackerProviderAdapter? adapter = _adapters[target];
        if (adapter == null ||
            providerBackoff.contains(target) ||
            isBlocked(entry.identity, target)) {
          continue;
        }
        if (!_targetsAccount(entry, adapter)) {
          blocked.add((entry.identity, target));
          continue;
        }
        try {
          if (entry.readbackBeforeWrite || entry.operationId == null) {
            // Old merged queues and recovered v1 operations have uncertain
            // transport history. Observe the actual account before writing.
            if (await _readbackConfirms(adapter, entry)) {
              entry = entry.deliveredTo(target).confirmedBy(target);
              journal[index] = entry;
              await _updateDelivery(
                entry.identity,
                target,
                'confirmed',
                operationId: entry.operationId,
                accountId: adapter.accountId,
              );
              continue;
            }
          }
          if (_unsupported(entry, target)) {
            entry = entry.deliveredTo(target).confirmedBy(target);
            journal[index] = entry;
            await _updateDelivery(
              entry.identity,
              target,
              'unsupported',
              operationId: entry.operationId,
              accountId: adapter.accountId,
              error:
                  'These fields are stored locally; this catalog does not support them.',
            );
            continue;
          }
          if (_store is ObservedFieldsTrackingSyncStore) {
            final missing = await (_store as ObservedFieldsTrackingSyncStore)
                .unobservedDeliveryFields(entry, target, adapter.accountId);
            if (missing.isNotEmpty) {
              await _updateDelivery(
                entry.identity,
                target,
                'pending',
                operationId: entry.operationId,
                accountId: adapter.accountId,
                error:
                    'Waiting for current catalog fields: ${missing.map((field) => field.name).join(', ')}.',
                nextAttemptAt: _now().toUtc().add(const Duration(minutes: 1)),
              );
              blocked.add((entry.identity, target));
              continue;
            }
          }
          await _updateDelivery(
            entry.identity,
            target,
            'sending',
            operationId: entry.operationId,
            accountId: adapter.accountId,
          );
          final acknowledged = adapter is AcknowledgingTrackerProviderAdapter
              ? await (adapter as AcknowledgingTrackerProviderAdapter)
                    .applyAndConfirm(entry)
              : false;
          if (adapter is! AcknowledgingTrackerProviderAdapter) {
            await adapter.applyMutation(entry);
          }
          _readbacks.remove((target, entry.identity.mediaKind));
          final bool awaitConfirmation =
              entry.patch.delete || entry.patch.touchesLibraryState;
          entry = entry.deliveredTo(
            target,
            awaitRemoteConfirmation: awaitConfirmation,
          );
          if (acknowledged) entry = entry.confirmedBy(target);
          journal[index] = entry;
          // Persist the uncertain/delivered state before read-back. If the
          // process dies during confirmation, the next flush reads the remote
          // result rather than blindly replaying a delete or toggle.
          await _saveJournal(
            journal
                .where((SyncJournalEntry value) => !value.isSettled)
                .toList(),
          );
          final bool hasSuccessor = journal
              .skip(index + 1)
              .any(
                (SyncJournalEntry later) =>
                    later.identity.matches(entry.identity) &&
                    later.tracks(target),
              );
          if (entry.awaitingRemoteTargets.contains(target) &&
              (entry.patch.delete || hasSuccessor)) {
            try {
              if (await _readbackConfirms(adapter, entry)) {
                entry = entry.confirmedBy(target);
                journal[index] = entry;
              }
            } on Object {
              // The write may have succeeded while list read-back is down.
              // Keep it awaiting confirmation and block successors.
            }
          }
          await _updateDelivery(
            entry.identity,
            target,
            entry.awaitingRemoteTargets.contains(target)
                ? 'delivered'
                : 'confirmed',
            operationId: entry.operationId,
            accountId: adapter.accountId,
          );
          if (entry.awaitingRemoteTargets.contains(target)) {
            blocked.add((entry.identity, target));
          }
          await _recordSuccessLocked(target);
          await _saveJournal(
            journal
                .where((SyncJournalEntry value) => !value.isSettled)
                .toList(),
          );
        } on UnresolvedProviderIdentityException catch (error) {
          blocked.add((entry.identity, target));
          // Mapping may be learned from a later provider refresh. This is not
          // a provider outage and the mutation remains queued.
          await _updateDelivery(
            entry.identity,
            target,
            'pending',
            operationId: entry.operationId,
            accountId: adapter.accountId,
            error: '$error',
          );
        } on TrackerMutationRejectedException catch (error) {
          blocked.add((entry.identity, target));
          await _updateDelivery(
            entry.identity,
            target,
            'blocked',
            operationId: entry.operationId,
            accountId: adapter.accountId,
            error: '$error',
          );
        } on TrackerAuthenticationException catch (error) {
          providerBackoff.add(target);
          blocked.add((entry.identity, target));
          journal[index] = entry.withReadbackBeforeWrite();
          await _recordFailureLocked(target, error, authentication: true);
          await _updateDelivery(
            entry.identity,
            target,
            'retry',
            operationId: entry.operationId,
            accountId: adapter.accountId,
            error: '$error',
          );
        } catch (error) {
          if (_stopping) {
            // A cancelled write may have reached the server. Preserve the
            // operation and require read-back when this workspace resumes.
            journal[index] = entry.withReadbackBeforeWrite();
            break;
          }
          providerBackoff.add(target);
          blocked.add((entry.identity, target));
          // A timeout can occur after the provider applied the mutation.
          journal[index] = entry.withReadbackBeforeWrite();
          // Check before retrying so delete/add cannot be inverted later.
          try {
            if (error is! TrackerRateLimitException &&
                await _readbackConfirms(adapter, entry)) {
              entry = entry.deliveredTo(target).confirmedBy(target);
              journal[index] = entry;
              providerBackoff.remove(target);
              await _recordSuccessLocked(target);
              blocked.removeWhere(
                ((MediaIdentity, TrackerSource) value) =>
                    value.$2 == target && value.$1.matches(entry.identity),
              );
              await _updateDelivery(
                entry.identity,
                target,
                'confirmed',
                operationId: entry.operationId,
                accountId: adapter.accountId,
              );
              continue;
            }
          } on Object {
            // Keep the original transport error and retry the operation.
          }
          await _recordFailureLocked(target, error);
          await _updateDelivery(
            entry.identity,
            target,
            'retry',
            operationId: entry.operationId,
            accountId: adapter.accountId,
            error: '$error',
          );
        }
      }
    }
    journal = journal
        .where((SyncJournalEntry entry) => !entry.isSettled)
        .toList();
    await _saveJournal(journal);
  }

  bool _unsupported(SyncJournalEntry entry, TrackerSource target) =>
      !entry.patch.delete &&
      !entry.patch.fields.any(
        providerEntryFields(
          target,
          mediaKind: entry.identity.mediaKind,
        ).contains,
      ) &&
      !(target == TrackerSource.anilist &&
          entry.patch.touches(UserMediaField.favorite));

  Future<LocalFirstLibraryResult> refreshAnimeList({
    required List<TrackerSource> providerOrder,
    TrackerSource? cacheSource,
    String mediaKind = 'anime',
  }) async {
    final LocalFirstLibraryResult result = await _serial(() async {
      List<UserMediaState> local = await _store.loadStates();
      List<SyncJournalEntry> journal = await _loadJournal();
      if (await _isInMigrationSafeMode()) {
        return LocalFirstLibraryResult(states: local, fromCache: true);
      }
      for (final TrackerSource source in providerOrder) {
        if (_stopping) break;
        final TrackerProviderAdapter? adapter = _adapters[source];
        if (adapter == null) continue;
        try {
          final List<UserMediaState> remote = await _fetchSnapshot(
            adapter,
            mediaKind,
          );
          if (_stopping) break;
          final List<SyncJournalEntry> pendingBeforeConfirmation = journal;
          final List<SyncJournalEntry> beforeConfirmation = journal;
          journal = _confirmRemoteSnapshot(journal, remote, source);
          await _recordSnapshotConfirmations(
            beforeConfirmation,
            journal,
            source,
          );
          final TrackingSyncStore store = _store;
          if (store is ReconciliationTrackingSyncStore) {
            final ProviderReconciliationResult
            reconciliation = await (store as ReconciliationTrackingSyncStore)
                .reconcileProviderSnapshot(
                  source: source,
                  accountId: adapter.accountId,
                  mediaKind: mediaKind,
                  remote: remote,
                  journal: pendingBeforeConfirmation,
                  propagationTargets: <TrackerSource>{..._adapters.keys}
                    ..remove(source),
                  propagationAccountIds: <TrackerSource, String>{
                    for (final MapEntry<TrackerSource, TrackerProviderAdapter>
                        target
                        in _adapters.entries)
                      if (target.key != source)
                        target.key: target.value.accountId,
                  },
                  completeSnapshot: true,
                );
            local = reconciliation.states;
            final List<SyncJournalEntry> beforeReconciliationConfirmation =
                reconciliation.journal;
            journal = _confirmRemoteSnapshot(
              reconciliation.journal,
              remote,
              source,
            );
            await _recordSnapshotConfirmations(
              beforeReconciliationConfirmation,
              journal,
              source,
            );
            _journalBaseline = List.of(beforeReconciliationConfirmation);
            await _saveJournal(journal);
          } else {
            await _saveJournal(journal);
            local = _mergeRemote(
              local,
              remote,
              journal,
              incomingProviderIsAuthoritative: true,
              incomingAiringIsAuthoritative: source == TrackerSource.anilist,
            );
            await _store.saveStates(local);
          }
          await _recordSuccessLocked(source);
          return LocalFirstLibraryResult(
            states: _statesForProviderSnapshot(local, remote, journal, source),
            remoteSource: source,
            fromCache: false,
          );
        } on TrackerAuthenticationException catch (error) {
          await _recordFailureLocked(source, error, authentication: true);
        } catch (error) {
          if (_stopping) break;
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

  /// Fetches and reconciles a complete snapshot from every requested,
  /// connected provider. A failure in one provider never prevents the other
  /// snapshots from being persisted and reconciled.
  ///
  /// This is intentionally different from [refreshAnimeList], which returns
  /// after the first available provider and is kept for read-only fallback
  /// flows. Library pull-to-refresh uses this method so external edits made on
  /// AniList, MAL and Shikimori are all observable independently.
  Future<LocalFirstLibraryResult> refreshAllProviderSnapshots({
    required List<TrackerSource> providerOrder,
    String mediaKind = 'anime',
    bool deliverAfterRefresh = true,
  }) async {
    final LocalFirstLibraryResult result = await _serial(() async {
      List<UserMediaState> local = await _store.loadStates();
      List<SyncJournalEntry> journal = await _loadJournal();
      if (await _isInMigrationSafeMode()) {
        return LocalFirstLibraryResult(states: local, fromCache: true);
      }

      TrackerSource? firstSuccessfulSource;
      bool requiresApproval = false;
      final Set<TrackerSource> visited = <TrackerSource>{};
      for (final TrackerSource source in providerOrder) {
        if (_stopping) break;
        if (!visited.add(source)) continue;
        final TrackerProviderAdapter? adapter = _adapters[source];
        if (adapter == null) continue;
        try {
          final List<UserMediaState> remote = await _fetchSnapshot(
            adapter,
            mediaKind,
          );
          if (_stopping) break;
          final List<SyncJournalEntry> pendingBeforeConfirmation = journal;
          final List<SyncJournalEntry> beforeConfirmation = journal;
          journal = _confirmRemoteSnapshot(journal, remote, source);
          await _recordSnapshotConfirmations(
            beforeConfirmation,
            journal,
            source,
          );
          final TrackingSyncStore store = _store;
          if (store is ReconciliationTrackingSyncStore) {
            final ProviderReconciliationResult
            reconciliation = await (store as ReconciliationTrackingSyncStore)
                .reconcileProviderSnapshot(
                  source: source,
                  accountId: adapter.accountId,
                  mediaKind: mediaKind,
                  remote: remote,
                  journal: pendingBeforeConfirmation,
                  propagationTargets: <TrackerSource>{
                    ..._adapters.keys,
                    ...targetAccountIds.keys,
                  }..remove(source),
                  propagationAccountIds: <TrackerSource, String>{
                    ...targetAccountIds,
                    for (final MapEntry<TrackerSource, TrackerProviderAdapter>
                        target
                        in _adapters.entries)
                      if (target.key != source)
                        target.key: target.value.accountId,
                  },
                  completeSnapshot: true,
                );
            local = reconciliation.states;
            requiresApproval =
                requiresApproval || reconciliation.requiresAccountApproval;
            final List<SyncJournalEntry> beforeReconciliationConfirmation =
                reconciliation.journal;
            journal = _confirmRemoteSnapshot(
              reconciliation.journal,
              remote,
              source,
            );
            await _recordSnapshotConfirmations(
              beforeReconciliationConfirmation,
              journal,
              source,
            );
            _journalBaseline = List.of(beforeReconciliationConfirmation);
            await _saveJournal(journal);
          } else {
            await _saveJournal(journal);
            local = _mergeRemote(
              local,
              remote,
              journal,
              incomingProviderIsAuthoritative: true,
              incomingAiringIsAuthoritative: source == TrackerSource.anilist,
            );
            await _store.saveStates(local);
          }
          await _recordSuccessLocked(source);
          firstSuccessfulSource ??= source;
        } on TrackerAuthenticationException catch (error) {
          await _recordFailureLocked(source, error, authentication: true);
        } catch (error) {
          if (_stopping) break;
          await _recordFailureLocked(source, error);
        }
      }
      return LocalFirstLibraryResult(
        states: local,
        remoteSource: firstSuccessfulSource,
        fromCache: firstSuccessfulSource == null,
        requiresAccountApproval: requiresApproval,
      );
    });
    // Reconciliation can create outbound mutations for the other connected
    // trackers. Deliver them only after every provider snapshot has been read,
    // so one provider cannot influence another provider's snapshot in the same
    // refresh pass.
    if (deliverAfterRefresh &&
        !result.requiresAccountApproval &&
        !result.fromCache) {
      await flush();
    }
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
      final store = _store;
      if (store is PresentationTrackingSyncStore) {
        // Partial previews and cached reads can enrich a title, not replace
        // tracking state or become outbound user mutations.
        await (store as PresentationTrackingSyncStore).enrichRemoteMetadata(
          remote,
        );
        return store.loadStates();
      }
      final List<UserMediaState> local = await _store.loadStates();
      if (await _isInMigrationSafeMode()) return local;
      List<SyncJournalEntry> journal = await _loadJournal();
      // A status-filtered preview is not an authoritative provider snapshot.
      // It may contain a just-created Watching entry while the already-loaded
      // full Library is still stale. Settling the journal from that preview
      // removes the local overlay too early and makes the entry disappear
      // until the user manually reloads the full list.
      if (snapshotSource != null && confirmRemoteMutations) {
        final List<SyncJournalEntry> beforeConfirmation = journal;
        journal = _confirmRemoteSnapshot(journal, remote, snapshotSource);
        await _recordSnapshotConfirmations(
          beforeConfirmation,
          journal,
          snapshotSource,
        );
        await _saveJournal(journal);
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
      _serial<void>(
        () => _recordFailureLocked(
          provider,
          error,
          authentication: error is TrackerAuthenticationException,
        ),
      );

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
    final TrackerProviderAdapter? adapter = _adapters[source];
    if (adapter == null) return journal;
    final List<MediaIdentity> unresolved = <MediaIdentity>[];
    final List<SyncJournalEntry> result = <SyncJournalEntry>[];
    for (final SyncJournalEntry mutation in journal) {
      if (!mutation.tracks(source)) {
        if (!mutation.isSettled) result.add(mutation);
        continue;
      }
      if (!_targetsAccount(mutation, adapter) ||
          unresolved.any((MediaIdentity id) => id.matches(mutation.identity))) {
        result.add(mutation);
        continue;
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
      if (confirmed) {
        final SyncJournalEntry settled = mutation
            .deliveredTo(source)
            .confirmedBy(source);
        if (!settled.isSettled) result.add(settled);
      } else {
        unresolved.add(mutation.identity);
        result.add(mutation);
      }
    }
    return result;
  }

  Future<void> _recordSnapshotConfirmations(
    List<SyncJournalEntry> before,
    List<SyncJournalEntry> after,
    TrackerSource source,
  ) async {
    for (final SyncJournalEntry previous in before) {
      if (!previous.tracks(source)) continue;
      final TrackerProviderAdapter? adapter = _adapters[source];
      if (adapter == null || !_targetsAccount(previous, adapter)) continue;
      SyncJournalEntry? current;
      for (final SyncJournalEntry candidate in after) {
        if (previous.operationId != null
            ? candidate.operationId == previous.operationId
            : candidate.identity.matches(previous.identity)) {
          current = candidate;
          break;
        }
      }
      if (current?.tracks(source) == true) continue;
      await _updateDelivery(
        previous.identity,
        source,
        'confirmed',
        operationId: previous.operationId,
        accountId: _adapters[source]?.accountId,
      );
    }
  }

  Future<void> _updateDelivery(
    MediaIdentity identity,
    TrackerSource target,
    String state, {
    String? operationId,
    String? accountId,
    String? error,
    DateTime? nextAttemptAt,
  }) async {
    final TrackingSyncStore store = _store;
    if (store is! DeliveryTrackingSyncStore) return;
    await (store as DeliveryTrackingSyncStore).updateTrackerDelivery(
      operationId: operationId,
      accountId: accountId,
      identity: identity,
      target: target,
      state: state,
      error: error,
      nextAttemptAt:
          nextAttemptAt ??
          (state == 'retry'
              ? (await _store.loadHealth())[target]?.nextRetryAt
              : null),
    );
  }

  bool _targetsAccount(
    SyncJournalEntry mutation,
    TrackerProviderAdapter adapter,
  ) {
    final String? expected = mutation.targetAccountIds[adapter.source];
    return expected == null || expected == adapter.accountId;
  }

  bool _providerSnapshotConfirms(
    UserMediaPatch patch,
    UserMediaState remote,
    TrackerSource source, {
    bool ignoreFavorite = false,
  }) {
    // List snapshots do not contain AniList's independent favourite state.
    // Treating a matching list entry as confirmation could silently skip a
    // favourite toggle after a crash or legacy queue migration. The AniList
    // adapter reads the actual favourite state before toggling instead.
    if (!ignoreFavorite && patch.touches(UserMediaField.favorite)) return false;
    return providerConfirmsPatch(patch, remote, source);
  }

  Future<bool> _readbackConfirms(
    TrackerProviderAdapter adapter,
    SyncJournalEntry mutation,
  ) async {
    if (mutation.patch.touches(UserMediaField.favorite)) {
      final bool? actual = adapter is TrackerFavoriteReadbackAdapter
          ? await (adapter as TrackerFavoriteReadbackAdapter).readFavorite(
              mutation.identity,
            )
          : null;
      if (actual == null || actual != mutation.patch.favorite) return false;
      if (!mutation.patch.delete && !mutation.patch.touchesLibraryState) {
        return true;
      }
    }
    final List<UserMediaState> remote = await _readbacks.putIfAbsent((
      adapter.source,
      mutation.identity.mediaKind,
    ), () => _fetchSnapshot(adapter, mutation.identity.mediaKind));
    UserMediaState? matching;
    for (final UserMediaState state in remote) {
      if (state.identity.matches(mutation.identity)) {
        matching = state;
        break;
      }
    }
    return mutation.patch.delete
        ? matching == null
        : matching != null &&
              _providerSnapshotConfirms(
                mutation.patch,
                matching,
                adapter.source,
                ignoreFavorite: true,
              );
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
    final TrackerProviderHealth current = _healthForAccount(
      provider,
      health[provider],
    );
    health[provider] = current.success(_now().toUtc());
    if (_store is ProviderHealthTrackingSyncStore) {
      await (_store as ProviderHealthTrackingSyncStore).saveProviderHealth(
        health[provider]!,
      );
    } else {
      await _store.saveHealth(health);
    }
  }

  bool _retryIsDeferred(TrackerProviderHealth health, DateTime now) {
    if (health.availability == TrackerProviderAvailability.authRequired) {
      return true;
    }
    if (health.nextRetryAt != null) return now.isBefore(health.nextRetryAt!);
    final DateTime? failedAt = health.lastFailureAt;
    if (health.consecutiveFailures <= 0 || failedAt == null) return false;
    final int seconds = (1 << health.consecutiveFailures.clamp(1, 9)).clamp(
      2,
      300,
    );
    return now.isBefore(failedAt.add(Duration(seconds: seconds)));
  }

  TrackerProviderHealth _healthForAccount(
    TrackerSource provider,
    TrackerProviderHealth? current,
  ) {
    final account =
        _adapters[provider]?.accountId ?? targetAccountIds[provider];
    if (current == null ||
        (current.accountId != null && current.accountId != account)) {
      return TrackerProviderHealth(provider: provider, accountId: account);
    }
    return TrackerProviderHealth.fromJson({
      ...current.toJson(),
      'accountId': ?account,
    });
  }

  Future<void> _recordFailureLocked(
    TrackerSource provider,
    Object error, {
    bool authentication = false,
  }) async {
    final Map<TrackerSource, TrackerProviderHealth> health = await _store
        .loadHealth();
    final TrackerProviderHealth current = _healthForAccount(
      provider,
      health[provider],
    );
    health[provider] = current.failure(
      _now().toUtc(),
      error,
      authentication: authentication || error is TrackerAuthenticationException,
      retryAt: error is TrackerRateLimitException ? error.retryAt : null,
    );
    if (_store is ProviderHealthTrackingSyncStore) {
      await (_store as ProviderHealthTrackingSyncStore).saveProviderHealth(
        health[provider]!,
      );
    } else {
      await _store.saveHealth(health);
    }
  }

  Future<bool> _isInMigrationSafeMode() async {
    final TrackingSyncStore store = _store;
    return store is MigrationSafeModeTrackingSyncStore &&
        await (store as MigrationSafeModeTrackingSyncStore)
            .isInMigrationSafeMode();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final Completer<void> release = Completer<void>();
    final Future<void> previous = _tail;
    _tail = release.future;
    return previous.then((_) => action()).whenComplete(release.complete);
  }
}
