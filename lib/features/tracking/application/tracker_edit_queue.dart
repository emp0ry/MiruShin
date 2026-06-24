import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/anilist_models.dart';

/// A pending tracker edit, merged per anime so the latest desired state wins.
class TrackerPendingEdit {
  const TrackerPendingEdit({
    required this.malId,
    this.status,
    this.progress,
    this.score,
  });

  final int malId;
  final AniListListStatus? status;
  final int? progress;
  final double? score;

  TrackerPendingEdit mergedWith(TrackerPendingEdit other) {
    return TrackerPendingEdit(
      malId: malId,
      status: other.status ?? status,
      progress: other.progress ?? progress,
      score: other.score ?? score,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'malId': malId,
        if (status != null) 'status': status!.name,
        if (progress != null) 'progress': progress,
        if (score != null) 'score': score,
      };

  static TrackerPendingEdit? fromJson(Map<String, dynamic> json) {
    final Object? id = json['malId'];
    final int malId = id is int ? id : int.tryParse('${id ?? ''}') ?? 0;
    if (malId <= 0) return null;
    final String? statusName = json['status'] as String?;
    return TrackerPendingEdit(
      malId: malId,
      status: statusName == null
          ? null
          : AniListListStatus.values.firstWhere(
              (AniListListStatus s) => s.name == statusName,
              orElse: () => AniListListStatus.current,
            ),
      progress: (json['progress'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toDouble(),
    );
  }
}

/// Offline queue of tracker edits for a single service, persisted under
/// [storageKey] in SharedPreferences. Mirrors `AniListEditQueue` but keyed by
/// MAL id (shared by MyAnimeList and Shikimori).
class TrackerEditQueue {
  const TrackerEditQueue(this.storageKey);

  final String storageKey;

  Future<void> upsert(TrackerPendingEdit edit) async {
    final List<TrackerPendingEdit> edits = await load();
    final int index =
        edits.indexWhere((TrackerPendingEdit e) => e.malId == edit.malId);
    if (index >= 0) {
      edits[index] = edits[index].mergedWith(edit);
    } else {
      edits.add(edit);
    }
    await save(edits);
  }

  Future<void> remove(int malId) async {
    final List<TrackerPendingEdit> edits = await load();
    edits.removeWhere((TrackerPendingEdit e) => e.malId == malId);
    await save(edits);
  }

  Future<List<TrackerPendingEdit>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(storageKey) ?? const <String>[];
    return raw
        .map((String value) {
          try {
            final Object? decoded = jsonDecode(value);
            return decoded is Map<String, dynamic>
                ? TrackerPendingEdit.fromJson(decoded)
                : null;
          } catch (_) {
            return null;
          }
        })
        .whereType<TrackerPendingEdit>()
        .toList();
  }

  Future<void> save(List<TrackerPendingEdit> edits) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey,
      edits.map((TrackerPendingEdit e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
