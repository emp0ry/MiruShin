# v2.6.5 fullscreen comparison checklist

Reference: `4331397332d5e80709b888d71246f16af82e8d27` (`v2.6.5`)

Regression source: `d2f6005774fc5300ee5017d8c9913f9e2d8d73aa`

## Code audit

| File | v2.6.5 behavior | `d2f600` change | Current restoration |
| --- | --- | --- | --- |
| `player_page.dart` | Captured `_isFullscreen`, combined it with the route's `_shouldStartFullscreen`, preserved system UI only on mobile, stopped online playback without delaying the route pop, and returned the state in the existing route result. | Replaced the formula with `advancing && currentFullscreen`, preserved fullscreen system UI on desktop too, and routed behavior through a new helper. | Restored the release formula and mobile-only preservation. Online stop/pop ordering matches the release; offline waits for teardown only so auto-delete cannot race open decoder/file handles. |
| `watch_page.dart` | Owned its platform-sensitive `_exitFullscreen()` and used it when a pending fullscreen continuation was cleared. | Replaced the page-local behavior with `PlayerFullscreenTransfer`. | Restored the release method and call site. |
| `player_models.dart` | Route results transported fullscreen state; no helper defined its semantics. | Added `fullscreenForPlayerAdvance` and a direct-route wrapper. | Removed the semantic helper. Kept `DirectPlayerRouteArgs` as an offline data-only adapter. |
| `router.dart` | Constructed `PlayerPage` directly from route data. | Added `PlayerPage.fromDirectRouteArgs`. | Translates the offline wrapper directly into the existing `PlayerPage` constructor. |
| `offline_title_page.dart` | Not present in the release lifecycle. | Used the generic transfer helper for offline continuation. | Propagates the route-result boolean through `DirectPlayerRouteArgs`; a small page-local exit restores UI only when no downloaded continuation exists. |
| `player_fullscreen_transfer.dart` | Did not exist. | Centralized `SystemChrome` and desktop method-channel calls. | Deleted. |

The lifecycle oracle is: capture the release state in `PlayerPage` -> begin
player teardown -> pop the player route with its result -> resolve the next
episode on the owning page -> construct the next `PlayerPage` with that result.

## Automated comparison coverage

- `test/player_fullscreen_transition_test.dart`: exercises a real player route,
  native fullscreen synchronization, exit via Next, and the release-specific
  `wasFullscreen || _shouldStartFullscreen` result behavior.
- `test/offline_playback_test.dart`: exercises result-to-downloaded-episode
  continuation, data-only route transport, next/select/no-next cases, and the
  resulting `PlayerPage` arguments.

## Manual behavior matrix

Run every row first with the v2.6.5 build and then with the corrected current
build. Record platform and result; do not infer a pass from unit tests.

| Scenario | v2.6.5 observed | Current observed | Match |
| --- | --- | --- | --- |
| Online E1 windowed -> manual Next -> E2 |  |  | [ ] |
| Online E1 fullscreen -> auto-next -> E2 |  |  | [ ] |
| Online E1 fullscreen -> manual Next -> E2 |  |  | [ ] |
| Online E1 fullscreen -> select E4 -> E4 |  |  | [ ] |
| Start fullscreen -> manually exit -> next episode |  |  | [ ] |
| Close player without advancing -> watch/details page |  |  | [ ] |
| Downloaded E1 fullscreen -> downloaded E2 | N/A |  | [ ] |
| Downloaded E1 with auto-delete -> resources deleted -> E2 | N/A |  | [ ] |

Repeat applicable rows on Windows, macOS, Linux, Android, and iOS because the
release intentionally distinguishes desktop fullscreen from mobile immersive
system UI.

## Manual seek-preview matrix

For each row record the selected quality, detected type, extraction path,
result, cold latency, and warm latency.

| Source | Expected path | Result and latency |
| --- | --- | --- |
| Explicit `.m3u8` | Indexed HLS segments; no type probe |  |
| Extensionless `#EXTM3U` | Probe -> indexed HLS segments |  |
| Extensionless direct video declared HLS | Probe -> direct libav with original URL and headers |  |
| Known failing okcdn-style URL | Probe actual response; direct libav when it is media |  |
| Single-quality online | Lowest/only quality |  |
| Multi-quality online | Lowest valid quality with per-bucket fallback |  |
| Offline MP4 | Exact downloaded file |  |
| Offline HLS | Exact downloaded playlist and segments |  |
| Offline DASH | Exact downloaded source |  |
