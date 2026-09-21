import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../settings/application/settings_state.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';
import 'tracker_sync_coordinator.dart';

/// A synchronous, provider-neutral view of edits made in this app.
///
/// AniList, MAL, and Shikimori list endpoints may remain stale briefly after a
/// successful mutation. The Library consumes this overlay directly so routing
/// to it never depends on a network refresh finishing first.
final trackerLibraryOptimisticMutationsProvider =
    NotifierProvider<
      TrackerLibraryOptimisticController,
      List<TrackerLibraryOptimisticMutation>
    >(TrackerLibraryOptimisticController.new);

/// Durable local view of the selected tracker account.
///
/// The provider list remains the authority once a live snapshot is available,
/// but this snapshot lets the UI render immediately during startup/outages and
/// restores pending edits after an app restart. Pending journal mutations are
/// kept separately so a stale provider response cannot overwrite them.
final trackerLocalAnimeLibraryProvider =
    FutureProvider<TrackerLocalAnimeLibrary>((Ref ref) async {
      final account = ref.watch(
        settingsProvider.select(
          (SettingsState settings) => (
            settings.effectivePrimaryTrackerSource,
            settings.anilistViewerId,
            settings.malViewerId,
            settings.shikimoriViewerId,
          ),
        ),
      );
      // The viewer ids are intentionally part of the dependency above. They
      // prevent a local snapshot from surviving an account switch in memory.
      final TrackerSource source = account.$1;
      final store = ref.watch(trackingSyncStoreProvider);
      final List<UserMediaState> states = await store.loadStates();
      final List<SyncJournalEntry> journal = await store.loadJournal();

      bool trackedBySource(MediaIdentity identity) => journal.any(
        (SyncJournalEntry mutation) =>
            mutation.identity.matches(identity) && mutation.tracks(source),
      );

      final List<UserMediaState> visibleStates = states
          .where(
            (UserMediaState state) =>
                state.identity.mediaKind == 'anime' &&
                (state.providerStates.containsKey(source) ||
                    trackedBySource(state.identity)),
          )
          .toList(growable: false);
      final List<AniListAnimeListFolder> folders = foldersFromUserMediaStates(
        visibleStates,
      );
      final List<AniListAnimeListEntry> entries = <AniListAnimeListEntry>[
        for (final AniListAnimeListFolder folder in folders) ...folder.entries,
      ];

      AniListAnimeListEntry? seedFor(MediaIdentity identity) {
        for (final AniListAnimeListEntry entry in entries) {
          if (_entryIdentity(entry).matches(identity)) return entry;
        }
        return null;
      }

      return TrackerLocalAnimeLibrary(
        folders: folders,
        pendingMutations: <TrackerLibraryOptimisticMutation>[
          for (final SyncJournalEntry mutation in journal)
            if (mutation.identity.mediaKind == 'anime' &&
                mutation.tracks(source) &&
                (mutation.patch.delete || mutation.patch.touchesLibraryState))
              TrackerLibraryOptimisticMutation(
                identity: mutation.identity,
                patch: mutation.patch,
                seedEntry: seedFor(mutation.identity),
                updatedAt: mutation.updatedAt,
              ),
        ],
      );
    });

class TrackerLocalAnimeLibrary {
  const TrackerLocalAnimeLibrary({
    required this.folders,
    required this.pendingMutations,
  });

  final List<AniListAnimeListFolder> folders;
  final List<TrackerLibraryOptimisticMutation> pendingMutations;
}

class TrackerLibraryOptimisticMutation {
  const TrackerLibraryOptimisticMutation({
    required this.identity,
    required this.patch,
    required this.updatedAt,
    this.seedEntry,
  });

  final MediaIdentity identity;
  final UserMediaPatch patch;
  final DateTime updatedAt;

  /// Supplies media/list metadata when the entry does not exist in the stale
  /// provider snapshot yet. Editable fields always come from [patch].
  final AniListAnimeListEntry? seedEntry;
}

class TrackerLibraryOptimisticController
    extends Notifier<List<TrackerLibraryOptimisticMutation>> {
  @override
  List<TrackerLibraryOptimisticMutation> build() {
    // Recreate the overlay when any active tracker account changes. A pending
    // edit must never leak from one user's library into another user's view.
    ref.watch(
      settingsProvider.select(
        (SettingsState settings) => (
          settings.anilistViewerId,
          settings.malViewerId,
          settings.shikimoriViewerId,
        ),
      ),
    );
    return const <TrackerLibraryOptimisticMutation>[];
  }

  void upsert(AniListAnimeListEntry entry) {
    final MediaIdentity identity = _entryIdentity(entry);
    _record(
      identity: identity,
      seedEntry: entry,
      patch: UserMediaPatch(
        status: entry.status,
        progress: entry.progress,
        score: entry.score,
        notes: entry.notes,
        repeat: entry.repeat,
        fields: const <UserMediaField>{
          UserMediaField.status,
          UserMediaField.progress,
          UserMediaField.score,
          UserMediaField.notes,
          UserMediaField.repeat,
        },
      ),
      updatedAt: entry.updatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              entry.updatedAt! * 1000,
              isUtc: true,
            ),
    );
  }

  void updateProgress({
    required MediaItem mediaItem,
    required int progress,
    required AniListListStatus status,
  }) {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      mediaItem.externalIds,
      mediaId: mediaItem.id,
    );
    _record(
      identity: identity,
      seedEntry: AniListAnimeListEntry(
        id: 0,
        status: status,
        progress: progress,
        mediaItem: mediaItem,
      ),
      patch: UserMediaPatch(
        status: status,
        progress: progress,
        fields: const <UserMediaField>{
          UserMediaField.status,
          UserMediaField.progress,
        },
      ),
    );
  }

  void remove(MediaItem mediaItem) {
    _record(
      identity: MediaIdentity.fromExternalIds(
        mediaItem.externalIds,
        mediaId: mediaItem.id,
      ),
      patch: UserMediaPatch(delete: true),
    );
  }

  void discard(MediaItem mediaItem) {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      mediaItem.externalIds,
      mediaId: mediaItem.id,
    );
    state = state
        .where(
          (TrackerLibraryOptimisticMutation mutation) =>
              !mutation.identity.matches(identity),
        )
        .toList(growable: false);
  }

  void removeByAniListId(int mediaId, {MediaItem? mediaItem}) {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      mediaItem?.externalIds ?? <String, String>{'anilist': '$mediaId'},
      mediaId: mediaItem?.id ?? 'anilist:$mediaId',
    );
    _record(identity: identity, patch: UserMediaPatch(delete: true));
  }

  /// Drop overlays once a complete provider snapshot contains the desired
  /// state. The durable sync journal still protects against another provider's
  /// temporarily stale response.
  void reconcile(List<AniListAnimeListFolder> folders) {
    final List<AniListAnimeListEntry> entries = <AniListAnimeListEntry>[
      for (final AniListAnimeListFolder folder in folders) ...folder.entries,
    ];
    final List<TrackerLibraryOptimisticMutation> next = state
        .where((TrackerLibraryOptimisticMutation mutation) {
          AniListAnimeListEntry? matching;
          for (final AniListAnimeListEntry entry in entries) {
            if (_entryIdentity(entry).matches(mutation.identity)) {
              matching = entry;
              break;
            }
          }
          if (mutation.patch.delete) return matching != null;
          if (matching == null) return true;
          final AniListAnimeListEntry desired = _applyPatchToEntry(
            matching,
            mutation.patch,
          );
          return !_sameTouchedState(matching, desired, mutation.patch.fields);
        })
        .toList(growable: false);
    if (next.length != state.length) state = next;
  }

  void _record({
    required MediaIdentity identity,
    required UserMediaPatch patch,
    AniListAnimeListEntry? seedEntry,
    DateTime? updatedAt,
  }) {
    final DateTime mutationTime = (updatedAt ?? DateTime.now()).toUtc();
    final int index = state.indexWhere(
      (TrackerLibraryOptimisticMutation mutation) =>
          mutation.identity.matches(identity),
    );
    if (index < 0) {
      state = <TrackerLibraryOptimisticMutation>[
        ...state,
        TrackerLibraryOptimisticMutation(
          identity: identity,
          patch: patch,
          seedEntry: seedEntry,
          updatedAt: mutationTime,
        ),
      ];
      return;
    }

    final TrackerLibraryOptimisticMutation previous = state[index];
    final bool incomingIsFullEntry = _touchesEveryEditableField(patch);
    final TrackerLibraryOptimisticMutation merged =
        TrackerLibraryOptimisticMutation(
          identity: previous.identity.merge(identity),
          patch: previous.patch.mergedWith(patch),
          seedEntry: incomingIsFullEntry
              ? seedEntry ?? previous.seedEntry
              : previous.seedEntry ?? seedEntry,
          updatedAt: mutationTime,
        );
    state = <TrackerLibraryOptimisticMutation>[
      for (int current = 0; current < state.length; current += 1)
        if (current == index) merged else state[current],
    ];
  }
}

List<AniListAnimeListFolder> applyTrackerLibraryOptimisticMutations(
  List<AniListAnimeListFolder> folders,
  List<TrackerLibraryOptimisticMutation> mutations,
) {
  List<AniListAnimeListFolder> result = folders;
  for (final TrackerLibraryOptimisticMutation mutation in mutations) {
    final List<AniListAnimeListFolder> withoutEntry =
        <AniListAnimeListFolder>[];
    AniListAnimeListEntry? matchingEntry;
    for (final AniListAnimeListFolder folder in result) {
      final List<AniListAnimeListEntry> entries = <AniListAnimeListEntry>[];
      for (final AniListAnimeListEntry entry in folder.entries) {
        if (_entryIdentity(entry).matches(mutation.identity)) {
          matchingEntry ??= entry;
        } else {
          entries.add(entry);
        }
      }
      if (entries.isNotEmpty) {
        withoutEntry.add(
          AniListAnimeListFolder(
            name: folder.name,
            status: folder.status,
            entries: entries,
          ),
        );
      }
    }

    if (mutation.patch.delete) {
      result = withoutEntry;
      continue;
    }

    final AniListAnimeListEntry? base = matchingEntry ?? mutation.seedEntry;
    if (base == null) {
      result = withoutEntry;
      continue;
    }
    final AniListAnimeListEntry desired = _applyPatchToEntry(
      base,
      mutation.patch,
      seedEntry: matchingEntry == null ? mutation.seedEntry : null,
      mutationUpdatedAt: mutation.updatedAt,
    );

    final int targetIndex = withoutEntry.indexWhere(
      (AniListAnimeListFolder folder) => folder.status == desired.status,
    );
    if (targetIndex < 0) {
      result = <AniListAnimeListFolder>[
        ...withoutEntry,
        AniListAnimeListFolder(
          name: desired.status.label,
          status: desired.status,
          entries: <AniListAnimeListEntry>[desired],
        ),
      ];
      continue;
    }

    final AniListAnimeListFolder target = withoutEntry[targetIndex];
    result = <AniListAnimeListFolder>[
      for (int index = 0; index < withoutEntry.length; index += 1)
        if (index == targetIndex)
          AniListAnimeListFolder(
            name: target.name,
            status: target.status,
            entries: <AniListAnimeListEntry>[...target.entries, desired],
          )
        else
          withoutEntry[index],
    ];
  }
  return result;
}

/// Combines a provider snapshot with durable pending state and the current
/// frame's optimistic edits. [useLocalFallback] should only be true before a
/// live snapshot resolves or while its provider is unavailable.
List<AniListAnimeListFolder> effectiveTrackerAnimeLibrary({
  required List<AniListAnimeListFolder> providerFolders,
  TrackerLocalAnimeLibrary? local,
  List<TrackerLibraryOptimisticMutation> optimistic =
      const <TrackerLibraryOptimisticMutation>[],
  bool useLocalFallback = false,
  Set<AniListListStatus>? statuses,
}) {
  List<AniListAnimeListFolder> result = useLocalFallback && local != null
      ? local.folders
      : providerFolders;
  if (local != null && local.pendingMutations.isNotEmpty) {
    result = applyTrackerLibraryOptimisticMutations(
      result,
      local.pendingMutations,
    );
  }
  if (optimistic.isNotEmpty) {
    result = applyTrackerLibraryOptimisticMutations(result, optimistic);
  }
  if (statuses == null || statuses.isEmpty) return result;
  return result
      .where(
        (AniListAnimeListFolder folder) =>
            folder.status != null && statuses.contains(folder.status),
      )
      .toList(growable: false);
}

MediaIdentity _entryIdentity(AniListAnimeListEntry entry) =>
    MediaIdentity.fromExternalIds(
      entry.mediaItem.externalIds,
      mediaId: entry.mediaItem.id,
    );

AniListAnimeListEntry _applyPatchToEntry(
  AniListAnimeListEntry base,
  UserMediaPatch patch, {
  AniListAnimeListEntry? seedEntry,
  DateTime? mutationUpdatedAt,
}) {
  final AniListAnimeListEntry metadata = seedEntry ?? base;
  return AniListAnimeListEntry(
    id: base.id > 0 ? base.id : metadata.id,
    status: patch.touches(UserMediaField.status)
        ? patch.status ?? base.status
        : base.status,
    progress: patch.touches(UserMediaField.progress)
        ? patch.progress ?? base.progress
        : base.progress,
    score: patch.touches(UserMediaField.score) ? patch.score : base.score,
    mediaItem: metadata.mediaItem,
    notes: patch.touches(UserMediaField.notes) ? patch.notes ?? '' : base.notes,
    repeat: patch.touches(UserMediaField.repeat)
        ? patch.repeat ?? 0
        : base.repeat,
    createdAt: metadata.createdAt ?? base.createdAt,
    updatedAt: mutationUpdatedAt == null
        ? metadata.updatedAt ?? base.updatedAt
        : mutationUpdatedAt.millisecondsSinceEpoch ~/ 1000,
    startedAt: metadata.startedAt ?? base.startedAt,
    completedAt: metadata.completedAt ?? base.completedAt,
    nextEpisode: metadata.nextEpisode ?? base.nextEpisode,
    airingAt: metadata.airingAt ?? base.airingAt,
    avgScore: metadata.avgScore ?? base.avgScore,
    format: metadata.format ?? base.format,
  );
}

bool _sameTouchedState(
  AniListAnimeListEntry left,
  AniListAnimeListEntry right,
  Set<UserMediaField> fields,
) {
  for (final UserMediaField field in fields) {
    final bool same = switch (field) {
      UserMediaField.status => left.status == right.status,
      UserMediaField.progress => left.progress == right.progress,
      UserMediaField.score => left.score == right.score,
      UserMediaField.notes => left.notes == right.notes,
      UserMediaField.repeat => left.repeat == right.repeat,
      UserMediaField.favorite => true,
    };
    if (!same) return false;
  }
  return true;
}

bool _touchesEveryEditableField(UserMediaPatch patch) {
  return const <UserMediaField>{
    UserMediaField.status,
    UserMediaField.progress,
    UserMediaField.score,
    UserMediaField.notes,
    UserMediaField.repeat,
  }.every(patch.touches);
}

/// Local-first anime library for MAL/Shikimori selection. The selected source
/// is tried first, then connected providers are used as fallbacks. The common
/// cache is returned when every provider is unavailable.
final trackerAnimeListProvider = FutureProvider<List<AniListAnimeListFolder>>((
  Ref ref,
) async {
  final SettingsState settings = ref.watch(settingsProvider);
  final TrackerLibrarySnapshot result = await ref
      .read(trackerSyncCoordinatorProvider)
      .refreshAnimeLibrary(preferred: settings.effectivePrimaryTrackerSource);
  ref
      .read(trackerLibraryOptimisticMutationsProvider.notifier)
      .reconcile(result.folders);
  return result.folders;
});
