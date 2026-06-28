import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

// Per-request timeout — short enough that failures are detected, but long
// enough for slow HLS CDNs that only send a chunk every few seconds.
const Duration _kConnectTimeout = Duration(seconds: 10);
const Duration _kReadTimeout = Duration(seconds: 30);
const int _kPlaylistRetries = 3;
const int _kSegmentRetries = 4;
const int _kRetryBackoffBaseMs = 150;
const Duration _kIdleReset = Duration(seconds: 40);
const int _kBufferedSegmentLimitBytes = 32 * 1024 * 1024;
const List<String> _kHttp11Protocols = <String>['http/1.1'];

class _SegmentBufferTooLarge implements Exception {
  const _SegmentBufferTooLarge();
}

/// Local HTTP/HLS proxy that sits between MPV/native PiP and the upstream CDN.
///
/// Why it helps vs. MPV fetching directly:
///  - Retries failed segment connections before bytes are sent downstream.
///  - Reuses a single HttpClient connection pool -> fewer TCP handshakes.
///  - Forwards all necessary headers on every request (MPV drops them after
///    the first playlist fetch when URLs are rewritten to localhost).
///  - Resets the connection after long idle to avoid stale keep-alive sockets.
///
/// Architecture: one `LocalHlsProxy` instance per `MediaKitPlayerEngine`.
/// The engine calls `start()` / `stop()` around each network stream open.
class LocalHlsProxy {
  static const String inlineDashScheme = 'mirushin-dash';

  static bool isInlineDashUrl(String url) {
    return Uri.tryParse(url)?.scheme == inlineDashScheme;
  }

  static String inlineDashSourceUrl(String manifest) {
    final String encoded = base64Url.encode(utf8.encode(manifest));
    return '$inlineDashScheme:$encoded';
  }

  static String decodeInlineDashSourceUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != inlineDashScheme) {
      return '';
    }
    final String encoded = url.substring('$inlineDashScheme:'.length);
    if (encoded.isEmpty) {
      return '';
    }
    try {
      return utf8.decode(base64Url.decode(encoded));
    } on Object {
      return '';
    }
  }

  HttpServer? _server;
  int? _port;
  HttpClient? _httpClient;
  DateTime? _lastRequestAt;
  Map<String, String> _forwardHeaders = <String, String>{};
  final Map<String, String> _inlineDashManifests = <String, String>{};
  final Map<String, Map<String, String>> _inlineDashHeaders =
      <String, Map<String, String>>{};
  int _inlineDashCounter = 0;
  bool _stopping = false;

  bool get isRunning => _server != null;

  Uri get _base {
    final int? p = _port;
    if (p == null) throw StateError('LocalHlsProxy not started');
    return Uri(scheme: 'http', host: '127.0.0.1', port: p);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_server != null) return;
    _stopping = false;
    _httpClient ??= _makeClient();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_dispatch, onError: (_) {}, cancelOnError: false);
    debugPrint('HlsProxy: started on port $_port');
  }

  Future<void> stop() async {
    final HttpServer? s = _server;
    final bool hadResources = s != null || _httpClient != null;
    _stopping = true;
    _server = null;
    _port = null;
    _forwardHeaders = <String, String>{};
    _inlineDashManifests.clear();
    _inlineDashHeaders.clear();
    _lastRequestAt = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
    _destroyClient();
    if (hadResources) {
      debugPrint('HlsProxy: stopped');
    }
  }

  // ── Public URL builder ────────────────────────────────────────────────────

  /// Returns the proxied URL for the given HLS master/media playlist.
  /// Headers are embedded as JSON in the `h` query-param so that the proxy
  /// can forward them to the CDN for both playlist AND segment requests.
  String playlistUrl(
    Uri remoteUrl, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final String u = Uri.encodeQueryComponent(remoteUrl.toString());
    if (headers.isEmpty) {
      return '$_base/m3u8?u=$u';
    }
    final String h = Uri.encodeQueryComponent(jsonEncode(headers));
    return '$_base/m3u8?u=$u&h=$h';
  }

  /// Returns the proxied URL for a direct network media resource.
  ///
  /// Direct URLs do not need playlist rewriting, but still need the same
  /// header forwarding, connection retrying, and Range support as HLS segments.
  String mediaUrl(
    Uri remoteUrl, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final String u = Uri.encodeQueryComponent(remoteUrl.toString());
    if (headers.isEmpty) {
      return '$_base/media?u=$u';
    }
    final String h = Uri.encodeQueryComponent(jsonEncode(headers));
    return '$_base/media?u=$u&h=$h';
  }

  String inlineDashUrl(
    String manifest, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final String id =
        '${DateTime.now().microsecondsSinceEpoch}-${_inlineDashCounter++}';
    _inlineDashManifests[id] = manifest;
    _inlineDashHeaders[id] = Map<String, String>.from(headers);
    return '$_base/dash?id=${Uri.encodeQueryComponent(id)}';
  }

  // ── Request dispatch ──────────────────────────────────────────────────────

  Future<void> _dispatch(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/m3u8':
          await _servePlaylist(req);
        case '/seg':
          await _serveSegment(req);
        case '/media':
          await _serveSegment(req, preserveContentType: true);
        case '/dash':
          await _serveInlineDash(req);
        default:
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveInlineDash(HttpRequest req) async {
    final String? id = req.uri.queryParameters['id'];
    final String? manifest = id == null ? null : _inlineDashManifests[id];
    if (id == null || manifest == null) {
      req.response.statusCode = HttpStatus.notFound;
      return req.response.close();
    }
    final Map<String, String> headers =
        _inlineDashHeaders[id] ?? const <String, String>{};
    final String rewritten = _rewriteDashBaseUrls(manifest, headers);
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set(HttpHeaders.contentTypeHeader, 'application/dash+xml')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    req.response.write(rewritten);
    return req.response.close();
  }

  String _rewriteDashBaseUrls(String manifest, Map<String, String> headers) {
    return manifest.replaceAllMapped(
      RegExp(r'<BaseURL>([^<]+)</BaseURL>', caseSensitive: false),
      (Match match) {
        final String rawUrl = _xmlUnescape(match.group(1) ?? '').trim();
        final Uri? remoteUri = Uri.tryParse(rawUrl);
        if (remoteUri == null ||
            (remoteUri.scheme != 'http' && remoteUri.scheme != 'https')) {
          return match.group(0) ?? '';
        }
        final String proxied = mediaUrl(remoteUri, headers: headers);
        return '<BaseURL>${_xmlEscape(proxied)}</BaseURL>';
      },
    );
  }

  static String _xmlUnescape(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#47;', '/')
        .replaceAll('&#x2F;', '/')
        .replaceAll('&#x2f;', '/');
  }

  static String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // ── Playlist handler ──────────────────────────────────────────────────────

  Future<void> _servePlaylist(HttpRequest req) async {
    final String? rawUrl = req.uri.queryParameters['u'];
    if (rawUrl == null) {
      req.response.statusCode = HttpStatus.badRequest;
      return req.response.close();
    }

    // Headers arrive via two channels:
    //   1. `h` query-param (JSON, set by the engine when building the URL).
    //   2. Inbound HTTP headers forwarded by MPV from httpHeaders.
    // The explicit query payload is the source of truth. Child playlist/segment
    // requests can arrive with localhost Referer/Origin values, so inbound
    // headers only fill gaps instead of replacing provider headers.
    _absorbQueryHeaders(req.uri.queryParameters['h']);
    _absorbInboundHeaders(req.headers);

    final Uri src = Uri.parse(rawUrl);
    debugPrint('HlsProxy playlist ← $src');

    try {
      final String raw = await _fetchPlaylist(src);

      // Validate: every HLS playlist must start with #EXTM3U.
      final String trimmed = raw.trimLeft();
      if (!trimmed.startsWith('#EXTM3U')) {
        debugPrint(
          'HlsProxy: invalid playlist from $src '
          '(first 120 chars: ${trimmed.substring(0, trimmed.length.clamp(0, 120))})',
        );
        req.response.statusCode = HttpStatus.badGateway;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
        req.response.write('invalid HLS response from upstream');
        return req.response.close();
      }

      final bool isMaster = raw.contains('#EXT-X-STREAM-INF');
      final String rewritten = isMaster
          ? _rewriteMaster(src, raw)
          : _rewriteMedia(src, raw);

      debugPrint(
        'HlsProxy playlist OK '
        '(${isMaster ? "master" : "media"}, '
        '${raw.length} -> ${rewritten.length} bytes)',
      );

      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          'application/vnd.apple.mpegurl',
        )
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      req.response.write(rewritten);
      return req.response.close();
    } catch (e) {
      debugPrint('HlsProxy playlist FAIL $src -> $e');
      req.response.statusCode = HttpStatus.badGateway;
      req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
      req.response.write('proxy error: $e');
      return req.response.close();
    }
  }

  Future<String> _fetchPlaylist(Uri url) async {
    for (int attempt = 1; attempt <= _kPlaylistRetries; attempt++) {
      try {
        _resetIfIdle();
        _lastRequestAt = DateTime.now();
        final HttpClientRequest r = await _client()
            .getUrl(url)
            .timeout(_kConnectTimeout);
        _applyUpstreamHeaders(r, url);
        final HttpClientResponse resp = await r.close().timeout(_kReadTimeout);

        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          // Drain body to free connection.
          await resp.drain<void>().catchError((_) {});
          throw HttpException('HTTP ${resp.statusCode}', uri: url);
        }

        // Decompress (autoUncompress handles gzip) then decode.
        return await resp.transform(utf8.decoder).join().timeout(_kReadTimeout);
      } catch (e) {
        debugPrint(
          'HlsProxy playlist attempt $attempt/$_kPlaylistRetries FAIL: $e',
        );
        if (attempt == _kPlaylistRetries) rethrow;
        _destroyClient();
        await Future<void>.delayed(
          Duration(milliseconds: _kRetryBackoffBaseMs * attempt),
        );
      }
    }
    throw StateError('unreachable');
  }

  // ── Segment handler ───────────────────────────────────────────────────────

  Future<void> _serveSegment(
    HttpRequest req, {
    bool preserveContentType = false,
  }) async {
    final String? rawUrl = req.uri.queryParameters['u'];
    if (rawUrl == null) {
      req.response.statusCode = HttpStatus.badRequest;
      return req.response.close();
    }

    _absorbQueryHeaders(req.uri.queryParameters['h']);
    _absorbInboundHeaders(req.headers);
    final Uri uri = Uri.parse(rawUrl);
    final String? range = req.headers.value(HttpHeaders.rangeHeader);

    if (!preserveContentType && req.method != 'HEAD') {
      return _serveBufferedSegment(req, uri, range);
    }

    return _serveStreamingSegment(
      req,
      uri,
      range,
      preserveContentType: preserveContentType,
    );
  }

  Future<void> _serveBufferedSegment(
    HttpRequest req,
    Uri uri,
    String? range,
  ) async {
    try {
      final ({Uint8List body, HttpHeaders headers, int statusCode}) upstream =
          await _fetchBufferedSegment(uri, range);

      req.response.statusCode = upstream.statusCode;
      req.response.bufferOutput = false;
      _copyResponseHeaders(
        upstream.headers,
        req.response.headers,
        defaultContentType: 'application/octet-stream',
        preserveContentType: false,
      );
      req.response.contentLength = upstream.body.length;
      req.response.add(upstream.body);
      return req.response.close();
    } on _SegmentBufferTooLarge {
      debugPrint('HlsProxy seg too large for prebuffer, streaming $uri');
      return _serveStreamingSegment(
        req,
        uri,
        range,
        preserveContentType: false,
      );
    } catch (e) {
      if (_stopping && _isShutdownError(e)) {
        try {
          await req.response.close();
        } catch (_) {}
        return;
      }
      debugPrint('HlsProxy seg FAIL $uri -> $e');
      req.response.statusCode = HttpStatus.badGateway;
      req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
      req.response.write('segment error: $e');
      return req.response.close();
    }
  }

  Future<({Uint8List body, HttpHeaders headers, int statusCode})>
  _fetchBufferedSegment(Uri uri, String? range) async {
    for (int attempt = 1; attempt <= _kSegmentRetries; attempt++) {
      _resetIfIdle();
      _lastRequestAt = DateTime.now();
      if (_stopping) throw StateError('proxy stopping');

      try {
        final HttpClientRequest r = await _client()
            .getUrl(uri)
            .timeout(_kConnectTimeout);
        r.persistentConnection = true;
        _applyUpstreamHeaders(r, uri);
        if (range != null && range.trim().isNotEmpty) {
          r.headers.set(HttpHeaders.rangeHeader, range.trim());
        }

        final HttpClientResponse upstream = await r.close().timeout(
          _kReadTimeout,
        );

        if (_isRetriableStatus(upstream.statusCode) &&
            attempt < _kSegmentRetries) {
          await upstream.drain<void>().catchError((_) {});
          debugPrint(
            'HlsProxy seg retry $attempt '
            '(HTTP ${upstream.statusCode}) $uri',
          );
          await _beforeRetry(attempt);
          continue;
        }

        if (upstream.contentLength > _kBufferedSegmentLimitBytes) {
          await upstream.drain<void>().catchError((_) {});
          throw const _SegmentBufferTooLarge();
        }

        final BytesBuilder body = BytesBuilder(copy: false);
        await for (final List<int> chunk in upstream.timeout(_kReadTimeout)) {
          if (_stopping) throw StateError('proxy stopping');
          body.add(chunk);
          if (body.length > _kBufferedSegmentLimitBytes) {
            throw const _SegmentBufferTooLarge();
          }
        }

        return (
          body: body.takeBytes(),
          headers: upstream.headers,
          statusCode: upstream.statusCode,
        );
      } on _SegmentBufferTooLarge {
        rethrow;
      } catch (e) {
        final bool canRetry =
            _isRetriableError(e) && attempt < _kSegmentRetries;
        if (canRetry) {
          debugPrint('HlsProxy seg retry $attempt ($e) $uri');
          await _beforeRetry(attempt);
          continue;
        }
        rethrow;
      }
    }
    throw StateError('unreachable');
  }

  Future<void> _serveStreamingSegment(
    HttpRequest req,
    Uri uri,
    String? range, {
    required bool preserveContentType,
  }) async {
    for (int attempt = 1; attempt <= _kSegmentRetries; attempt++) {
      _resetIfIdle();
      _lastRequestAt = DateTime.now();
      if (_stopping) {
        try {
          await req.response.close();
        } catch (_) {}
        return;
      }

      try {
        final HttpClientRequest r =
            await (req.method == 'HEAD'
                    ? _client().headUrl(uri)
                    : _client().getUrl(uri))
                .timeout(_kConnectTimeout);
        r.persistentConnection = true;
        _applyUpstreamHeaders(r, uri);
        if (range != null && range.trim().isNotEmpty) {
          r.headers.set(HttpHeaders.rangeHeader, range.trim());
        }

        final HttpClientResponse upstream = await r.close().timeout(
          _kReadTimeout,
        );

        if (_isRetriableStatus(upstream.statusCode) &&
            attempt < _kSegmentRetries) {
          await upstream.drain<void>().catchError((_) {});
          debugPrint(
            'HlsProxy seg retry $attempt '
            '(HTTP ${upstream.statusCode}) $uri',
          );
          await _beforeRetry(attempt);
          continue;
        }

        req.response.statusCode = upstream.statusCode;
        req.response.bufferOutput = false;
        _copyResponseHeaders(
          upstream.headers,
          req.response.headers,
          defaultContentType: 'application/octet-stream',
          preserveContentType: preserveContentType,
        );
        if (upstream.contentLength >= 0) {
          req.response.contentLength = upstream.contentLength;
        }
        if (req.method == 'HEAD') {
          await upstream.drain<void>().catchError((_) {});
          return req.response.close();
        }
        try {
          await req.response.addStream(_activeStream(upstream));
          return req.response.close();
        } catch (e) {
          if (_stopping && _isShutdownError(e)) {
            try {
              await req.response.close();
            } catch (_) {}
            return;
          }
          debugPrint('HlsProxy seg stream FAIL $uri -> $e');
          try {
            await req.response.close();
          } catch (_) {}
          return;
        }
      } catch (e) {
        if (_stopping && _isShutdownError(e)) {
          try {
            await req.response.close();
          } catch (_) {}
          return;
        }
        final bool canRetry =
            _isRetriableError(e) && attempt < _kSegmentRetries;
        if (canRetry) {
          debugPrint('HlsProxy seg retry $attempt ($e) $uri');
          await _beforeRetry(attempt);
          continue;
        }
        debugPrint('HlsProxy seg FAIL $uri -> $e');
        req.response.statusCode = HttpStatus.badGateway;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
        req.response.write('segment error: $e');
        return req.response.close();
      }
    }
  }

  // ── M3U8 rewriting ────────────────────────────────────────────────────────

  String _rewriteMaster(Uri base, String text) {
    final List<String> lines = const LineSplitter().convert(text);
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trimRight();
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        out.writeln(line);
        if (i + 1 < lines.length) {
          final String next = lines[++i].trimRight();
          if (next.isEmpty || next.startsWith('#')) {
            out.writeln(next);
          } else {
            out.writeln(_proxiedPlaylist(base.resolve(next)));
          }
        }
        continue;
      }
      if (line.startsWith('#') && _hasUriAttr(line)) {
        out.writeln(
          _rewriteUriAttr(
            base,
            line,
            isPlaylist: _masterUriAttrIsPlaylist(line),
          ),
        );
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) {
        out.writeln(line);
        continue;
      }
      out.writeln(_proxiedPlaylist(base.resolve(line)));
    }
    return out.toString();
  }

  String _rewriteMedia(Uri base, String text) {
    final List<String> lines = const LineSplitter().convert(text);
    final StringBuffer out = StringBuffer();
    for (final String rawLine in lines) {
      final String line = rawLine.trimRight();
      if (line.startsWith('#') && _hasUriAttr(line)) {
        out.writeln(
          _rewriteUriAttr(
            base,
            line,
            isPlaylist: _mediaUriAttrIsPlaylist(line),
          ),
        );
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) {
        out.writeln(line);
        continue;
      }
      out.writeln(_proxiedSegment(base.resolve(line)));
    }
    return out.toString();
  }

  String _proxiedPlaylist(Uri r) => _canProxy(r)
      ? '$_base/m3u8?u=${Uri.encodeQueryComponent(r.toString())}${_headersQuerySuffix()}'
      : r.toString();

  String _proxiedSegment(Uri r) => _canProxy(r)
      ? '$_base/seg?u=${Uri.encodeQueryComponent(r.toString())}${_headersQuerySuffix()}'
      : r.toString();

  String _headersQuerySuffix() {
    if (_forwardHeaders.isEmpty) return '';
    return '&h=${Uri.encodeQueryComponent(jsonEncode(_forwardHeaders))}';
  }

  String _rewriteUriAttr(
    Uri base,
    String line, {
    required bool isPlaylist,
  }) => line.replaceAllMapped(RegExp(r'URI="([^"]+)"', caseSensitive: false), (
    Match m,
  ) {
    final Uri resolved = base.resolve(m.group(1)!);
    return 'URI="${isPlaylist ? _proxiedPlaylist(resolved) : _proxiedSegment(resolved)}"';
  });

  bool _hasUriAttr(String line) =>
      RegExp(r'URI="[^"]+"', caseSensitive: false).hasMatch(line);

  bool _masterUriAttrIsPlaylist(String line) =>
      line.startsWith('#EXT-X-MEDIA') ||
      line.startsWith('#EXT-X-I-FRAME-STREAM-INF');

  bool _mediaUriAttrIsPlaylist(String line) =>
      line.startsWith('#EXT-X-RENDITION-REPORT');

  bool _canProxy(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  Stream<List<int>> _activeStream(Stream<List<int>> upstream) async* {
    try {
      await for (final List<int> chunk in upstream.timeout(_kReadTimeout)) {
        if (_stopping) break;
        _lastRequestAt = DateTime.now();
        yield chunk;
      }
    } on Object catch (e) {
      if (_stopping && _isShutdownError(e)) return;
      rethrow;
    }
  }

  // ── HttpClient helpers ────────────────────────────────────────────────────

  HttpClient _makeClient() => HttpClient()
    ..connectionTimeout = _kConnectTimeout
    ..idleTimeout = const Duration(seconds: 20)
    ..maxConnectionsPerHost = 16
    ..autoUncompress = true
    ..findProxy = ((_) => 'DIRECT')
    ..connectionFactory = _openSocket
    // ignore: avoid_redundant_argument_values
    ..badCertificateCallback = (cert, host, port) => true;

  Future<ConnectionTask<Socket>> _openSocket(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (proxyHost != null) {
      return Socket.startConnect(proxyHost, proxyPort ?? 80);
    }

    final String connectHost = _okCdnEdgeHost(uri) ?? uri.host;
    final int port = uri.hasPort ? uri.port : _defaultPort(uri);
    final Future<ConnectionTask<Socket>> pending = Socket.startConnect(
      connectHost,
      port,
    );

    return pending.then((ConnectionTask<Socket> task) {
      Future<Socket> socket = task.socket;
      if (uri.scheme == 'https') {
        socket = socket.then(
          (Socket raw) => SecureSocket.secure(
            raw,
            host: uri.host,
            onBadCertificate: (_) => true,
            supportedProtocols: _kHttp11Protocols,
          ),
        );
      }
      return ConnectionTask.fromSocket<Socket>(socket, task.cancel);
    });
  }

  int _defaultPort(Uri uri) => uri.scheme == 'https'
      ? HttpClient.defaultHttpsPort
      : HttpClient.defaultHttpPort;

  HttpClient _client() {
    _httpClient ??= _makeClient();
    return _httpClient!;
  }

  void _destroyClient() {
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
  }

  void _resetIfIdle() {
    if (_stopping) return;
    final DateTime? last = _lastRequestAt;
    if (last != null && DateTime.now().difference(last) >= _kIdleReset) {
      debugPrint('HlsProxy: resetting idle HttpClient');
      _destroyClient();
    }
  }

  void _applyUpstreamHeaders(HttpClientRequest r, Uri url) {
    final bool isOkCdnPinned = _okCdnEdgeHost(url) != null;
    if (isOkCdnPinned) {
      // OK CDN signed URLs can pin the real edge in the `urls` query param.
      // The same vd*.okcdn.ru host may point at different edge IPs, so do not
      // reuse pooled sockets across signed links.
      r.persistentConnection = false;
    }

    // Always send cache-busting headers.
    r.headers.set('Cache-Control', 'no-cache');
    r.headers.set('Pragma', 'no-cache');

    // Set Accept and Accept-Encoding explicitly — some CDNs reject requests
    // that omit them, and autoUncompress on the client only adds
    // Accept-Encoding when not already set.
    if (r.headers.value('Accept') == null) {
      r.headers.set('Accept', '*/*');
    }

    // Forward all cached session headers (User-Agent, Referer, Origin, etc.).
    _forwardHeaders.forEach((String k, String v) {
      final String lk = k.toLowerCase();
      if (lk == 'host' || lk == 'connection' || lk == 'content-length') {
        return;
      }
      if (isOkCdnPinned && lk == 'origin') {
        return;
      }
      if (v.trim().isEmpty) return;
      try {
        r.headers.set(k, v);
      } catch (_) {}
    });

    // Ensure Referer is always set — many CDNs require it.
    if (r.headers.value(HttpHeaders.refererHeader) == null) {
      r.headers.set(HttpHeaders.refererHeader, '${url.scheme}://${url.host}/');
    }

    // Default User-Agent if none was forwarded.
    if (r.headers.value(HttpHeaders.userAgentHeader) == null) {
      r.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0 Safari/537.36',
      );
    }
  }

  bool _isOkCdnHost(String host) {
    final String lower = host.toLowerCase();
    return lower == 'okcdn.ru' ||
        lower.endsWith('.okcdn.ru') ||
        lower == 'mycdn.me' ||
        lower.endsWith('.mycdn.me');
  }

  String? _okCdnEdgeHost(Uri uri) {
    if (!_isOkCdnHost(uri.host)) return null;
    final String? rawUrls = uri.queryParameters['urls'];
    if (rawUrls == null || rawUrls.trim().isEmpty) return null;

    for (final String candidate in rawUrls.split(RegExp(r'[,;|]'))) {
      final String trimmed = candidate.trim();
      if (trimmed.isEmpty) continue;
      if (InternetAddress.tryParse(trimmed) != null) return trimmed;
    }

    final Match? match = RegExp(r'(?:\d{1,3}\.){3}\d{1,3}').firstMatch(rawUrls);
    return match?.group(0);
  }

  void _copyResponseHeaders(
    HttpHeaders from,
    HttpHeaders to, {
    String defaultContentType = 'application/octet-stream',
    bool preserveContentType = true,
  }) {
    const Set<String> hopByHop = <String>{
      'connection',
      'transfer-encoding',
      'content-length',
      'content-encoding',
      'keep-alive',
      'proxy-connection',
      'trailer',
      'upgrade',
    };
    from.forEach((String name, List<String> values) {
      final String lower = name.toLowerCase();
      if (hopByHop.contains(lower)) return;
      if (!preserveContentType && lower == HttpHeaders.contentTypeHeader) {
        return;
      }
      for (final String v in values) {
        try {
          to.add(name, v);
        } catch (_) {}
      }
    });
    if (to.value(HttpHeaders.contentTypeHeader) == null) {
      to.set(HttpHeaders.contentTypeHeader, defaultContentType);
    }
  }

  /// Capture User-Agent, Referer, Origin etc. from an inbound MPV request
  /// and merge them into `_forwardHeaders` so they survive playlist rewrites
  /// (MPV doesn't re-send them for sub-playlist / segment requests).
  void _absorbInboundHeaders(HttpHeaders headers) {
    const List<String> interestingHeaders = <String>[
      'user-agent',
      'referer',
      'origin',
      'cookie',
      'authorization',
      'accept',
    ];
    for (final String name in interestingHeaders) {
      final String? v = headers.value(name);
      if (v == null || v.trim().isEmpty) continue;
      _putForwardHeader(name, v, overwrite: false);
    }
  }

  void _absorbQueryHeaders(String? rawH) {
    if (rawH == null || rawH.isEmpty) return;
    try {
      final Map<String, dynamic> dec = jsonDecode(rawH) as Map<String, dynamic>;
      for (final MapEntry<String, dynamic> entry in dec.entries) {
        _putForwardHeader(entry.key, entry.value.toString(), overwrite: true);
      }
    } catch (e) {
      debugPrint('HlsProxy: failed to parse h-param: $e');
    }
  }

  void _putForwardHeader(String name, String value, {required bool overwrite}) {
    final String canonical = _canonicalForwardHeaderName(name);
    final String trimmed = value.trim();
    if (canonical.isEmpty || trimmed.isEmpty) return;
    if (overwrite) {
      _forwardHeaders[canonical] = trimmed;
    } else {
      _forwardHeaders.putIfAbsent(canonical, () => trimmed);
    }
  }

  String _canonicalForwardHeaderName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'user-agent':
        return HttpHeaders.userAgentHeader;
      case 'referer':
      case 'referrer':
        return HttpHeaders.refererHeader;
      case 'origin':
        return 'Origin';
      case 'cookie':
        return HttpHeaders.cookieHeader;
      case 'authorization':
        return 'Authorization';
      case 'accept':
        return HttpHeaders.acceptHeader;
      default:
        return name.trim();
    }
  }

  Future<void> _beforeRetry(int attempt) async {
    if (_stopping) return;
    _destroyClient();
    await Future<void>.delayed(
      Duration(milliseconds: _kRetryBackoffBaseMs * attempt),
    );
  }

  bool _isRetriableStatus(int code) =>
      code == HttpStatus.requestTimeout ||
      code == HttpStatus.tooManyRequests ||
      (code >= 500 && code < 600);

  bool _isRetriableError(Object e) =>
      e is TimeoutException || e is SocketException || e is HttpException;

  bool _isShutdownError(Object e) =>
      e is HttpException ||
      e is SocketException ||
      e is TimeoutException ||
      e is StateError;
}
