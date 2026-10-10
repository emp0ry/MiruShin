# Local-first tracking sync

MiruShin treats AniList, MyAnimeList, and Shikimori as independent adapters
around one local model. Settings → Library Log → Library sync source selects
the only catalog allowed to import anime/manga tracking changes; AniList is the
default, with MyAnimeList and Shikimori available as alternatives. Every other
connected catalog is an outgoing mirror. If the selected source is unavailable
or disconnected, local data stays available without another catalog taking over.
Catalog browsing fallback is separate from this tracking policy.

When a MAL account is connected, AniList catalog reads also fall back to MAL:
Board uses MAL rankings, Discovery uses MAL search/rankings, and `mal:*` results
open through MAL details while remaining inside the AniList catalog mode. The
normal AniList path is retried on later reads and automatically becomes primary
again when it succeeds. Exact airing-calendar data has no MAL equivalent, so
that screen keeps using its local cache during an AniList outage.

Watch Order keeps Shikimori franchise membership as its boundary. AniList
relations and dates remain preferred, but an AniList failure rebuilds the same
membership from MAL details plus Shikimori links. If MAL is unavailable,
Shikimori's public title/poster/episode metadata supplies a smaller fallback.
Any valid expired Watch Order cache remains usable when discovery is offline;
fallback results use a short cache lifetime so AniList is retried after
recovery. MAL-backed detail pages can open Watch Order directly, and progress
is matched by stable MAL identity when no AniList id is available.

## Data flow

```text
UI / playback
    -> UserMediaPatch
    -> canonical local UserMediaState
    -> one coalescing SyncJournalEntry
       -> AniList adapter
       -> MAL adapter
       -> Shikimori adapter
```

Only the selected catalog can create local entries or change their tracking
fields on refresh. Destination snapshots confirm deliveries, resolve identity
mappings, and queue corrections from the canonical local values. Remote-only
destination titles are neither imported nor deleted; a verified local tombstone
is required to mirror a deletion. Unknown catalog-specific fields are left alone.
Mirror repairs do not change local edit timestamps or field revisions and are
not exported as new edits through Google Drive.

`MediaIdentity` owns the stable local id and the known AniList, MAL, and
Shikimori ids. A newly fetched provider record is joined by any known id; the
existing local id is retained while missing mappings are added. Shikimori's
explicit id is stored when its library supplies it. Writes preserve the
existing behavior by using MAL id as Shikimori's anime `target_id`; the explicit
Shikimori id is used only when a returned record has no MAL mapping.

`UserMediaState` contains the provider-neutral status, progress, 0–10 score,
notes, repeat count, added/updated/start/completion dates, airing state,
average score, and format used by Library sorting and filters.
`ProviderUserMediaState` retains each provider's raw status, score, entry id,
timestamp, and opaque data. Adapters only send fields present in a patch, so
provider-only fields are not erased. MAL and Shikimori integer scores are
rounded only at their API boundary; the canonical decimal score and raw
per-provider snapshots remain local.

For a local addition, `createdAt` is written once and later edits only advance
`updatedAt`. A start date is added when local status/progress first indicates
watching, and a completion date is added on a local Completed transition.
Provider dates replace missing local metadata without being cleared by a
provider that does not expose the same field. MAL exposes no user-list added
date, so its first successful import time is kept as a stable local fallback
until a real date is learned from another provider.

MAL fallback records include available genres, media status, source, NSFW
classification, mean score, media format, and user start/finish/update data.
Existing AniList-only tags and licensed metadata remain cached when known;
they are never fabricated from MAL data.

## Offline and recovery

The journal and per-account deliveries are persisted in SQLite and coalesce
obsolete edits by stable media identity without deleting audit history. The
latest value for each touched field wins, while the
set of unacknowledged targets is unioned. Successful targets are removed one at
a time; failed or signed-out targets remain pending. The previous AniList, MAL,
and Shikimori queues are imported once and retained for backward-compatible
backup restore.

Edit/Add/status/score changes and watched-episode progress create or update the
canonical local entry before delivery is attempted. This also applies to a
`mal:*` fallback card that does not yet have an AniList id: Watch and Edit stay
available, the local Library and continue-watching state use the MAL identity,
and the AniList target remains queued. On recovery the AniList adapter resolves
the AniList id through `idMal` and then delivers the pending mutation.

Favorite is persisted separately from list membership, so tapping the heart
does not accidentally add a title to Planning. Its desired value is coalesced
in the same journal and targets AniList only. Delivery first reads AniList's
current favorite state and toggles only when needed, which makes outage replay
safe even if a previous mutation response was lost.

On refresh, the local state is available first. Independent provider lanes
fetch snapshots and deliver changes without waiting for another catalog's
network requests. Only the selected source reconciles genuine external edits
against local field edit dates; timestamp-only acknowledgments are not new edits.
Destination timestamps cannot overwrite any canonical tracking field. Changing
the selection retires the former sources' pending proposals and queued imports,
preserving local values and history until the new selected source is reconciled.

Playback progress never regresses a locally known Completed entry and preserves
Repeating status. The entry editor journals only fields the user actually
changed, so editing score or notes cannot rewrite status or progress. During an
outage those local patches are applied immediately and remain queued per target;
each provider independently acknowledges the same local patch. A failed source
never turns a destination into an inbound authority.

On startup/recovery, snapshots are reconciled before replaying older queued
writes. Persisted retries wake automatically; a successful fetch can also add
a missing identity mapping so blocked delivery can resume.

## Main implementation files

- `lib/features/tracking/domain/tracking_sync_models.dart`: canonical identity,
  user state, patches, journal entries, health, mappings, conflict policy.
- `lib/features/tracking/data/tracking_sync_store.dart`: versioned persistence
  and legacy-queue migration.
- `lib/features/tracking/application/local_first_sync_engine.dart`: provider
  ordering, local merge, journal replay, and recovery.
- `lib/features/tracking/application/tracker_sync_coordinator.dart`: Riverpod
  facade and AniList/MAL/Shikimori adapters.
- `lib/features/tracking/application/anilist_library_provider.dart`: existing
  AniList cache and selected-source/local-library fallback on failure.
- `lib/features/catalog/application/catalog_repository.dart`: AniList-first
  Board/Discovery/details reads with MAL catalog fallback.
- `lib/features/media_details/presentation/media_details_page.dart` and player
  flow: provider-neutral Watch/Edit actions and local progress for fallback ids.
- `lib/features/tracking/data/shikimori_api_client.dart`: retains explicit
  Shikimori and MAL ids without changing title/search behavior.
- `test/tracking_sync_architecture_test.dart`: identity, queue migration,
  coalescing, outage, recovery, health, and conflict regressions.
