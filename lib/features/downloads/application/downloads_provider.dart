import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/media_item.dart';
import '../../addons/application/sora_addons_provider.dart';
import '../../addons/application/sora_source_providers.dart';
import '../../addons/domain/sora_models.dart';
import '../../addons/domain/sora_parsers.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../watch/domain/normalized_models.dart';
import '../data/download_engine.dart';
import '../data/download_store.dart';
import '../domain/download_models.dart';
import 'download_episode_availability.dart';
import 'download_stream_candidates.dart';

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
    unawaited(_cacheMissingArtworkForCompletedDownloads());
    unawaited(_pump());
  }

  Future<void> _ensureLoaded() => _initFuture ??= _init();

  String? get rootPath => _rootPath;

  // Queries

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

  // Mutations

  Future<void> enqueue({
    required MediaItem item,
    required SoraSearchResult source,
    required SoraEpisode episode,
    required int seasonNumber,
    int? availableEpisodeLimit,
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
    final MediaItem storedItem =
        availableEpisodeLimit != null && availableEpisodeLimit > 0
        ? item.copyWith(
            externalIds: <String, String>{
              ...item.externalIds,
              downloadAvailableEpisodeLimitKey: availableEpisodeLimit
                  .toString(),
            },
          )
        : item;

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
      media: storedItem,
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
      videoFileName: kind == DownloadKind.mp4 ? 'video.mp4' : 'index.m3u8',
      streamPreference: streamPreference,
      episodeData: _episodeToMap(episode, source: source),
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

  // Queue runner

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

      SoraEpisode episode = _episodeFromMap(item.episodeData, item);
      SoraSearchResult? source = _sourceFromEpisodeMap(item.episodeData);
      SoraResolvedStreams streams = await ref
          .read(soraJsRuntimeProvider)
          .extractStreams(addon: addon, episode: episode, voiceover: null);
      if (token.isCancelled) throw const DownloadCancelledException();

      NormalizedStreamBundle bundle = parseSoraStreamBundle(
        streams,
        streamType: addon.manifest.streamType,
      );
      List<DownloadStreamCandidate> candidates = buildDownloadStreamCandidates(
        bundle,
        item.streamPreference,
      );
      final DownloadedEpisode current = _byId(item.id) ?? item;
      final dir = await _store.ensureEpisodeDir(rootPath, current);

      void onPlaylistParsed(int total) {
        _updateById(
          item.id,
          (DownloadedEpisode e) => e.copyWith(totalSegments: total),
        );
      }

      void onSegmentProgress(int done, int total, int bytes) {
        _updateById(
          item.id,
          (DownloadedEpisode e) => e.copyWith(
            doneSegments: done,
            totalSegments: total,
            receivedBytes: bytes,
          ),
        );
        _schedulePersist();
      }

      DownloadStreamCandidate? pick;
      Object? lastCandidateError;
      final List<Object> candidateErrors = <Object>[];
      final Set<String> attemptedUrls = <String>{};
      for (
        int resolutionRound = 0;
        resolutionRound < 2 && pick == null;
        resolutionRound += 1
      ) {
        for (int index = 0; index < candidates.length; index += 1) {
          final DownloadStreamCandidate candidate = candidates[index];
          attemptedUrls.add(candidate.url);
          try {
            await _engine.prepareMediaAttempt(
              dirPath: dir.path,
              // The marker is hashed by DownloadEngine. Including the resolved
              // URL prevents partial files from an expired descriptor being
              // mixed with segments returned by its refreshed replacement.
              candidateKey: stableDownloadCandidateKey(candidate),
            );
            final DownloadKind? kind = await _engine.sniffKind(
              url: candidate.url,
              headers: candidate.headers,
              streamTypeHint: bundle.streamType,
              cancelToken: token,
            );
            if (kind == null) {
              throw const DownloadUnsupportedException(
                'This stream format cannot be downloaded.',
              );
            }
            final String videoFileName = kind == DownloadKind.mp4
                ? 'video.mp4'
                : 'index.m3u8';
            _updateById(
              item.id,
              (DownloadedEpisode e) => e.copyWith(
                kind: kind,
                qualityLabel: candidate.qualityLabel,
                videoFileName: videoFileName,
                totalBytes: 0,
                receivedBytes: 0,
                totalSegments: 0,
                doneSegments: 0,
              ),
            );
            debugPrint(
              '[Download] episode=${item.displayNumber} '
              'resolution=${resolutionRound + 1}/2 '
              'attempt=${index + 1}/${candidates.length} kind=${kind.name}',
            );

            switch (kind) {
              case DownloadKind.mp4:
                await _engine.downloadFile(
                  url: candidate.url,
                  headers: candidate.headers,
                  dirPath: dir.path,
                  fileName: videoFileName,
                  cancelToken: token,
                  onProgress: (int received, int total) {
                    _updateById(
                      item.id,
                      (DownloadedEpisode e) => e.copyWith(
                        receivedBytes: received,
                        totalBytes: total,
                      ),
                    );
                    _schedulePersist();
                  },
                );
              case DownloadKind.hls:
                await _engine.downloadHls(
                  playlistUrl: candidate.url,
                  headers: candidate.headers,
                  dirPath: dir.path,
                  cancelToken: token,
                  onPlaylistParsed: onPlaylistParsed,
                  onProgress: onSegmentProgress,
                );
              case DownloadKind.dash:
                await _engine.downloadDash(
                  manifestUrl: candidate.url,
                  headers: candidate.headers,
                  dirPath: dir.path,
                  cancelToken: token,
                  onPlaylistParsed: onPlaylistParsed,
                  onProgress: onSegmentProgress,
                );
            }
            pick = candidate;
            break;
          } on DownloadCancelledException {
            rethrow;
          } on Object catch (error) {
            lastCandidateError = error;
            candidateErrors.add(error);
            if (kDebugMode) {
              debugPrint(
                '[Download] media attempt ${index + 1}/${candidates.length} '
                'failed: $error',
              );
            }
          }
        }

        if (pick != null || resolutionRound > 0) break;
        final bool descriptorMayBeStale =
            candidates.isEmpty || candidateErrors.any(_isStaleStreamFailure);
        if (!descriptorMayBeStale) break;

        final ({SoraEpisode episode, SoraSearchResult source})? refreshed =
            await _refreshDownloadEpisode(
              item: item,
              addon: addon,
              savedSource: source,
              cancelToken: token,
            );
        if (refreshed == null) break;
        if (token.isCancelled) throw const DownloadCancelledException();

        streams = await ref
            .read(soraJsRuntimeProvider)
            .extractStreams(
              addon: addon,
              episode: refreshed.episode,
              voiceover: null,
            );
        if (token.isCancelled) throw const DownloadCancelledException();
        final NormalizedStreamBundle refreshedBundle = parseSoraStreamBundle(
          streams,
          streamType: addon.manifest.streamType,
        );
        final List<DownloadStreamCandidate> refreshedCandidates =
            buildDownloadStreamCandidates(
              refreshedBundle,
              item.streamPreference,
            );
        if (refreshedCandidates.isEmpty ||
            refreshedCandidates.every(
              (DownloadStreamCandidate candidate) =>
                  attemptedUrls.contains(candidate.url),
            )) {
          break;
        }

        episode = refreshed.episode;
        source = refreshed.source;
        bundle = refreshedBundle;
        candidates = refreshedCandidates;
        _updateById(
          item.id,
          (DownloadedEpisode e) =>
              e.copyWith(episodeData: _episodeToMap(episode, source: source)),
        );
        await _persist();
        debugPrint(
          '[Download] refreshed the episode descriptor after terminal '
          'stream responses; retrying newly resolved qualities.',
        );
      }
      if (pick == null) {
        if (candidates.isEmpty && item.streamPreference.isEmpty) {
          throw const DownloadUnsupportedException(
            "This module's stream can't be downloaded directly "
            '(in-app playback only). Try a different module.',
          );
        }
        if (candidates.isEmpty) {
          throw const DownloadUnsupportedException(
            'Selected stream is not available for this episode. '
            'Choose another stream.',
          );
        }
        throw DownloadUnsupportedException(
          'All available stream qualities failed. '
          '${lastCandidateError ?? 'No compatible media was returned.'}',
        );
      }
      if (token.isCancelled) throw const DownloadCancelledException();

      final DownloadedEpisode artworkSource = _byId(item.id) ?? current;
      final DownloadedEpisode artworkUpdated = await _cacheArtwork(
        artworkSource,
        dirPath: dir.path,
        headers: pick.headers,
        cancelToken: token,
      );
      if (_artworkChanged(artworkSource, artworkUpdated)) {
        _updateById(item.id, (_) => artworkUpdated);
        _schedulePersist();
      }

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

  bool _isStaleStreamFailure(Object error) {
    if (error is! DioException || error.type != DioExceptionType.badResponse) {
      return false;
    }
    return switch (error.response?.statusCode) {
      400 || 401 || 403 || 404 || 410 => true,
      _ => false,
    };
  }

  Future<({SoraEpisode episode, SoraSearchResult source})?>
  _refreshDownloadEpisode({
    required DownloadedEpisode item,
    required SoraInstalledAddon addon,
    required SoraSearchResult? savedSource,
    required CancelToken cancelToken,
  }) async {
    final runtime = ref.read(soraJsRuntimeProvider);

    Future<SoraEpisode?> episodeFor(SoraSearchResult result) async {
      if (cancelToken.isCancelled) {
        throw const DownloadCancelledException();
      }
      try {
        final List<SoraEpisode> episodes = await runtime.extractEpisodes(
          addon: addon,
          result: result,
        );
        return _matchingDownloadEpisode(episodes, item);
      } on Object catch (error) {
        if (cancelToken.isCancelled) {
          throw const DownloadCancelledException();
        }
        if (kDebugMode) {
          debugPrint('[Download] episode descriptor refresh failed: $error');
        }
        return null;
      }
    }

    // New queue records retain the stable search result separately from the
    // episode descriptor. Re-extracting its episode list is the cheapest and
    // most accurate way to replace embedded, short-lived media data.
    if (savedSource != null) {
      final SoraEpisode? refreshed = await episodeFor(savedSource);
      if (refreshed != null) {
        return (episode: refreshed, source: savedSource);
      }
    }

    // Older persisted records do not contain their search result. Re-discover
    // it generically from the stored media titles, then match the same season
    // and episode number. No server or host knowledge is involved.
    final Set<String> titles = <String>{};
    void addTitle(String value) {
      final String title = value.trim();
      if (title.isNotEmpty) titles.add(title);
    }

    addTitle(savedSource?.query ?? '');
    addTitle(savedSource?.title ?? '');
    addTitle(item.media.title);
    addTitle(item.media.originalTitle);
    for (final String alias in item.media.aliases) {
      addTitle(alias);
    }
    addTitle(item.media.externalIds['sora_season_name'] ?? '');
    addTitle(item.media.externalIds['sora_season_original_name'] ?? '');
    for (final String alias
        in (item.media.externalIds['sora_season_aliases'] ?? '').split('\n')) {
      addTitle(alias);
    }
    if (titles.isEmpty) return null;

    final List<String> configuredLanguages = ref.read(
      soraSourceLanguagesProvider,
    );
    final List<String> languages = configuredLanguages.isEmpty
        ? SoraSearchLanguage.defaultPriority
        : configuredLanguages;
    final List<SoraTitleVariant> variants = <SoraTitleVariant>[
      for (final String language in languages)
        for (final String title in titles)
          SoraTitleVariant(
            languageCode: language,
            title: title,
            source: 'download-refresh',
          ),
    ];
    final Map<String, SoraSearchResult> results = <String, SoraSearchResult>{};
    for (final String query in titles.take(6)) {
      if (cancelToken.isCancelled) {
        throw const DownloadCancelledException();
      }
      try {
        final List<SoraSearchResult> found = await runtime.searchResults(
          addon: addon,
          keyword: query,
          languageCode: languages.first,
          titleVariants: variants,
          shouldCancel: () => cancelToken.isCancelled,
        );
        for (final SoraSearchResult result in found) {
          final SoraSearchResult? previous = results[result.href];
          if (previous == null || result.score > previous.score) {
            results[result.href] = result;
          }
        }
      } on Object catch (error) {
        if (cancelToken.isCancelled) {
          throw const DownloadCancelledException();
        }
        if (kDebugMode) {
          debugPrint('[Download] source refresh search failed: $error');
        }
      }
    }

    final List<SoraSearchResult> ordered = results.values.toList()
      ..sort(
        (SoraSearchResult a, SoraSearchResult b) => b.score.compareTo(a.score),
      );
    for (final SoraSearchResult result in ordered.take(6)) {
      final SoraEpisode? refreshed = await episodeFor(result);
      if (refreshed != null) {
        return (episode: refreshed, source: result);
      }
    }
    return null;
  }

  SoraEpisode? _matchingDownloadEpisode(
    List<SoraEpisode> episodes,
    DownloadedEpisode item,
  ) {
    final List<SoraEpisode> numbered = episodes
        .where(
          (SoraEpisode episode) =>
              (episode.number - item.episodeNumber).abs() < 0.001,
        )
        .toList(growable: false);
    if (numbered.isEmpty) return null;
    if (item.seasonNumber > 0) {
      for (final SoraEpisode episode in numbered) {
        if (episode.season == item.seasonNumber) return episode;
      }
    }
    return numbered.first;
  }

  // Helpers

  Future<void> _cacheMissingArtworkForCompletedDownloads() async {
    final String rootPath = _rootPath ??= await _store.rootPath();
    bool changed = false;
    for (final DownloadedEpisode snapshot in List<DownloadedEpisode>.from(
      state,
    )) {
      final DownloadedEpisode? current = _byId(snapshot.id);
      if (current == null ||
          !current.isComplete ||
          !_needsArtworkCache(current)) {
        continue;
      }

      final CancelToken token = CancelToken();
      final dir = await _store.ensureEpisodeDir(rootPath, current);
      final DownloadedEpisode updated = await _cacheArtwork(
        current,
        dirPath: dir.path,
        headers: const <String, String>{},
        cancelToken: token,
      );
      if (!_artworkChanged(current, updated)) continue;
      _updateById(current.id, (_) => updated);
      changed = true;
    }
    if (changed) {
      await _persist();
    }
  }

  Future<DownloadedEpisode> _cacheArtwork(
    DownloadedEpisode episode, {
    required String dirPath,
    required Map<String, String> headers,
    required CancelToken cancelToken,
  }) async {
    String mediaPosterFileName = episode.mediaPosterFileName;
    String mediaBackdropFileName = episode.mediaBackdropFileName;
    String episodeImageFileName = episode.episodeImageFileName;

    if (mediaPosterFileName.isEmpty) {
      mediaPosterFileName =
          await _downloadFirstArtwork(
            urls: <String>[episode.media.posterUrl],
            fileNamePrefix: 'poster',
            headers: headers,
            dirPath: dirPath,
            cancelToken: cancelToken,
          ) ??
          '';
    }

    if (mediaBackdropFileName.isEmpty) {
      mediaBackdropFileName =
          await _downloadFirstArtwork(
            urls: <String>[episode.media.backdropUrl],
            fileNamePrefix: 'backdrop',
            headers: headers,
            dirPath: dirPath,
            cancelToken: cancelToken,
          ) ??
          '';
    }

    if (episodeImageFileName.isEmpty) {
      episodeImageFileName =
          await _downloadFirstArtwork(
            urls: _episodeArtworkSources(episode),
            fileNamePrefix: 'episode',
            headers: headers,
            dirPath: dirPath,
            cancelToken: cancelToken,
          ) ??
          '';
    }

    return episode.copyWith(
      mediaPosterFileName: mediaPosterFileName,
      mediaBackdropFileName: mediaBackdropFileName,
      episodeImageFileName: episodeImageFileName,
    );
  }

  Future<String?> _downloadFirstArtwork({
    required List<String> urls,
    required String fileNamePrefix,
    required Map<String, String> headers,
    required String dirPath,
    required CancelToken cancelToken,
  }) async {
    for (final String url in urls) {
      if (!_isHttpUrl(url)) continue;
      final String? fileName = await _engine.downloadImage(
        url: url,
        fileNamePrefix: fileNamePrefix,
        headers: headers,
        dirPath: dirPath,
        cancelToken: cancelToken,
      );
      if (fileName != null && fileName.isNotEmpty) return fileName;
    }
    return null;
  }

  List<String> _episodeArtworkSources(DownloadedEpisode episode) {
    return <String>[
      _episodeDataString(episode, 'metadataImage'),
      episode.episodeImage,
      episode.media.backdropUrl,
      episode.media.posterUrl,
    ];
  }

  bool _needsArtworkCache(DownloadedEpisode episode) {
    return (episode.mediaPosterFileName.isEmpty &&
            _isHttpUrl(episode.media.posterUrl)) ||
        (episode.mediaBackdropFileName.isEmpty &&
            _isHttpUrl(episode.media.backdropUrl)) ||
        (episode.episodeImageFileName.isEmpty &&
            _episodeArtworkSources(episode).any(_isHttpUrl));
  }

  bool _artworkChanged(DownloadedEpisode before, DownloadedEpisode after) {
    return before.mediaPosterFileName != after.mediaPosterFileName ||
        before.mediaBackdropFileName != after.mediaBackdropFileName ||
        before.episodeImageFileName != after.episodeImageFileName;
  }

  String _episodeDataString(DownloadedEpisode episode, String key) {
    final Object? value = episode.episodeData[key];
    return value is String ? value.trim() : '';
  }

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

  bool _isHttpUrl(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Map<String, dynamic> _episodeToMap(
    SoraEpisode e, {
    SoraSearchResult? source,
  }) => <String, dynamic>{
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
    if (source != null) '_downloadSource': _searchResultToMap(source),
  };

  Map<String, dynamic> _searchResultToMap(SoraSearchResult result) =>
      <String, dynamic>{
        'addonId': result.addonId,
        'addonName': result.addonName,
        'title': result.title,
        'image': result.image,
        'href': result.href,
        'languageCode': result.languageCode,
        'query': result.query,
        'score': result.score,
        'raw': result.raw,
      };

  SoraSearchResult? _sourceFromEpisodeMap(Map<String, dynamic> episodeData) {
    final Object? rawSource = episodeData['_downloadSource'];
    if (rawSource is! Map) return null;
    final Map<String, dynamic> source = rawSource.cast<String, dynamic>();
    final String href = source['href'] as String? ?? '';
    if (href.trim().isEmpty) return null;
    return SoraSearchResult(
      addonId: source['addonId'] as String? ?? '',
      addonName: source['addonName'] as String? ?? '',
      title: source['title'] as String? ?? '',
      image: source['image'] as String? ?? '',
      href: href,
      languageCode: source['languageCode'] as String? ?? '',
      query: source['query'] as String? ?? '',
      score: (source['score'] as num?)?.toDouble() ?? 0,
      raw:
          (source['raw'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

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
