import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../watch/domain/normalized_models.dart';

final localLibraryProvider =
    NotifierProvider<LocalLibraryController, List<LibraryItem>>(
      LocalLibraryController.new,
    );

class LocalLibraryController extends Notifier<List<LibraryItem>> {
  static const String _storageKey = 'library.localItems';
  static const String _episodeProgressKey = 'library.episodeProgress';
  SharedPreferences? _preferences;
  bool _loading = false;
  bool _episodeProgressLoaded = false;
  Future<void>? _episodeProgressLoadFuture;
  Map<String, EpisodeProgress> _episodeProgress = <String, EpisodeProgress>{};

  @override
  List<LibraryItem> build() {
    if (!_loading) {
      _loading = true;
      unawaited(_load());
      unawaited(_ensureEpisodeProgressLoaded());
    }
    return const <LibraryItem>[];
  }

  EpisodeProgress? episodeProgress(String mediaId, int season, double episode) {
    return _episodeProgress[_episodeKey(mediaId, season, episode)];
  }

  Future<EpisodeProgress?> loadEpisodeProgress(
    String mediaId,
    int season,
    double episode,
  ) async {
    await _ensureEpisodeProgressLoaded();
    return episodeProgress(mediaId, season, episode);
  }

  Future<void> saveEpisodeProgress({
    required String mediaId,
    required int season,
    required double episode,
    required int positionSeconds,
    int? durationSeconds,
    bool completed = false,
  }) async {
    await _ensureEpisodeProgressLoaded();
    final String key = _episodeKey(mediaId, season, episode);
    _episodeProgress = Map<String, EpisodeProgress>.from(_episodeProgress)
      ..[key] = EpisodeProgress(
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        updatedAt: DateTime.now(),
        completed: completed,
      );
    await _persistEpisodeProgress();
  }

  String _episodeKey(String mediaId, int season, double episode) =>
      '$mediaId|S${season}E$episode';

  Future<void> _ensureEpisodeProgressLoaded() {
    if (_episodeProgressLoaded) {
      return Future<void>.value();
    }
    return _episodeProgressLoadFuture ??= _loadEpisodeProgress();
  }

  Future<void> _loadEpisodeProgress() async {
    final SharedPreferences preferences = await _prefs();
    final String? raw = preferences.getString(_episodeProgressKey);
    if (raw == null || raw.isEmpty) {
      _episodeProgressLoaded = true;
      return;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      _episodeProgress = <String, EpisodeProgress>{
        for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
          if (entry.key is String && entry.value is Map<String, dynamic>)
            entry.key as String: EpisodeProgress.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      };
    } catch (_) {
      // Ignore corrupt progress cache and start fresh instead of blocking playback.
    } finally {
      _episodeProgressLoaded = true;
    }
  }

  Future<void> _persistEpisodeProgress() async {
    final SharedPreferences preferences = await _prefs();
    await preferences.setString(
      _episodeProgressKey,
      jsonEncode(
        _episodeProgress.map(
          (String key, EpisodeProgress value) =>
              MapEntry<String, dynamic>(key, value.toJson()),
        ),
      ),
    );
  }

  bool contains(String mediaId) {
    return state.any((LibraryItem item) => item.mediaItem.id == mediaId);
  }

  LibraryItem? find(String mediaId) {
    for (final LibraryItem item in state) {
      if (item.mediaItem.id == mediaId) {
        return item;
      }
    }
    return null;
  }

  Future<void> addToLibrary(
    MediaItem media, {
    LibraryStatus status = LibraryStatus.planned,
    double progress = 0,
  }) async {
    final DateTime now = DateTime.now();
    final LibraryItem? existing = find(media.id);
    final LibraryItem item = LibraryItem(
      id: existing?.id ?? 'local:${media.id}',
      mediaItem: media,
      status: status,
      progress: progress,
      addedAt: existing?.addedAt ?? now,
      updatedAt: now,
      trackingSyncState: 'Local',
    );

    state = <LibraryItem>[
      item,
      ...state.where((LibraryItem current) => current.mediaItem.id != media.id),
    ];
    await _persist();
  }

  Future<void> markWatched(MediaItem media) {
    return addToLibrary(media, status: LibraryStatus.completed, progress: 1);
  }

  Future<void> remove(String mediaId) async {
    state = state
        .where((LibraryItem item) => item.mediaItem.id != mediaId)
        .toList(growable: false);
    await _persist();
  }

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<void> _load() async {
    final SharedPreferences preferences = await _prefs();
    final String? raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return;
      }
      final List<LibraryItem> loaded = decoded
          .whereType<Map<String, dynamic>>()
          .map(LibraryItem.fromJson)
          .where((LibraryItem item) => item.mediaItem.id.isNotEmpty)
          .toList(growable: false);
      if (state.isEmpty) {
        state = loaded;
        return;
      }

      final Set<String> currentIds = state
          .map((LibraryItem item) => item.mediaItem.id)
          .toSet();
      state = <LibraryItem>[
        ...state,
        ...loaded.where(
          (LibraryItem item) => !currentIds.contains(item.mediaItem.id),
        ),
      ];
      await _persist();
    } catch (_) {
      state = const <LibraryItem>[];
    }
  }

  Future<void> _persist() async {
    final SharedPreferences preferences = await _prefs();
    await preferences.setString(
      _storageKey,
      jsonEncode(
        state.map((LibraryItem item) => item.toJson()).toList(growable: false),
      ),
    );
  }
}
