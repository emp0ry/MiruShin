import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/anilist_models.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';

abstract class TrackingSyncStore {
  Future<List<UserMediaState>> loadStates();

  Future<void> saveStates(List<UserMediaState> states);

  Future<List<SyncJournalEntry>> loadJournal();

  Future<void> saveJournal(List<SyncJournalEntry> entries);

  Future<List<LocalMediaFavoriteState>> loadFavorites();

  Future<void> saveFavorites(List<LocalMediaFavoriteState> favorites);

  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth();

  Future<void> saveHealth(Map<TrackerSource, TrackerProviderHealth> health);
}

/// Versioned local persistence for canonical user state, identity mappings,
/// provider health and the single offline mutation journal.
class SharedPreferencesTrackingSyncStore implements TrackingSyncStore {
  const SharedPreferencesTrackingSyncStore();

  static const String statesKey = 'tracking.userMedia.v1';
  static const String journalKey = 'tracking.syncJournal.v1';
  static const String favoritesKey = 'tracking.favorites.v1';
  static const String healthKey = 'tracking.providerHealth.v1';
  static const String _migrationKey = 'tracking.syncJournal.v1.migrated';

  @override
  Future<List<UserMediaState>> loadStates() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getStringList(statesKey), UserMediaState.fromJson);
  }

  @override
  Future<void> saveStates(List<UserMediaState> states) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      statesKey,
      states.map((UserMediaState state) => jsonEncode(state.toJson())).toList(),
    );
  }

  @override
  Future<List<SyncJournalEntry>> loadJournal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _migrateLegacyQueues(prefs);
    return _decodeList(
      prefs.getStringList(journalKey),
      SyncJournalEntry.fromJson,
    );
  }

  @override
  Future<void> saveJournal(List<SyncJournalEntry> entries) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      journalKey,
      entries
          .map((SyncJournalEntry entry) => jsonEncode(entry.toJson()))
          .toList(),
    );
  }

  @override
  Future<List<LocalMediaFavoriteState>> loadFavorites() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _decodeList(
      prefs.getStringList(favoritesKey),
      LocalMediaFavoriteState.fromJson,
    );
  }

  @override
  Future<void> saveFavorites(List<LocalMediaFavoriteState> favorites) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      favoritesKey,
      favorites
          .map(
            (LocalMediaFavoriteState favorite) => jsonEncode(favorite.toJson()),
          )
          .toList(),
    );
  }

  @override
  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<TrackerProviderHealth> values = _decodeList(
      prefs.getStringList(healthKey),
      TrackerProviderHealth.fromJson,
    );
    return <TrackerSource, TrackerProviderHealth>{
      for (final TrackerProviderHealth value in values) value.provider: value,
    };
  }

  @override
  Future<void> saveHealth(
    Map<TrackerSource, TrackerProviderHealth> health,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      healthKey,
      health.values
          .map((TrackerProviderHealth value) => jsonEncode(value.toJson()))
          .toList(),
    );
  }

  Future<void> _migrateLegacyQueues(SharedPreferences prefs) async {
    if (prefs.getBool(_migrationKey) == true) return;

    final List<SyncJournalEntry> entries = _decodeList(
      prefs.getStringList(journalKey),
      SyncJournalEntry.fromJson,
    );
    final DateTime now = DateTime.now().toUtc();
    _importAniListQueue(
      entries,
      prefs.getStringList('anilist.pendingEdits'),
      now,
    );
    _importSecondaryQueue(
      entries,
      prefs.getStringList('mal.pendingEdits'),
      TrackerSource.mal,
      now,
    );
    _importSecondaryQueue(
      entries,
      prefs.getStringList('shikimori.pendingEdits'),
      TrackerSource.shikimori,
      now,
    );
    final List<SyncJournalEntry> coalesced = _coalesce(entries);
    await prefs.setStringList(
      journalKey,
      coalesced
          .map((SyncJournalEntry entry) => jsonEncode(entry.toJson()))
          .toList(),
    );
    // Old keys are intentionally retained for one release so backups made by
    // older MiruShin builds remain readable. The marker prevents re-import.
    await prefs.setBool(_migrationKey, true);
  }

  void _importAniListQueue(
    List<SyncJournalEntry> target,
    List<String>? raw,
    DateTime now,
  ) {
    for (final Map<String, dynamic> json in _jsonMaps(raw)) {
      final int? mediaId = _positiveInt(json['mediaId']);
      if (mediaId == null) continue;
      final bool delete = json['kind'] == 'delete';
      final Set<UserMediaField> fields = <UserMediaField>{
        if (json.containsKey('status')) UserMediaField.status,
        if (json.containsKey('progress')) UserMediaField.progress,
        if (json.containsKey('score')) UserMediaField.score,
        if (json.containsKey('notes')) UserMediaField.notes,
        if (json.containsKey('repeat')) UserMediaField.repeat,
      };
      final int? entryId = _positiveInt(json['entryId']);
      target.add(
        SyncJournalEntry(
          identity: MediaIdentity(
            localId: 'anime:anilist:$mediaId',
            anilistId: mediaId,
          ),
          patch: UserMediaPatch(
            status: json['status'] == null
                ? null
                : AniListListStatusLabel.fromGraphQl('${json['status']}'),
            progress: json['progress'] == null
                ? null
                : _nonNegativeInt(json['progress']),
            score: (json['score'] as num?)?.toDouble(),
            notes: json['notes']?.toString(),
            repeat: json['repeat'] == null
                ? null
                : _nonNegativeInt(json['repeat']),
            delete: delete,
            fields: fields,
          ),
          pendingTargets: const <TrackerSource>{TrackerSource.anilist},
          createdAt: now,
          updatedAt: now,
          providerEntryIds: <TrackerSource, int>{
            TrackerSource.anilist: ?entryId,
          },
        ),
      );
    }
  }

  void _importSecondaryQueue(
    List<SyncJournalEntry> target,
    List<String>? raw,
    TrackerSource source,
    DateTime now,
  ) {
    for (final Map<String, dynamic> json in _jsonMaps(raw)) {
      final int? malId = _positiveInt(json['malId']);
      if (malId == null) continue;
      final String? statusName = json['status']?.toString();
      final Set<UserMediaField> fields = <UserMediaField>{
        if (statusName != null) UserMediaField.status,
        if (json.containsKey('progress')) UserMediaField.progress,
        if (json.containsKey('score')) UserMediaField.score,
      };
      target.add(
        SyncJournalEntry(
          identity: MediaIdentity(localId: 'anime:mal:$malId', malId: malId),
          patch: UserMediaPatch(
            status: statusName == null
                ? null
                : AniListListStatus.values.firstWhere(
                    (AniListListStatus value) => value.name == statusName,
                    orElse: () => AniListListStatus.current,
                  ),
            progress: json['progress'] == null
                ? null
                : _nonNegativeInt(json['progress']),
            score: (json['score'] as num?)?.toDouble(),
            fields: fields,
          ),
          pendingTargets: <TrackerSource>{source},
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  List<SyncJournalEntry> _coalesce(List<SyncJournalEntry> entries) {
    final List<SyncJournalEntry> result = <SyncJournalEntry>[];
    for (final SyncJournalEntry entry in entries) {
      final int index = result.indexWhere(
        (SyncJournalEntry current) => current.identity.matches(entry.identity),
      );
      if (index < 0) {
        result.add(entry);
      } else {
        result[index] = result[index].mergedWith(entry);
      }
    }
    return result;
  }

  static List<T> _decodeList<T>(
    List<String>? raw,
    T Function(Map<String, dynamic>) decode,
  ) {
    return _jsonMaps(raw).map(decode).toList();
  }

  static Iterable<Map<String, dynamic>> _jsonMaps(List<String>? raw) sync* {
    for (final String value in raw ?? const <String>[]) {
      try {
        final Object? decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) yield decoded;
      } catch (_) {
        // Corrupt individual records are ignored; the remaining journal stays
        // replayable.
      }
    }
  }

  static int _nonNegativeInt(Object? value) {
    final int parsed = value is num
        ? value.toInt()
        : int.tryParse('${value ?? ''}') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static int? _positiveInt(Object? value) {
    final int parsed = _nonNegativeInt(value);
    return parsed > 0 ? parsed : null;
  }
}
