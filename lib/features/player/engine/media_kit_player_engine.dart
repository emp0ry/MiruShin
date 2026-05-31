import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../domain/player_models.dart';
import 'local_hls_proxy.dart';
import 'player_engine.dart';

const Duration _openTimeout = Duration(seconds: 90);
const Duration _stateTick = Duration(milliseconds: 120);
const Duration _startupSettleTimeout = Duration(seconds: 60);
// When playing through the local proxy AND a direct fallback is still available,
// only give the proxy a short window to deliver the first frame. If it can't,
// we switch to direct immediately instead of stalling on the full 60s timeout
// (the proxy can fetch the playlist yet fail on segments from a different CDN
// host, which otherwise wastes a minute before falling back).
const Duration _proxyStartupSettleTimeout = Duration(seconds: 8);
const Duration _startupPollInterval = Duration(milliseconds: 250);
const Duration _startupActionDelay = Duration(milliseconds: 750);
const Duration _proxyStallFallbackDelay = Duration(seconds: 10);
const Duration _tinyHlsDurationLimit = Duration(seconds: 30);

// MPV buffer config mirrors FVP's _bufferConfigFor() logic.
// demuxer-max-bytes: bytes to keep cached; demuxer-readahead-secs: look-ahead.
({int maxBytes, int readaheadSecs}) _mpvBufferConfig({
  required bool isHls,
  required bool isNetwork,
  required double speed,
}) {
  if (!isNetwork) return (maxBytes: 32 * 1024 * 1024, readaheadSecs: 10);
  // readaheadSecs is the TARGET look-ahead, not the minimum-to-start.
  // Keep it moderate (≤30s) so MPV starts reporting buffer progress quickly
  // even on slow CDNs.  Larger maxBytes gives plenty of room once playing.
  if (isHls) {
    if (speed <= 1.0) return (maxBytes: 300 * 1024 * 1024, readaheadSecs: 15);
    if (speed <= 1.5) return (maxBytes: 400 * 1024 * 1024, readaheadSecs: 20);
    if (speed <= 2.0) return (maxBytes: 500 * 1024 * 1024, readaheadSecs: 25);
    return (maxBytes: 600 * 1024 * 1024, readaheadSecs: 30);
  }
  if (speed <= 1.0) return (maxBytes: 150 * 1024 * 1024, readaheadSecs: 15);
  if (speed <= 1.5) return (maxBytes: 200 * 1024 * 1024, readaheadSecs: 20);
  if (speed <= 2.0) return (maxBytes: 300 * 1024 * 1024, readaheadSecs: 25);
  return (maxBytes: 400 * 1024 * 1024, readaheadSecs: 30);
}

// I/O buffer handed to MPV via PlayerConfiguration.bufferSize.
// This is the FFmpeg I/O buffer beneath the demuxer cache, which affects how
// much data MPV reads per syscall.  Use a larger value on desktop (Windows /
// macOS / Linux) for HLS CDN links that send large TCP payloads.
int _mkIoBufferBytes() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return 128 * 1024 * 1024; // 128 MB
  }
  return 64 * 1024 * 1024; // 64 MB (Android / iOS)
}

/// MPV-like MediaKit implementation of MiruShin's PlayerEngine.
///
/// MediaKit is the default native backend. It keeps the same PlayerEngine
/// contract as the old FVP and VideoPlayer engines, so the existing MiruShin
/// player UI, subtitles, auto-next, RPC, skip markers, seek preview and
/// progress logic continue to work above it.
class MediaKitPlayerEngine extends PlayerEngine {
  MediaKitPlayerEngine({double? initialAspectRatio, bool previewMode = false})
    : _initialAspectRatio = initialAspectRatio,
      _previewMode = previewMode,
      _state = ValueNotifier<PlayerEngineState>(
        PlayerEngineState(
          aspectRatio: _usableAspectRatio(initialAspectRatio) ?? 16 / 9,
        ),
      );

  final double? _initialAspectRatio;
  final bool _previewMode;
  final ValueNotifier<PlayerEngineState> _state;

  mk.Player? _player;
  mkv.VideoController? _videoController;
  Timer? _positionTimer;
  Timer? _openTimeoutTimer;
  Timer? _startupRetryTimer;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  // Local HTTP/HLS proxy for network playback. HLS playlists use /m3u8 and
  // direct media URLs use /media so headers, retries, and Range handling stay
  // consistent across providers. Preview mode skips it to stay lightweight.
  final LocalHlsProxy _proxy = LocalHlsProxy();

  bool _opening = false;
  bool _hasMedia = false;
  String? _lastError;
  double _volume = 1;
  double _playbackSpeed = 1;
  PlayerSource? _currentSource;
  String? _nativePlaybackUrl;
  Map<String, String> _nativePlaybackHeaders = const <String, String>{};
  String? _directPlaybackUrl;
  Map<String, String> _currentOpenHeaders = const <String, String>{};
  Duration _currentRequestedStartAt = Duration.zero;
  double _currentTargetPlaybackSpeed = 1;
  bool _currentAutoplay = true;
  bool _usingProxy = false;
  bool _directFallbackTried = false;
  bool _directFallbackInProgress = false;
  Duration _lastProxyProgressPosition = Duration.zero;
  DateTime? _proxyStallStartedAt;
  int _openGeneration = 0;
  Size _lastVideoSize = Size.zero;
  Duration _lastReliableDuration = Duration.zero;
  List<PlayerBufferedRange> _lastBufferedRanges = const <PlayerBufferedRange>[];

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  String? get nativePlaybackUrl => _nativePlaybackUrl;

  @override
  Map<String, String> get nativePlaybackHeaders => _nativePlaybackHeaders;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) {
    final mkv.VideoController? controller = _videoController;
    if (controller == null) return const SizedBox.shrink();
    return mkv.Video(
      controller: controller,
      fit: BoxFit.contain,
      controls: null,
      wakelock: false,
      pauseUponEnteringBackgroundMode: false,
    );
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    await _disposePlayerOnly();
    final int openGeneration = ++_openGeneration;

    _currentSource = source;

    _volume = _state.value.volume;
    _playbackSpeed = _state.value.playbackSpeed;
    _lastError = null;
    _lastVideoSize = Size.zero;
    _lastBufferedRanges = const <PlayerBufferedRange>[];
    _lastReliableDuration = Duration.zero;

    final mk.Player player = mk.Player(
      configuration: mk.PlayerConfiguration(
        title: 'MiruShin',
        // Use a small I/O buffer for the lightweight preview decoder; use a
        // large one for the main player so CDN TCP payloads are absorbed fast.
        bufferSize: _previewMode ? 8 * 1024 * 1024 : _mkIoBufferBytes(),
        ready: () {
          _syncState();
        },
      ),
    );
    final mkv.VideoController videoController = mkv.VideoController(player);
    _player = player;
    _videoController = videoController;

    _attachListeners(player);
    _startPositionTimer();
    _startOpenTimeout();

    try {
      _opening = true;
      _hasMedia = true;
      _state.value = _state.value.copyWith(
        isBuffering: true,
        isInitialized: false,
        hasError: false,
        clearError: true,
      );

      final double targetPlaybackSpeed = _playbackSpeed;
      _currentRequestedStartAt = startAt ?? Duration.zero;
      _currentTargetPlaybackSpeed = targetPlaybackSpeed;
      _currentAutoplay = autoplay;
      _directFallbackTried = false;
      _directFallbackInProgress = false;
      _usingProxy = false;
      _lastProxyProgressPosition = Duration.zero;
      _proxyStallStartedAt = null;

      await player.setVolume((_volume * 100).clamp(0.0, 100.0).toDouble());
      // Always start the native backend at 1.0x. Some HLS/TS streams
      // stall during startup if the demuxer/decoder is forced to begin at
      // 1.25x or higher before the first frames & timestamps are ready.
      await player.setRate(1.0);

      // Configure MPV buffer and network properties before opening.
      await _applyMpvProperties(player, source, _playbackSpeed);

      final Uri remoteUri = Uri.parse(source.url);
      final Map<String, String> headers = _normalizedHeaders(
        remoteUri,
        source.headers,
      );
      _directPlaybackUrl = remoteUri.toString();
      _currentOpenHeaders = headers;

      // For network streams use the local proxy so MPV/FFmpeg always gets a
      // localhost URL while the proxy handles CDN headers, retries, Range, and
      // HLS playlist rewrites. Preview mode skips it to keep decoders cheap.
      final bool isNetwork = _isNetworkUrl(source.url);
      final bool isHls = _isHlsLikeSource(source);
      final bool useProxy = !_previewMode && isNetwork;

      String playbackUrl = remoteUri.toString();
      if (useProxy) {
        try {
          // Restart proxy on each open so stale CDN headers are not reused.
          await _proxy.stop();
          await _proxy.start();
          playbackUrl = isHls
              ? _proxy.playlistUrl(remoteUri, headers: headers)
              : _proxy.mediaUrl(remoteUri, headers: headers);
          _usingProxy = true;
          debugPrint('MediaKit open via proxy: $playbackUrl');
        } on Object catch (proxyErr) {
          // Proxy failed to start — fall back to direct CDN access.
          debugPrint(
            'MediaKit proxy start failed, falling back direct: $proxyErr',
          );
          playbackUrl = remoteUri.toString();
        }
      } else {
        // Stop any running proxy so it does not keep a stale HTTP server open.
        unawaited(_proxy.stop());
        debugPrint('MediaKit open direct: $playbackUrl');
      }
      _nativePlaybackUrl = playbackUrl;
      _nativePlaybackHeaders = headers;

      await player.open(
        mk.Media(playbackUrl, httpHeaders: headers),
        play: autoplay,
      );

      unawaited(
        _finishStartupAfterOpen(
          player,
          openGeneration,
          requestedStartAt: startAt ?? Duration.zero,
          targetPlaybackSpeed: targetPlaybackSpeed,
        ),
      );

      if (!autoplay) {
        await player.pause();
      }
      _syncState();
    } on Object catch (error) {
      _lastError = error.toString();
      _state.value = _state.value.copyWith(
        isBuffering: false,
        hasError: true,
        errorDescription: _lastError,
      );
      rethrow;
    }
  }

  bool _isNetworkUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  bool _isHlsLikeSource(PlayerSource? source) {
    final String lower = (source?.url ?? '').toLowerCase();
    return source?.streamType == StreamType.hls ||
        lower.contains('.m3u8') ||
        lower.contains(':hls:') ||
        lower.contains('/hls/') ||
        lower.contains('manifest.m3u8') ||
        lower.contains('.mp4:hls:');
  }

  // Applies MPV buffer, cache, and network properties.
  //
  // All critical properties are awaited in parallel via Future.wait so they are
  // guaranteed to be set before player.open() is called. Speed-dependent
  // properties (demuxer-max-bytes, demuxer-readahead-secs) are re-applied on
  // every setPlaybackSpeed() call so the buffer grows proportionally to the
  // playback rate.
  Future<void> _applyMpvProperties(
    mk.Player player,
    PlayerSource source,
    double speed,
  ) async {
    if (player.platform is! mk.NativePlayer) return;
    final mk.NativePlayer native = player.platform as mk.NativePlayer;

    final bool isNetwork = _isNetworkUrl(source.url);
    final bool isHls = _isHlsLikeSource(source);

    final (:int maxBytes, :int readaheadSecs) = _mpvBufferConfig(
      isHls: isHls,
      isNetwork: isNetwork,
      speed: speed,
    );

    // Only include confirmed MPV runtime-settable properties. Avoid:
    //   - demuxer-lavf-o / stream-lavf-o  — key-value list options; MPV can
    //     emit async "Expected '=' and a value" errors on player.stream.error
    //     when the value format or option name is not recognised at runtime,
    //     which our catchError cannot intercept (MPV reports it after the call).
    //   - demuxer-lavf-analyzeduration / demuxer-lavf-probesize — init-time
    //     options only; not settable at runtime via mpv_set_property_string.
    //   - stream-timeout / vd-lavc-software-fallback — uncertain availability.
    final List<(String, String)> props = <(String, String)>[
      // ── Demuxer cache ─────────────────────────────────────────────────────
      ('cache', 'yes'),
      ('cache-secs', '30'),
      ('demuxer-seekable-cache', 'yes'),
      ('demuxer-max-back-bytes', '${64 * 1024 * 1024}'),

      // ── Speed-scaled forward buffer ───────────────────────────────────────
      ('demuxer-max-bytes', '$maxBytes'),
      ('demuxer-readahead-secs', '$readaheadSecs'),

      // ── Seek / frame-drop policy ──────────────────────────────────────────
      ('hr-seek-framedrop', 'no'),
      ('framedrop', 'no'),

      // ── A/V sync ──────────────────────────────────────────────────────────
      ('video-sync', 'audio'),

      // ── Hardware decoding ─────────────────────────────────────────────────
      ('hwdec', 'auto-safe'),
    ];

    if (isNetwork) {
      props.add(('network-timeout', '15'));
    }

    // Apply all properties in parallel; ignore per-property errors so an
    // unsupported option on an older MPV build never blocks playback.
    await Future.wait(<Future<void>>[
      for (final (String prop, String val) in props)
        native
            .setProperty(prop, val)
            .catchError(
              (Object e) => debugPrint(
                'MediaKit: setProperty("$prop","$val") failed: $e',
              ),
            ),
    ]);
  }

  bool _isTinyUnreliableDuration(Duration duration) {
    if (duration <= Duration.zero) return false;
    if (!_isHlsLikeSource(_currentSource)) return false;
    final String url = _currentSource?.url ?? '';
    if (!_isNetworkUrl(url)) return false;
    return duration < _tinyHlsDurationLimit;
  }

  bool _isReliableDuration(Duration duration) {
    if (duration <= Duration.zero) return false;
    if (_isTinyUnreliableDuration(duration)) return false;
    return true;
  }

  Duration _publicDuration(Duration nativeDuration) {
    if (_isReliableDuration(nativeDuration)) {
      if (nativeDuration > _lastReliableDuration) {
        _lastReliableDuration = nativeDuration;
      }
      return nativeDuration;
    }
    return _lastReliableDuration;
  }

  bool _hasStartupContent(mk.PlayerState native) {
    final bool hasVideoSize =
        ((native.width ?? 0) > 0 && (native.height ?? 0) > 0);
    final bool hasClock = native.position > Duration.zero;
    final bool hasBuffer = native.buffer > Duration.zero;
    final bool hasReliableDuration = _isReliableDuration(native.duration);

    // Important: tiny HLS duration like 4-10 seconds is not startup success.
    // It is usually an early segment/window estimate and causes false complete,
    // wrong progress, and bad automatic source switching.
    return hasVideoSize || hasClock || hasBuffer || hasReliableDuration;
  }

  Future<void> _finishStartupAfterOpen(
    mk.Player player,
    int generation, {
    required Duration requestedStartAt,
    required double targetPlaybackSpeed,
  }) async {
    // If we can still bail to direct, only wait the short proxy window so a
    // segment-level proxy failure does not cost the full settle timeout.
    final Duration settleTimeout = _canRetryDirectAfterProxy(player)
        ? _proxyStartupSettleTimeout
        : _startupSettleTimeout;
    final bool ready = await _waitForStableStartup(
      player,
      generation,
      timeout: settleTimeout,
    );
    if (!_isActivePlayer(player, generation)) return;

    if (!ready) {
      if (_canRetryDirectAfterProxy(player)) {
        await _retryDirectAfterProxyIssue(
          player,
          reason: 'proxy stream did not settle',
        );
        return;
      }
      // Slow CDN stream — skip seek to avoid breaking loading.
      // PlaybackController._reinforceInitialSeek retries once initialised.
      debugPrint(
        'MediaKit: startup did not settle within '
        '${_startupSettleTimeout.inSeconds}s — skipping startup seek.',
      );
      if (targetPlaybackSpeed != 1.0) {
        try {
          await player.setRate(targetPlaybackSpeed);
        } on Object catch (e) {
          debugPrint('MediaKit speed apply (no-settle) failed: $e');
        }
      }
      return;
    }

    // Stream settled — safe to seek and apply speed.
    await Future<void>.delayed(_startupActionDelay);
    if (!_isActivePlayer(player, generation)) return;

    if (requestedStartAt > Duration.zero) {
      await _safeStartupSeek(player, requestedStartAt);
      if (!_isActivePlayer(player, generation)) return;
      await Future<void>.delayed(_startupActionDelay);
    }

    if (!_isActivePlayer(player, generation)) return;
    if (targetPlaybackSpeed != 1.0) {
      try {
        await player.setRate(targetPlaybackSpeed);
      } on Object catch (error) {
        debugPrint('MediaKit delayed speed apply failed: $error');
      }
    }

    _syncState();
  }

  Future<bool> _waitForStableStartup(
    mk.Player player,
    int generation, {
    Duration timeout = _startupSettleTimeout,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    Duration lastPosition = player.state.position;
    int stableTicks = 0;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_startupPollInterval);
      if (!_isActivePlayer(player, generation)) return false;

      final mk.PlayerState native = player.state;
      final bool hasContent = _hasStartupContent(native);
      final bool moved =
          (native.position - lastPosition).abs() >
          const Duration(milliseconds: 450);
      final bool hasVideoSize =
          ((native.width ?? 0) > 0 && (native.height ?? 0) > 0);
      final bool ready = hasVideoSize || moved || hasContent;

      if (_isTinyUnreliableDuration(native.duration)) {
        debugPrint(
          'MediaKit ignored tiny HLS duration during startup: '
          '${native.duration.inSeconds}s',
        );
      }

      stableTicks = ready ? stableTicks + 1 : 0;
      lastPosition = native.position;

      // Require several consecutive ticks so a single fake duration or tiny
      // buffer pulse does not count as success.
      if (stableTicks >= 3) return true;
    }

    return false;
  }

  bool _isActivePlayer(mk.Player player, int generation) {
    return generation == _openGeneration && _player == player && _hasMedia;
  }

  bool _canRetryDirectAfterProxy(mk.Player player) {
    return _player == player &&
        _hasMedia &&
        _usingProxy &&
        !_directFallbackTried &&
        !_directFallbackInProgress &&
        !_requiresPinnedProxy(_directPlaybackUrl) &&
        (_directPlaybackUrl?.isNotEmpty ?? false);
  }

  bool _shouldRetryDirectAfterProxyError(mk.Player player) {
    if (!_canRetryDirectAfterProxy(player)) return false;

    final mk.PlayerState native = player.state;
    if (_hasStartupContent(native) ||
        _lastReliableDuration > Duration.zero ||
        _lastBufferedRanges.isNotEmpty) {
      return false;
    }

    return true;
  }

  Future<void> _retryDirectAfterProxyIssue(
    mk.Player player, {
    required String reason,
  }) async {
    if (!_canRetryDirectAfterProxy(player)) return;

    final String directUrl = _directPlaybackUrl!;
    final Map<String, String> headers = _currentOpenHeaders;
    final Duration requestedStartAt = player.state.position > Duration.zero
        ? player.state.position
        : _currentRequestedStartAt;
    final bool shouldPlay = player.state.playing || _currentAutoplay;

    _directFallbackTried = true;
    _directFallbackInProgress = true;
    _usingProxy = false;
    _proxyStallStartedAt = null;
    final int generation = ++_openGeneration;

    debugPrint('MediaKit: $reason; retrying direct before source fallback.');

    _lastError = null;
    _opening = true;
    _hasMedia = true;
    _state.value = _state.value.copyWith(
      isBuffering: true,
      isInitialized: false,
      hasError: false,
      clearError: true,
    );
    _startOpenTimeout();

    try {
      await _proxy.stop();
      _nativePlaybackUrl = directUrl;
      _nativePlaybackHeaders = headers;
      await player.setRate(1.0);
      await player.open(
        mk.Media(directUrl, httpHeaders: headers),
        play: shouldPlay,
      );
      _directFallbackInProgress = false;

      unawaited(
        _finishStartupAfterOpen(
          player,
          generation,
          requestedStartAt: requestedStartAt,
          targetPlaybackSpeed: _currentTargetPlaybackSpeed,
        ),
      );
      _syncState();
    } on Object catch (error) {
      _directFallbackInProgress = false;
      if (!_isActivePlayer(player, generation)) return;
      _lastError = 'Direct retry failed after proxy issue: $error';
      _syncState();
    }
  }

  void _watchProxyStall(
    mk.Player player, {
    required mk.PlayerState native,
    required Duration position,
    required bool initialized,
  }) {
    if (!_canRetryDirectAfterProxy(player)) {
      _proxyStallStartedAt = null;
      _lastProxyProgressPosition = position;
      return;
    }

    final bool moved =
        (position - _lastProxyProgressPosition).abs() >
        const Duration(milliseconds: 500);
    if (moved) {
      _lastProxyProgressPosition = position;
      _proxyStallStartedAt = null;
      return;
    }

    if (!initialized || !native.playing || !native.buffering) {
      _lastProxyProgressPosition = position;
      _proxyStallStartedAt = null;
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime startedAt = _proxyStallStartedAt ?? now;
    _proxyStallStartedAt = startedAt;
    if (now.difference(startedAt) >= _proxyStallFallbackDelay) {
      _proxyStallStartedAt = null;
      unawaited(
        _retryDirectAfterProxyIssue(
          player,
          reason: 'proxy stalled while buffering',
        ),
      );
    }
  }

  Future<void> _safeStartupSeek(mk.Player player, Duration requested) async {
    if (requested <= Duration.zero) return;

    Duration target = requested;
    final Duration duration = _publicDuration(player.state.duration);
    if (duration > Duration.zero &&
        target > duration - const Duration(seconds: 10)) {
      target = duration - const Duration(seconds: 10);
    }
    if (target < Duration.zero) target = Duration.zero;

    try {
      debugPrint('MediaKit delayed startup seek: ${target.inSeconds}s');
      await player.seek(target);
    } on Object catch (error) {
      debugPrint('MediaKit delayed startup seek failed: $error');
    }
  }

  void _attachListeners(mk.Player player) {
    void listen<T>(Stream<T> stream) {
      _subscriptions.add(stream.listen((_) => _syncState()));
    }

    listen<bool>(player.stream.playing);
    listen<bool>(player.stream.buffering);
    listen<Duration>(player.stream.position);
    listen<Duration>(player.stream.duration);
    listen<Duration>(player.stream.buffer);
    listen<double>(player.stream.volume);
    listen<double>(player.stream.rate);
    listen<int?>(player.stream.width);
    listen<int?>(player.stream.height);
    _subscriptions.add(
      player.stream.error.listen((String error) {
        if (_directFallbackInProgress) return;
        if (_shouldRetryDirectAfterProxyError(player)) {
          unawaited(
            _retryDirectAfterProxyIssue(
              player,
              reason: 'proxy stream error: $error',
            ),
          );
          return;
        }
        if (_canRetryDirectAfterProxy(player)) {
          debugPrint(
            'MediaKit: transient proxy stream error after startup; '
            'keeping proxy active: $error',
          );
          return;
        }
        _lastError = error;
        _syncState();
      }),
    );
  }

  @override
  Future<void> play() async {
    final mk.Player? player = _player;
    if (player == null) return;
    await player.play();
    _syncState();
  }

  @override
  Future<void> pause() async {
    final mk.Player? player = _player;
    if (player == null) return;
    await player.pause();
    _syncState();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final mk.Player? player = _player;
    if (player == null) return;
    _state.value = _state.value.copyWith(position: position, isBuffering: true);
    await player.seek(position);
    _syncState();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.25, 3.0).toDouble();
    final mk.Player? player = _player;
    if (player != null) {
      await player.setRate(_playbackSpeed);
      // Reapply buffer config scaled for the new speed, mirroring FVP's
      // _configureNetworkAndBuffering call in setPlaybackSpeed.
      final PlayerSource? source = _currentSource;
      if (source != null) {
        unawaited(_applyMpvProperties(player, source, _playbackSpeed));
      }
    }
    _syncState();
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    final mk.Player? player = _player;
    if (player != null) {
      await player.setVolume((_volume * 100).clamp(0.0, 100.0).toDouble());
    }
    _syncState();
  }

  @override
  Future<void> dispose() async {
    await _disposePlayerOnly();
    await _proxy.stop();
    _state.value = const PlayerEngineState();
    _state.dispose();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(_stateTick, (_) => _syncState());
  }

  void _startOpenTimeout() {
    _openTimeoutTimer?.cancel();
    _openTimeoutTimer = Timer(_openTimeout, () {
      if (!_opening) return;
      final PlayerEngineState current = _state.value;
      if (current.hasError) return;
      final mk.Player? player = _player;
      if (player != null && _canRetryDirectAfterProxy(player)) {
        unawaited(
          _retryDirectAfterProxyIssue(player, reason: 'proxy open timeout'),
        );
        return;
      }
      _lastError =
          'The stream did not start within 90 seconds. The source may be unavailable or require different headers.';
      _state.value = current.copyWith(
        isBuffering: false,
        hasError: true,
        errorDescription: _lastError,
      );
    });
  }

  void _syncState() {
    final mk.Player? player = _player;
    if (player == null) return;

    final mk.PlayerState native = player.state;
    final Duration position = native.position;
    final Duration nativeDuration = native.duration;
    final Duration duration = _publicDuration(nativeDuration);
    final Duration buffer = native.buffer;
    final bool hasVideoSize =
        (native.width ?? 0) > 0 && (native.height ?? 0) > 0;
    final bool hasContent = _hasStartupContent(native);

    if (hasVideoSize) {
      _lastVideoSize = Size(
        native.width!.toDouble(),
        native.height!.toDouble(),
      );
    }

    if (hasContent || _lastError != null) {
      _opening = false;
      _openTimeoutTimer?.cancel();
      _openTimeoutTimer = null;
      _startupRetryTimer?.cancel();
      _startupRetryTimer = null;
    }

    final List<PlayerBufferedRange> buffered = _bufferedRanges(
      position: position,
      buffer: buffer,
      duration: duration,
    );
    if (buffered.isNotEmpty) {
      _lastBufferedRanges = buffered;
    }

    final bool initialized = _hasMedia && hasContent;
    final bool hasError = _lastError != null;
    final double aspectRatio = _effectiveAspectRatio(_lastVideoSize);

    _state.value = PlayerEngineState(
      position: position,
      duration: duration,
      volume: _volume,
      playbackSpeed: _playbackSpeed,
      aspectRatio: aspectRatio,
      videoSize: _lastVideoSize,
      buffered: buffered.isNotEmpty ? buffered : _lastBufferedRanges,
      isInitialized: initialized,
      isPlaying: native.playing,
      isBuffering: !initialized || native.buffering,
      hasVideoSurface: hasVideoSize,
      hasError: hasError,
      errorDescription: _lastError,
    );

    _watchProxyStall(
      player,
      native: native,
      position: position,
      initialized: initialized,
    );
  }

  List<PlayerBufferedRange> _bufferedRanges({
    required Duration position,
    required Duration buffer,
    required Duration duration,
  }) {
    if (duration > Duration.zero && buffer > position) {
      return <PlayerBufferedRange>[
        PlayerBufferedRange(start: position, end: buffer),
      ];
    }
    if (buffer > Duration.zero) {
      final Duration end = position + buffer;
      return <PlayerBufferedRange>[
        PlayerBufferedRange(start: position, end: end),
      ];
    }
    return const <PlayerBufferedRange>[];
  }

  Map<String, String> _normalizedHeaders(
    Uri uri,
    Map<String, String> sourceHeaders,
  ) {
    final Map<String, String> headers = <String, String>{};
    for (final MapEntry<String, String> entry in sourceHeaders.entries) {
      final String name = entry.key.trim();
      final String value = entry.value.trim();
      if (name.isEmpty || value.isEmpty) continue;
      headers[_canonicalHeaderName(name)] = value;
    }

    headers.putIfAbsent(
      HttpHeaders.userAgentHeader,
      () =>
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 MiruShin/1.0',
    );
    headers.putIfAbsent(HttpHeaders.acceptHeader, () => '*/*');

    if (_isOkCdnHost(uri.host)) {
      headers.remove('Origin');
      return headers;
    }

    final String? referer = headers[HttpHeaders.refererHeader];
    if (referer != null &&
        referer.isNotEmpty &&
        !headers.containsKey('Origin')) {
      final Uri? refUri = Uri.tryParse(referer);
      if (refUri != null && refUri.hasScheme && refUri.host.isNotEmpty) {
        headers['Origin'] = '${refUri.scheme}://${refUri.host}';
      }
    }

    return headers;
  }

  bool _requiresPinnedProxy(String? url) {
    if (url == null || url.isEmpty) return false;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !_isOkCdnHost(uri.host)) return false;
    return (uri.queryParameters['urls']?.trim().isNotEmpty ?? false);
  }

  bool _isOkCdnHost(String host) {
    final String lower = host.toLowerCase();
    return lower == 'okcdn.ru' ||
        lower.endsWith('.okcdn.ru') ||
        lower == 'mycdn.me' ||
        lower.endsWith('.mycdn.me');
  }

  String _canonicalHeaderName(String name) {
    final String lower = name.toLowerCase();
    if (lower == 'user-agent') return HttpHeaders.userAgentHeader;
    if (lower == 'referer' || lower == 'referrer') {
      return HttpHeaders.refererHeader;
    }
    if (lower == 'origin') return 'Origin';
    if (lower == 'accept') return HttpHeaders.acceptHeader;
    if (lower == 'cookie') return HttpHeaders.cookieHeader;
    return name;
  }

  double _effectiveAspectRatio(Size videoSize) {
    if (videoSize.width > 0 && videoSize.height > 0) {
      final double reported = videoSize.width / videoSize.height;
      final double? usable = _usableAspectRatio(reported);
      if (usable != null) return usable;
    }
    return _usableAspectRatio(_state.value.aspectRatio) ??
        _usableAspectRatio(_initialAspectRatio) ??
        16 / 9;
  }

  static double? _usableAspectRatio(double? value) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    if (value < 1.2 || value > 2.4) return null;
    return value;
  }

  Future<void> _disposePlayerOnly() async {
    _openGeneration += 1;
    _positionTimer?.cancel();
    _positionTimer = null;
    _openTimeoutTimer?.cancel();
    _openTimeoutTimer = null;
    _startupRetryTimer?.cancel();
    _startupRetryTimer = null;
    _opening = false;
    _hasMedia = false;
    _lastError = null;
    _currentSource = null;
    _nativePlaybackUrl = null;
    _nativePlaybackHeaders = const <String, String>{};
    _directPlaybackUrl = null;
    _currentOpenHeaders = const <String, String>{};
    _currentRequestedStartAt = Duration.zero;
    _currentTargetPlaybackSpeed = 1;
    _currentAutoplay = true;
    _usingProxy = false;
    _directFallbackTried = false;
    _directFallbackInProgress = false;
    _lastProxyProgressPosition = Duration.zero;
    _proxyStallStartedAt = null;
    _lastBufferedRanges = const <PlayerBufferedRange>[];
    _lastVideoSize = Size.zero;
    _lastReliableDuration = Duration.zero;

    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    final mk.Player? player = _player;
    _player = null;
    _videoController = null;
    if (player != null) {
      await player.dispose();
    }
  }
}
