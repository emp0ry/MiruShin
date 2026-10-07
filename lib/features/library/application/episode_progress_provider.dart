import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../watch/domain/normalized_models.dart';
import 'canonical_library_repository.dart';

/// Workspace-scoped, source-independent checkpoints. Includes Drive restores
/// immediately without loading or copying the entire compatibility history.
final mediaEpisodeProgressProvider = StreamProvider.autoDispose
    .family<Map<(int, double), EpisodeProgress>, String>((ref, mediaId) {
      return ref
          .watch(canonicalLibraryRepositoryProvider)
          .watchEpisodeProgress(mediaId)
          .map(
            (checkpoints) => {
              for (final entry in checkpoints.entries)
                entry.key: EpisodeProgress(
                  positionSeconds: entry.value.positionSeconds,
                  durationSeconds: entry.value.durationSeconds,
                  updatedAt: entry.value.updatedAt,
                  completed: entry.value.completed,
                ),
            },
          );
    });

/// Do not display a previous account's data while the workspace dependency
/// switches. Normal SQLite checkpoint emissions are not loading transitions.
Map<(int, double), EpisodeProgress> currentEpisodeCheckpoints(
  AsyncValue<Map<(int, double), EpisodeProgress>> state,
) => state.isLoading || state.hasError ? const {} : state.value ?? const {};

/// A present canonical checkpoint wins even when its value is 0/unwatched.
/// Source keys are read solely for older installations, never written here.
EpisodeProgress? sharedEpisodeProgress({
  required Map<(int, double), EpisodeProgress> checkpoints,
  required int season,
  required double episode,
  EpisodeProgress? compatible,
  EpisodeProgress? legacySource,
}) => checkpoints[(season, episode)] ?? compatible ?? legacySource;
