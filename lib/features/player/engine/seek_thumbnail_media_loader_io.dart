import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../domain/player_models.dart';
import 'local_hls_proxy.dart';
import 'player_engine.dart';
import 'seek_thumbnail.dart';
import 'seek_thumbnail_hls.dart';
import 'seek_thumbnail_hls_index.dart';

class PreparedThumbnailInput {
  PreparedThumbnailInput({
    required this.input,
    required this.position,
    required this.headers,
    required this.windowSegmentCount,
    this.resolvedSourceKind = SeekThumbnailSourceKind.unknown,
    this.indexLookupMicroseconds = 0,
    this.temporaryDirectory,
  });

  final String input;
  final Duration position;
  final Map<String, String> headers;
  final int windowSegmentCount;
  final SeekThumbnailSourceKind resolvedSourceKind;
  final int indexLookupMicroseconds;
  final Directory? temporaryDirectory;

  Future<void> dispose() async {
    final Directory? directory = temporaryDirectory;
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary preview inputs are best-effort cleanup during app teardown.
    }
  }
}

class SeekThumbnailLoadException implements Exception {
  const SeekThumbnailLoadException(this.failure);

  final SeekThumbnailFailure failure;
}

class SeekThumbnailMediaLoader {
  SeekThumbnailMediaLoader() {
    _client.connectionTimeout = const Duration(seconds: 3);
    _client.idleTimeout = const Duration(seconds: 15);
    _client.maxConnectionsPerHost = 4;
  }

  static const Duration _requestTimeout = Duration(seconds: 4);
  static const int _maxRedirects = 5;
  static const int _maxAttempts = 2;
  static const int _networkProbeBytes = 64 * 1024;

  final HttpClient _client = HttpClient();
  final LocalHlsProxy _proxy = LocalHlsProxy();
  final Set<HttpClientRequest> _activeRequests = <HttpClientRequest>{};
  final Map<String, Future<_HlsSession>> _hlsSessions =
      <String, Future<_HlsSession>>{};
  final Map<String, Future<_ResolvedNetworkSource>> _sourceProbes =
      <String, Future<_ResolvedNetworkSource>>{};
  final Set<String> _rangeRejectedOrigins = <String>{};
  Directory? _temporaryRoot;
  int _requestSerial = 0;
  int _generation = 0;
  bool _disposed = false;

  void cancelPending() {
    _generation += 1;
    for (final HttpClientRequest request in List<HttpClientRequest>.of(
      _activeRequests,
    )) {
      request.abort(const HttpException('Preview request superseded.'));
    }
    _activeRequests.clear();
  }

  Future<void> warm(SeekThumbnailSource source) async {
    if (_disposed) return;
    final int generation = _generation;
    final _ResolvedNetworkSource? resolved =
        source.kind == SeekThumbnailSourceKind.networkUnknown
        ? await _resolveNetworkSource(source, generation)
        : null;
    final SeekThumbnailSource effective = resolved?.source ?? source;
    if (_isHls(effective)) await _hlsSession(effective);
  }

  Future<PreparedThumbnailInput?> prepare(
    SeekThumbnailSource source,
    Duration position, {
    int windowSegments = 1,
  }) async {
    final int generation = _generation;
    if (_disposed) return null;
    final _ResolvedNetworkSource? resolved =
        source.kind == SeekThumbnailSourceKind.networkUnknown
        ? await _resolveNetworkSource(source, generation)
        : null;
    final SeekThumbnailSource effective = resolved?.source ?? source;
    if (!_isHls(effective)) {
      String input = effective.isOffline
          ? _localPath(effective.source.url)
          : effective.source.url;
      Map<String, String> headers = effective.source.headers;
      if (effective.kind == SeekThumbnailSourceKind.networkFile) {
        await _proxy.start();
        input = _proxy.mediaUrl(Uri.parse(input), headers: headers);
        headers = const <String, String>{};
      }
      return PreparedThumbnailInput(
        input: input,
        position: position,
        headers: headers,
        windowSegmentCount: 0,
        resolvedSourceKind: effective.kind,
      );
    }

    final _HlsSession session = await _hlsSession(effective);
    _throwIfCancelled(generation);
    final Stopwatch indexLookup = Stopwatch()..start();
    final List<HlsMediaSegment> decodeWindow = session.index.decodeWindowFor(
      position,
      maxSegments: windowSegments,
      maxBackward: const Duration(seconds: 30),
    );
    indexLookup.stop();
    if (decodeWindow.isEmpty) {
      throw const SeekThumbnailLoadException(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.bucketSpecific,
          reason: SeekThumbnailFailureReason.missingRandomAccessContext,
        ),
      );
    }
    return _materializeSegments(
      session,
      decodeWindow,
      position,
      generation,
      indexLookup.elapsedMicroseconds,
    );
  }

  bool _isHls(SeekThumbnailSource source) {
    return source.kind == SeekThumbnailSourceKind.localHls ||
        source.kind == SeekThumbnailSourceKind.networkHls ||
        source.kind == SeekThumbnailSourceKind.networkDash;
  }

  Future<_ResolvedNetworkSource> _resolveNetworkSource(
    SeekThumbnailSource source,
    int generation,
  ) {
    final Future<_ResolvedNetworkSource>
    pending = _sourceProbes.putIfAbsent(source.decoderKey, () async {
      final _NetworkProbeResponse probe = await _probeNetworkSource(
        Uri.parse(source.source.url),
        source.source.headers,
        generation,
      );
      final _NetworkProbeKind probeKind = _networkProbeKind(probe);
      final SeekThumbnailSourceKind kind = switch (probeKind) {
        _NetworkProbeKind.hls => SeekThumbnailSourceKind.networkHls,
        _NetworkProbeKind.dash => SeekThumbnailSourceKind.networkDash,
        _NetworkProbeKind.directMedia ||
        _NetworkProbeKind.unknown => SeekThumbnailSourceKind.networkDirect,
      };
      final StreamType streamType = switch (probeKind) {
        _NetworkProbeKind.hls => StreamType.hls,
        _NetworkProbeKind.dash => StreamType.dash,
        _NetworkProbeKind.directMedia => StreamType.mp4,
        _NetworkProbeKind.unknown => StreamType.unknown,
      };
      final SeekThumbnailSource resolvedSource = SeekThumbnailSource(
        source: PlayerSource(
          url: source.source.url,
          headers: source.source.headers,
          streamType: streamType,
          disableProxy: source.source.disableProxy,
          allowDirectFallback: false,
        ),
        sourceKey: source.sourceKey,
        decoderKey: source.decoderKey,
        label: source.label,
        isOffline: source.isOffline,
        kind: kind,
        declaredStreamType:
            source.declaredStreamType ?? source.source.streamType,
        inspectMasterPlaylist: source.inspectMasterPlaylist || probe.hlsMaster,
      );
      if (kDebugMode) {
        final String selectedPath = switch (probeKind) {
          _NetworkProbeKind.hls => 'indexed-hls',
          _NetworkProbeKind.dash => 'indexed-dash',
          _NetworkProbeKind.directMedia ||
          _NetworkProbeKind.unknown => 'direct-libav',
        };
        debugPrint(
          'SeekPreview source probe: '
          'quality=${_safeDebugLabel(source.label)} '
          'declaredType=${(source.declaredStreamType ?? source.source.streamType).name} '
          'urlExtension=${_urlExtension(source.source.url)} '
          'rangeProbe=${probe.rangeProbe} '
          'plainProbe=${probe.plainProbe} '
          'probe=${probeKind == _NetworkProbeKind.directMedia ? 'direct-media' : probeKind.name} '
          'selectedPath=$selectedPath.',
        );
      }
      return _ResolvedNetworkSource(source: resolvedSource);
    });
    return pending.onError((Object error, StackTrace stackTrace) {
      if (identical(_sourceProbes[source.decoderKey], pending)) {
        _sourceProbes.remove(source.decoderKey);
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<_HlsSession> _hlsSession(SeekThumbnailSource source) {
    final Future<_HlsSession>
    pending = _hlsSessions.putIfAbsent(source.decoderKey, () async {
      final int generation = _generation;
      try {
        String playlistUrl = source.source.url;
        Map<String, String> playlistHeaders = source.source.headers;
        bool inspectMasterPlaylist = source.inspectMasterPlaylist;
        if (source.kind == SeekThumbnailSourceKind.networkDash) {
          await _proxy.start();
          if (LocalHlsProxy.isInlineDashUrl(playlistUrl)) {
            final String manifest = LocalHlsProxy.decodeInlineDashSourceUrl(
              playlistUrl,
            );
            if (manifest.trim().isEmpty) {
              throw const SeekThumbnailLoadException(
                SeekThumbnailFailure(
                  scope: SeekThumbnailFailureScope.permanentSource,
                  reason: SeekThumbnailFailureReason.invalidPlaylist,
                ),
              );
            }
            playlistUrl = _proxy.inlineDashHlsUrl(
              manifest,
              headers: playlistHeaders,
            );
          } else {
            playlistUrl = await _proxy.dashHlsUrl(
              Uri.parse(playlistUrl),
              headers: playlistHeaders,
              proxyMedia: true,
            );
          }
          playlistHeaders = const <String, String>{};
          inspectMasterPlaylist = true;
        }
        Uri playlistUri = _sourceUri(playlistUrl);
        final Uint8List playlistBytes = await _readResource(
          playlistUri,
          playlistHeaders,
          generation: generation,
          allowNetwork: !source.isOffline,
        );
        if (!_hasHlsSignature(playlistBytes)) {
          throw const SeekThumbnailLoadException(
            SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.permanentSource,
              reason: SeekThumbnailFailureReason.notHlsPlaylist,
            ),
          );
        }
        String playlist = utf8.decode(playlistBytes, allowMalformed: true);
        HlsMediaIndex index = parseHlsMediaIndex(playlist, playlistUri);

        // An explicit quality URL is fetched exactly once before parsing. Only
        // unknown/server URLs proactively receive master inspection; if a
        // provider mislabeled an explicit URL, the already-read document can
        // be rejected and the quality fallback can advance to a known server
        // source instead of issuing an unexpected second inspection request.
        if (index.kind == HlsPlaylistKind.master) {
          if (!inspectMasterPlaylist) {
            throw const SeekThumbnailLoadException(
              SeekThumbnailFailure(
                scope: SeekThumbnailFailureScope.permanentSource,
                reason: SeekThumbnailFailureReason.invalidPlaylist,
              ),
            );
          }
          final HlsVideoVariant? variant = lowestVideoHlsVariant(
            playlist,
            playlistUri,
          );
          if (variant == null) {
            throw const SeekThumbnailLoadException(
              SeekThumbnailFailure(
                scope: SeekThumbnailFailureScope.permanentSource,
                reason: SeekThumbnailFailureReason.noVideoTrack,
              ),
            );
          }
          playlistUri = variant.uri;
          final Uint8List variantBytes = await _readResource(
            playlistUri,
            playlistHeaders,
            generation: generation,
            allowNetwork: !source.isOffline,
          );
          if (!_hasHlsSignature(variantBytes)) {
            throw const SeekThumbnailLoadException(
              SeekThumbnailFailure(
                scope: SeekThumbnailFailureScope.permanentSource,
                reason: SeekThumbnailFailureReason.notHlsPlaylist,
              ),
            );
          }
          playlist = utf8.decode(variantBytes, allowMalformed: true);
          index = parseHlsMediaIndex(playlist, playlistUri);
        }
        if (index.kind != HlsPlaylistKind.media || index.segments.isEmpty) {
          throw const SeekThumbnailLoadException(
            SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.permanentSource,
              reason: SeekThumbnailFailureReason.hlsParseFailure,
            ),
          );
        }
        return _HlsSession(
          index: index,
          resourceHeaders: playlistHeaders,
          isOffline: source.isOffline,
          sourceKind: source.kind,
        );
      } on SeekThumbnailLoadException {
        rethrow;
      } on Object {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.permanentSource,
            reason: SeekThumbnailFailureReason.hlsParseFailure,
          ),
        );
      }
    });
    return pending.onError((Object error, StackTrace stackTrace) {
      if (identical(_hlsSessions[source.decoderKey], pending)) {
        _hlsSessions.remove(source.decoderKey);
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<_NetworkProbeResponse> _probeNetworkSource(
    Uri uri,
    Map<String, String> headers,
    int generation,
  ) async {
    final String origin =
        '${uri.scheme.toLowerCase()}://${uri.host}:${uri.port}';
    Object? rangeError;
    if (!_rangeRejectedOrigins.contains(origin)) {
      try {
        final _NetworkProbeResponse result = await _probeWithRetries(
          uri,
          headers,
          generation,
          useRange: true,
        );
        _throwIfCancelled(generation);
        return result.withProbeResults(
          rangeProbe: 'success',
          plainProbe: 'not-needed',
        );
      } on SeekThumbnailLoadException {
        rethrow;
      } on _PreviewHttpException catch (error) {
        rangeError = error;
        if (error.statusCode == HttpStatus.badRequest ||
            error.statusCode == HttpStatus.methodNotAllowed ||
            error.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          _rangeRejectedOrigins.add(origin);
        }
      } on Object catch (error) {
        rangeError = error;
      }
    } else {
      rangeError = const _ProbeSkippedException('cached-origin-rejection');
    }

    Object? plainError;
    try {
      final _NetworkProbeResponse result = await _probeWithRetries(
        uri,
        headers,
        generation,
        useRange: false,
      );
      _throwIfCancelled(generation);
      return result.withProbeResults(
        rangeProbe: _probeErrorLabel(rangeError),
        plainProbe: 'success',
        clearSupportsRanges: true,
      );
    } on SeekThumbnailLoadException {
      rethrow;
    } on Object catch (error) {
      plainError = error;
    }

    _throwIfCancelled(generation);
    // Classification probes are advisory. The original URL and every provider
    // header are deliberately retained so libav can perform its own HTTP
    // redirects, format probing, and native seek.
    return _NetworkProbeResponse(
      bytes: Uint8List(0),
      contentType: null,
      supportsRanges: null,
      contentLength: null,
      rangeProbe: _probeErrorLabel(rangeError),
      plainProbe: _probeErrorLabel(plainError),
    );
  }

  Future<_NetworkProbeResponse> _probeWithRetries(
    Uri uri,
    Map<String, String> headers,
    int generation, {
    required bool useRange,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt < _maxAttempts; attempt += 1) {
      try {
        return await _probeHttp(uri, headers, generation, useRange: useRange);
      } on SeekThumbnailLoadException {
        rethrow;
      } on _PreviewHttpException catch (error) {
        lastError = error;
        if (error.statusCode >= 400 && error.statusCode < 500) break;
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    throw const HttpException('Preview probe failed.');
  }

  Future<PreparedThumbnailInput?> _materializeSegments(
    _HlsSession session,
    List<HlsMediaSegment> segments,
    Duration requestedPosition,
    int generation,
    int indexLookupMicroseconds,
  ) async {
    if (segments.isEmpty) return null;
    if (session.isOffline) {
      return _materializeLocalSegments(
        session,
        segments,
        requestedPosition,
        generation,
        indexLookupMicroseconds,
      );
    }
    final List<_MaterializedSegment> materialized = <_MaterializedSegment>[];
    for (final HlsMediaSegment segment in segments) {
      final HlsEncryption? encryption = segment.encryption;
      if (encryption != null &&
          (!encryption.isAes128 || encryption.keyUri == null)) {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.permanentSource,
            reason: SeekThumbnailFailureReason.unsupportedEncryption,
          ),
        );
      }
      final Uint8List segmentBytes = await _readSessionResource(
        session,
        segment.uri,
        range: segment.byteRange,
        generation: generation,
      );
      final HlsInitMap? initMap = segment.initMap;
      final Uint8List? initBytes = initMap == null
          ? null
          : await _readSessionResource(
              session,
              initMap.uri,
              range: initMap.byteRange,
              generation: generation,
            );
      final Uint8List? keyBytes = encryption == null
          ? null
          : await _readSessionResource(
              session,
              encryption.keyUri!,
              generation: generation,
            );
      if (segmentBytes.isEmpty || (keyBytes != null && keyBytes.length != 16)) {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.bucketSpecific,
            reason: SeekThumbnailFailureReason.decodeFailure,
          ),
        );
      }
      materialized.add(
        _MaterializedSegment(
          segment: segment,
          mediaBytes: segmentBytes,
          initBytes: initBytes,
          keyBytes: keyBytes,
        ),
      );
    }

    final Directory root = await _ensureTemporaryRoot();
    final Directory requestDirectory = await Directory(
      p.join(root.path, 'request-${_requestSerial++}'),
    ).create();
    final HlsMediaSegment first = segments.first;
    final StringBuffer playlist = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln(
        '#EXT-X-TARGETDURATION:${session.index.targetDuration.inSeconds.clamp(1, 86400)}',
      )
      ..writeln('#EXT-X-MEDIA-SEQUENCE:${first.sequence}')
      ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:${first.discontinuitySequence}');
    for (int index = 0; index < materialized.length; index += 1) {
      final _MaterializedSegment item = materialized[index];
      final HlsMediaSegment segment = item.segment;
      if (index > 0 &&
          segment.discontinuitySequence !=
              materialized[index - 1].segment.discontinuitySequence) {
        playlist.writeln('#EXT-X-DISCONTINUITY');
      }
      if (item.initBytes != null) {
        final String initName = 'init-$index.mp4';
        await File(
          p.join(requestDirectory.path, initName),
        ).writeAsBytes(item.initBytes!, flush: true);
        playlist.writeln('#EXT-X-MAP:URI="$initName"');
      }
      final HlsEncryption? encryption = segment.encryption;
      if (encryption == null) {
        playlist.writeln('#EXT-X-KEY:METHOD=NONE');
      } else {
        final String keyName = 'key-$index.key';
        await File(
          p.join(requestDirectory.path, keyName),
        ).writeAsBytes(item.keyBytes!, flush: true);
        final String iv = encryption.iv == null ? '' : ',IV=${encryption.iv}';
        final String keyFormat = encryption.keyFormat == null
            ? ''
            : ',KEYFORMAT="${encryption.keyFormat}"';
        playlist.writeln(
          '#EXT-X-KEY:METHOD=AES-128,URI="$keyName"$iv$keyFormat',
        );
      }
      final String segmentName =
          'segment-$index${_segmentExtension(segment, segment.initMap)}';
      await File(
        p.join(requestDirectory.path, segmentName),
      ).writeAsBytes(item.mediaBytes, flush: true);
      playlist
        ..writeln('#EXTINF:${segment.duration.inMicroseconds / 1000000},')
        ..writeln(segmentName);
    }
    playlist.writeln('#EXT-X-ENDLIST');
    final File playlistFile = File(
      p.join(requestDirectory.path, 'preview.m3u8'),
    );
    await playlistFile.writeAsString(playlist.toString(), flush: true);

    final Duration localPosition = requestedPosition <= first.start
        ? Duration.zero
        : requestedPosition - first.start;
    final Duration windowDuration = segments.fold<Duration>(
      Duration.zero,
      (Duration total, HlsMediaSegment segment) => total + segment.duration,
    );
    return PreparedThumbnailInput(
      input: playlistFile.path,
      position: localPosition < windowDuration
          ? localPosition
          : windowDuration - const Duration(milliseconds: 1),
      headers: const <String, String>{},
      windowSegmentCount: segments.length,
      resolvedSourceKind: session.sourceKind,
      indexLookupMicroseconds: indexLookupMicroseconds,
      temporaryDirectory: requestDirectory,
    );
  }

  Future<PreparedThumbnailInput> _materializeLocalSegments(
    _HlsSession session,
    List<HlsMediaSegment> segments,
    Duration requestedPosition,
    int generation,
    int indexLookupMicroseconds,
  ) async {
    _throwIfCancelled(generation);
    for (final HlsMediaSegment segment in segments) {
      if (!_isLocalUri(segment.uri) ||
          (segment.initMap != null && !_isLocalUri(segment.initMap!.uri)) ||
          (segment.encryption?.keyUri != null &&
              !_isLocalUri(segment.encryption!.keyUri!))) {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.permanentSource,
            reason: SeekThumbnailFailureReason.invalidPlaylist,
          ),
        );
      }
      final HlsEncryption? encryption = segment.encryption;
      if (encryption != null &&
          (!encryption.isAes128 || encryption.keyUri == null)) {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.permanentSource,
            reason: SeekThumbnailFailureReason.unsupportedEncryption,
          ),
        );
      }
    }

    final String sourcePlaylistPath = _localPath(
      session.index.playlistUri.toString(),
    );
    final Directory requestDirectory;
    try {
      requestDirectory = await Directory(
        p.join(
          File(sourcePlaylistPath).parent.path,
          '.mirushin_seek_preview_${pid}_${_requestSerial++}',
        ),
      ).create();
    } on FileSystemException {
      throw const SeekThumbnailLoadException(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.transient,
          reason: SeekThumbnailFailureReason.decodeFailure,
        ),
      );
    }
    final HlsMediaSegment first = segments.first;
    final StringBuffer playlist = _playlistHeader(session, first);
    for (int index = 0; index < segments.length; index += 1) {
      final HlsMediaSegment segment = segments[index];
      if (index > 0 &&
          segment.discontinuitySequence !=
              segments[index - 1].discontinuitySequence) {
        playlist.writeln('#EXT-X-DISCONTINUITY');
      }
      final HlsInitMap? initMap = segment.initMap;
      if (initMap != null) {
        final String byteRange = initMap.byteRange == null
            ? ''
            : ',BYTERANGE="${initMap.byteRange!.length}@${initMap.byteRange!.offset}"';
        playlist.writeln(
          '#EXT-X-MAP:URI="${_localHlsReference(initMap.uri, requestDirectory)}"$byteRange',
        );
      }
      final HlsEncryption? encryption = segment.encryption;
      if (encryption == null) {
        playlist.writeln('#EXT-X-KEY:METHOD=NONE');
      } else {
        final String iv = encryption.iv == null ? '' : ',IV=${encryption.iv}';
        final String keyFormat = encryption.keyFormat == null
            ? ''
            : ',KEYFORMAT="${encryption.keyFormat}"';
        playlist.writeln(
          '#EXT-X-KEY:METHOD=AES-128,'
          'URI="${_localHlsReference(encryption.keyUri!, requestDirectory)}"$iv$keyFormat',
        );
      }
      if (segment.byteRange != null) {
        playlist.writeln(
          '#EXT-X-BYTERANGE:${segment.byteRange!.length}@${segment.byteRange!.offset}',
        );
      }
      playlist
        ..writeln('#EXTINF:${segment.duration.inMicroseconds / 1000000},')
        ..writeln(_localHlsReference(segment.uri, requestDirectory));
    }
    playlist.writeln('#EXT-X-ENDLIST');
    final File playlistFile = File(
      p.join(requestDirectory.path, 'preview.m3u8'),
    );
    await playlistFile.writeAsString(playlist.toString(), flush: true);
    _throwIfCancelled(generation);
    return PreparedThumbnailInput(
      input: playlistFile.path,
      position: _localWindowPosition(segments, requestedPosition),
      headers: const <String, String>{},
      windowSegmentCount: segments.length,
      resolvedSourceKind: session.sourceKind,
      indexLookupMicroseconds: indexLookupMicroseconds,
      temporaryDirectory: requestDirectory,
    );
  }

  Future<Directory> _ensureTemporaryRoot() async {
    final Directory? current = _temporaryRoot;
    if (current != null) return current;
    final Directory created = await Directory.systemTemp.createTemp(
      'mirushin_seek_preview_',
    );
    _temporaryRoot = created;
    return created;
  }

  StringBuffer _playlistHeader(
    _HlsSession session,
    HlsMediaSegment first,
  ) => StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:7')
    ..writeln(
      '#EXT-X-TARGETDURATION:${session.index.targetDuration.inSeconds.clamp(1, 86400)}',
    )
    ..writeln('#EXT-X-MEDIA-SEQUENCE:${first.sequence}')
    ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:${first.discontinuitySequence}');

  Duration _localWindowPosition(
    List<HlsMediaSegment> segments,
    Duration requestedPosition,
  ) {
    final HlsMediaSegment first = segments.first;
    final Duration localPosition = requestedPosition <= first.start
        ? Duration.zero
        : requestedPosition - first.start;
    final Duration windowDuration = segments.fold<Duration>(
      Duration.zero,
      (Duration total, HlsMediaSegment segment) => total + segment.duration,
    );
    return localPosition < windowDuration
        ? localPosition
        : windowDuration - const Duration(milliseconds: 1);
  }

  Future<Uint8List> _readSessionResource(
    _HlsSession session,
    Uri uri, {
    HlsByteRange? range,
    required int generation,
  }) async {
    final String key =
        '${uri.toString()}|'
        '${range?.offset ?? -1}:${range?.length ?? -1}';
    final Uint8List? cached = session.resourceCache.remove(key);
    if (cached != null) {
      session.resourceCache[key] = cached;
      return cached;
    }
    final Uint8List bytes = await _readResource(
      uri,
      session.resourceHeaders,
      range: range,
      generation: generation,
      allowNetwork: !session.isOffline,
    );
    if (bytes.length <= _HlsSession.maxCacheBytes) {
      session.resourceCache[key] = bytes;
      session.resourceCacheBytes += bytes.length;
      while (session.resourceCache.isNotEmpty &&
          (session.resourceCache.length > _HlsSession.maxCacheEntries ||
              session.resourceCacheBytes > _HlsSession.maxCacheBytes)) {
        final String oldest = session.resourceCache.keys.first;
        session.resourceCacheBytes -= session.resourceCache
            .remove(oldest)!
            .length;
      }
    }
    return bytes;
  }

  void _throwIfCancelled(int generation) {
    if (_disposed || generation != _generation) {
      throw const SeekThumbnailLoadException(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.cancelled,
          reason: SeekThumbnailFailureReason.cancelled,
        ),
      );
    }
  }

  String _segmentExtension(HlsMediaSegment segment, HlsInitMap? initMap) {
    final String path = segment.uri.path.toLowerCase();
    for (final String extension in const <String>[
      '.ts',
      '.m4s',
      '.mp4',
      '.aac',
      '.webm',
    ]) {
      if (path.endsWith(extension)) return extension;
    }
    // A map plus media fragment is the normal fMP4 shape; MPEG-TS is the safe
    // default for extensionless transport segments.
    return initMap == null ? '.ts' : '.m4s';
  }

  Future<Uint8List> _readResource(
    Uri uri,
    Map<String, String> headers, {
    HlsByteRange? range,
    required int generation,
    bool allowNetwork = true,
  }) async {
    _throwIfCancelled(generation);
    if (_isLocalUri(uri)) {
      try {
        final Uint8List bytes = await _readLocal(uri, range);
        _throwIfCancelled(generation);
        return bytes;
      } on FileSystemException {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.bucketSpecific,
            reason: SeekThumbnailFailureReason.decodeFailure,
          ),
        );
      }
    }
    if (!allowNetwork) {
      throw const SeekThumbnailLoadException(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.permanentSource,
          reason: SeekThumbnailFailureReason.invalidPlaylist,
        ),
      );
    }

    Object? lastError;
    for (int attempt = 0; attempt < _maxAttempts; attempt += 1) {
      try {
        final Uint8List bytes = await _readHttp(
          uri,
          headers,
          range,
          generation,
        );
        _throwIfCancelled(generation);
        return bytes;
      } on SeekThumbnailLoadException {
        rethrow;
      } on _PreviewHttpException catch (error) {
        lastError = error;
        if (error.statusCode == HttpStatus.notFound ||
            error.statusCode == HttpStatus.gone ||
            error.statusCode == HttpStatus.forbidden) {
          break;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastError is _PreviewHttpException) {
      final int status = lastError.statusCode;
      throw SeekThumbnailLoadException(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.transient,
          reason: status == HttpStatus.notFound || status == HttpStatus.gone
              ? SeekThumbnailFailureReason.httpNotFound
              : status == HttpStatus.forbidden
              ? SeekThumbnailFailureReason.httpForbidden
              : SeekThumbnailFailureReason.httpStatus,
        ),
      );
    }
    if (lastError is TimeoutException) {
      throw const SeekThumbnailLoadException(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.transient,
          reason: SeekThumbnailFailureReason.networkTimeout,
        ),
      );
    }
    throw const SeekThumbnailLoadException(
      SeekThumbnailFailure(
        scope: SeekThumbnailFailureScope.transient,
        reason: SeekThumbnailFailureReason.network,
      ),
    );
  }

  Future<Uint8List> _readLocal(Uri uri, HlsByteRange? range) async {
    final File file = File(_localPath(uri.toString()));
    if (range == null) return file.readAsBytes();
    final RandomAccessFile handle = await file.open();
    try {
      await handle.setPosition(range.offset);
      return Uint8List.fromList(await handle.read(range.length));
    } finally {
      await handle.close();
    }
  }

  Future<_NetworkProbeResponse> _probeHttp(
    Uri initialUri,
    Map<String, String> headers,
    int generation, {
    required bool useRange,
  }) async {
    Uri uri = initialUri;
    for (int redirect = 0; redirect <= _maxRedirects; redirect += 1) {
      _throwIfCancelled(generation);
      final HttpClientRequest request = await _client
          .getUrl(uri)
          .timeout(_requestTimeout);
      _activeRequests.add(request);
      try {
        headers.forEach((String key, String value) {
          if (useRange || key.toLowerCase() != HttpHeaders.rangeHeader) {
            request.headers.set(key, value);
          }
        });
        if (useRange) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=0-${_networkProbeBytes - 1}',
          );
        }
        request.followRedirects = false;
        final HttpClientResponse response = await request.close().timeout(
          _requestTimeout,
          onTimeout: () {
            request.abort();
            throw TimeoutException('Preview probe response timed out.');
          },
        );
        if (response.isRedirect) {
          final String? location = response.headers.value(
            HttpHeaders.locationHeader,
          );
          await response.drain<void>();
          if (location == null || redirect == _maxRedirects) {
            throw const HttpException('Invalid preview probe redirect.');
          }
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          throw _PreviewHttpException(response.statusCode);
        }

        final BytesBuilder bytes = BytesBuilder(copy: false);
        await for (final List<int> chunk in response.timeout(_requestTimeout)) {
          final int remaining = _networkProbeBytes - bytes.length;
          if (remaining <= 0) break;
          bytes.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
          if (bytes.length >= _networkProbeBytes) break;
        }
        final String? acceptRanges = response.headers.value(
          HttpHeaders.acceptRangesHeader,
        );
        final String? contentRange = response.headers.value(
          HttpHeaders.contentRangeHeader,
        );
        return _NetworkProbeResponse(
          bytes: bytes.takeBytes(),
          contentType: response.headers.contentType?.mimeType.toLowerCase(),
          supportsRanges: useRange
              ? response.statusCode == HttpStatus.partialContent ||
                    (acceptRanges?.toLowerCase().contains('bytes') ?? false)
              : null,
          contentLength: _probeContentLength(
            contentRange,
            response.contentLength,
            response.statusCode,
          ),
        );
      } finally {
        _activeRequests.remove(request);
      }
    }
    throw const HttpException('Too many preview probe redirects.');
  }

  Future<Uint8List> _readHttp(
    Uri initialUri,
    Map<String, String> headers,
    HlsByteRange? range,
    int generation,
  ) async {
    Uri uri = initialUri;
    for (int redirect = 0; redirect <= _maxRedirects; redirect += 1) {
      _throwIfCancelled(generation);
      final HttpClientRequest request = await _client
          .getUrl(uri)
          .timeout(_requestTimeout);
      _activeRequests.add(request);
      try {
        headers.forEach((String key, String value) {
          request.headers.set(key, value);
        });
        if (range != null) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=${range.offset}-${range.endExclusive - 1}',
          );
        }
        request.followRedirects = false;
        final HttpClientResponse response = await request.close().timeout(
          _requestTimeout,
          onTimeout: () {
            request.abort();
            throw TimeoutException('Preview response timed out.');
          },
        );
        if (response.isRedirect) {
          final String? location = response.headers.value(
            HttpHeaders.locationHeader,
          );
          await response.drain<void>();
          if (location == null || redirect == _maxRedirects) {
            throw const HttpException('Invalid preview redirect.');
          }
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>();
          throw _PreviewHttpException(response.statusCode);
        }
        final BytesBuilder bytes = BytesBuilder(copy: false);
        await for (final List<int> chunk in response.timeout(_requestTimeout)) {
          bytes.add(chunk);
        }
        Uint8List result = bytes.takeBytes();
        if (range != null && response.statusCode == HttpStatus.ok) {
          if (result.length < range.endExclusive) {
            throw const HttpException('Preview range response was incomplete.');
          }
          result = Uint8List.sublistView(
            result,
            range.offset,
            range.endExclusive,
          );
        }
        if (range != null && result.length != range.length) {
          throw const HttpException('Preview range length did not match.');
        }
        return result;
      } finally {
        _activeRequests.remove(request);
      }
    }
    throw const HttpException('Too many preview redirects.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
    _client.close(force: true);
    _hlsSessions.clear();
    _sourceProbes.clear();
    await _proxy.stop();
    final Directory? root = _temporaryRoot;
    _temporaryRoot = null;
    if (root != null) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } on FileSystemException {
        // Native teardown may already be deleting a just-finished request.
      }
    }
  }
}

class _HlsSession {
  _HlsSession({
    required this.index,
    required this.resourceHeaders,
    required this.isOffline,
    required this.sourceKind,
  });

  static const int maxCacheEntries = 12;
  static const int maxCacheBytes = 12 * 1024 * 1024;

  final HlsMediaIndex index;
  final Map<String, String> resourceHeaders;
  final bool isOffline;
  final SeekThumbnailSourceKind sourceKind;
  final LinkedHashMap<String, Uint8List> resourceCache =
      LinkedHashMap<String, Uint8List>();
  int resourceCacheBytes = 0;
}

class _ResolvedNetworkSource {
  const _ResolvedNetworkSource({required this.source});

  final SeekThumbnailSource source;
}

enum _NetworkProbeKind { hls, dash, directMedia, unknown }

class _NetworkProbeResponse {
  const _NetworkProbeResponse({
    required this.bytes,
    required this.contentType,
    required this.supportsRanges,
    required this.contentLength,
    this.rangeProbe = 'unknown',
    this.plainProbe = 'unknown',
  });

  final Uint8List bytes;
  final String? contentType;
  final bool? supportsRanges;
  final int? contentLength;
  final String rangeProbe;
  final String plainProbe;

  _NetworkProbeResponse withProbeResults({
    required String rangeProbe,
    required String plainProbe,
    bool clearSupportsRanges = false,
  }) => _NetworkProbeResponse(
    bytes: bytes,
    contentType: contentType,
    supportsRanges: clearSupportsRanges ? null : supportsRanges,
    contentLength: contentLength,
    rangeProbe: rangeProbe,
    plainProbe: plainProbe,
  );

  bool get hlsMaster =>
      _probeText(bytes).toUpperCase().contains('#EXT-X-STREAM-INF:');
}

class _ProbeSkippedException implements Exception {
  const _ProbeSkippedException(this.reason);

  final String reason;
}

String _probeErrorLabel(Object? error) {
  if (error == null) return 'not-attempted';
  if (error is _ProbeSkippedException) return error.reason;
  if (error is _PreviewHttpException) return 'http-${error.statusCode}';
  if (error is TimeoutException) return 'timeout';
  return error.runtimeType.toString();
}

_NetworkProbeKind _networkProbeKind(_NetworkProbeResponse probe) {
  if (_hasHlsSignature(probe.bytes)) return _NetworkProbeKind.hls;
  final String text = _probeText(probe.bytes);
  if (RegExp(
        r'<(?:[A-Za-z0-9_-]+:)?MPD\b',
        caseSensitive: false,
      ).hasMatch(text) ||
      (probe.contentType == 'application/dash+xml' &&
          text.trimLeft().startsWith('<'))) {
    return _NetworkProbeKind.dash;
  }
  if (_looksLikeDirectMedia(probe.bytes, probe.contentType)) {
    return _NetworkProbeKind.directMedia;
  }
  return _NetworkProbeKind.unknown;
}

bool _hasHlsSignature(Uint8List bytes) {
  int offset = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    offset = 3;
  }
  while (offset < bytes.length &&
      (bytes[offset] == 0x20 ||
          bytes[offset] == 0x09 ||
          bytes[offset] == 0x0a ||
          bytes[offset] == 0x0d)) {
    offset += 1;
  }
  const List<int> signature = <int>[0x23, 0x45, 0x58, 0x54, 0x4d, 0x33, 0x55];
  if (bytes.length - offset < signature.length) return false;
  for (int index = 0; index < signature.length; index += 1) {
    final int value = bytes[offset + index];
    final int upper = value >= 0x61 && value <= 0x7a ? value - 0x20 : value;
    if (upper != signature[index]) return false;
  }
  return true;
}

bool _looksLikeDirectMedia(Uint8List bytes, String? contentType) {
  if (contentType?.startsWith('video/') ?? false) return true;
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return true;
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x1a &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xdf &&
      bytes[3] == 0xa3) {
    return true;
  }
  if (bytes.length >= 4 &&
      ((bytes[0] == 0x46 && bytes[1] == 0x4c && bytes[2] == 0x56) ||
          (bytes[0] == 0x4f &&
              bytes[1] == 0x67 &&
              bytes[2] == 0x67 &&
              bytes[3] == 0x53))) {
    return true;
  }
  return bytes.length >= 377 &&
      bytes[0] == 0x47 &&
      bytes[188] == 0x47 &&
      bytes[376] == 0x47;
}

String _probeText(Uint8List bytes) => latin1.decode(bytes, allowInvalid: true);

int? _probeContentLength(String? contentRange, int responseLength, int status) {
  final RegExpMatch? match = RegExp(
    r'/(\d+)$',
  ).firstMatch(contentRange?.trim() ?? '');
  final int? total = match == null ? null : int.tryParse(match.group(1)!);
  if (total != null && total >= 0) return total;
  if (status == HttpStatus.ok && responseLength >= 0) return responseLength;
  return null;
}

String _safeDebugLabel(String value) {
  final String cleaned = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  return cleaned.length <= 40 ? cleaned : '${cleaned.substring(0, 40)}...';
}

String _urlExtension(String value) {
  final Uri? uri = Uri.tryParse(value);
  final String extension = p.extension(uri?.path ?? '').toLowerCase();
  if (extension.isEmpty || extension.length > 12) return 'none';
  return extension;
}

class _PreviewHttpException implements Exception {
  const _PreviewHttpException(this.statusCode);

  final int statusCode;
}

class _MaterializedSegment {
  const _MaterializedSegment({
    required this.segment,
    required this.mediaBytes,
    required this.initBytes,
    required this.keyBytes,
  });

  final HlsMediaSegment segment;
  final Uint8List mediaBytes;
  final Uint8List? initBytes;
  final Uint8List? keyBytes;
}

Uri _sourceUri(String value) {
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) return File(value).uri;
  final Uri uri = Uri.parse(value);
  return uri.scheme.isEmpty ? File(value).uri : uri;
}

bool _isLocalUri(Uri uri) => uri.scheme.isEmpty || uri.scheme == 'file';

String _localPath(String value) {
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) return value;
  final Uri uri = Uri.parse(value);
  return uri.scheme == 'file' ? File.fromUri(uri).path : value;
}

String _localHlsReference(Uri uri, Directory playlistDirectory) {
  final String relative = p
      .relative(_localPath(uri.toString()), from: playlistDirectory.path)
      .replaceAll('\\', '/');
  return Uri(path: relative).toString().replaceAll('"', '%22');
}
