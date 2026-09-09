# Local-first tracking sync

MiruShin treats AniList, MyAnimeList, and Shikimori as independent adapters
around one local model. AniList remains the default primary source. MAL and
Shikimori can provide an anime-library fallback when the preferred provider is
unavailable, and every connected provider can independently acknowledge a
local edit. No provider reads from or writes to another provider.

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

The single journal is persisted in SharedPreferences and coalesces edits by
stable media identity. The latest value for each touched field wins, while the
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

On refresh, the local state is available first. Providers are tried in order,
starting with the configured primary (AniList by default); failures update the
persisted provider health state and the next connected adapter is attempted.
Pending local fields win conflicts. When a primary-provider snapshot exists it
remains canonical even if a fallback response is newer; a fallback may fill a
missing title but cannot passively move an AniList Completed entry back to
Watching. Provider timestamps only choose between snapshots with the same
authority, or between fallback providers when no primary snapshot exists. All
raw provider snapshots are kept regardless of the canonical winner.

Playback progress never regresses a locally known Completed entry and preserves
Repeating status. The entry editor journals only fields the user actually
changed, so editing score or notes cannot rewrite status or progress. During an
outage those local patches are applied immediately and remain queued per target;
delivery always attempts the configured primary first, after which MAL and
Shikimori acknowledge the same local patch independently. A failed primary
attempt never turns either fallback into an authority over another provider.

When AniList recovers, its queued mutations are replayed before refresh. A
successful fetch can also add a missing identity mapping, after which the
journal is replayed once more.

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
  AniList cache plus MAL/Shikimori fallback on failure.
- `lib/features/catalog/application/catalog_repository.dart`: AniList-first
  Board/Discovery/details reads with MAL catalog fallback.
- `lib/features/media_details/presentation/media_details_page.dart` and player
  flow: provider-neutral Watch/Edit actions and local progress for fallback ids.
- `lib/features/tracking/data/shikimori_api_client.dart`: retains explicit
  Shikimori and MAL ids without changing title/search behavior.
- `test/tracking_sync_architecture_test.dart`: identity, queue migration,
  coalescing, outage, recovery, health, and conflict regressions.
