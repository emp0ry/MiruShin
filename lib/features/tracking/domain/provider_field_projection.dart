import 'package:collection/collection.dart';
import '../../../shared/models/anilist_models.dart';

import 'tracker_models.dart';
import 'tracking_sync_models.dart';

/// The same projection is used for importing, sending and confirming fields.
/// A provider cannot acknowledge a field it cannot store or did not return.
Set<UserMediaField> providerEntryFields(
  TrackerSource source, {
  String mediaKind = 'anime',
}) =>
    {
      ...switch (source) {
        TrackerSource.anilist => const {
          UserMediaField.status,
          UserMediaField.progress,
          UserMediaField.progressVolumes,
          UserMediaField.score,
          UserMediaField.notes,
          UserMediaField.repeat,
          UserMediaField.startedAt,
          UserMediaField.completedAt,
          UserMediaField.priority,
          UserMediaField.private,
          UserMediaField.hiddenFromStatusLists,
          UserMediaField.customLists,
          UserMediaField.advancedScores,
        },
        TrackerSource.mal => const {
          UserMediaField.status,
          UserMediaField.progress,
          UserMediaField.progressVolumes,
          UserMediaField.score,
          UserMediaField.notes,
          UserMediaField.repeat,
          UserMediaField.startedAt,
          UserMediaField.completedAt,
          UserMediaField.malPriority,
          UserMediaField.malRewatchValue,
          UserMediaField.malTags,
        },
        TrackerSource.shikimori => const {
          UserMediaField.status,
          UserMediaField.progress,
          UserMediaField.progressVolumes,
          UserMediaField.score,
          UserMediaField.notes,
          UserMediaField.repeat,
        },
      },
    }..removeAll(
      mediaKind == 'manga' ? const {} : {UserMediaField.progressVolumes},
    );

bool providerReturnedField(
  UserMediaState state,
  TrackerSource source,
  UserMediaField field,
) {
  final present = state.providerStates[source]?.data['presentFields'];
  // Legacy snapshots/tests predate presence metadata. Live clients always set it.
  return present is! List || present.contains(field.name);
}

Object? providerFieldValue(UserMediaState state, UserMediaField field) {
  final al = state.providerStates[TrackerSource.anilist]?.data ?? const {};
  final mal = state.providerStates[TrackerSource.mal]?.data ?? const {};
  return switch (field) {
    UserMediaField.status => state.status.name,
    UserMediaField.progress => state.progress,
    UserMediaField.progressVolumes => state.progressVolumes,
    UserMediaField.score => state.score ?? 0.0,
    UserMediaField.notes => state.notes,
    UserMediaField.repeat => state.repeat,
    UserMediaField.startedAt => _day(state.startedAt),
    UserMediaField.completedAt => _day(state.completedAt),
    UserMediaField.priority => al['priority'] ?? 0,
    UserMediaField.private => al['private'] ?? false,
    UserMediaField.hiddenFromStatusLists =>
      al['hiddenFromStatusLists'] ?? false,
    UserMediaField.customLists => al['customLists'] ?? const {},
    UserMediaField.advancedScores => al['advancedScores'] ?? const {},
    UserMediaField.malPriority => mal['priority'] ?? 0,
    UserMediaField.malRewatchValue =>
      mal[state.identity.mediaKind == 'manga'
              ? 'rereadValue'
              : 'rewatchValue'] ??
          0,
    UserMediaField.malTags => mal['tags'] ?? const [],
    _ => null,
  };
}

bool providerConfirmsPatch(
  UserMediaPatch patch,
  UserMediaState remote,
  TrackerSource source,
) {
  final values = patch.toJson();
  for (final field in patch.fields.intersection(
    providerEntryFields(source, mediaKind: remote.identity.mediaKind),
  )) {
    if (!providerReturnedField(remote, source, field)) return false;
    Object? desired = values[field.name];
    Object? actual = providerFieldValue(remote, field);
    if (field == UserMediaField.startedAt ||
        field == UserMediaField.completedAt) {
      desired = _day(DateTime.tryParse('$desired'));
    } else if (field == UserMediaField.score) {
      final score = (desired as num?)?.toDouble() ?? 0.0;
      final remoteScore = (actual as num?)?.toDouble() ?? 0.0;
      if (source == TrackerSource.anilist
          ? (score - remoteScore).abs() > 0.001
          : score.round() != remoteScore.round()) {
        return false;
      }
      continue;
    } else if (field == UserMediaField.notes) {
      desired ??= '';
    } else if ({
      UserMediaField.progress,
      UserMediaField.progressVolumes,
      UserMediaField.repeat,
      UserMediaField.priority,
      UserMediaField.malPriority,
      UserMediaField.malRewatchValue,
    }.contains(field)) {
      desired ??= 0;
    } else if ({
      UserMediaField.private,
      UserMediaField.hiddenFromStatusLists,
    }.contains(field)) {
      desired ??= false;
    }
    if (field == UserMediaField.malTags) desired ??= const [];
    // An absent false/zero custom-list/category key is the provider's default.
    if (field == UserMediaField.customLists ||
        field == UserMediaField.advancedScores) {
      Map normalize(Object? value) => {
        if (value is Map)
          for (final entry in value.entries)
            if (entry.value != false && entry.value != 0)
              entry.key: entry.value,
      };
      desired = normalize(desired);
      actual = normalize(actual);
    }
    if (!const DeepCollectionEquality.unordered().equals(desired, actual)) {
      return false;
    }
  }
  return true;
}

String? _day(DateTime? date) => date == null
    ? null
    : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool providerResponseConfirmsPatch(
  Map<String, dynamic>? response,
  UserMediaPatch patch,
  TrackerSource source,
  String kind,
) {
  if (response == null) return false;
  final manga = kind == 'manga';
  final keys = switch (source) {
    TrackerSource.anilist => {
      for (final field in providerEntryFields(source, mediaKind: kind))
        field: field.name,
    },
    TrackerSource.mal => {
      UserMediaField.status: 'status',
      UserMediaField.score: 'score',
      UserMediaField.progress: manga
          ? 'num_chapters_read'
          : 'num_episodes_watched',
      UserMediaField.progressVolumes: 'num_volumes_read',
      UserMediaField.notes: 'comments',
      UserMediaField.repeat: manga ? 'num_times_reread' : 'num_times_rewatched',
      UserMediaField.startedAt: 'start_date',
      UserMediaField.completedAt: 'finish_date',
      UserMediaField.malPriority: 'priority',
      UserMediaField.malTags: 'tags',
      UserMediaField.malRewatchValue: manga ? 'reread_value' : 'rewatch_value',
    },
    TrackerSource.shikimori => {
      UserMediaField.status: 'status',
      UserMediaField.score: 'score',
      UserMediaField.progress: manga ? 'chapters' : 'episodes',
      UserMediaField.progressVolumes: 'volumes',
      UserMediaField.notes: 'text',
      UserMediaField.repeat: 'rewatches',
    },
  };
  final desired = patch.toJson();
  for (final field in patch.fields.intersection(
    providerEntryFields(source, mediaKind: kind),
  )) {
    final key = keys[field]!;
    if (!response.containsKey(key) &&
        !(source == TrackerSource.mal &&
            (field == UserMediaField.startedAt ||
                field == UserMediaField.completedAt) &&
            desired[field.name] == null &&
            response.containsKey('updated_at') &&
            response.containsKey('score') &&
            response.containsKey(
              manga ? 'num_chapters_read' : 'num_episodes_watched',
            ))) {
      return false;
    }
    Object? actual = response[key];
    Object? wanted = desired[field.name];
    if (field == UserMediaField.status) {
      actual = switch (source) {
        TrackerSource.anilist => AniListListStatusLabel.fromGraphQl(
          '$actual',
        ).name,
        TrackerSource.mal =>
          response[manga ? 'is_rereading' : 'is_rewatching'] == true
              ? AniListListStatus.repeating.name
              : malStatusToCanonical('$actual').name,
        TrackerSource.shikimori => shikimoriStatusToCanonical('$actual').name,
      };
    } else if (field == UserMediaField.startedAt ||
        field == UserMediaField.completedAt) {
      wanted = _day(DateTime.tryParse('$wanted'));
      if (actual is Map) {
        actual =
            actual['year'] == null ||
                actual['month'] == null ||
                actual['day'] == null
            ? null
            : _day(
                DateTime(
                  actual['year'] as int,
                  actual['month'] as int,
                  actual['day'] as int,
                ),
              );
      } else {
        actual = _day(DateTime.tryParse('$actual'));
      }
    } else if (field == UserMediaField.score) {
      final a = (actual as num?)?.toDouble() ?? 0;
      final b = (wanted as num?)?.toDouble() ?? 0;
      if (source == TrackerSource.anilist
          ? (a - b).abs() > 0.001
          : a.round() != b.round()) {
        return false;
      }
      continue;
    } else if (field == UserMediaField.notes) {
      actual ??= '';
      wanted ??= '';
    } else if ({
      UserMediaField.progress,
      UserMediaField.progressVolumes,
      UserMediaField.repeat,
      UserMediaField.priority,
      UserMediaField.malPriority,
      UserMediaField.malRewatchValue,
    }.contains(field)) {
      actual ??= 0;
      wanted ??= 0;
    } else if ({
      UserMediaField.private,
      UserMediaField.hiddenFromStatusLists,
    }.contains(field)) {
      actual ??= false;
      wanted ??= false;
    } else if (field == UserMediaField.malTags) {
      actual ??= const [];
      wanted ??= const [];
    } else if (field == UserMediaField.customLists ||
        field == UserMediaField.advancedScores) {
      Map normalize(Object? value) => {
        if (value is Map)
          for (final entry in value.entries)
            if (entry.value != false && entry.value != 0)
              entry.key: entry.value,
      };
      actual = normalize(actual);
      wanted = normalize(wanted);
    }
    if (!const DeepCollectionEquality.unordered().equals(actual, wanted)) {
      return false;
    }
  }
  return true;
}
