import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../domain/player_models.dart';
import 'player_engine.dart';

const mdk.SeekFlag _vodSeekFlag = mdk.SeekFlag(
  mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache,
);
const mdk.SeekFlag _previewSeekFlag = mdk.SeekFlag(
  mdk.SeekFlag.fromStart | mdk.SeekFlag.keyFrame,
);
const Duration _seekVerificationDelay = Duration(milliseconds: 180);
const Duration _seekAcceptanceTolerance = Duration(milliseconds: 1500);
const Duration _previewPrepareTimeout = Duration(milliseconds: 1800);
const Duration _previewTextureTimeout = Duration(milliseconds: 1200);
const Duration _startupRetryDelay = Duration(seconds: 45);
const int _startupRetryLimit = 0;
const Duration _fragileHlsSmallResumeThreshold = Duration(seconds: 30);
const Duration _firstFramePollInterval = Duration(milliseconds: 250);
const int _firstFramePollAttempts = 120;

/// Pure FVP/MDK implementation of MiruShin's PlayerEngine.
///
/// This engine intentionally does not use VideoPlayerController at runtime.
/// It talks directly to the MDK Player backend exposed by fvp.
class FvpPlayerEngine extends PlayerEngine {
  FvpPlayerEngine({double? initialAspectRatio, bool previewMode = false})
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

  mdk.Player? _player;
  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<dynamic>? _stateSubscription;
  StreamSubscription<dynamic>? _mediaStatusSubscription;
  Timer? _positionTimer;
  Timer? _openTimeoutTimer;
  Timer? _startupRetryTimer;
  bool _opening = false;
  bool _hasMedia = false;
  // Stores errors set by the open-timeout so _syncState() doesn't silently
  // overwrite them the next time the position timer fires.
  String? _lastError;
  double _volume = 1;
  double _playbackSpeed = 1;
  PlayerSource? _currentSource;
  Duration _currentStartAt = Duration.zero;
  bool _currentAutoplay = true;
  int _openGeneration = 0;
  int _startupRetryCount = 0;
  bool _preserveStartupRetryCount = false;
  List<PlayerBufferedRange> _lastBufferedRanges = const <PlayerBufferedRange>[];

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) {
    final mdk.Player? player = _player;
    if (player == null) return const SizedBox.shrink();

    return ValueListenableBuilder<int?>(
      valueListenable: player.textureId,
      builder: (BuildContext context, int? textureId, Widget? child) {
        if (textureId == null) return const SizedBox.shrink();
        return Texture(
          textureId: textureId,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    final bool preserveRetryCount = _preserveStartupRetryCount;
    _preserveStartupRetryCount = false;
    if (!preserveRetryCount) {
      _startupRetryCount = 0;
    }

    await _disposePlayerOnly();
    final int openGeneration = ++_openGeneration;

    final mdk.Player player = mdk.Player();
    _player = player;
    _volume = _state.value.volume;
    _playbackSpeed = _state.value.playbackSpeed;
    _currentSource = source;
    _currentStartAt = startAt ?? Duration.zero;
    _currentAutoplay = autoplay;
    _lastError = null;

    _configureNetworkAndBuffering(player, source, playbackSpeed: _playbackSpeed);
    _attachListeners(player);

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

      player.volume = _volume;
      // Always start the native backend at 1.0x. Some HLS/TS streams stall
      // during startup if playback begins at 1.25x or higher before first
      // frames/timestamps are ready. The saved speed is applied after startup.
      player.playbackRate = 1.0;

      final Uri remoteUri = Uri.parse(source.url);
      _applyDirectMdkHeaders(player, remoteUri, source.headers);
      final String playbackUrl = remoteUri.toString();
      debugPrint('FVP open direct MDK URL: $playbackUrl');

      player.media = playbackUrl;
      if (_previewMode) {
        await _openPreparedPreview(
          player,
          startAt: startAt ?? Duration.zero,
          autoplay: autoplay,
        );
        _syncState();
        return;
      }

      // FVP/MDK direct examples open the main source by setting `media`, then
      // setting playback state, then creating/updating the Flutter texture.
      // Do not call `prepare()` for normal playback: HLS can stay async and
      // prepare may fail or never complete while the player would otherwise
      // start normally.
      player.state = autoplay
          ? mdk.PlaybackState.playing
          : mdk.PlaybackState.paused;
      // FVP examples call updateTexture() without awaiting. Awaiting it can
      // keep PlaybackController in loading forever on streams that start
      // asynchronously or require playlist/segment requests through proxy.
      unawaited(player.updateTexture());

      _startPositionTimer();
      _startOpenTimeout();
      _scheduleStartupRetry(openGeneration);

      final bool fragileHls = _isFragileHls(playbackUrl);
      final Duration requestedInitialPosition = startAt ?? Duration.zero;
      final Duration initialPosition = fragileHls
          ? _safeFragileHlsStartupPosition(requestedInitialPosition)
          : requestedInitialPosition;

      if (fragileHls) {
        if (initialPosition > Duration.zero) {
          unawaited(_seekAfterFirstFrame(player, initialPosition));
        }
        if (targetPlaybackSpeed != 1.0) {
          unawaited(_applySpeedAfterFirstFrame(player, targetPlaybackSpeed));
        }
      } else {
        if (initialPosition > Duration.zero) {
          unawaited(_seekAfterOpen(initialPosition));
        }
        if (targetPlaybackSpeed != 1.0) {
          unawaited(_applySpeedAfterStartup(player, targetPlaybackSpeed));
        }
      }

      _syncState();
    } on Object catch (error) {
      _state.value = _state.value.copyWith(
        hasError: true,
        errorDescription: error.toString(),
      );
      rethrow;
    }
  }

  bool _isFragileHls(String url) {
    final String lower = url.toLowerCase();
    return lower.contains('solodcdn.com') ||
        lower.contains(':hls:manifest.m3u8') ||
        lower.contains('.mp4:hls:');
  }

  Duration _safeFragileHlsStartupPosition(Duration position) {
    if (position < _fragileHlsSmallResumeThreshold) {
      return Duration.zero;
    }
    return position;
  }

  void _scheduleStartupRetry(int generation) {
    _startupRetryTimer?.cancel();
    _startupRetryTimer = Timer(_startupRetryDelay, () {
      if (generation != _openGeneration) return;
      if (!_opening || !_hasMedia || _lastError != null) return;

      final mdk.Player? player = _player;
      if (player == null) return;
      if (_hasStartupContent(player)) return;
      if (_startupRetryCount >= _startupRetryLimit) return;

      _startupRetryCount += 1;
      debugPrint(
        'FVP startup retry $_startupRetryCount/$_startupRetryLimit: '
        'stream did not produce frames within ${_startupRetryDelay.inSeconds}s.',
      );
      unawaited(_retryOpenCurrentSource());
    });
  }

  bool _hasStartupContent(mdk.Player player) {
    final mdk.MediaStatus status = player.mediaStatus;
    final mdk.MediaInfo info = player.mediaInfo;
    final Size videoSize = _videoSize(info);
    return player.position > 0 ||
        info.duration > 0 ||
        player.textureId.value != null ||
        videoSize.width > 0 ||
        videoSize.height > 0 ||
        player.buffered() > 0 ||
        status.test(mdk.MediaStatus.prepared) ||
        status.test(mdk.MediaStatus.loaded);
  }

  Future<void> _retryOpenCurrentSource() async {
    final PlayerSource? source = _currentSource;
    if (source == null) return;

    final Duration position = _state.value.position > Duration.zero
        ? _state.value.position
        : _currentStartAt;
    final bool autoplay = _currentAutoplay;

    _preserveStartupRetryCount = true;
    await open(source, startAt: position, autoplay: autoplay);
  }

  Future<void> _openPreparedPreview(
    mdk.Player player, {
    required Duration startAt,
    required bool autoplay,
  }) async {
    _startPositionTimer();
    try {
      final int preparedPosition = await player
          .prepare(position: startAt.inMilliseconds, flags: _previewSeekFlag)
          .timeout(_previewPrepareTimeout);
      if (preparedPosition < 0) {
        throw StateError('FVP preview prepare failed ($preparedPosition).');
      }

      final int textureResult = await player
          .updateTexture(width: 320, height: 180)
          .timeout(_previewTextureTimeout, onTimeout: () => -1);
      if (textureResult < 0) {
        unawaited(player.updateTexture(width: 320, height: 180));
      }
    } on Object catch (error) {
      debugPrint('FVP preview prepare fallback: $error');
      player.state = autoplay
          ? mdk.PlaybackState.playing
          : mdk.PlaybackState.paused;
      unawaited(player.updateTexture(width: 320, height: 180));
      if (startAt > Duration.zero) {
        unawaited(_seekPreviewAfterOpen(player, startAt));
      }
      _startOpenTimeout();
      _syncState();
      return;
    }

    _opening = false;
    _openTimeoutTimer?.cancel();
    _openTimeoutTimer = null;

    if (autoplay) {
      player.state = mdk.PlaybackState.playing;
    } else {
      player.state = mdk.PlaybackState.paused;
    }
  }

  Future<void> _seekPreviewAfterOpen(
    mdk.Player player,
    Duration position,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final mdk.Player? active = _player;
    if (active == null || active != player || !_hasMedia) return;

    try {
      await _seekWithVerification(
        active,
        position.inMilliseconds,
        flag: _previewSeekFlag,
        attempts: 2,
        verificationDelay: const Duration(milliseconds: 120),
      );
    } on Object catch (error) {
      debugPrint('FVP preview delayed seek ignored: $error');
    }
  }

  @override
  Future<void> play() async {
    final mdk.Player? player = _player;
    if (player == null) return;

    // Do NOT reopen HLS on resume. Reopening replaces the decoder/session and
    // can reset MDK to 0 if the delayed seek is ignored or stream metadata is
    // not ready. Resume must only continue the existing player instance.
    player.state = mdk.PlaybackState.playing;
    _state.value = _state.value.copyWith(isPlaying: true);
    _syncState();
  }

  @override
  Future<void> pause() async {
    final mdk.Player? player = _player;
    if (player == null) return;
    player.state = mdk.PlaybackState.paused;
    _state.value = _state.value.copyWith(isPlaying: false, isBuffering: false);
    _syncState();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final mdk.Player? player = _player;
    if (player == null) return;
    final int targetMs = position.inMilliseconds.clamp(0, 1 << 62).toInt();
    await _seekWithVerification(
      player,
      targetMs,
      flag: _previewMode ? _previewSeekFlag : _vodSeekFlag,
      attempts: 4,
      verificationDelay: _seekVerificationDelay,
    );
    _syncState();
  }

  Future<void> _seekAfterOpen(Duration position) async {
    // MDK/FVP often reports the player as usable before HLS metadata and
    // keyframes are actually ready. A single early seek can be ignored, which
    // makes resume always start from 0:00. Keep retrying for a short window and
    // stop as soon as the native player accepts the resume position.
    final int targetMs = position.inMilliseconds;

    for (int attempt = 0; attempt < 40; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final mdk.Player? player = _player;
      if (player == null || !_hasMedia) return;

      try {
        if (await _seekWithVerification(
          player,
          targetMs,
          flag: _vodSeekFlag,
          attempts: 1,
          verificationDelay: const Duration(milliseconds: 120),
        )) {
          return;
        }
      } on Object catch (error) {
        if (attempt == 39) {
          debugPrint('FVP initial seek ignored after retries: $error');
        }
      }
    }
  }

  Future<void> _applySpeedAfterStartup(
    mdk.Player player,
    double speed,
  ) async {
    // Keep native startup at 1.0x, then apply the saved speed after the stream
    // has real media state. This fixes HLS streams that start at 1x but stall
    // when opened directly at 1.25x or higher.
    for (int attempt = 0; attempt < 60; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final mdk.Player? active = _player;
      if (active == null || active != player || !_hasMedia) return;

      final bool ready = _hasStartupContent(active);

      if (ready) {
        break;
      }
    }

    final mdk.Player? active = _player;
    if (active == null || active != player || !_hasMedia) return;

    final PlayerSource? source = _currentSource;
    if (source != null) {
      _configureNetworkAndBuffering(
        active,
        source,
        playbackSpeed: speed,
      );
    }

    active.playbackRate = speed;
    _syncState();
  }


  Future<bool> _waitForFirstFrame(mdk.Player player) async {
    for (int attempt = 0; attempt < _firstFramePollAttempts; attempt += 1) {
      await Future<void>.delayed(_firstFramePollInterval);

      final mdk.Player? active = _player;
      if (active == null || active != player || !_hasMedia) return false;

      final mdk.MediaInfo info = active.mediaInfo;
      final Size videoSize = _videoSize(info);
      final bool hasVideoSize = videoSize.width > 0 && videoSize.height > 0;
      final bool hasPlaybackClock = active.position > 0;
      final bool hasDemuxedMedia = info.duration > 0 || active.buffered() > 0;

      if (hasVideoSize && (hasPlaybackClock || hasDemuxedMedia)) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return true;
      }
    }
    return false;
  }

  Future<void> _seekAfterFirstFrame(
    mdk.Player player,
    Duration position,
  ) async {
    final bool ready = await _waitForFirstFrame(player);
    if (!ready) return;

    final mdk.Player? active = _player;
    if (active == null || active != player || !_hasMedia) return;

    try {
      await _seekWithVerification(
        active,
        position.inMilliseconds,
        flag: _vodSeekFlag,
        attempts: 3,
        verificationDelay: _seekVerificationDelay,
      );
    } on Object catch (error) {
      debugPrint('FVP fragile HLS delayed seek failed: $error');
    }
    _syncState();
  }

  Future<void> _applySpeedAfterFirstFrame(
    mdk.Player player,
    double speed,
  ) async {
    final bool ready = await _waitForFirstFrame(player);
    if (!ready) return;

    final mdk.Player? active = _player;
    if (active == null || active != player || !_hasMedia) return;

    final PlayerSource? source = _currentSource;
    if (source != null) {
      _configureNetworkAndBuffering(active, source, playbackSpeed: speed);
    }
    active.playbackRate = speed;
    _syncState();
  }


  Future<bool> _seekWithVerification(
    mdk.Player player,
    int targetMs, {
    required mdk.SeekFlag flag,
    required int attempts,
    required Duration verificationDelay,
  }) async {
    int attemptCount = attempts < 1 ? 1 : attempts;
    final Duration target = Duration(milliseconds: targetMs);

    for (int attempt = 0; attempt < attemptCount; attempt += 1) {
      final mdk.Player? active = _player;
      if (active == null || active != player || !_hasMedia) return false;

      final int beforeMs = active.position.clamp(0, 1 << 62).toInt();
      final PlayerEngineState current = _state.value;
      _state.value = current.copyWith(
        position: target,
        isBuffering:
            _isPositionBuffered(current.buffered, target, current.duration)
            ? false
            : current.isBuffering,
      );

      await active.seek(position: targetMs, flags: flag);
      await Future<void>.delayed(verificationDelay);

      final mdk.Player? verifyPlayer = _player;
      if (verifyPlayer == null || verifyPlayer != player || !_hasMedia) {
        return false;
      }

      _syncState();
      final int actualMs = verifyPlayer.position.clamp(0, 1 << 62).toInt();
      if (_seekWasAccepted(
        beforeMs: beforeMs,
        actualMs: actualMs,
        targetMs: targetMs,
      )) {
        return true;
      }
    }

    return false;
  }

  bool _seekWasAccepted({
    required int beforeMs,
    required int actualMs,
    required int targetMs,
  }) {
    final int toleranceMs = _seekAcceptanceTolerance.inMilliseconds;
    if ((actualMs - targetMs).abs() <= toleranceMs) {
      return true;
    }

    final bool seekingForward = targetMs >= beforeMs;
    if (seekingForward) {
      return actualMs >= targetMs - toleranceMs;
    }
    return actualMs <= targetMs + toleranceMs;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    final double safeSpeed = speed.clamp(0.25, 3.0).toDouble();
    _playbackSpeed = safeSpeed;
    final mdk.Player? player = _player;
    final PlayerSource? source = _currentSource;
    if (player != null) {
      if (source != null) {
        _configureNetworkAndBuffering(
          player,
          source,
          playbackSpeed: safeSpeed,
        );
      }
      player.playbackRate = safeSpeed;
    }
    _syncState();
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    final mdk.Player? player = _player;
    if (player != null) {
      player.volume = _volume;
    }
    _syncState();
  }

  @override
  Future<void> dispose() async {
    await _disposePlayerOnly();
    _state.value = const PlayerEngineState();
    _state.dispose();
  }

  void _applyDirectMdkHeaders(
    mdk.Player player,
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

    // Many CDNs validate that Origin matches the Referer host.
    // Derive Origin from Referer when not already set by the addon.
    final String? referer = headers[HttpHeaders.refererHeader];
    if (referer != null && referer.isNotEmpty && !headers.containsKey('Origin')) {
      final Uri? refUri = Uri.tryParse(referer);
      if (refUri != null && refUri.hasScheme && refUri.host.isNotEmpty) {
        headers['Origin'] = '${refUri.scheme}://${refUri.host}';
      }
    }

    final String? userAgent = headers.remove(HttpHeaders.userAgentHeader);
    if (userAgent != null && userAgent.isNotEmpty) {
      player.setProperty('avio.user_agent', userAgent);
    }

    // Use the dedicated avio.referer property so libavformat re-sends the
    // Referer header after cross-domain CDN redirects (avio.headers is dropped
    // on such redirects, but avio.referer is preserved for the entire session).
    final String? refererValue = headers.remove(HttpHeaders.refererHeader);
    if (refererValue != null && refererValue.isNotEmpty) {
      try {
        player.setProperty('avio.referer', refererValue);
      } on Object {
        // Fall back: re-include in avio.headers if property unsupported.
        headers[HttpHeaders.refererHeader] = refererValue;
      }
    }

    // FFmpeg/MDK expects HTTP headers as CRLF-separated "Name: Value" lines.
    final String avioHeaders = headers.entries
        .map((MapEntry<String, String> entry) => '${entry.key}: ${entry.value}')
        .join('\r\n');
    if (avioHeaders.isNotEmpty) {
      player.setProperty('avio.headers', '$avioHeaders\r\n');
    }
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

  ({int min, int max, String ranges}) _bufferConfigFor({
    required bool previewMode,
    required bool isHls,
    required bool isNetwork,
    required double speed,
  }) {
    if (previewMode) {
      return (min: 500, max: 8000, ranges: '2');
    }

    // MPV-like FVP profile: start fast with a small minimum buffer, but allow
    // a large read-ahead cache. This helps streams that only continue loading
    // well when the playback pressure is low, without forcing visible pauses.
    if (isHls) {
      if (speed <= 1.0) {
        return (min: 1500, max: 300000, ranges: '24');
      }
      if (speed <= 1.5) {
        return (min: 3000, max: 360000, ranges: '28');
      }
      if (speed <= 2.0) {
        return (min: 6000, max: 420000, ranges: '32');
      }
      return (min: 12000, max: 480000, ranges: '40');
    }

    if (isNetwork) {
      if (speed <= 1.0) {
        return (min: 2000, max: 180000, ranges: '12');
      }
      if (speed <= 1.5) {
        return (min: 4000, max: 240000, ranges: '16');
      }
      if (speed <= 2.0) {
        return (min: 8000, max: 300000, ranges: '20');
      }
      return (min: 12000, max: 360000, ranges: '24');
    }

    return (min: 1000, max: 60000, ranges: '4');
  }

  void _configureNetworkAndBuffering(
    mdk.Player player,
    PlayerSource source, {
    double playbackSpeed = 1.0,
  }) {
    final String url = source.url.toLowerCase();
    final bool isNetwork =
        url.startsWith('http://') || url.startsWith('https://');
    final bool isHls =
        source.streamType == StreamType.hls || url.contains('.m3u8') || url.contains(':hls:');
    final config = _bufferConfigFor(
      previewMode: _previewMode,
      isHls: isHls,
      isNetwork: isNetwork,
      speed: playbackSpeed,
    );

    try {
      player.setProperty('demux.buffer.protocols', 'file,http,https');
      player.setProperty('demux.buffer.ranges', config.ranges);
      player.setBufferRange(
        min: config.min,
        max: config.max,
        drop: _previewMode,
      );
    } on Object {
      player.setBufferRange(
        min: config.min,
        max: config.max,
        drop: _previewMode,
      );
    }

    try {
      player.setProperty('avformat.strict', 'experimental');
      player.setProperty('avformat.safe', '0');
      player.setProperty('avformat.extension_picky', '0');
      player.setProperty('avformat.allowed_segment_extensions', 'ALL');
      player.setProperty('avformat.protocol_whitelist', 'file,http,https,tcp,tls,crypto');
    } on Object {
      // Not all MDK builds expose avformat properties — safe to ignore.
    }

    try {
      player.setProperty('avio.reconnect', '1');
      player.setProperty('avio.reconnect_streamed', '1');
      player.setProperty('avio.reconnect_at_eof', '1');
      player.setProperty('avio.reconnect_delay_max', '5');
      player.setProperty('avio.rw_timeout', '15000000');
    } on Object {
      // Older MDK builds may not expose all avio properties — safe to ignore.
    }
  }

  void _attachListeners(mdk.Player player) {
    _eventSubscription = player.onEvent.listen((dynamic _) => _syncState());
    _stateSubscription = player.onStateChanged.listen(
      (dynamic _) => _syncState(),
    );
    _mediaStatusSubscription = player.onMediaStatus.listen(
      (dynamic _) => _syncState(),
    );
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _syncState(),
    );
  }

  void _startOpenTimeout() {
    _openTimeoutTimer?.cancel();
    _openTimeoutTimer = Timer(const Duration(seconds: 90), () {
      if (!_opening) return;
      final PlayerEngineState current = _state.value;
      if (current.hasError) return;
      _lastError =
          'The stream did not start within 90 seconds. '
          'The source may be unavailable or require different headers.';
      _state.value = current.copyWith(
        isBuffering: false,
        hasError: true,
        errorDescription: _lastError,
      );
    });
  }

  void _syncState() {
    final mdk.Player? player = _player;
    if (player == null) return;

    final mdk.MediaStatus status = player.mediaStatus;
    final mdk.MediaInfo info = player.mediaInfo;
    final Size videoSize = _videoSize(info);
    final double reportedAspectRatio =
        videoSize.width > 0 && videoSize.height > 0
        ? videoSize.width / videoSize.height
        : 0;
    final double aspectRatio = _effectiveAspectRatio(reportedAspectRatio);
    final Duration position = Duration(
      milliseconds: player.position.clamp(0, 1 << 62).toInt(),
    );
    final Duration duration = Duration(
      milliseconds: info.duration.clamp(0, 1 << 62).toInt(),
    );
    final bool hasTexture = player.textureId.value != null;
    final bool hasVideoSize = videoSize.width > 0 && videoSize.height > 0;
    final bool hasDuration = duration > Duration.zero;
    final bool invalid = status.test(mdk.MediaStatus.invalid);
    // Preserve errors set by the open-timeout: _syncState fires every 120ms
    // and would silently reset hasError back to false otherwise.
    final bool hasError = invalid || _lastError != null;
    final bool isPlaying =
        player.state == mdk.PlaybackState.playing ||
        player.state == mdk.PlaybackState.running;
    final bool nativeBuffering =
        status.test(mdk.MediaStatus.buffering) ||
        status.test(mdk.MediaStatus.loading) ||
        status.test(mdk.MediaStatus.stalled);
    final bool initialized =
        !invalid &&
        _hasMedia &&
        (hasTexture ||
            hasVideoSize ||
            hasDuration ||
            status.test(mdk.MediaStatus.prepared) ||
            status.test(mdk.MediaStatus.loaded) ||
            player.state == mdk.PlaybackState.paused ||
            player.state == mdk.PlaybackState.playing ||
            player.state == mdk.PlaybackState.running);

    // Only consider the stream truly opened once it has real content or an error.
    // Player state alone (paused/playing) is set immediately and must not clear
    // _opening prematurely, otherwise the open-timeout never fires for stuck streams.
    final bool hasContent =
        hasDuration ||
        hasTexture ||
        hasVideoSize ||
        status.test(mdk.MediaStatus.prepared) ||
        status.test(mdk.MediaStatus.loaded);
    if (hasContent || invalid) {
      _opening = false;
      _openTimeoutTimer?.cancel();
      _openTimeoutTimer = null;
      _startupRetryTimer?.cancel();
      _startupRetryTimer = null;
    }

    final List<PlayerBufferedRange> nativeBufferedRanges = _bufferedRanges(
      player,
    );
    if (nativeBufferedRanges.isNotEmpty) {
      _lastBufferedRanges = nativeBufferedRanges;
    }
    final bool transientBufferReset =
        nativeBufferedRanges.isEmpty &&
        (status.test(mdk.MediaStatus.seeking) || nativeBuffering);
    final List<PlayerBufferedRange> bufferedRanges = transientBufferReset
        ? _lastBufferedRanges
        : nativeBufferedRanges;
    final bool seekIsBuffered = _isPositionBuffered(
      bufferedRanges,
      position,
      duration,
    );

    _state.value = PlayerEngineState(
      position: position,
      duration: duration,
      volume: _volume,
      playbackSpeed: _playbackSpeed,
      aspectRatio: aspectRatio,
      videoSize: videoSize,
      buffered: bufferedRanges,
      isInitialized: initialized,
      isPlaying: isPlaying,
      isBuffering:
          !initialized ||
          (status.test(mdk.MediaStatus.seeking) && !seekIsBuffered) ||
          (isPlaying && nativeBuffering),
      hasVideoSurface: hasTexture,
      hasError: hasError,
      errorDescription: _lastError ?? (invalid ? status.toString() : null),
    );
  }

  double _effectiveAspectRatio(double reportedAspectRatio) {
    final double fallback =
        _usableAspectRatio(_state.value.aspectRatio) ??
        _usableAspectRatio(_initialAspectRatio) ??
        16 / 9;
    final double? reported = _usableAspectRatio(reportedAspectRatio);
    if (reported == null) return fallback;

    final double? seeded = _usableAspectRatio(_initialAspectRatio);
    if (seeded != null) {
      final double diff = (reported - seeded).abs();
      // Some low-quality HLS variants report coded size like 640x480 even
      // when the visible video is still 16:9. During quality switch, prefer
      // the already-known aspect ratio if the new variant suddenly reports a
      // much narrower/wider ratio.
      if (diff > 0.20) return seeded;
    }

    return reported;
  }

  static double? _usableAspectRatio(double? value) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    if (value < 1.2 || value > 2.4) return null;
    return value;
  }

  Size _videoSize(mdk.MediaInfo info) {
    final List<mdk.VideoStreamInfo>? videos = info.video;
    if (videos == null || videos.isEmpty) return _state.value.videoSize;
    final mdk.VideoCodecParameters codec = videos.first.codec;
    final int width = codec.width;
    final int height = codec.height;
    if (width <= 0 || height <= 0) return _state.value.videoSize;
    return Size(width.toDouble(), height.toDouble());
  }

  List<PlayerBufferedRange> _bufferedRanges(mdk.Player player) {
    final List<PlayerBufferedRange> bufferedRanges = <PlayerBufferedRange>[];
    try {
      final List<dynamic> ranges = player.bufferedTimeRanges();
      bufferedRanges.addAll(
        ranges.map(
          (dynamic range) => PlayerBufferedRange(
            start: range.start as Duration,
            end: range.end as Duration,
          ),
        ),
      );
    } on Object {
      // Fall back to buffered duration below.
    }

    if (bufferedRanges.isNotEmpty) {
      return bufferedRanges;
    }

    final int bufferedMs = player.buffered();
    if (bufferedMs > 0) {
      final int positionMs = player.position.clamp(0, 1 << 62).toInt();
      bufferedRanges.add(
        PlayerBufferedRange(
          start: Duration(milliseconds: positionMs),
          end: Duration(milliseconds: positionMs + bufferedMs),
        ),
      );
    }
    return bufferedRanges;
  }

  bool _isPositionBuffered(
    List<PlayerBufferedRange> ranges,
    Duration position,
    Duration duration,
  ) {
    final int totalMs = duration.inMilliseconds;
    if (totalMs <= 0 || ranges.isEmpty) return false;
    final int positionMs = position.inMilliseconds.clamp(0, totalMs).toInt();
    final int toleranceMs = const Duration(milliseconds: 1200).inMilliseconds;
    for (final PlayerBufferedRange range in ranges) {
      final int startMs = range.start.inMilliseconds.clamp(0, totalMs).toInt();
      final int endMs = range.end.inMilliseconds.clamp(0, totalMs).toInt();
      if (endMs <= startMs) continue;
      if (positionMs >= startMs - toleranceMs &&
          positionMs <= endMs + toleranceMs) {
        return true;
      }
    }
    return false;
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
    _lastBufferedRanges = const <PlayerBufferedRange>[];
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _mediaStatusSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription = null;
    _mediaStatusSubscription = null;

    final mdk.Player? player = _player;
    _player = null;
    if (player != null) {
      player.state = mdk.PlaybackState.stopped;
      player.dispose();
    }
  }
}
