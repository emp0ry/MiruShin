import '../../../shared/models/anilist_models.dart';

/// The tracker whose library feeds the in-app Library view. Progress is still
/// pushed to every connected tracker regardless of this selection.
enum TrackerSource {
  anilist,
  mal,
  shikimori;

  static TrackerSource fromName(String? name) {
    return TrackerSource.values.firstWhere(
      (TrackerSource s) => s.name == name,
      orElse: () => TrackerSource.anilist,
    );
  }

  String get label {
    return switch (this) {
      TrackerSource.anilist => 'AniList',
      TrackerSource.mal => 'MyAnimeList',
      TrackerSource.shikimori => 'Shikimori',
    };
  }
}

/// Minimal signed-in user info shared by the MAL/Shikimori trackers.
class TrackerViewer {
  const TrackerViewer({required this.id, required this.name, this.avatarUrl});

  final int id;
  final String name;
  final String? avatarUrl;
}

/// Maps the app's canonical [AniListListStatus] to/from MyAnimeList status
/// strings. MAL has no "repeating" status (it uses an `is_rewatching` flag), so
/// repeating is represented as `watching`.
extension MalListStatus on AniListListStatus {
  String get malValue {
    return switch (this) {
      AniListListStatus.current => 'watching',
      AniListListStatus.repeating => 'watching',
      AniListListStatus.planning => 'plan_to_watch',
      AniListListStatus.completed => 'completed',
      AniListListStatus.dropped => 'dropped',
      AniListListStatus.paused => 'on_hold',
    };
  }

  /// Whether MAL should mark this entry as a rewatch.
  bool get malIsRewatching => this == AniListListStatus.repeating;

  /// Maps the app's canonical status to a Shikimori user_rate status.
  String get shikimoriValue {
    return switch (this) {
      AniListListStatus.current => 'watching',
      AniListListStatus.repeating => 'rewatching',
      AniListListStatus.planning => 'planned',
      AniListListStatus.completed => 'completed',
      AniListListStatus.dropped => 'dropped',
      AniListListStatus.paused => 'on_hold',
    };
  }
}

AniListListStatus malStatusToCanonical(String? value) {
  return switch (value) {
    'watching' => AniListListStatus.current,
    'plan_to_watch' => AniListListStatus.planning,
    'completed' => AniListListStatus.completed,
    'dropped' => AniListListStatus.dropped,
    'on_hold' => AniListListStatus.paused,
    _ => AniListListStatus.planning,
  };
}

AniListListStatus shikimoriStatusToCanonical(String? value) {
  return switch (value) {
    'watching' => AniListListStatus.current,
    'rewatching' => AniListListStatus.repeating,
    'planned' => AniListListStatus.planning,
    'completed' => AniListListStatus.completed,
    'dropped' => AniListListStatus.dropped,
    'on_hold' => AniListListStatus.paused,
    _ => AniListListStatus.planning,
  };
}
