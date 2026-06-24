import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/anilist_models.dart';
import '../../settings/presentation/settings_state.dart';
import '../data/mal_api_client.dart';
import '../data/shikimori_api_client.dart';
import '../domain/tracker_models.dart';
import 'tracker_sync_coordinator.dart';

/// Reads the anime library from the chosen primary tracker, mapped into the
/// shared folder/entry model so the existing Library UI can render it. Returns
/// an empty list when the primary is AniList (that path has its own provider)
/// or when the primary service is signed out.
///
/// Pending edits for connected trackers are flushed opportunistically whenever
/// this provider runs, mirroring how the AniList library flushes its queue.
final trackerAnimeListProvider =
    FutureProvider<List<AniListAnimeListFolder>>((Ref ref) async {
  final SettingsState settings = ref.watch(settingsProvider);
  final SettingsController controller = ref.read(settingsProvider.notifier);

  unawaited(ref.read(trackerSyncCoordinatorProvider).flushPending());

  switch (settings.effectivePrimaryTrackerSource) {
    case TrackerSource.mal:
      final String? token = await controller.validMalAccessToken();
      if (token == null) return const <AniListAnimeListFolder>[];
      return MalApiClient(
        accessToken: token,
        onRefreshToken: controller.refreshMalToken,
      ).fetchAnimeList();
    case TrackerSource.shikimori:
      final String? token = await controller.validShikimoriAccessToken();
      final int? userId = settings.shikimoriViewerId;
      if (token == null || userId == null) {
        return const <AniListAnimeListFolder>[];
      }
      return ShikimoriApiClient(
        accessToken: token,
        userId: userId,
        onRefreshToken: controller.refreshShikimoriToken,
      ).fetchAnimeList();
    case TrackerSource.anilist:
      return const <AniListAnimeListFolder>[];
  }
});
