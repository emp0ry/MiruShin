import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart' as mk;

import '../domain/player_models.dart';
import 'local_hls_proxy.dart';
import 'media_kit_runtime.dart';
import 'player_engine.dart';
import 'seek_thumbnail.dart';
import 'seek_thumbnail_hls.dart';

const Duration _openTimeout = Duration(seconds: 4);
const Duration _frameTimeout = Duration(milliseconds: 2400);
const Duration _playlistTimeout = Duration(seconds: 3);
const int _thumbnailWidth = 320;

bool get seekThumbnailExtractionSupported => !Platform.isLinux;

PlayerBackend seekThumbnailExtractionBackend(PlayerBackend _) {
  return seekThumbnailExtractionSupported
      ? PlayerBackend.mpv
      : PlayerBackend.auto;
}

SeekThumbnailExtractor createSeekThumbnailExtractor(PlayerBackend backend) {
  if (!seekThumbnailExtractionSupported || backend != PlayerBackend.mpv) {
    return const _UnsupportedSeekThumbnailExtractor();
  }
  return MediaKitSeekThumbnailExtractor();
}

class MediaKitSeekThumbnailExtractor implements SeekThumbnailExtractor {
  final LocalHlsProxy _proxy = LocalHlsProxy();

  mk.Player? _player;
  String? _sourceKey;
  bool _disposed = false;

  @override
  Future<SeekThumbnail?> extract({
    required PlayerSource source,
    required Duration position,
    required Duration duration,
    required String sourceKey,
  }) async {
    if (_disposed) return null;
    try {
      final mk.Player player = await _ensurePlayer(source, sourceKey, position);
      if (_disposed || _player != player) return null;

      if (_sourceKey == sourceKey && player.state.position != position) {
        await player.play();
        await player.seek(position).timeout(_frameTimeout);
      }
      await _waitForDecoderProgress(player, position);
      if (_disposed || _player != player) return null;

      final Uint8List? screenshot = await _captureFrame(player);
      await player.pause();
      if (screenshot == null || screenshot.isEmpty) return null;

      final Map<String, Object>? resized = await compute(
        _resizeThumbnail,
        <String, Object>{'bytes': screenshot, 'width': _thumbnailWidth},
      );
      if (resized == null) return null;
      return SeekThumbnail(
        bytes: resized['bytes']! as Uint8List,
        position: position,
        width: resized['width']! as int,
        height: resized['height']! as int,
      );
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('SeekPreview: extraction failed (${error.runtimeType}).');
      }
      return null;
    }
  }

  Future<mk.Player> _ensurePlayer(
    PlayerSource source,
    String sourceKey,
    Duration position,
  ) async {
    final mk.Player? current = _player;
    if (current != null && _sourceKey == sourceKey) return current;

    await _disposePlayer();
    if (_disposed) throw StateError('Thumbnail extractor disposed.');
    MediaKitRuntime.ensureInitialized();

    final _PreparedPreviewSource prepared = await _prepareSource(source);
    if (_disposed) throw StateError('Thumbnail extractor disposed.');
    final mk.Player player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'MiruShin Seek Preview',
        vo: 'null',
        muted: true,
        libass: false,
        bufferSize: 8 * 1024 * 1024,
      ),
    );
    _player = player;
    _sourceKey = sourceKey;
    await player.setVolume(0);
    await player
        .open(
          mk.Media(
            prepared.url,
            httpHeaders: prepared.headers,
            start: position,
          ),
          play: true,
        )
        .timeout(_openTimeout);
    await player.setVolume(0);
    await player.setVideoTrack(mk.VideoTrack.auto());
    await player.setSubtitleTrack(mk.SubtitleTrack.no());
    if (kDebugMode) {
      debugPrint('SeekPreview: headless MPV decoder opened.');
    }
    return player;
  }

  Future<_PreparedPreviewSource> _prepareSource(PlayerSource source) async {
    final bool inlineDash = LocalHlsProxy.isInlineDashUrl(source.url);
    final Uri uri = inlineDash
        ? Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address)
        : Uri.parse(source.url);
    final String path = uri.path.toLowerCase();
    final bool localHlsRepresentation =
        uri.scheme == 'file' && path.endsWith('.m3u8');
    final bool hls =
        source.streamType == StreamType.hls ||
        localHlsRepresentation ||
        path.endsWith('.m3u8');
    final bool dash =
        source.streamType == StreamType.dash && !localHlsRepresentation ||
        path.endsWith('.mpd') ||
        inlineDash;
    final bool network = uri.scheme == 'http' || uri.scheme == 'https';
    final bool useProxy = network || inlineDash || localHlsRepresentation;
    if (!useProxy) {
      await _proxy.stop();
      return _PreparedPreviewSource(source.url, source.headers);
    }

    await _proxy.start();
    String url;
    if (inlineDash) {
      final String manifest = LocalHlsProxy.decodeInlineDashSourceUrl(
        source.url,
      );
      if (manifest.trim().isEmpty) {
        throw const FormatException('Invalid inline DASH manifest.');
      }
      url = Platform.isWindows
          ? _proxy.inlineDashHlsUrl(manifest, headers: source.headers)
          : _proxy.inlineDashUrl(manifest, headers: source.headers);
    } else if (hls) {
      url = _proxy.playlistUrl(uri, headers: source.headers);
      if (network) {
        url = await _lowestVideoVariantUrl(url);
      }
    } else if (dash) {
      url = Platform.isWindows
          ? await _proxy.dashHlsUrl(
              uri,
              headers: source.headers,
              proxyMedia: true,
            )
          : _proxy.dashUrl(uri, headers: source.headers);
    } else {
      url = _proxy.mediaUrl(uri, headers: source.headers);
    }
    return _PreparedPreviewSource(url, const <String, String>{});
  }

  Future<String> _lowestVideoVariantUrl(String proxiedPlaylistUrl) async {
    final Uri uri = Uri.parse(proxiedPlaylistUrl);
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(_playlistTimeout);
      final HttpClientResponse response = await request.close().timeout(
        _playlistTimeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return proxiedPlaylistUrl;
      }
      final String playlist = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_playlistTimeout);
      return lowestVideoHlsVariant(playlist, uri)?.uri.toString() ??
          proxiedPlaylistUrl;
    } on Object {
      return proxiedPlaylistUrl;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _waitForDecoderProgress(
    mk.Player player,
    Duration target,
  ) async {
    final int targetMs = target.inMilliseconds;
    for (int attempt = 0; attempt < 10; attempt += 1) {
      if ((player.state.position.inMilliseconds - targetMs).abs() <= 1500) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<Uint8List?> _captureFrame(mk.Player player) async {
    final DateTime deadline = DateTime.now().add(_frameTimeout);
    do {
      if (_disposed || _player != player) return null;
      try {
        final Uint8List? screenshot = await player
            .screenshot(format: 'image/jpeg')
            .timeout(const Duration(milliseconds: 700));
        if (screenshot != null && screenshot.isNotEmpty) return screenshot;
      } on Object {
        // The decoder may be open before its first frame is available.
      }
      await Future<void>.delayed(const Duration(milliseconds: 90));
    } while (DateTime.now().isBefore(deadline));
    if (kDebugMode) {
      final mk.VideoParams params = player.state.videoParams;
      debugPrint(
        'SeekPreview: no frame after ${_frameTimeout.inMilliseconds}ms '
        '(position=${player.state.position.inMilliseconds}ms, '
        'duration=${player.state.duration.inMilliseconds}ms, '
        'video=${params.w ?? params.dw ?? 0}x${params.h ?? params.dh ?? 0}, '
        'tracks=${player.state.tracks.video.length}, '
        'playing=${player.state.playing}, '
        'buffering=${player.state.buffering}).',
      );
    }
    return null;
  }

  Future<void> _disposePlayer() async {
    final mk.Player? player = _player;
    _player = null;
    _sourceKey = null;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // The native player may already be gone during app teardown.
      }
    }
    await _proxy.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _disposePlayer();
    if (kDebugMode) debugPrint('SeekPreview: disposed.');
  }
}

class _PreparedPreviewSource {
  const _PreparedPreviewSource(this.url, this.headers);

  final String url;
  final Map<String, String> headers;
}

class _UnsupportedSeekThumbnailExtractor implements SeekThumbnailExtractor {
  const _UnsupportedSeekThumbnailExtractor();

  @override
  Future<SeekThumbnail?> extract({
    required PlayerSource source,
    required Duration position,
    required Duration duration,
    required String sourceKey,
  }) async {
    return null;
  }

  @override
  Future<void> dispose() async {}
}

Map<String, Object>? _resizeThumbnail(Map<String, Object> message) {
  final Uint8List bytes = message['bytes']! as Uint8List;
  final int targetWidth = message['width']! as int;
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return null;
  final int width = decoded.width > targetWidth ? targetWidth : decoded.width;
  final img.Image resized = decoded.width == width
      ? decoded
      : img.copyResize(
          decoded,
          width: width,
          interpolation: img.Interpolation.average,
        );
  return <String, Object>{
    'bytes': Uint8List.fromList(img.encodeJpg(resized, quality: 76)),
    'width': resized.width,
    'height': resized.height,
  };
}
