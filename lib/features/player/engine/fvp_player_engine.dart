import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../domain/player_models.dart';
import 'local_hls_metadata.dart';
import 'local_hls_proxy.dart';
import 'player_engine.dart';
import 'startup_seek.dart';
import 'stream_url_policy.dart';

const mdk.SeekFlag _networkVodSeekFlag = mdk.SeekFlag(mdk.SeekFlag.fromStart);
const mdk.SeekFlag _cachedVodSeekFlag = mdk.SeekFlag(
  mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache,
);
const Duration _seekAcceptanceTolerance = Duration(milliseconds: 1500);
const Duration _startupRetryDelay = Duration(seconds: 45);
const Duration _videoSurfaceStartupTimeout = Duration(seconds: 20);
const Duration _nativeDisposeSettleDelay = Duration(milliseconds: 250);
const Duration _mediaClearSettleDelay = Duration(milliseconds: 80);
const int _minimumTextureMdkVersion = 8960;
const int _startupRetryLimit = 0;
const Duration _firstFramePollInterval = Duration(milliseconds: 250);
const int _firstFramePollAttempts = 120;
const Duration _invalidStatusGrace = Duration(seconds: 3);
const Duration _nativeCompletionRearmDelay = Duration(milliseconds: 700);
const List<Duration> _speedStartupReapplyDelays = <Duration>[
  Duration(milliseconds: 300),
  Duration(milliseconds: 900),
  Duration(milliseconds: 1600),
  Duration(milliseconds: 3000),
];

class _NativeSeekRequest {
  _NativeSeekRequest({
    required this.player,
    required this.openGeneration,
    required this.seekEpoch,
    required this.targetMs,
    required this.flag,
  });

  final mdk.Player player;
  final int openGeneration;
  final int seekEpoch;
  final int targetMs;
  final mdk.SeekFlag flag;
  final Completer<int> completion = Completer<int>();
}

@visibleForTesting
bool shouldExposeFvpNativeCompletion({
  required bool nativeEnded,
  required bool initialized,
  required bool nativeSeekActive,
  required bool nativeSeekPending,
  required bool completionSuppressed,
  required bool completionRearmReady,
  required bool acceptedPositionMatches,
}) {
  if (!nativeEnded || !initialized || nativeSeekActive || nativeSeekPending) {
    return false;
  }
  if (!completionSuppressed) return true;
  return completionRearmReady && acceptedPositionMatches;
}

/// Pure FVP/MDK implementation of MiruShin's PlayerEngine.
///
/// This engine intentionally does not use VideoPlayerController at runtime.
/// It talks directly to the MDK Player backend exposed by fvp.
class FvpPlayerEngine extends PlayerEngine {
  FvpPlayerEngine({double? initialAspectRatio})
    : _initialAspectRatio = initialAspectRatio,
      _state = ValueNotifier<PlayerEngineState>(
        PlayerEngineState(
          aspectRatio: _usableAspectRatio(initialAspectRatio) ?? 16 / 9,
        ),
      );

  final double? _initialAspectRatio;
  final ValueNotifier<PlayerEngineState> _state;

  mdk.Player? _player;
  final LocalHlsProxy _proxy = LocalHlsProxy();
  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<dynamic>? _stateSubscription;
  StreamSubscription<dynamic>? _mediaStatusSubscription;
  Timer? _positionTimer;
  Timer? _openTimeoutTimer;
  Timer? _startupRetryTimer;
  Timer? _videoSurfaceTimeoutTimer;
  bool _opening = false;
  bool _hasMedia = false;
  // Stores errors set by the open-timeout so _syncState() doesn't silently
  // overwrite them the next time the position timer fires.
  String? _lastError;
  double _volume = 1;
  double _playbackSpeed = 1;
  PlayerSource? _currentSource;
  String? _nativePlaybackUrl;
  Map<String, String> _nativePlaybackHeaders = const <String, String>{};
  Duration _currentStartAt = Duration.zero;
  bool _currentAutoplay = true;
  int _openGeneration = 0;
  int _seekEpoch = 0;
  bool _initialPositionSettled = true;
  int _speedApplyGeneration = 0;
  bool _disposed = false;
  int _startupRetryCount = 0;
  bool _preserveStartupRetryCount = false;
  bool _requireVideoSurfaceDuringStartup = false;
  List<PlayerBufferedRange> _lastBufferedRanges = const <PlayerBufferedRange>[];
  Duration _knownSourceDuration = Duration.zero;
  DateTime? _invalidSince;
  bool _reportedInvalid = false;
  _NativeSeekRequest? _activeNativeSeek;
  _NativeSeekRequest? _pendingNativeSeek;
  int? _nativeSeekLoopGeneration;
  Timer? _completionRearmTimer;
  int? _completionSuppressedOpenGeneration;
  int? _completionSuppressedSeekEpoch;
  int? _completionAcceptedSeekEpoch;
  int? _completionAcceptedTargetMs;
  bool _completionRearmReady = false;
  static int? _cachedMdkRuntimeVersion;

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  String? get nativePlaybackUrl => _nativePlaybackUrl;

  @override
  Map<String, String> get nativePlaybackHeaders => _nativePlaybackHeaders;

  @override
  bool get managesInitialPosition => true;

  @override
  bool get initialPositionSettled => _initialPositionSettled;

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
    if (_disposed) return;
    final bool preserveRetryCount = _preserveStartupRetryCount;
    _preserveStartupRetryCount = false;
    if (!preserveRetryCount) {
      _startupRetryCount = 0;
    }

    await _disposePlayerOnly();
    try {
      _ensureTextureRuntimeCompatible();
    } on Object catch (error) {
      _setState(
        _state.value.copyWith(
          isBuffering: false,
          hasError: true,
          errorDescription: error.toString(),
        ),
      );
      rethrow;
    }
    final int openGeneration = ++_openGeneration;

    final mdk.Player player = mdk.Player();
    _player = player;
    _volume = _state.value.volume;
    _playbackSpeed = _state.value.playbackSpeed;
    _currentSource = source;
    _currentStartAt = startAt ?? Duration.zero;
    final int startupSeekEpoch = ++_seekEpoch;
    _initialPositionSettled = _currentStartAt <= Duration.zero;
    _currentAutoplay = autoplay;
    _lastError = null;
    _invalidSince = null;
    _reportedInvalid = false;
    _requireVideoSurfaceDuringStartup = false;

    _configureNetworkAndBuffering(
      player,
      source,
      playbackSpeed: _playbackSpeed,
    );
    _attachListeners(player);

    try {
      _opening = true;
      _hasMedia = true;
      _setState(
        _state.value.copyWith(
          isBuffering: true,
          isInitialized: false,
          hasError: false,
          clearError: true,
        ),
      );

      final double targetPlaybackSpeed = _playbackSpeed;

      player.volume = _volume;
      // Always start the native backend at 1.0x. Some HLS/TS streams stall
      // during startup if playback begins at 1.25x or higher before first
      // frames/timestamps are ready. The saved speed is applied after startup.
      player.playbackRate = 1.0;

      final bool isInlineDash = LocalHlsProxy.isInlineDashUrl(source.url);
      final String inlineDashManifest = isInlineDash
          ? LocalHlsProxy.decodeInlineDashSourceUrl(source.url)
          : '';
      if (isInlineDash && inlineDashManifest.trim().isEmpty) {
        throw const FormatException('Invalid inline DASH manifest.');
      }
      final Uri remoteUri = isInlineDash
          ? Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address)
          : Uri.parse(source.url);
      final bool isNetwork = _isNetworkUrl(source.url);
      final bool isHls = _isHlsLikeSource(source);
      final bool isDash = _isDashLikeSource(source);
      final bool isLocalHls = remoteUri.scheme == 'file' && isHls;
      _knownSourceDuration = isLocalHls
          ? await readLocalHlsDuration(remoteUri)
          : Duration.zero;
      final bool useProxy =
          !source.disableProxy && (isNetwork || isInlineDash || isLocalHls);
      // A downloaded DASH presentation is stored as local HLS metadata around
      // the original fMP4 tracks. It is already demuxable without the MPD
      // parser, so only a real direct MPD needs this Windows guard.
      if (isDash && !isHls && Platform.isWindows && !useProxy) {
        throw UnsupportedError(
          'FVP direct MPEG-DASH is unavailable on Windows because its bundled '
          'FFmpeg does not include the MPD demuxer. Use the local DASH '
          'compatibility proxy.',
        );
      }
      _requireVideoSurfaceDuringStartup = isNetwork;
      String playbackUrl = remoteUri.toString();
      if (useProxy && isInlineDash) {
        await _proxy.stop();
        await _proxy.start();
        playbackUrl = Platform.isWindows
            ? _proxy.inlineDashHlsUrl(
                inlineDashManifest,
                headers: source.headers,
              )
            : _proxy.inlineDashUrl(inlineDashManifest, headers: source.headers);
        debugPrint(
          Platform.isWindows
              ? 'FVP open inline DASH via HLS compatibility proxy: $playbackUrl'
              : 'FVP open inline DASH via proxy: $playbackUrl',
        );
      } else if (useProxy) {
        await _proxy.stop();
        await _proxy.start();
        playbackUrl = isHls
            ? _proxy.playlistUrl(remoteUri, headers: source.headers)
            : isDash
            ? Platform.isWindows
                  ? await _proxy.dashHlsUrl(
                      remoteUri,
                      headers: source.headers,
                      // The local endpoint supplies only HLS metadata. Sending
                      // every multi-megabyte fMP4 fragment through Dart adds a
                      // second socket and makes slow CDN seeks much worse.
                      proxyMedia: false,
                    )
                  : _proxy.dashUrl(remoteUri, headers: source.headers)
            : _proxy.mediaUrl(remoteUri, headers: source.headers);
        debugPrint(
          isDash && Platform.isWindows
              ? 'FVP open DASH via HLS compatibility proxy: $playbackUrl'
              : 'FVP open via proxy: $playbackUrl',
        );
      } else {
        unawaited(_proxy.stop());
        debugPrint(
          source.disableProxy
              ? 'FVP open direct after proxy fallback: $playbackUrl'
              : 'FVP open direct MDK URL: $playbackUrl',
        );
      }
      _nativePlaybackUrl = isLocalHls && useProxy ? playbackUrl : null;
      _nativePlaybackHeaders = const <String, String>{};
      _applyDirectMdkHeaders(
        player,
        isInlineDash ? Uri.parse(playbackUrl) : remoteUri,
        isInlineDash ? const <String, String>{} : source.headers,
      );

      player.media = playbackUrl;
      // FVP/MDK direct examples open the main source by setting `media`, then
      // setting playback state, then creating/updating the Flutter texture.
      // Do not call `prepare()` for normal playback: HLS can stay async and
      // prepare may fail or never complete while the player would otherwise
      // start normally.
      player.state = autoplay
          ? mdk.PlaybackState.playing
          : mdk.PlaybackState.paused;
      // Do not leave a raw updateTexture() future parked on a stream that may
      // never report video. On failed HLS loads that pending native texture
      // work can overlap with the next fallback source and crash inside FVP.
      unawaited(_updateTextureWhenVideoAvailable(player, openGeneration));

      _startPositionTimer();
      _startOpenTimeout();
      _scheduleStartupRetry(openGeneration);
      _startVideoSurfaceTimeout(openGeneration);

      final Duration requestedInitialPosition = startAt ?? Duration.zero;
      if (requestedInitialPosition > Duration.zero) {
        unawaited(
          _applyInitialPosition(
            player,
            openGeneration,
            requestedInitialPosition,
            startupSeekEpoch,
          ),
        );
      }
      if (targetPlaybackSpeed != 1.0) {
        unawaited(_applySpeedAfterStartup(player, targetPlaybackSpeed));
      }

      _syncState();
    } on Object catch (error) {
      _setState(
        _state.value.copyWith(
          hasError: true,
          errorDescription: error.toString(),
        ),
      );
      rethrow;
    }
  }

  bool _isNetworkUrl(String url) {
    if (LocalHlsProxy.isInlineDashUrl(url)) return true;
    final Uri? uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
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

  void _startVideoSurfaceTimeout(int generation) {
    _videoSurfaceTimeoutTimer?.cancel();
    if (!_requireVideoSurfaceDuringStartup) return;

    _videoSurfaceTimeoutTimer = Timer(_videoSurfaceStartupTimeout, () {
      if (generation != _openGeneration ||
          !_hasMedia ||
          !_requireVideoSurfaceDuringStartup ||
          _lastError != null) {
        return;
      }

      final mdk.Player? player = _player;
      if (player == null) return;

      final Size videoSize = _videoSize(player.mediaInfo);
      if (videoSize.width > 0 && videoSize.height > 0) return;

      _lastError = 'Playback did not produce a video surface.';
      debugPrint('FVP: playback did not produce a video surface.');
      _syncState();
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

  void _ensureTextureRuntimeCompatible() {
    final int runtimeVersion = _cachedMdkRuntimeVersion ??= mdk.version();
    if (runtimeVersion >= _minimumTextureMdkVersion) return;

    throw StateError(
      'FVP MDK runtime $runtimeVersion is older than the texture renderer '
      'ABI $_minimumTextureMdkVersion.',
    );
  }

  bool _isActivePlayer(mdk.Player player, int generation) {
    return generation == _openGeneration &&
        _player == player &&
        _hasMedia &&
        _lastError == null;
  }

  Future<void> _updateTextureWhenVideoAvailable(
    mdk.Player player,
    int generation,
  ) async {
    for (int attempt = 0; attempt < _firstFramePollAttempts; attempt += 1) {
      if (!_isActivePlayer(player, generation)) return;

      final Size videoSize = _videoSize(player.mediaInfo);
      if (videoSize.width > 0 && videoSize.height > 0) {
        break;
      }

      final mdk.MediaStatus status = player.mediaStatus;
      if (status.test(mdk.MediaStatus.invalid) ||
          status.test(mdk.MediaStatus.end)) {
        return;
      }

      await Future<void>.delayed(_firstFramePollInterval);
    }

    if (!_isActivePlayer(player, generation)) return;

    final Size videoSize = _videoSize(player.mediaInfo);
    if (videoSize.width <= 0 || videoSize.height <= 0) return;

    try {
      await player.updateTexture();
    } on Object catch (error) {
      if (!_isActivePlayer(player, generation)) return;
      _lastError = 'FVP texture creation failed: $error';
      debugPrint(_lastError);
    }

    if (_isActivePlayer(player, generation)) {
      _syncState();
    }
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

  @override
  Future<void> play() async {
    if (_disposed) return;
    final mdk.Player? player = _player;
    if (player == null) return;

    // Do not reopen HLS on resume. Reopening replaces the decoder and session and
    // can reset MDK to 0 if the delayed seek is ignored or stream metadata is
    // not ready. Resume must only continue the existing player instance.
    player.state = mdk.PlaybackState.playing;
    _setState(_state.value.copyWith(isPlaying: true));
    _syncState();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    final mdk.Player? player = _player;
    if (player == null) return;
    player.state = mdk.PlaybackState.paused;
    _setState(_state.value.copyWith(isPlaying: false, isBuffering: false));
    _syncState();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final int seekEpoch = ++_seekEpoch;
    try {
      await _seekToNative(position, seekEpoch: seekEpoch);
    } finally {
      if (_player != null && _hasMedia) {
        _initialPositionSettled = true;
        _syncState();
      }
    }
  }

  Future<void> _seekToNative(
    Duration position, {
    required int seekEpoch,
  }) async {
    final mdk.Player? player = _player;
    if (player == null) return;
    final int targetMs = position.inMilliseconds.clamp(0, 1 << 62).toInt();
    _beginNativeCompletionSuppression(
      player,
      openGeneration: _openGeneration,
      seekEpoch: seekEpoch,
    );

    // A network seek may remain pending while the selected HLS/fMP4 fragment is
    // downloaded. Keep exactly one native operation active and make every
    // duplicate caller await that same operation. This preserves seekTo's
    // completion contract without creating overlapping native callbacks.
    _publishPendingSeek(Duration(milliseconds: targetMs));
    final mdk.SeekFlag flag = _seekFlagFor(position);
    final int resultMs = await _queueNativeSeek(
      player,
      targetMs,
      flag: flag,
      seekEpoch: seekEpoch,
    );
    if (resultMs < 0) {
      throw StateError(
        'FVP native seek failed at ${position.inMilliseconds}ms '
        '(result=$resultMs).',
      );
    }
    if (player != _player || _disposed || !_hasMedia) return;
    _acceptNativeSeekForCompletion(
      player,
      openGeneration: _openGeneration,
      seekEpoch: seekEpoch,
      resultMs: resultMs,
    );
    _syncState();
    if ((resultMs - targetMs).abs() > _seekAcceptanceTolerance.inMilliseconds) {
      throw StateError(
        'FVP seek completed at ${resultMs}ms instead of ${targetMs}ms.',
      );
    }
    if (kDebugMode) {
      debugPrint(
        'FVP seek complete: target=${targetMs}ms result=${resultMs}ms '
        'mode=${flag.rawValue == _cachedVodSeekFlag.rawValue ? 'cache' : 'network'}',
      );
    }
    _syncState();
  }

  void _publishPendingSeek(Duration target) {
    final PlayerEngineState current = _state.value;
    final bool buffered = _isPositionBuffered(
      current.buffered,
      target,
      current.duration,
    );
    _setState(current.copyWith(isBuffering: buffered ? false : true));
  }

  void _beginNativeCompletionSuppression(
    mdk.Player player, {
    required int openGeneration,
    required int seekEpoch,
  }) {
    if (player != _player || openGeneration != _openGeneration || !_hasMedia) {
      return;
    }
    _completionRearmTimer?.cancel();
    _completionRearmTimer = null;
    _completionSuppressedOpenGeneration = openGeneration;
    _completionSuppressedSeekEpoch = seekEpoch;
    _completionAcceptedSeekEpoch = null;
    _completionAcceptedTargetMs = null;
    _completionRearmReady = false;
  }

  void _acceptNativeSeekForCompletion(
    mdk.Player player, {
    required int openGeneration,
    required int seekEpoch,
    required int resultMs,
  }) {
    if (player != _player ||
        openGeneration != _openGeneration ||
        seekEpoch != _seekEpoch ||
        _completionSuppressedOpenGeneration != openGeneration ||
        _completionSuppressedSeekEpoch != seekEpoch) {
      return;
    }
    _completionAcceptedSeekEpoch = seekEpoch;
    _completionAcceptedTargetMs = resultMs;
    _completionRearmReady = false;
    _completionRearmTimer?.cancel();
    _completionRearmTimer = Timer(_nativeCompletionRearmDelay, () {
      if (_disposed ||
          player != _player ||
          openGeneration != _openGeneration ||
          seekEpoch != _seekEpoch ||
          _completionSuppressedOpenGeneration != openGeneration ||
          _completionSuppressedSeekEpoch != seekEpoch ||
          _completionAcceptedSeekEpoch != seekEpoch) {
        return;
      }
      _completionRearmReady = true;
      _syncState();
    });
  }

  void _clearNativeCompletionSuppression() {
    _completionRearmTimer?.cancel();
    _completionRearmTimer = null;
    _completionSuppressedOpenGeneration = null;
    _completionSuppressedSeekEpoch = null;
    _completionAcceptedSeekEpoch = null;
    _completionAcceptedTargetMs = null;
    _completionRearmReady = false;
  }

  bool _isCurrentNativeSeek(_NativeSeekRequest? request, mdk.Player player) {
    return request != null &&
        request.player == player &&
        request.openGeneration == _openGeneration;
  }

  mdk.SeekFlag _seekFlagFor(Duration target) {
    final PlayerEngineState current = _state.value;
    return target > current.position &&
            _isPositionBuffered(current.buffered, target, current.duration)
        ? _cachedVodSeekFlag
        : _networkVodSeekFlag;
  }

  Future<int> _queueNativeSeek(
    mdk.Player player,
    int targetMs, {
    required mdk.SeekFlag flag,
    required int seekEpoch,
  }) {
    if (_disposed || player != _player || !_hasMedia) {
      return Future<int>.value(-3);
    }
    final int generation = _openGeneration;
    final _NativeSeekRequest? active = _activeNativeSeek;
    if (active != null &&
        active.player == player &&
        active.openGeneration == generation &&
        active.seekEpoch == seekEpoch &&
        active.targetMs == targetMs) {
      return active.completion.future;
    }
    final _NativeSeekRequest? pending = _pendingNativeSeek;
    if (pending != null &&
        pending.player == player &&
        pending.openGeneration == generation &&
        pending.seekEpoch == seekEpoch &&
        pending.targetMs == targetMs) {
      return pending.completion.future;
    }
    if (pending != null && !pending.completion.isCompleted) {
      pending.completion.complete(-2);
    }

    final _NativeSeekRequest request = _NativeSeekRequest(
      player: player,
      openGeneration: generation,
      seekEpoch: seekEpoch,
      targetMs: targetMs,
      flag: flag,
    );
    _pendingNativeSeek = request;
    if (_nativeSeekLoopGeneration == generation) {
      return request.completion.future;
    }
    _nativeSeekLoopGeneration = generation;
    unawaited(_drainNativeSeekQueue(generation));
    return request.completion.future;
  }

  Future<void> _drainNativeSeekQueue(int generation) async {
    try {
      while (!_disposed) {
        final request = _pendingNativeSeek;
        if (request == null || request.openGeneration != generation) return;
        _pendingNativeSeek = null;
        if (request.player != _player ||
            request.openGeneration != _openGeneration ||
            !_hasMedia) {
          continue;
        }

        _activeNativeSeek = request;
        try {
          final int result = await request.player.seek(
            position: request.targetMs,
            flags: request.flag,
          );
          if (!request.completion.isCompleted) {
            request.completion.complete(result);
          }
        } on Object catch (error, stackTrace) {
          if (!request.completion.isCompleted) {
            request.completion.completeError(error, stackTrace);
          }
          if (request.player == _player &&
              request.openGeneration == _openGeneration &&
              !_disposed) {
            debugPrint(
              'FVP native seek failed at ${request.targetMs}ms: $error',
            );
          }
        } finally {
          if (identical(_activeNativeSeek, request)) {
            _activeNativeSeek = null;
          }
        }
        if (request.player == _player &&
            request.openGeneration == _openGeneration &&
            !_disposed) {
          _syncState();
        }
      }
    } finally {
      if (_nativeSeekLoopGeneration == generation) {
        _nativeSeekLoopGeneration = null;
      }
      final pending = _pendingNativeSeek;
      if (pending != null && !_disposed) {
        final int pendingGeneration = pending.openGeneration;
        if (_nativeSeekLoopGeneration != pendingGeneration) {
          _nativeSeekLoopGeneration = pendingGeneration;
          unawaited(_drainNativeSeekQueue(pendingGeneration));
        }
      }
    }
  }

  Future<void> _applyInitialPosition(
    mdk.Player player,
    int openGeneration,
    Duration position,
    int startupSeekEpoch,
  ) async {
    try {
      await _seekAfterOpen(player, openGeneration, position, startupSeekEpoch);
    } finally {
      if (_isActivePlayer(player, openGeneration) &&
          startupSeekEpoch == _seekEpoch) {
        _initialPositionSettled = true;
        _syncState();
      }
    }
  }

  Future<void> _seekAfterOpen(
    mdk.Player expectedPlayer,
    int openGeneration,
    Duration position,
    int startupSeekEpoch,
  ) async {
    // MDK/FVP often reports the player as usable before HLS metadata and
    // keyframes are actually ready. A single early seek can be ignored, which
    // makes resume always start from 0:00. Keep retrying for a short window and
    // stop as soon as the native player accepts the resume position.
    for (int attempt = 0; attempt < 40; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final mdk.Player? player = _player;
      if (player == null ||
          player != expectedPlayer ||
          openGeneration != _openGeneration ||
          startupSeekEpoch != _seekEpoch ||
          !_hasMedia) {
        return;
      }

      // Submit exactly once after metadata becomes usable. FVP owns startAt, so
      // PlaybackController does not submit a second startup-resume seek.
      if (_hasStartupContent(player)) {
        final Duration current = Duration(
          milliseconds: player.position.clamp(0, 1 << 62).toInt(),
        );
        if (!startupSeekNeeded(requested: position, current: current)) return;
        try {
          await _seekToNative(position, seekEpoch: startupSeekEpoch);
        } on Object catch (error) {
          debugPrint('FVP initial seek failed: $error');
        }
        return;
      }
    }
  }

  Future<void> _applySpeedAfterStartup(mdk.Player player, double speed) async {
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

    _applyPlaybackSpeed(active, speed);
    _syncState();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (_disposed) return;
    final double safeSpeed = speed.clamp(0.25, 3.0).toDouble();
    final int speedGeneration = ++_speedApplyGeneration;
    _playbackSpeed = safeSpeed;
    final mdk.Player? player = _player;
    if (player != null) {
      _applyPlaybackSpeed(player, safeSpeed);
      if (safeSpeed != 1.0 && (_opening || !_state.value.isInitialized)) {
        unawaited(
          _reapplyPlaybackSpeedDuringStartup(
            player,
            _openGeneration,
            speedGeneration,
          ),
        );
      }
    }
    _syncState();
  }

  void _applyPlaybackSpeed(mdk.Player player, double speed) {
    final PlayerSource? source = _currentSource;
    if (source != null) {
      _configureNetworkAndBuffering(player, source, playbackSpeed: speed);
    }
    player.playbackRate = speed;
  }

  Future<void> _reapplyPlaybackSpeedDuringStartup(
    mdk.Player player,
    int openGeneration,
    int speedGeneration,
  ) async {
    for (int i = 0; i < _speedStartupReapplyDelays.length; i += 1) {
      await Future<void>.delayed(_speedStartupReapplyDelays[i]);

      final mdk.Player? active = _player;
      if (active == null ||
          active != player ||
          openGeneration != _openGeneration ||
          speedGeneration != _speedApplyGeneration ||
          !_hasMedia) {
        return;
      }

      final bool ready = _hasStartupContent(active);
      final bool lastAttempt = i == _speedStartupReapplyDelays.length - 1;
      if (!ready && !lastAttempt) {
        continue;
      }

      // MDK can accept a rate before HLS startup, then continue native playback
      // at 1x once frames arrive. Reassert the latest requested speed during
      // that settling window so auto-next/new-player opens do not drift from UI.
      _applyPlaybackSpeed(active, _playbackSpeed);
      _syncState();
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _volume = volume.clamp(0.0, 1.0).toDouble();
    final mdk.Player? player = _player;
    if (player != null) {
      player.volume = _volume;
    }
    _syncState();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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

    if (explicitMediaEdgeAddress(uri) != null) {
      headers.remove('Origin');
    }

    // Many CDNs validate that Origin matches the Referer host.
    // Derive Origin from Referer when not already set by the addon.
    final String? referer = headers[HttpHeaders.refererHeader];
    if (referer != null &&
        referer.isNotEmpty &&
        explicitMediaEdgeAddress(uri) == null &&
        !headers.containsKey('Origin')) {
      final Uri? refUri = Uri.tryParse(referer);
      if (refUri != null && refUri.hasScheme && refUri.host.isNotEmpty) {
        headers['Origin'] = '${refUri.scheme}://${refUri.host}';
      }
    }

    final String? userAgent = headers[HttpHeaders.userAgentHeader];
    if (userAgent != null && userAgent.isNotEmpty) {
      try {
        player.setProperty('avio.user_agent', userAgent);
      } on Object {
        // avio.headers below still carries User-Agent on MDK builds without
        // the dedicated user_agent option.
      }
    }

    // Keep Referer in avio.headers for compatibility with fvp's default
    // implementation, and also set the dedicated property when available so
    // libavformat can preserve it across CDN redirects.
    final String? refererValue = headers[HttpHeaders.refererHeader];
    if (refererValue != null && refererValue.isNotEmpty) {
      try {
        player.setProperty('avio.referer', refererValue);
      } on Object catch (error) {
        debugPrint('FVP avio.referer unsupported: $error');
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

  bool _isHlsLikeSource(PlayerSource source) {
    final String lower = source.url.toLowerCase();
    return source.streamType == StreamType.hls ||
        lower.contains('.m3u8') ||
        lower.contains(':hls:') ||
        lower.contains('/hls/') ||
        lower.contains('manifest.m3u8') ||
        lower.contains('.mp4:hls:');
  }

  bool _isDashLikeSource(PlayerSource source) {
    final String lower = source.url.toLowerCase();
    return source.streamType == StreamType.dash ||
        lower.endsWith('.mpd') ||
        lower.contains('.mpd?');
  }

  ({int min, int max, String ranges}) _bufferConfigFor({
    required bool isHls,
    required bool isNetwork,
    required double speed,
  }) {
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
        LocalHlsProxy.isInlineDashUrl(source.url) ||
        url.startsWith('http://') ||
        url.startsWith('https://');
    final bool isHls =
        source.streamType == StreamType.hls ||
        // On Windows DASH is exposed to MDK as generated HLS metadata.
        (Platform.isWindows && _isDashLikeSource(source)) ||
        url.contains('.m3u8') ||
        url.contains(':hls:');
    final config = _bufferConfigFor(
      isHls: isHls,
      isNetwork: isNetwork,
      speed: playbackSpeed,
    );

    try {
      player.setProperty('demux.buffer.protocols', 'file,http,https');
      player.setProperty('demux.buffer.ranges', config.ranges);
      player.setBufferRange(min: config.min, max: config.max, drop: false);
    } on Object {
      player.setBufferRange(min: config.min, max: config.max, drop: false);
    }

    try {
      player.setProperty('avformat.strict', 'experimental');
      player.setProperty('avformat.safe', '0');
      player.setProperty('avformat.extension_picky', '0');
      player.setProperty('avformat.allowed_segment_extensions', 'ALL');
      player.setProperty(
        'avformat.protocol_whitelist',
        'file,http,https,tcp,tls,crypto',
      );
    } on Object {
      // Ignore missing avformat properties on MDK builds that omit them.
    }

    try {
      player.setProperty('avio.reconnect', '1');
      player.setProperty('avio.reconnect_streamed', '1');
      player.setProperty('avio.reconnect_at_eof', '1');
      player.setProperty('avio.reconnect_delay_max', '5');
      player.setProperty('avio.rw_timeout', '15000000');
    } on Object {
      // Ignore missing avio properties on older MDK builds.
    }
  }

  void _attachListeners(mdk.Player player) {
    _eventSubscription = player.onEvent.listen((dynamic event) {
      if (event is mdk.MediaEvent &&
          event.error != 0 &&
          event.category != 'reader.buffering') {
        debugPrint(
          'FVP media event: ${event.category} ${event.detail} '
          '(${event.error})',
        );
      }
      _syncState();
    });
    _stateSubscription = player.onStateChanged.listen(
      (dynamic _) => _syncState(),
    );
    _mediaStatusSubscription = player.onMediaStatus.listen((event) {
      final bool freshNativeEnd =
          !event.oldValue.test(mdk.MediaStatus.end) &&
          event.newValue.test(mdk.MediaStatus.end);
      if (freshNativeEnd &&
          _completionSuppressedOpenGeneration == _openGeneration &&
          _completionSuppressedSeekEpoch == _seekEpoch &&
          _completionAcceptedSeekEpoch == _seekEpoch &&
          !_isCurrentNativeSeek(_activeNativeSeek, player) &&
          !_isCurrentNativeSeek(_pendingNativeSeek, player)) {
        _completionRearmReady = true;
      }
      _syncState();
    });
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
      if (_disposed) return;
      if (!_opening) return;
      final PlayerEngineState current = _state.value;
      if (current.hasError) return;
      _lastError =
          'The stream did not start within 90 seconds. '
          'The source may be unavailable or require different headers.';
      _setState(
        current.copyWith(
          isBuffering: false,
          hasError: true,
          errorDescription: _lastError,
        ),
      );
    });
  }

  void _syncState() {
    if (_disposed) return;
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
    final Duration nativeDuration = Duration(
      milliseconds: info.duration.clamp(0, 1 << 62).toInt(),
    );
    final Duration duration = nativeDuration > _knownSourceDuration
        ? nativeDuration
        : _knownSourceDuration;
    final bool hasTexture = player.textureId.value != null;
    final bool hasVideoSize = videoSize.width > 0 && videoSize.height > 0;
    if (_requireVideoSurfaceDuringStartup && hasVideoSize) {
      _requireVideoSurfaceDuringStartup = false;
    }
    final bool hasDuration = duration > Duration.zero;
    final bool hasContent =
        hasDuration ||
        hasTexture ||
        hasVideoSize ||
        status.test(mdk.MediaStatus.prepared) ||
        status.test(mdk.MediaStatus.loaded);
    final bool nativeInvalid = status.test(mdk.MediaStatus.invalid);
    if (nativeInvalid && !hasContent) {
      _invalidSince ??= DateTime.now();
    } else {
      _invalidSince = null;
      _reportedInvalid = false;
    }
    final DateTime? invalidSince = _invalidSince;
    final bool invalid =
        nativeInvalid &&
        (hasContent ||
            (invalidSince != null &&
                DateTime.now().difference(invalidSince) >=
                    _invalidStatusGrace));
    if (invalid && !_reportedInvalid) {
      _reportedInvalid = true;
      debugPrint('FVP stream invalid: $status');
    }
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
    final bool nativeEnded = status.test(mdk.MediaStatus.end);
    final bool startupRequirementSatisfied = _requireVideoSurfaceDuringStartup
        ? hasVideoSize
        : hasContent;
    final bool initialized =
        !nativeInvalid && _hasMedia && startupRequirementSatisfied;

    // Only consider the stream truly opened once it has real content or a
    // debounced error. Player state alone is set immediately and must not clear
    // _opening prematurely, otherwise the open-timeout never fires.
    if (startupRequirementSatisfied || invalid || _lastError != null) {
      _opening = false;
      _openTimeoutTimer?.cancel();
      _openTimeoutTimer = null;
      _startupRetryTimer?.cancel();
      _startupRetryTimer = null;
      _videoSurfaceTimeoutTimer?.cancel();
      _videoSurfaceTimeoutTimer = null;
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
    final bool nativeSeekActive = _isCurrentNativeSeek(
      _activeNativeSeek,
      player,
    );
    final bool nativeSeekPending = _isCurrentNativeSeek(
      _pendingNativeSeek,
      player,
    );
    bool completionSuppressed =
        _completionSuppressedOpenGeneration == _openGeneration &&
        _completionSuppressedSeekEpoch == _seekEpoch;
    final bool acceptedForCurrentSeek =
        completionSuppressed &&
        _completionAcceptedSeekEpoch == _seekEpoch &&
        _completionAcceptedTargetMs != null;
    if (acceptedForCurrentSeek &&
        !nativeSeekActive &&
        !nativeSeekPending &&
        !nativeEnded) {
      // The accepted seek has produced a normal post-seek state. A later END
      // is therefore a fresh backend event and can use the normal EOF path.
      _clearNativeCompletionSuppression();
      completionSuppressed = false;
    }
    final int? acceptedTargetMs = _completionAcceptedTargetMs;
    final bool acceptedPositionMatches =
        acceptedTargetMs != null &&
        (position.inMilliseconds - acceptedTargetMs).abs() <=
            _seekAcceptanceTolerance.inMilliseconds;
    final bool exposeNativeCompletion = shouldExposeFvpNativeCompletion(
      nativeEnded: nativeEnded,
      initialized: initialized,
      nativeSeekActive: nativeSeekActive,
      nativeSeekPending: nativeSeekPending,
      completionSuppressed: completionSuppressed,
      completionRearmReady: _completionRearmReady,
      acceptedPositionMatches: acceptedPositionMatches,
    );
    if (exposeNativeCompletion && completionSuppressed) {
      _clearNativeCompletionSuppression();
    }

    _setState(
      PlayerEngineState(
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
        isCompleted: exposeNativeCompletion,
        hasVideoSurface: hasTexture,
        hasError: hasError,
        errorDescription: _lastError ?? (invalid ? status.toString() : null),
      ),
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

  void _setState(PlayerEngineState value) {
    if (_disposed) return;
    _state.value = value;
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
    _seekEpoch += 1;
    _clearNativeCompletionSuppression();
    _initialPositionSettled = true;
    final _NativeSeekRequest? pendingSeek = _pendingNativeSeek;
    if (pendingSeek != null && !pendingSeek.completion.isCompleted) {
      pendingSeek.completion.complete(-3);
    }
    _pendingNativeSeek = null;
    final _NativeSeekRequest? activeSeek = _activeNativeSeek;
    if (activeSeek != null && !activeSeek.completion.isCompleted) {
      activeSeek.completion.complete(-3);
    }
    _activeNativeSeek = null;
    _positionTimer?.cancel();
    _positionTimer = null;
    _openTimeoutTimer?.cancel();
    _openTimeoutTimer = null;
    _startupRetryTimer?.cancel();
    _startupRetryTimer = null;
    _videoSurfaceTimeoutTimer?.cancel();
    _videoSurfaceTimeoutTimer = null;
    _opening = false;
    _hasMedia = false;
    _lastError = null;
    _currentSource = null;
    _nativePlaybackUrl = null;
    _nativePlaybackHeaders = const <String, String>{};
    _lastBufferedRanges = const <PlayerBufferedRange>[];
    _knownSourceDuration = Duration.zero;
    _invalidSince = null;
    _reportedInvalid = false;
    _requireVideoSurfaceDuringStartup = false;
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _mediaStatusSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription = null;
    _mediaStatusSubscription = null;
    await _proxy.stop();

    final mdk.Player? player = _player;
    _player = null;
    if (player != null) {
      try {
        player.state = mdk.PlaybackState.stopped;
      } on Object catch (error) {
        debugPrint('FVP stop during dispose ignored: $error');
      }

      if (player.textureId.value == null && player.media.isNotEmpty) {
        try {
          player.media = '';
          await Future<void>.delayed(_mediaClearSettleDelay);
        } on Object catch (error) {
          debugPrint('FVP media clear during dispose ignored: $error');
        }
      }

      try {
        player.dispose();
      } on Object catch (error) {
        debugPrint('FVP dispose ignored: $error');
      }
      await Future<void>.delayed(_nativeDisposeSettleDelay);
    }
  }
}
