import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../player/engine/local_hls_proxy.dart';
import '../domain/download_models.dart';

/// Thrown when a download is stopped by the user (pause/cancel) rather than by a
/// real error, so the controller can distinguish the two.
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
  @override
  String toString() => 'Download cancelled';
}

/// Thrown for sources we recognise but cannot download (e.g. DRM/SAMPLE-AES).
class DownloadUnsupportedException implements Exception {
  const DownloadUnsupportedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Pure IO downloader: resumable single-file (MP4) and full HLS (segments + AES
/// key + a rewritten local playlist). Holds no app state.
class DownloadEngine {
  DownloadEngine({Dio? dio}) : _dio = dio ?? _createDownloadDio();

  final Dio _dio;

  static const int _hlsConcurrency = 5;
  static const int _networkAttempts = 4;
  static const int _retryBackoffBaseMs = 180;
  static const String _mediaSourceMarker = '.media-source';

  /// Preserves resumable files only when they belong to the same logical
  /// quality. Switching to a fallback quality first removes incompatible
  /// segments so identically named files can never be mixed across manifests.
  Future<void> prepareMediaAttempt({
    required String dirPath,
    required String candidateKey,
  }) async {
    final Directory directory = Directory(dirPath);
    await directory.create(recursive: true);
    final File marker = File(p.join(dirPath, _mediaSourceMarker));
    final String fingerprint = sha256
        .convert(utf8.encode(candidateKey))
        .toString();
    String existing = '';
    try {
      if (await marker.exists()) {
        existing = (await marker.readAsString()).trim();
      }
    } on Object {
      existing = '';
    }

    if (existing != fingerprint) {
      await _clearMediaArtifacts(directory);
      await marker.writeAsString(fingerprint, flush: true);
    }
  }

  Future<void> _clearMediaArtifacts(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final FileSystemEntity entity in directory.list()) {
      final String name = p.basename(entity.path).toLowerCase();
      final bool generatedFile =
          entity is File &&
          (name == 'video.mp4' ||
              name == 'video.mp4.part' ||
              name == 'index.m3u8' ||
              name == 'key.bin' ||
              name.startsWith('seg_') ||
              name.startsWith('init.'));
      final bool generatedDirectory =
          entity is Directory && (name == 'video' || name == 'audio');
      if (generatedFile || generatedDirectory) {
        await entity.delete(recursive: entity is Directory);
      }
    }
  }

  static Dio _createDownloadDio() {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        followRedirects: true,
        maxRedirects: 5,
        headers: const <String, String>{
          HttpHeaders.acceptHeader: '*/*',
          HttpHeaders.userAgentHeader:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/126.0 Safari/537.36',
        },
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final HttpClient client = HttpClient()
          ..idleTimeout = const Duration(seconds: 20)
          ..maxConnectionsPerHost = 12
          ..autoUncompress = true;
        // This client is isolated to user-requested media downloads. Stream
        // hosts frequently serve incomplete certificate chains even while the
        // same media works in native players, so downloads accept the upstream
        // certificate without weakening API/authentication clients elsewhere.
        client.badCertificateCallback = (X509Certificate _, String _, int _) =>
            true;
        return client;
      },
    );
    return dio;
  }

  Future<DownloadKind?> sniffKind({
    required String url,
    required Map<String, String> headers,
    required String streamTypeHint,
    required CancelToken cancelToken,
  }) async {
    final String trimmedUrl = url.trim();
    final Uri? uri = Uri.tryParse(trimmedUrl);
    if (uri != null) {
      final String pathAndQuery = '${uri.path}?${uri.query}'.toLowerCase();
      if (pathAndQuery.contains('.m3u8')) return DownloadKind.hls;
      if (pathAndQuery.contains('.mpd')) return DownloadKind.dash;

      final String path = uri.path.toLowerCase();
      for (final String ext in const <String>[
        '.mp4',
        '.mkv',
        '.webm',
        '.m4v',
        '.mov',
      ]) {
        if (path.endsWith(ext)) return DownloadKind.mp4;
      }
    }

    final Map<String, String> reqHeaders = <String, String>{...headers}
      ..removeWhere((String key, String _) => key.toLowerCase() == 'range');
    reqHeaders[HttpHeaders.rangeHeader] = 'bytes=0-2047';
    try {
      final Response<List<int>> response = await _dio.get<List<int>>(
        trimmedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: reqHeaders,
          validateStatus: (int? s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
      final Uint8List bytes = Uint8List.fromList(
        response.data ?? const <int>[],
      );
      final Uint8List headBytes = bytes.length > 2048
          ? bytes.sublist(0, 2048)
          : bytes;
      final String head = utf8
          .decode(headBytes, allowMalformed: true)
          .trimLeft();
      final String contentType =
          response.headers
              .value(HttpHeaders.contentTypeHeader)
              ?.toLowerCase() ??
          '';
      if (contentType.contains('dash+xml')) return DownloadKind.dash;
      if (contentType.contains('mpegurl')) return DownloadKind.hls;
      if (head.startsWith('#EXTM3U')) return DownloadKind.hls;
      if (RegExp(r'<MPD(?:\s|>)', caseSensitive: false).hasMatch(head)) {
        return DownloadKind.dash;
      }
      return DownloadKind.mp4;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const DownloadCancelledException();
      return _kindFromHint(streamTypeHint);
    } catch (_) {
      if (cancelToken.isCancelled) throw const DownloadCancelledException();
      return _kindFromHint(streamTypeHint);
    }
  }

  DownloadKind _kindFromHint(String hint) {
    return switch (hint.trim().toUpperCase()) {
      'HLS' => DownloadKind.hls,
      'DASH' => DownloadKind.dash,
      _ => DownloadKind.mp4,
    };
  }

  // Single-file MP4 and MKV downloads support HTTP range requests.

  Future<void> downloadFile({
    required String url,
    required Map<String, String> headers,
    required String dirPath,
    required String fileName,
    required CancelToken cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final File partFile = File(p.join(dirPath, '$fileName.part'));
    final File finalFile = File(p.join(dirPath, fileName));
    if (finalFile.existsSync()) return;

    int existing = partFile.existsSync() ? await partFile.length() : 0;
    final Map<String, String> reqHeaders = <String, String>{...headers};
    if (existing > 0) {
      reqHeaders['Range'] = 'bytes=$existing-';
    }

    Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: reqHeaders,
          // Accept 206 (partial) and 200 (full) without throwing.
          validateStatus: (int? s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const DownloadCancelledException();
      rethrow;
    }

    // If we asked for a range but the server ignored it (200), restart fresh.
    final bool serverResumed = response.statusCode == 206;
    if (existing > 0 && !serverResumed) {
      existing = 0;
      if (partFile.existsSync()) await partFile.delete();
    }

    final int contentLength = _contentLengthFor(response, fromOffset: existing);
    int received = existing;
    if (onProgress != null) onProgress(received, contentLength);

    final IOSink sink = partFile.openWrite(
      mode: existing > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final Uint8List chunk in response.data!.stream) {
        if (cancelToken.isCancelled) {
          throw const DownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) onProgress(received, contentLength);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (cancelToken.isCancelled) throw const DownloadCancelledException();
    await partFile.rename(finalFile.path);
  }

  int _contentLengthFor(
    Response<ResponseBody> response, {
    required int fromOffset,
  }) {
    // Prefer Content-Range total ("bytes start-end/total") when resuming.
    final String? contentRange = response.headers.value(
      HttpHeaders.contentRangeHeader,
    );
    if (contentRange != null && contentRange.contains('/')) {
      final String totalPart = contentRange.split('/').last.trim();
      final int? total = int.tryParse(totalPart);
      if (total != null && total > 0) return total;
    }
    final String? lenHeader = response.headers.value(
      HttpHeaders.contentLengthHeader,
    );
    final int? len = int.tryParse(lenHeader ?? '');
    if (len != null && len > 0) return fromOffset + len;
    return 0;
  }

  // HLS downloads include every segment and key in a local playlist.

  Future<void> downloadHls({
    required String playlistUrl,
    required Map<String, String> headers,
    required String dirPath,
    String playlistFileName = 'index.m3u8',
    required CancelToken cancelToken,
    void Function(int totalSegments)? onPlaylistParsed,
    void Function(int doneSegments, int totalSegments, int receivedBytes)?
    onProgress,
  }) async {
    final File finalPlaylist = File(p.join(dirPath, playlistFileName));
    if (finalPlaylist.existsSync()) return;

    // Resolve master -> variant if needed.
    Uri mediaUri = Uri.parse(playlistUrl);
    String playlistText = await _fetchText(mediaUri, headers, cancelToken);
    _ensureHlsPlaylist(playlistText);
    if (playlistText.contains('#EXT-X-STREAM-INF')) {
      final _VariantPick? pick = _pickBestVariant(playlistText, mediaUri);
      if (pick == null) {
        throw const DownloadUnsupportedException(
          'HLS master playlist had no playable variant.',
        );
      }
      final _AudioPick? audio = pick.audioGroupId == null
          ? null
          : _pickAudioRendition(playlistText, mediaUri, pick.audioGroupId!);
      if (pick.audioGroupId != null && audio == null) {
        throw const DownloadUnsupportedException(
          'HLS master references an unavailable audio rendition.',
        );
      }
      if (audio != null) {
        await _downloadHlsWithExternalAudio(
          video: pick,
          audio: audio,
          headers: headers,
          dirPath: dirPath,
          finalPlaylist: finalPlaylist,
          cancelToken: cancelToken,
          onPlaylistParsed: onPlaylistParsed,
          onProgress: onProgress,
        );
        return;
      }
      mediaUri = pick.uri;
      playlistText = await _fetchText(mediaUri, headers, cancelToken);
      _ensureHlsPlaylist(playlistText);
    }

    final List<String> lines = const LineSplitter().convert(playlistText);
    final List<String> outLines = <String>[];
    final List<_PendingSegment> segments = <_PendingSegment>[];
    int segIndex = 0;

    for (final String rawLine in lines) {
      final String line = rawLine.trimRight();
      if (line.startsWith('#EXT-X-KEY')) {
        outLines.add(
          await _rewriteKeyLine(line, mediaUri, headers, dirPath, cancelToken),
        );
        continue;
      }
      if (line.startsWith('#EXT-X-MAP')) {
        outLines.add(
          await _rewriteMapLine(line, mediaUri, headers, dirPath, cancelToken),
        );
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) {
        outLines.add(line);
        continue;
      }
      // A media segment URI.
      final Uri segUri = mediaUri.resolve(line);
      final String ext = _segmentExtension(segUri);
      final String name =
          'seg_${(segIndex + 1).toString().padLeft(5, '0')}$ext';
      segments.add(_PendingSegment(uri: segUri, fileName: name));
      outLines.add(name);
      segIndex += 1;
    }

    if (onPlaylistParsed != null) onPlaylistParsed(segments.length);

    int done = 0;
    int receivedBytes = 0;
    final List<_PendingSegment> queue = List<_PendingSegment>.from(segments);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (cancelToken.isCancelled) throw const DownloadCancelledException();
        final _PendingSegment seg = queue.removeLast();
        final File file = File(p.join(dirPath, seg.fileName));
        if (file.existsSync() && file.lengthSync() > 0) {
          done += 1;
          receivedBytes += file.lengthSync();
          onProgress?.call(done, segments.length, receivedBytes);
          continue;
        }
        final Uint8List bytes = await _fetchBytes(
          seg.uri,
          headers,
          cancelToken,
        );
        await file.writeAsBytes(bytes, flush: true);
        done += 1;
        receivedBytes += bytes.length;
        onProgress?.call(done, segments.length, receivedBytes);
      }
    }

    final int workers = segments.length < _hlsConcurrency
        ? (segments.isEmpty ? 0 : 1)
        : _hlsConcurrency;
    try {
      await Future.wait(<Future<void>>[
        for (int i = 0; i < workers; i++) worker(),
      ]);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const DownloadCancelledException();
      rethrow;
    }
    if (cancelToken.isCancelled) throw const DownloadCancelledException();

    // Write the rewritten playlist last so its presence reliably signals a
    // complete download (an interrupted run leaves only segments and resumes).
    await finalPlaylist.writeAsString('${outLines.join('\n')}\n', flush: true);
  }

  Future<void> downloadDash({
    required String manifestUrl,
    required Map<String, String> headers,
    required String dirPath,
    String playlistFileName = 'index.m3u8',
    required CancelToken cancelToken,
    void Function(int totalSegments)? onPlaylistParsed,
    void Function(int doneSegments, int totalSegments, int receivedBytes)?
    onProgress,
  }) async {
    final Uri? manifestUri = Uri.tryParse(manifestUrl.trim());
    if (manifestUri == null ||
        (manifestUri.scheme != 'http' && manifestUri.scheme != 'https')) {
      throw const DownloadUnsupportedException(
        'DASH download requires an HTTP(S) manifest.',
      );
    }

    final LocalHlsProxy bridge = LocalHlsProxy();
    await bridge.start();
    try {
      if (cancelToken.isCancelled) {
        throw const DownloadCancelledException();
      }
      final String localHlsUrl = await bridge.dashHlsUrl(
        manifestUri,
        headers: headers,
        proxyMedia: true,
      );
      if (cancelToken.isCancelled) {
        throw const DownloadCancelledException();
      }
      await downloadHls(
        playlistUrl: localHlsUrl,
        headers: const <String, String>{},
        dirPath: dirPath,
        playlistFileName: playlistFileName,
        cancelToken: cancelToken,
        onPlaylistParsed: onPlaylistParsed,
        onProgress: onProgress,
      );
    } on UnsupportedError catch (error) {
      throw DownloadUnsupportedException(
        'Unsupported DASH presentation: ${error.message ?? error}',
      );
    } on FormatException catch (error) {
      throw DownloadUnsupportedException(
        'Invalid DASH presentation: ${error.message}',
      );
    } finally {
      await bridge.stop();
    }
  }

  Future<void> _downloadHlsWithExternalAudio({
    required _VariantPick video,
    required _AudioPick audio,
    required Map<String, String> headers,
    required String dirPath,
    required File finalPlaylist,
    required CancelToken cancelToken,
    void Function(int totalSegments)? onPlaylistParsed,
    void Function(int doneSegments, int totalSegments, int receivedBytes)?
    onProgress,
  }) async {
    final Directory videoDir = Directory(p.join(dirPath, 'video'));
    final Directory audioDir = Directory(p.join(dirPath, 'audio'));
    await Future.wait(<Future<Directory>>[
      videoDir.create(recursive: true),
      audioDir.create(recursive: true),
    ]);

    int videoTotal = 0;
    int audioTotal = 0;
    int videoDone = 0;
    int audioDone = 0;
    int videoBytes = 0;
    int audioBytes = 0;

    void reportTotal() => onPlaylistParsed?.call(videoTotal + audioTotal);
    void reportProgress() => onProgress?.call(
      videoDone + audioDone,
      videoTotal + audioTotal,
      videoBytes + audioBytes,
    );

    await Future.wait(<Future<void>>[
      downloadHls(
        playlistUrl: video.uri.toString(),
        headers: headers,
        dirPath: videoDir.path,
        cancelToken: cancelToken,
        onPlaylistParsed: (int total) {
          videoTotal = total;
          reportTotal();
        },
        onProgress: (int done, int _, int bytes) {
          videoDone = done;
          videoBytes = bytes;
          reportProgress();
        },
      ),
      downloadHls(
        playlistUrl: audio.uri.toString(),
        headers: headers,
        dirPath: audioDir.path,
        cancelToken: cancelToken,
        onPlaylistParsed: (int total) {
          audioTotal = total;
          reportTotal();
        },
        onProgress: (int done, int _, int bytes) {
          audioDone = done;
          audioBytes = bytes;
          reportProgress();
        },
      ),
    ]);
    if (cancelToken.isCancelled) throw const DownloadCancelledException();

    final String localAudioLine = audio.mediaLine.replaceFirst(
      RegExp(r'URI="[^"]+"', caseSensitive: false),
      'URI="audio/index.m3u8"',
    );
    await finalPlaylist.writeAsString(
      '#EXTM3U\n'
      '#EXT-X-VERSION:7\n'
      '#EXT-X-INDEPENDENT-SEGMENTS\n'
      '$localAudioLine\n'
      '${video.streamInfoLine}\n'
      'video/index.m3u8\n',
      flush: true,
    );
  }

  _VariantPick? _pickBestVariant(String masterText, Uri masterUri) {
    final List<String> lines = const LineSplitter().convert(masterText);
    int bestBandwidth = -1;
    Uri? bestUri;
    String? bestStreamInfoLine;
    String? bestAudioGroupId;
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final RegExpMatch? m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final int bandwidth = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
      // The URI is the next non-comment line.
      for (int j = i + 1; j < lines.length; j++) {
        final String candidate = lines[j].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        if (bandwidth > bestBandwidth) {
          bestBandwidth = bandwidth;
          bestUri = masterUri.resolve(candidate);
          bestStreamInfoLine = line;
          bestAudioGroupId = _hlsAttribute(line, 'AUDIO');
        }
        break;
      }
    }
    return bestUri == null || bestStreamInfoLine == null
        ? null
        : _VariantPick(
            uri: bestUri,
            streamInfoLine: bestStreamInfoLine,
            audioGroupId: bestAudioGroupId,
          );
  }

  _AudioPick? _pickAudioRendition(
    String masterText,
    Uri masterUri,
    String groupId,
  ) {
    _AudioPick? fallback;
    for (final String rawLine in const LineSplitter().convert(masterText)) {
      final String line = rawLine.trim();
      if (!line.startsWith('#EXT-X-MEDIA') ||
          _hlsAttribute(line, 'TYPE')?.toUpperCase() != 'AUDIO' ||
          _hlsAttribute(line, 'GROUP-ID') != groupId) {
        continue;
      }
      final String? rawUri = _hlsAttribute(line, 'URI');
      if (rawUri == null || rawUri.isEmpty) continue;
      final _AudioPick pick = _AudioPick(
        uri: masterUri.resolve(rawUri),
        mediaLine: line,
      );
      fallback ??= pick;
      if (_hlsAttribute(line, 'DEFAULT')?.toUpperCase() == 'YES') return pick;
    }
    return fallback;
  }

  String? _hlsAttribute(String line, String name) {
    final RegExpMatch? match = RegExp(
      '${RegExp.escape(name)}=(?:"([^"]*)"|([^,]*))',
      caseSensitive: false,
    ).firstMatch(line);
    return (match?.group(1) ?? match?.group(2))?.trim();
  }

  void _ensureHlsPlaylist(String playlistText) {
    if (!playlistText.contains('#EXTM3U')) {
      throw const DownloadUnsupportedException('Not an HLS playlist');
    }
  }

  Future<String> _rewriteKeyLine(
    String line,
    Uri mediaUri,
    Map<String, String> headers,
    String dirPath,
    CancelToken cancelToken,
  ) async {
    final RegExpMatch? method = RegExp(r'METHOD=([A-Z0-9-]+)').firstMatch(line);
    final String methodValue = method?.group(1) ?? 'NONE';
    if (methodValue == 'NONE') return line;
    if (methodValue != 'AES-128') {
      throw DownloadUnsupportedException(
        'Encrypted stream ($methodValue) cannot be downloaded.',
      );
    }
    final RegExpMatch? uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
    if (uriMatch == null) return line;
    final Uri keyUri = mediaUri.resolve(uriMatch.group(1)!);
    final Uint8List keyBytes = await _fetchBytes(keyUri, headers, cancelToken);
    await File(p.join(dirPath, 'key.bin')).writeAsBytes(keyBytes, flush: true);
    return line.replaceFirst(RegExp(r'URI="[^"]+"'), 'URI="key.bin"');
  }

  Future<String> _rewriteMapLine(
    String line,
    Uri mediaUri,
    Map<String, String> headers,
    String dirPath,
    CancelToken cancelToken,
  ) async {
    final RegExpMatch? uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
    if (uriMatch == null) return line;
    final Uri mapUri = mediaUri.resolve(uriMatch.group(1)!);
    final String ext = _segmentExtension(mapUri);
    final String name = 'init$ext';
    final Uint8List bytes = await _fetchBytes(mapUri, headers, cancelToken);
    await File(p.join(dirPath, name)).writeAsBytes(bytes, flush: true);
    return line.replaceFirst(RegExp(r'URI="[^"]+"'), 'URI="$name"');
  }

  String _segmentExtension(Uri uri) {
    // Relayed/signed media URLs often hide the original filename in a query
    // parameter, so inspect the complete resource reference instead of only
    // the outer endpoint path.
    final String path = '${uri.path}?${uri.query}'.toLowerCase();
    for (final String ext in const <String>['.ts', '.m4s', '.mp4', '.aac']) {
      if (path.contains(ext)) return ext;
    }
    return '.ts';
  }

  // Subtitles

  Future<DownloadedSubtitle?> downloadSubtitle({
    required String url,
    required String language,
    required String label,
    required Map<String, String> headers,
    required String dirPath,
    required CancelToken cancelToken,
  }) async {
    try {
      final Uri uri = Uri.parse(url);
      final String ext = _subtitleExtension(uri);
      final String safeLang = sanitizeForPath(
        language.isNotEmpty ? language : (label.isNotEmpty ? label : 'sub'),
      );
      final String fileName = 'sub_$safeLang$ext';
      final Uint8List bytes = await _fetchBytes(uri, headers, cancelToken);
      await File(p.join(dirPath, fileName)).writeAsBytes(bytes, flush: true);
      return DownloadedSubtitle(
        language: language,
        label: label.isNotEmpty ? label : language,
        fileName: fileName,
      );
    } catch (error) {
      debugPrint('Subtitle download failed ($url): $error');
      return null;
    }
  }

  Future<String?> downloadImage({
    required String url,
    required String fileNamePrefix,
    required Map<String, String> headers,
    required String dirPath,
    required CancelToken cancelToken,
  }) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    final String safePrefix = sanitizeForPath(fileNamePrefix);
    final String fileName = '$safePrefix${_imageExtension(uri)}';
    final File file = File(p.join(dirPath, fileName));
    if (file.existsSync() && file.lengthSync() > 0) {
      return fileName;
    }

    try {
      final Uint8List bytes = await _fetchBytes(uri, headers, cancelToken);
      if (bytes.isEmpty) return null;
      await file.writeAsBytes(bytes, flush: true);
      return fileName;
    } catch (error) {
      if (cancelToken.isCancelled) throw const DownloadCancelledException();
      debugPrint('Artwork download failed ($url): $error');
      return null;
    }
  }

  String _subtitleExtension(Uri uri) {
    final String path = uri.path.toLowerCase();
    if (path.endsWith('.ass') || path.endsWith('.ssa')) return '.ass';
    if (path.endsWith('.srt')) return '.srt';
    return '.vtt';
  }

  String _imageExtension(Uri uri) {
    final String path = uri.path.toLowerCase();
    for (final String ext in const <String>[
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
    ]) {
      if (path.endsWith(ext)) return ext == '.jpeg' ? '.jpg' : ext;
    }
    return '.jpg';
  }

  // Low-level fetch helpers

  Future<String> _fetchText(
    Uri uri,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    return _withNetworkRetry<String>(uri, cancelToken, () async {
      final Response<String> response = await _dio.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers.isEmpty ? null : headers,
        ),
        cancelToken: cancelToken,
      );
      return response.data ?? '';
    });
  }

  Future<Uint8List> _fetchBytes(
    Uri uri,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    return _withNetworkRetry<Uint8List>(uri, cancelToken, () async {
      final Response<List<int>> response = await _dio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers.isEmpty ? null : headers,
        ),
        cancelToken: cancelToken,
      );
      return Uint8List.fromList(response.data ?? const <int>[]);
    });
  }

  Future<T> _withNetworkRetry<T>(
    Uri uri,
    CancelToken cancelToken,
    Future<T> Function() request,
  ) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (int attempt = 1; attempt <= _networkAttempts; attempt++) {
      if (cancelToken.isCancelled) {
        throw const DownloadCancelledException();
      }
      try {
        return await request();
      } on DioException catch (error, stackTrace) {
        if (CancelToken.isCancel(error) || cancelToken.isCancelled) {
          throw const DownloadCancelledException();
        }
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt == _networkAttempts || !_isRetryable(error)) rethrow;
      }

      debugPrint(
        '[Download] retrying ${uri.host} '
        '(attempt ${attempt + 1}/$_networkAttempts)',
      );
      await Future.any<void>(<Future<void>>[
        Future<void>.delayed(
          Duration(milliseconds: _retryBackoffBaseMs * attempt),
        ),
        cancelToken.whenCancel.then<void>((_) {}),
      ]);
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  bool _isRetryable(DioException error) {
    if (error.error is HandshakeException) return false;
    if (error.type == DioExceptionType.badResponse) {
      final int? status = error.response?.statusCode;
      return status == 408 ||
          status == 425 ||
          status == 429 ||
          (status != null && status >= 500);
    }
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }
}

class _PendingSegment {
  const _PendingSegment({required this.uri, required this.fileName});
  final Uri uri;
  final String fileName;
}

class _VariantPick {
  const _VariantPick({
    required this.uri,
    required this.streamInfoLine,
    required this.audioGroupId,
  });

  final Uri uri;
  final String streamInfoLine;
  final String? audioGroupId;
}

class _AudioPick {
  const _AudioPick({required this.uri, required this.mediaLine});

  final Uri uri;
  final String mediaLine;
}
