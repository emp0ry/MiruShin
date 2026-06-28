import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/models/media_item.dart';
import '../../addons/application/sora_addons_provider.dart';
import '../../addons/domain/sora_models.dart';
import '../../addons/domain/sora_parsers.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../watch/domain/normalized_models.dart';
import '../data/download_engine.dart';
import '../data/download_store.dart';
import '../domain/download_models.dart';

final downloadStoreProvider = Provider<DownloadStore>((Ref ref) {
  return DownloadStore();
});

final downloadEngineProvider = Provider<DownloadEngine>((Ref ref) {
  return DownloadEngine();
});

final downloadsProvider =
    NotifierProvider<DownloadController, List<DownloadedEpisode>>(
      DownloadController.new,
    );

/// `addonId|episodeHref` -> status, for fast badge lookups in the episode picker.
final downloadedKeysProvider = Provider<Map<String, DownloadStatus>>((Ref ref) {
  final List<DownloadedEpisode> list = ref.watch(downloadsProvider);
  return <String, DownloadStatus>{
    for (final DownloadedEpisode e in list)
      '${e.addonId}|${e.episodeHref}': e.status,
  };
});

class DownloadController extends Notifier<List<DownloadedEpisode>> {
  late DownloadStore _store;
  late DownloadEngine _engine;
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  Future<void>? _initFuture;
  bool _pumping = false;
  String? _rootPath;
  Timer? _persistTimer;

  @override
  List<DownloadedEpisode> build() {
    _store = ref.read(downloadStoreProvider);
    _engine = ref.read(downloadEngineProvider);
    ref.onDispose(() {
      _persistTimer?.cancel();
      for (final CancelToken token in _tokens.values) {
        token.cancel('disposed');
      }
      _tokens.clear();
    });
    _initFuture ??= _init();
    return const <DownloadedEpisode>[];
  }

  Future<void> _init() async {
    _rootPath = await _store.rootPath();
    final List<DownloadedEpisode> loaded = await _store.load();
    // Anything left mid-flight from a previous run is re-queued so it resumes
    // automatically on launch. Explicitly paused/failed items are left alone.
    state = loaded
        .map(
          (DownloadedEpisode e) => e.status == DownloadStatus.downloading
              ? e.copyWith(status: DownloadStatus.queued)
              : e,
        )
        .toList(growable: false);
    unawaited(_pump());
  }

  Future<void> _ensureLoaded() => _initFuture ??= _init();

  String? get rootPath => _rootPath;

  /// Absolute path to a downloaded episode's playable file.
  String? videoPathFor(DownloadedEpisode episode) {
    final String? root = _rootPath;
    if (root == null) return null;
    return _store.videoPath(root, episode);
  }

  String? filePathFor(DownloadedEpisode episode, String fileName) {
    final String? root = _rootPath;
    if (root == null) return null;
    return p.join(root, episode.relDir, fileName);
  }

  // ---- Queries -------------------------------------------------------------

  DownloadedEpisode? _byId(String id) {
    for (final DownloadedEpisode e in state) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<DownloadedTitle> titlesForCatalog(CatalogMode mode) {
    return groupDownloadsByTitle(
      state
          .where((DownloadedEpisode e) => _matchesCatalog(e.media, mode))
          .toList(growable: false),
    );
  }

  List<DownloadedEpisode> episodesFor(String mediaId) {
    return state
        .where((DownloadedEpisode e) => e.mediaId == mediaId)
        .toList(growable: false)
      ..sort((DownloadedEpisode a, DownloadedEpisode b) {
        final int s = a.seasonNumber.compareTo(b.seasonNumber);
        if (s != 0) return s;
        return a.episodeNumber.compareTo(b.episodeNumber);
      });
  }

  bool _matchesCatalog(MediaItem media, CatalogMode mode) {
    final bool isTmdb = media.id.startsWith('tmdb:');
    return mode == CatalogMode.tmdb ? isTmdb : !isTmdb;
  }

  // ---- Mutations -----------------------------------------------------------

  Future<void> enqueue({
    required MediaItem item,
    required SoraSearchResult source,
    required SoraEpisode episode,
    required int seasonNumber,
    DownloadStreamPreference streamPreference = DownloadStreamPreference.empty,
  }) async {
    await _ensureLoaded();
    final String id = '${item.id}::${source.addonId}::${episode.href}';
    if (_byId(id) != null) return;

    final SoraInstalledAddon? addon = ref
        .read(soraAddonsProvider)
        .byId(source.addonId);
    final String addonName = addon?.manifest.sourceName.isNotEmpty == true
        ? addon!.manifest.sourceName
        : source.addonName;
    // The actual resolved stream is sniffed in _process; queued records use a
    // harmless placeholder so unreliable module-level hints don't persist.
    const DownloadKind kind = DownloadKind.mp4;

    final String relDir = _store.relDirFor(
      mediaId: item.id,
      addonId: source.addonId,
      seasonNumber: seasonNumber,
      episodeNumber: episode.number,
    );
    final DateTime now = DateTime.now();
    final DownloadedEpisode record = DownloadedEpisode(
      id: id,
      mediaId: item.id,
      media: item,
      addonId: source.addonId,
      addonName: addonName,
      episodeHref: episode.href,
      episodeNumber: episode.number,
      seasonNumber: seasonNumber,
      episodeTitle: episode.title,
      episodeImage: episode.image,
      qualityLabel: '',
      kind: kind,
      relDir: relDir,
      videoFileName: kind == DownloadKind.hls ? 'index.m3u8' : 'video.mp4',
      streamPreference: streamPreference,
      episodeData: _episodeToMap(episode),
      openingStart: episode.openingStart,
      openingEnd: episode.openingEnd,
      endingStart: episode.endingStart,
      endingEnd: episode.endingEnd,
      status: DownloadStatus.queued,
      createdAt: now,
      updatedAt: now,
    );
    state = <DownloadedEpisode>[...state, record];
    await _persist();
    unawaited(_pump());
  }

  Future<void> pauseResume(String id) async {
    final DownloadedEpisode? e = _byId(id);
    if (e == null) return;
    if (e.status == DownloadStatus.downloading ||
        e.status == DownloadStatus.queued) {
      _tokens[id]?.cancel('paused');
      _updateById(
        id,
        (DownloadedEpisode x) => x.copyWith(status: DownloadStatus.paused),
      );
      await _persist();
    } else if (e.status == DownloadStatus.paused ||
        e.status == DownloadStatus.failed) {
      _updateById(
        id,
        (DownloadedEpisode x) =>
            x.copyWith(status: DownloadStatus.queued, clearError: true),
      );
      await _persist();
      unawaited(_pump());
    }
  }

  Future<void> retry(String id) => pauseResume(id);

  Future<void> delete(String id) async {
    final DownloadedEpisode? e = _byId(id);
    if (e == null) return;
    _tokens[id]?.cancel('deleted');
    state = state
        .where((DownloadedEpisode x) => x.id != id)
        .toList(growable: false);
    await _store.deleteEpisodeFiles(e);
    await _persist();
  }

  Future<void> deleteTitle(String mediaId) async {
    final List<DownloadedEpisode> toDelete = state
        .where((DownloadedEpisode e) => e.mediaId == mediaId)
        .toList(growable: false);
    for (final DownloadedEpisode e in toDelete) {
      _tokens[e.id]?.cancel('deleted');
    }
    state = state
        .where((DownloadedEpisode e) => e.mediaId != mediaId)
        .toList(growable: false);
    for (final DownloadedEpisode e in toDelete) {
      await _store.deleteEpisodeFiles(e);
    }
    await _persist();
  }

  Future<void> deleteAll() async {
    for (final CancelToken token in _tokens.values) {
      token.cancel('deleted');
    }
    _tokens.clear();
    state = const <DownloadedEpisode>[];
    await _store.deleteAll();
    await _persist();
  }

  // ---- Queue runner --------------------------------------------------------

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        DownloadedEpisode? next;
        for (final DownloadedEpisode e in state) {
          if (e.status == DownloadStatus.queued) {
            next = e;
            break;
          }
        }
        if (next == null) break;
        await _process(next);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _process(DownloadedEpisode item) async {
    final CancelToken token = CancelToken();
    _tokens[item.id] = token;
    _updateById(
      item.id,
      (DownloadedEpisode e) =>
          e.copyWith(status: DownloadStatus.downloading, clearError: true),
    );
    await _persist();

    try {
      final String rootPath = _rootPath ??= await _store.rootPath();
      final SoraInstalledAddon? addon = ref
          .read(soraAddonsProvider)
          .byId(item.addonId);
      if (addon == null) {
        throw Exception('Module “${item.addonName}” is not installed.');
      }

      final SoraEpisode episode = _episodeFromMap(item.episodeData, item);
      final SoraResolvedStreams streams = await ref
          .read(soraJsRuntimeProvider)
          .extractStreams(addon: addon, episode: episode, voiceover: null);
      if (token.isCancelled) throw const DownloadCancelledException();

      final NormalizedStreamBundle bundle = parseSoraStreamBundle(
        streams,
        streamType: addon.manifest.streamType,
      );
      if (bundle.availableServers.isEmpty) {
        throw Exception('No downloadable stream was returned.');
      }

      final _StreamPick? pick = item.streamPreference.isEmpty
          ? _pickHighest(bundle)
          : _pickPreferred(bundle, item.streamPreference);
      if (pick == null) {
        if (item.streamPreference.isEmpty) {
          throw const DownloadUnsupportedException(
            "This module's stream can't be downloaded directly "
            '(in-app playback only). Try a different module.',
          );
        }
        throw const DownloadUnsupportedException(
          'Selected stream is not available for this episode. '
          'Choose another stream.',
        );
      }
      final DownloadKind? kind = await _engine.sniffKind(
        url: pick.url,
        headers: pick.headers,
        streamTypeHint: bundle.streamType,
        cancelToken: token,
      );
      if (kind == null) {
        throw const DownloadUnsupportedException(
          'This stream format cannot be downloaded.',
        );
      }
      final String videoFileName = kind == DownloadKind.hls
          ? 'index.m3u8'
          : 'video.mp4';
      _updateById(
        item.id,
        (DownloadedEpisode e) => e.copyWith(
          kind: kind,
          qualityLabel: pick.qualityLabel,
          videoFileName: videoFileName,
          totalBytes: 0,
          receivedBytes: 0,
          totalSegments: 0,
          doneSegments: 0,
        ),
      );
      debugPrint(
        '[Download] addon=${item.addonId} episode=${item.displayNumber} '
        'kind=${kind.name} url=${pick.url}',
      );

      final DownloadedEpisode current = _byId(item.id) ?? item;
      final dir = await _store.ensureEpisodeDir(rootPath, current);

      if (kind == DownloadKind.mp4) {
        await _engine.downloadFile(
          url: pick.url,
          headers: pick.headers,
          dirPath: dir.path,
          fileName: videoFileName,
          cancelToken: token,
          onProgress: (int received, int total) {
            _updateById(
              item.id,
              (DownloadedEpisode e) =>
                  e.copyWith(receivedBytes: received, totalBytes: total),
            );
            _schedulePersist();
          },
        );
      } else {
        await _engine.downloadHls(
          playlistUrl: pick.url,
          headers: pick.headers,
          dirPath: dir.path,
          cancelToken: token,
          onPlaylistParsed: (int total) {
            _updateById(
              item.id,
              (DownloadedEpisode e) => e.copyWith(totalSegments: total),
            );
          },
          onProgress: (int done, int total, int bytes) {
            _updateById(
              item.id,
              (DownloadedEpisode e) => e.copyWith(
                doneSegments: done,
                totalSegments: total,
                receivedBytes: bytes,
              ),
            );
            _schedulePersist();
          },
        );
      }
      if (token.isCancelled) throw const DownloadCancelledException();

      final List<DownloadedSubtitle> subs = <DownloadedSubtitle>[];
      for (final NormalizedSubtitle s in bundle.subtitles) {
        if (token.isCancelled) break;
        final DownloadedSubtitle? d = await _engine.downloadSubtitle(
          url: s.url,
          language: s.language,
          label: s.label,
          headers: s.headers.isNotEmpty ? s.headers : pick.headers,
          dirPath: dir.path,
          cancelToken: token,
        );
        if (d != null) subs.add(d);
      }

      _updateById(
        item.id,
        (DownloadedEpisode e) => e.copyWith(
          status: DownloadStatus.completed,
          subtitles: subs,
          clearError: true,
        ),
      );
    } on DownloadCancelledException {
      final DownloadedEpisode? e = _byId(item.id);
      if (e != null && e.status == DownloadStatus.downloading) {
        _updateById(
          item.id,
          (DownloadedEpisode x) => x.copyWith(status: DownloadStatus.paused),
        );
      }
    } catch (error) {
      debugPrint('Download failed (${item.id}): $error');
      _updateById(
        item.id,
        (DownloadedEpisode e) =>
            e.copyWith(status: DownloadStatus.failed, error: error.toString()),
      );
    } finally {
      _tokens.remove(item.id);
      await _persist();
    }
  }

  // ---- Helpers -------------------------------------------------------------

  void _updateById(
    String id,
    DownloadedEpisode Function(DownloadedEpisode) transform,
  ) {
    bool changed = false;
    final List<DownloadedEpisode> next = <DownloadedEpisode>[];
    for (final DownloadedEpisode e in state) {
      if (e.id == id) {
        next.add(transform(e));
        changed = true;
      } else {
        next.add(e);
      }
    }
    if (changed) state = next;
  }

  void _schedulePersist() {
    _persistTimer ??= Timer(const Duration(seconds: 2), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _store.save(state);
  }

  /// Picks the best directly-downloadable (http/https) stream. Embed-aggregator
  /// modules (e.g. Kodik/CVH iframes) hand back non-http descriptors that mpv
  /// can't open and we can't download — those return null so the caller fails
  /// cleanly instead of crashing on `Uri.parse`.
  _StreamPick? _pickHighest(NormalizedStreamBundle bundle) {
    // Prefer the player's default server, then any other server.
    final List<NormalizedServer> servers = <NormalizedServer>[
      bundle.selectedServer,
      ...bundle.availableServers.where(
        (NormalizedServer s) => s.id != bundle.selectedServer.id,
      ),
    ];

    for (final NormalizedServer server in servers) {
      NormalizedQuality? best;
      int bestHeight = -1;
      for (final NormalizedQuality q in server.qualities) {
        if (!_isHttpUrl(q.streamUrl)) continue;
        final int h = _heightFromLabel(q.label);
        if (h > bestHeight) {
          bestHeight = h;
          best = q;
        }
      }
      if (best != null) {
        return _StreamPick(
          url: best.streamUrl,
          headers: _headersFor(bundle, server, best.headers),
          qualityLabel: best.label,
        );
      }
      if (_isHttpUrl(server.streamUrl)) {
        return _StreamPick(
          url: server.streamUrl,
          headers: _headersFor(bundle, server, const <String, String>{}),
          qualityLabel: bundle.selectedQuality?.label ?? '',
        );
      }
    }
    return null;
  }

  _StreamPick? _pickPreferred(
    NormalizedStreamBundle bundle,
    DownloadStreamPreference preference,
  ) {
    final NormalizedServer? server = _preferredServer(bundle, preference);
    if (server == null) return null;

    final String qualityLabel = preference.qualityLabel.trim().toLowerCase();
    if (qualityLabel.isNotEmpty) {
      for (final NormalizedQuality quality in server.qualities) {
        if (quality.label.trim().toLowerCase() != qualityLabel) continue;
        if (!_isHttpUrl(quality.streamUrl)) return null;
        return _StreamPick(
          url: quality.streamUrl,
          headers: _headersFor(bundle, server, quality.headers),
          qualityLabel: quality.label,
        );
      }
      return null;
    }

    if (_isHttpUrl(server.streamUrl)) {
      return _StreamPick(
        url: server.streamUrl,
        headers: _headersFor(bundle, server, const <String, String>{}),
        qualityLabel: server.qualities.isNotEmpty
            ? server.qualities.first.label
            : '',
      );
    }
    return null;
  }

  NormalizedServer? _preferredServer(
    NormalizedStreamBundle bundle,
    DownloadStreamPreference preference,
  ) {
    final String serverTitle = preference.serverTitle.trim().toLowerCase();
    if (serverTitle.isNotEmpty) {
      for (final NormalizedServer server in bundle.availableServers) {
        if (server.title.trim().toLowerCase() == serverTitle) return server;
      }
    }

    final String serverId = preference.serverId.trim();
    if (serverId.isNotEmpty) {
      for (final NormalizedServer server in bundle.availableServers) {
        if (server.id == serverId) return server;
      }
    }
    return null;
  }

  Map<String, String> _headersFor(
    NormalizedStreamBundle bundle,
    NormalizedServer server,
    Map<String, String> primary,
  ) {
    if (primary.isNotEmpty) return primary;
    if (server.headers.isNotEmpty) return server.headers;
    return bundle.headers;
  }

  bool _isHttpUrl(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  int _heightFromLabel(String label) {
    final String l = label.toLowerCase();
    if (l.contains('4k') || l.contains('2160')) return 2160;
    if (l.contains('1440') || l == '2k') return 1440;
    final RegExpMatch? m = RegExp(r'(\d{3,4})').firstMatch(l);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    if (l.contains('fhd')) return 1080;
    if (l.contains('hd')) return 720;
    return 0;
  }

  Map<String, dynamic> _episodeToMap(SoraEpisode e) => <String, dynamic>{
    'number': e.number,
    'href': e.href,
    'title': e.title,
    'image': e.image,
    'description': e.description,
    'duration': e.duration,
    if (e.openingStart != null) 'openingStart': e.openingStart,
    if (e.openingEnd != null) 'openingEnd': e.openingEnd,
    if (e.endingStart != null) 'endingStart': e.endingStart,
    if (e.endingEnd != null) 'endingEnd': e.endingEnd,
    'metadataTitle': e.metadataTitle,
    'metadataImage': e.metadataImage,
    'tvdbTitle': e.tvdbTitle,
    'raw': e.raw,
  };

  SoraEpisode _episodeFromMap(Map<String, dynamic> m, DownloadedEpisode fb) {
    if (m.isEmpty) {
      return SoraEpisode(
        number: fb.episodeNumber,
        href: fb.episodeHref,
        title: fb.episodeTitle,
        image: fb.episodeImage,
        description: '',
        duration: '',
      );
    }
    return SoraEpisode(
      number: (m['number'] as num?)?.toDouble() ?? fb.episodeNumber,
      href: m['href'] as String? ?? fb.episodeHref,
      title: m['title'] as String? ?? fb.episodeTitle,
      image: m['image'] as String? ?? fb.episodeImage,
      description: m['description'] as String? ?? '',
      duration: m['duration'] as String? ?? '',
      openingStart: (m['openingStart'] as num?)?.toInt(),
      openingEnd: (m['openingEnd'] as num?)?.toInt(),
      endingStart: (m['endingStart'] as num?)?.toInt(),
      endingEnd: (m['endingEnd'] as num?)?.toInt(),
      metadataTitle: m['metadataTitle'] as String? ?? '',
      metadataImage: m['metadataImage'] as String? ?? '',
      tvdbTitle: m['tvdbTitle'] as String? ?? '',
      raw:
          (m['raw'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}

class _StreamPick {
  const _StreamPick({
    required this.url,
    required this.headers,
    required this.qualityLabel,
  });
  final String url;
  final Map<String, String> headers;
  final String qualityLabel;
}
