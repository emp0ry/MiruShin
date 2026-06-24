import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/anilist_models.dart';
import '../../settings/presentation/settings_state.dart';
import '../data/mal_api_client.dart';
import '../data/shikimori_api_client.dart';
import 'tracker_edit_queue.dart';

final malEditQueueProvider = Provider<TrackerEditQueue>(
  (Ref ref) => const TrackerEditQueue('mal.pendingEdits'),
);

final shikimoriEditQueueProvider = Provider<TrackerEditQueue>(
  (Ref ref) => const TrackerEditQueue('shikimori.pendingEdits'),
);

final trackerSyncCoordinatorProvider = Provider<TrackerSyncCoordinator>(
  (Ref ref) => TrackerSyncCoordinator(ref),
);

/// Fans out watch progress and entry edits to every connected secondary tracker
/// (MyAnimeList and Shikimori). AniList keeps its own dedicated push path. Each
/// service that is offline or errors enqueues the edit for a later flush.
class TrackerSyncCoordinator {
  TrackerSyncCoordinator(this._ref);

  final Ref _ref;

  static int? _malIdOf(Map<String, String> externalIds) {
    final int? id = int.tryParse(externalIds['mal'] ?? '');
    return (id != null && id > 0) ? id : null;
  }

  /// Pushes episode progress. [status] defaults to completed when [total] is
  /// reached, otherwise watching.
  Future<void> pushEpisodeProgress({
    required Map<String, String> externalIds,
    required int episode,
    int? total,
  }) async {
    final int? malId = _malIdOf(externalIds);
    if (malId == null) return;
    final AniListListStatus status =
        (total != null && total > 0 && episode >= total)
            ? AniListListStatus.completed
            : AniListListStatus.current;
    await pushEntryEdit(
      externalIds: externalIds,
      status: status,
      progress: episode,
    );
  }

  /// Pushes an arbitrary status/progress/score change.
  Future<void> pushEntryEdit({
    required Map<String, String> externalIds,
    AniListListStatus? status,
    int? progress,
    double? score,
  }) async {
    final int? malId = _malIdOf(externalIds);
    if (malId == null) return;
    await Future.wait<void>(<Future<void>>[
      _pushMal(malId, status: status, progress: progress, score: score),
      _pushShikimori(malId, status: status, progress: progress, score: score),
    ]);
  }

  SettingsState get _settings => _ref.read(settingsProvider);
  SettingsController get _controller => _ref.read(settingsProvider.notifier);

  Future<void> _pushMal(
    int malId, {
    AniListListStatus? status,
    int? progress,
    double? score,
  }) async {
    if (!_settings.hasMalSession) return;
    final TrackerPendingEdit edit = TrackerPendingEdit(
      malId: malId,
      status: status,
      progress: progress,
      score: score,
    );
    final String? token = await _controller.validMalAccessToken();
    if (token == null) {
      await _ref.read(malEditQueueProvider).upsert(edit);
      return;
    }
    try {
      await MalApiClient(
        accessToken: token,
        onRefreshToken: _controller.refreshMalToken,
      ).updateStatus(
        malId: malId,
        status: status,
        episodesWatched: progress,
        score: score,
      );
    } catch (_) {
      await _ref.read(malEditQueueProvider).upsert(edit);
    }
  }

  Future<void> _pushShikimori(
    int malId, {
    AniListListStatus? status,
    int? progress,
    double? score,
  }) async {
    if (!_settings.hasShikimoriSession) return;
    final int? userId = _settings.shikimoriViewerId;
    if (userId == null) return;
    final TrackerPendingEdit edit = TrackerPendingEdit(
      malId: malId,
      status: status,
      progress: progress,
      score: score,
    );
    final String? token = await _controller.validShikimoriAccessToken();
    if (token == null) {
      await _ref.read(shikimoriEditQueueProvider).upsert(edit);
      return;
    }
    try {
      await ShikimoriApiClient(
        accessToken: token,
        userId: userId,
        onRefreshToken: _controller.refreshShikimoriToken,
      ).updateUserRate(
        malId: malId,
        status: status,
        episodes: progress,
        score: score,
      );
    } catch (_) {
      await _ref.read(shikimoriEditQueueProvider).upsert(edit);
    }
  }

  /// Flushes any queued edits for connected trackers. Safe to call on app
  /// resume / reconnect; failures are left queued for the next attempt.
  Future<void> flushPending() async {
    await Future.wait<void>(<Future<void>>[
      _flushMal(),
      _flushShikimori(),
    ]);
  }

  Future<void> _flushMal() async {
    if (!_settings.hasMalSession) return;
    final TrackerEditQueue queue = _ref.read(malEditQueueProvider);
    final List<TrackerPendingEdit> edits = await queue.load();
    if (edits.isEmpty) return;
    final String? token = await _controller.validMalAccessToken();
    if (token == null) return;
    final MalApiClient client = MalApiClient(
      accessToken: token,
      onRefreshToken: _controller.refreshMalToken,
    );
    for (final TrackerPendingEdit edit in edits) {
      try {
        await client.updateStatus(
          malId: edit.malId,
          status: edit.status,
          episodesWatched: edit.progress,
          score: edit.score,
        );
        await queue.remove(edit.malId);
      } catch (_) {
        // Leave queued for the next flush.
      }
    }
  }

  Future<void> _flushShikimori() async {
    if (!_settings.hasShikimoriSession) return;
    final int? userId = _settings.shikimoriViewerId;
    if (userId == null) return;
    final TrackerEditQueue queue = _ref.read(shikimoriEditQueueProvider);
    final List<TrackerPendingEdit> edits = await queue.load();
    if (edits.isEmpty) return;
    final String? token = await _controller.validShikimoriAccessToken();
    if (token == null) return;
    final ShikimoriApiClient client = ShikimoriApiClient(
      accessToken: token,
      userId: userId,
      onRefreshToken: _controller.refreshShikimoriToken,
    );
    for (final TrackerPendingEdit edit in edits) {
      try {
        await client.updateUserRate(
          malId: edit.malId,
          status: edit.status,
          episodes: edit.progress,
          score: edit.score,
        );
        await queue.remove(edit.malId);
      } catch (_) {
        // Leave queued for the next flush.
      }
    }
  }
}
