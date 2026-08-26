import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'local_hls_proxy.dart';
import 'seek_thumbnail.dart';
import 'seek_thumbnail_hls.dart';
import 'seek_thumbnail_hls_index.dart';

class PreparedThumbnailInput {
  PreparedThumbnailInput({
    required this.input,
    required this.position,
    required this.headers,
    required this.windowSegmentCount,
    this.indexLookupMicroseconds = 0,
    this.temporaryDirectory,
  });

  final String input;
  final Duration position;
  final Map<String, String> headers;
  final int windowSegmentCount;
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

  final HttpClient _client = HttpClient();
  final LocalHlsProxy _proxy = LocalHlsProxy();
  final Set<HttpClientRequest> _activeRequests = <HttpClientRequest>{};
  final Map<String, Future<_HlsSession>> _hlsSessions =
      <String, Future<_HlsSession>>{};
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
    if (_disposed || !_isHls(source)) return;
    await _hlsSession(source);
  }

  Future<PreparedThumbnailInput?> prepare(
    SeekThumbnailSource source,
    Duration position, {
    int windowSegments = 1,
  }) async {
    final int generation = _generation;
    if (_disposed) return null;
    if (!_isHls(source)) {
      String input = source.isOffline
          ? _localPath(source.source.url)
          : source.source.url;
      Map<String, String> headers = source.source.headers;
      if (source.kind == SeekThumbnailSourceKind.networkFile) {
        await _proxy.start();
        input = _proxy.mediaUrl(Uri.parse(input), headers: headers);
        headers = const <String, String>{};
      }
      return PreparedThumbnailInput(
        input: input,
        position: position,
        headers: headers,
        windowSegmentCount: 0,
      );
    }

    final _HlsSession session = await _hlsSession(source);
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
        String playlist = utf8.decode(
          await _readResource(
            playlistUri,
            playlistHeaders,
            generation: generation,
            allowNetwork: !source.isOffline,
          ),
          allowMalformed: true,
        );
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
          playlist = utf8.decode(
            await _readResource(
              playlistUri,
              playlistHeaders,
              generation: generation,
              allowNetwork: !source.isOffline,
            ),
            allowMalformed: true,
          );
          index = parseHlsMediaIndex(playlist, playlistUri);
        }
        if (index.kind != HlsPlaylistKind.media || index.segments.isEmpty) {
          throw const SeekThumbnailLoadException(
            SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.permanentSource,
              reason: SeekThumbnailFailureReason.invalidPlaylist,
            ),
          );
        }
        return _HlsSession(
          index: index,
          resourceHeaders: playlistHeaders,
          isOffline: source.isOffline,
        );
      } on SeekThumbnailLoadException {
        rethrow;
      } on Object {
        throw const SeekThumbnailLoadException(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.transient,
            reason: SeekThumbnailFailureReason.network,
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
              : SeekThumbnailFailureReason.network,
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
  });

  static const int maxCacheEntries = 12;
  static const int maxCacheBytes = 12 * 1024 * 1024;

  final HlsMediaIndex index;
  final Map<String, String> resourceHeaders;
  final bool isOffline;
  final LinkedHashMap<String, Uint8List> resourceCache =
      LinkedHashMap<String, Uint8List>();
  int resourceCacheBytes = 0;
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
