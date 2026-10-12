import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../shared/models/media_item.dart';
import '../../tracking/domain/tracking_sync_models.dart';

/// A repository-local, bounded read-through cache, never a source of truth.
/// Every read still queries SQLite and compares the exact serialized row. This
/// also handles writes made in another transaction, imports and rollbacks.
class TrackingStateDecoder {
  TrackingStateDecoder({
    this.maximumEntries = 1024,
    this.maximumJsonBytes = 32 * 1024 * 1024,
  });

  final int maximumEntries;
  final int maximumJsonBytes;
  final _cache = <String, (String, UserMediaState?)>{};
  int _jsonBytes = 0;

  Future<List<UserMediaState>> decode(List<(String, String)> rows) async {
    final missing = <(String, String)>[];
    final decoded = <String, UserMediaState?>{};
    for (final row in rows) {
      final cached = _cache.remove(row.$1);
      if (cached != null) {
        if (cached.$1 == row.$2) {
          _cache[row.$1] = cached;
          decoded[row.$1] = cached.$2;
          continue;
        }
        _jsonBytes -= cached.$1.length * 2;
      }
      missing.add(row);
    }
    if (missing.isNotEmpty) {
      // Moving only changed rows avoids repeatedly copying the whole rich
      // library into an isolate for a one-episode progress update.
      final values =
          !kIsWeb &&
              (missing.length > 8 ||
                  missing.fold<int>(0, (n, row) => n + row.$2.length) > 32768)
          ? await compute(
              _decodeTrackingStates,
              missing.map((row) => row.$2).toList(growable: false),
              debugLabel: 'MiruShin changed Library rows',
            )
          : await _decodeInBatches(missing);
      for (int i = 0; i < missing.length; i++) {
        final row = missing[i];
        final value = values[i];
        decoded[row.$1] = value;
        final previous = _cache.remove(row.$1);
        if (previous != null) _jsonBytes -= previous.$1.length * 2;
        if (row.$2.length * 2 > maximumJsonBytes || maximumEntries <= 0) {
          continue;
        }
        _cache[row.$1] = (row.$2, value);
        _jsonBytes += row.$2.length * 2;
        while (_cache.length > maximumEntries ||
            _jsonBytes > maximumJsonBytes) {
          final removed = _cache.remove(_cache.keys.first)!;
          _jsonBytes -= removed.$1.length * 2;
        }
      }
    }
    return <UserMediaState>[for (final row in rows) ?decoded[row.$1]]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}

Future<List<UserMediaState?>> _decodeInBatches(
  List<(String, String)> rows,
) async {
  final result = <UserMediaState?>[];
  for (int start = 0; start < rows.length; start += 8) {
    if (start > 0) await Future<void>.delayed(Duration.zero);
    result.addAll(
      _decodeTrackingStates(
        rows.skip(start).take(8).map((row) => row.$2).toList(growable: false),
      ),
    );
  }
  return result;
}

List<UserMediaState?> _decodeTrackingStates(List<String> encoded) => [
  for (final json in encoded) _decodeTrackingState(json),
];

UserMediaState? _decodeTrackingState(String encoded) {
  try {
    final json = jsonDecode(encoded);
    if (json is! Map<String, dynamic>) return null;
    final value = UserMediaState.fromJson(json);
    final media = value.mediaItem;
    // Reusing decoded values is safe only when callers cannot mutate them.
    return UserMediaState(
      identity: value.identity,
      mediaItem: media.copyWith(
        genres: List.unmodifiable(media.genres),
        aliases: List.unmodifiable(media.aliases),
        externalIds: Map.unmodifiable(media.externalIds),
        seasons: List.unmodifiable(
          media.seasons.map(
            (season) => MediaSeason(
              seasonNumber: season.seasonNumber,
              name: season.name,
              episodeCount: season.episodeCount,
              posterUrl: season.posterUrl,
              overview: season.overview,
              originalName: season.originalName,
              aliases: List.unmodifiable(season.aliases),
              externalIds: Map.unmodifiable(season.externalIds),
              isSpecials: season.isSpecials,
              year: season.year,
              rating: season.rating,
              format: season.format,
              relationType: season.relationType,
            ),
          ),
        ),
      ),
      status: value.status,
      progress: value.progress,
      progressVolumes: value.progressVolumes,
      score: value.score,
      notes: value.notes,
      repeat: value.repeat,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      startedAt: value.startedAt,
      completedAt: value.completedAt,
      nextEpisode: value.nextEpisode,
      airingAt: value.airingAt,
      avgScore: value.avgScore,
      format: value.format,
      source: value.source,
      providerStates: Map.unmodifiable({
        for (final entry in value.providerStates.entries)
          entry.key: ProviderUserMediaState(
            provider: entry.value.provider,
            entryId: entry.value.entryId,
            rawStatus: entry.value.rawStatus,
            rawScore: entry.value.rawScore,
            updatedAt: entry.value.updatedAt,
            data: _freezeJson(entry.value.data) as Map<String, dynamic>,
          ),
      }),
    );
  } on Object {
    // A malformed entry never prevents the remaining Library from loading.
    return null;
  }
}

Object? _freezeJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, value) => MapEntry(key, _freezeJson(value))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  return value;
}
