import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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
  DownloadEngine({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              followRedirects: true,
              maxRedirects: 5,
            ),
          );

  final Dio _dio;

  static const int _hlsConcurrency = 5;

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
      if (pathAndQuery.contains('.mpd')) return null;

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
      final Uint8List headBytes = bytes.length > 64
          ? bytes.sublist(0, 64)
          : bytes;
      final String head = utf8
          .decode(headBytes, allowMalformed: true)
          .trimLeft();
      return head.startsWith('#EXTM3U') ? DownloadKind.hls : DownloadKind.mp4;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const DownloadCancelledException();
      return streamTypeHint.trim().toUpperCase() == 'HLS'
          ? DownloadKind.hls
          : DownloadKind.mp4;
    } catch (_) {
      if (cancelToken.isCancelled) throw const DownloadCancelledException();
      return streamTypeHint.trim().toUpperCase() == 'HLS'
          ? DownloadKind.hls
          : DownloadKind.mp4;
    }
  }

  // --------------------------------------------------------------------------
  // Single-file (MP4/MKV) — resumable via HTTP Range.
  // --------------------------------------------------------------------------

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

  // --------------------------------------------------------------------------
  // HLS — download every segment + key and write a local playlist.
  // --------------------------------------------------------------------------

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

  _VariantPick? _pickBestVariant(String masterText, Uri masterUri) {
    final List<String> lines = const LineSplitter().convert(masterText);
    int bestBandwidth = -1;
    Uri? bestUri;
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
        }
        break;
      }
    }
    return bestUri == null ? null : _VariantPick(bestUri);
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
    final String path = uri.path.toLowerCase();
    for (final String ext in const <String>['.ts', '.m4s', '.mp4', '.aac']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.ts';
  }

  // --------------------------------------------------------------------------
  // Subtitles
  // --------------------------------------------------------------------------

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

  // --------------------------------------------------------------------------
  // Low-level fetch helpers
  // --------------------------------------------------------------------------

  Future<String> _fetchText(
    Uri uri,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    try {
      final Response<String> response = await _dio.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers.isEmpty ? null : headers,
        ),
        cancelToken: cancelToken,
      );
      return response.data ?? '';
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const DownloadCancelledException();
      rethrow;
    }
  }

  Future<Uint8List> _fetchBytes(
    Uri uri,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    try {
      final Response<List<int>> response = await _dio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers.isEmpty ? null : headers,
        ),
        cancelToken: cancelToken,
      );
      return Uint8List.fromList(response.data ?? const <int>[]);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw const DownloadCancelledException();
      rethrow;
    }
  }
}

class _PendingSegment {
  const _PendingSegment({required this.uri, required this.fileName});
  final Uri uri;
  final String fileName;
}

class _VariantPick {
  const _VariantPick(this.uri);
  final Uri uri;
}
