import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/download_models.dart';

/// Persists the downloads registry and resolves on-disk paths.
///
/// Layout under `{applicationSupport}/downloads`:
/// ```
/// registry.json
/// {mediaId}/{addonId}/S{season}E{ep}/   <- DownloadedEpisode.relDir
///     video.mp4 | index.m3u8 (+ seg_*.ts, key.bin)
///     sub_{lang}.{ext}
/// ```
/// The registry stores paths **relative** to the root so they survive the
/// sandbox container path changing between launches.
class DownloadStore {
  static const String _registryFile = 'registry.json';

  String? _rootPath;

  String? get rootPathOrNull => _rootPath;

  Future<Directory> root() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory dir = Directory(p.join(support.path, 'downloads'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _rootPath = dir.path;
    return dir;
  }

  Future<String> rootPath() async => (await root()).path;

  /// Absolute path to an episode's video file.
  String videoPath(String rootPath, DownloadedEpisode episode) =>
      p.join(rootPath, episode.relDir, episode.videoFileName);

  String filePath(
    String rootPath,
    DownloadedEpisode episode,
    String fileName,
  ) => p.join(rootPath, episode.relDir, fileName);

  /// Relative directory for a new episode download.
  String relDirFor({
    required String mediaId,
    required String addonId,
    required int seasonNumber,
    required double episodeNumber,
  }) {
    final String epToken =
        (episodeNumber == episodeNumber.roundToDouble()
                ? episodeNumber.round().toString()
                : episodeNumber.toString())
            .replaceAll('.', '_');
    return p.join(
      sanitizeForPath(mediaId),
      sanitizeForPath(addonId),
      'S${seasonNumber}E$epToken',
    );
  }

  Future<Directory> ensureEpisodeDir(
    String rootPath,
    DownloadedEpisode episode,
  ) async {
    final Directory dir = Directory(p.join(rootPath, episode.relDir));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<DownloadedEpisode>> load() async {
    try {
      final Directory dir = await root();
      final File file = File(p.join(dir.path, _registryFile));
      if (!file.existsSync()) return <DownloadedEpisode>[];
      final String raw = await file.readAsString();
      if (raw.trim().isEmpty) return <DownloadedEpisode>[];
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <DownloadedEpisode>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DownloadedEpisode.fromJson)
          .where((DownloadedEpisode e) => e.id.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      debugPrint('DownloadStore.load failed: $error');
      return <DownloadedEpisode>[];
    }
  }

  Future<void> save(List<DownloadedEpisode> episodes) async {
    try {
      final Directory dir = await root();
      final File file = File(p.join(dir.path, _registryFile));
      await file.writeAsString(
        jsonEncode(episodes.map((DownloadedEpisode e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (error) {
      debugPrint('DownloadStore.save failed: $error');
    }
  }

  /// Removes the on-disk files for an episode (its whole directory).
  Future<void> deleteEpisodeFiles(DownloadedEpisode episode) async {
    try {
      final String rootPath = await this.rootPath();
      final Directory dir = Directory(p.join(rootPath, episode.relDir));
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      // Best effort: prune now-empty addon/media parent directories.
      await _pruneEmptyParents(rootPath, dir.parent);
    } catch (error) {
      debugPrint('DownloadStore.deleteEpisodeFiles failed: $error');
    }
  }

  Future<void> _pruneEmptyParents(String rootPath, Directory dir) async {
    Directory current = dir;
    while (p.isWithin(rootPath, current.path)) {
      if (!current.existsSync()) {
        current = current.parent;
        continue;
      }
      final bool empty = current.listSync().isEmpty;
      if (!empty) break;
      final Directory parent = current.parent;
      await current.delete();
      current = parent;
    }
  }

  /// Total bytes used by all downloads on disk.
  Future<int> totalSizeBytes() async {
    try {
      final Directory dir = await root();
      int total = 0;
      await for (final FileSystemEntity entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> deleteAll() async {
    try {
      final Directory dir = await root();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
    } catch (error) {
      debugPrint('DownloadStore.deleteAll failed: $error');
    }
  }
}
