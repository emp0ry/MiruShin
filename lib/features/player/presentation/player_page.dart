import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../core/platform/tv_platform.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../../catalog/application/catalog_mode.dart';
import '../application/playback_controller.dart';
import '../application/player_settings.dart';
import '../data/cast_controller.dart';
import '../data/discord_rpc_service.dart';
import '../data/native_player_service.dart';
import '../data/pip_controller.dart';
import '../data/subtitle_parser.dart';
import '../domain/auto_skip.dart';
import '../domain/player_models.dart';
import '../engine/player_engine.dart';
import '../domain/skip_markers_provider.dart';
import 'widgets/auto_next_overlay.dart';
import 'widgets/gesture_overlay.dart';
import 'widgets/player_shortcuts_view.dart';

ButtonStyle _overlayActionButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: Colors.black.withValues(alpha: .85),
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    required this.item,
    this.startInFullscreen = false,
    super.key,
  });

  final MediaPlaybackItem item;
  final bool startInFullscreen;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const MethodChannel _windowChannel = MethodChannel('mirushin/window');
  static const Duration _spaceHoldSpeedDelay = Duration(milliseconds: 260);
  static const Duration _exitCleanupTimeout = Duration(seconds: 2);
  static const Duration _controlsHideDelay = Duration(seconds: 4);
  static const Duration _macosTrailerControlsHideDelay = Duration(seconds: 4);
  static const Duration _defaultTrailerControlsHideDelay = Duration(seconds: 5);

  Timer? _hideTimer;
  Timer? _autoNextTimer;
  Timer? _wakelockTimer;
  Timer? _spaceHoldTimer;
  StreamSubscription<bool>? _pipSub;
  StreamSubscription<NativePlayerEvent>? _nativePlayerSub;
  StreamSubscription<PlayerEngineUiCommand>? _trailerCommandSub;
  PlayerEngine? _trailerCommandEngine;
  bool _inPipMode = false;
  bool _nativePipActive = false;
  bool? _lastPipIsPlaying;
  late final bool _nativePipSupported;
  // Windows mini-player PiP (shrinks the main window, keeps the current
  // player engine running) instead of the native AVPlayer PiP used on iOS/macOS.
  late final bool _windowPipSupported;
  // skipTraversal keeps the full-screen surface node out of D-pad traversal on
  // TV (it would otherwise be a whole-screen "invisible" stop), while still
  // allowing requestFocus() to put keys back on the surface.
  final FocusNode _playerFocusNode = FocusNode(
    debugLabel: 'MiruShinPlayerFocus',
    skipTraversal: true,
  );
  // First chrome control the D-pad lands on (the centre play/pause button).
  final FocusNode _tvChromeSeedFocus = FocusNode(
    debugLabel: 'MiruShinTvChromeSeed',
  );
  bool _stoppedPlayback = false;
  bool _exitingPlayer = false;
  bool _allowRoutePop = false;
  bool _isFullscreen = false;
  bool _preserveFullscreenForNextRoute = false;
  bool _spacePressed = false;
  bool _spaceTemporarySpeedActive = false;
  DateTime? _lastTrailerFullscreenShortcutAt;
  DateTime? _lastTrailerEscapeShortcutAt;
  late final bool _isMobile;
  late final bool _isTv;
  // Engine we are watching for play/pause transitions on Android TV, so we can
  // keep the controls up while paused and let the D-pad reach them.
  PlayerEngine? _tvObservedEngine;
  bool _tvWasPlaying = true;
  late final PlaybackController _playbackNotifier;

  Duration get _trailerControlsHideDelay {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return _macosTrailerControlsHideDelay;
    }
    return _defaultTrailerControlsHideDelay;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    unawaited(WakelockPlus.enable());
    // Re-assert the wakelock every 60 s – guards against any platform-level
    // release that the one-shot enable() might not survive (e.g. system sleep
    // assertion expiry on macOS or focus-change edge cases on Android).
    _wakelockTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) unawaited(WakelockPlus.enable());
    });
    _isMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    _isTv = TvPlatform.isAndroidTv;
    _nativePipSupported = NativePlayerService.isSupported;
    _windowPipSupported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    _playbackNotifier = ref.read(playbackControllerProvider.notifier);
    _playbackNotifier.setNextEpisodeHandler(
      widget.item.ignoreProgress
          ? null
          : () => unawaited(_exitPlayer(playNext: true)),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _shouldStartFullscreen
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      ),
    );
    if (_nativePipSupported) {
      NativePlayerService.init();
      _nativePlayerSub = NativePlayerService.events.listen(
        _handleNativePlayerEvent,
      );
    }
    _pipSub = ref.read(pipControllerProvider).pipModeStream.listen((inPip) {
      if (!mounted) return;
      setState(() => _inPipMode = inPip);
      if (inPip) {
        _hideControls();
      }
    });
    // Initialise from current PiP state in case we're opened while already in PiP.
    _inPipMode = ref.read(pipControllerProvider).isInPipMode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncFullscreenState());
      if (_shouldStartFullscreen) {
        unawaited(_setFullscreen(true));
      }
      _requestPlayerFocus();
      _playbackNotifier.load(widget.item);
      _scheduleHide(
        _isYoutubeTrailerPlayback(
              ref.read(playbackControllerProvider),
              widget.item,
            )
            ? _trailerControlsHideDelay
            : _controlsHideDelay,
      );
    });
  }

  void _handleNativePlayerEvent(NativePlayerEvent event) {
    if (!mounted) return;
    switch (event) {
      case NativePlayerDismissed(
        :final positionMs,
        :final durationMs,
        :final wasPlaying,
      ):
        setState(() => _nativePipActive = false);
        unawaited(
          _restoreFromNativeDismiss(
            positionMs: positionMs,
            durationMs: durationMs,
            wasPlaying: wasPlaying,
          ),
        );
      case NativePlayerCompleted(:final positionMs, :final durationMs):
        setState(() => _nativePipActive = false);
        unawaited(
          _playbackNotifier.saveNativeProgress(
            positionMs: positionMs,
            durationMs: durationMs,
            completed: true,
          ),
        );
        unawaited(_exitPlayer(playNext: true));
      case NativePlayerPipRestored(:final positionMs, :final durationMs):
        unawaited(
          _playbackNotifier.saveNativeProgress(
            positionMs: positionMs,
            durationMs: durationMs,
          ),
        );
    }
  }

  Future<void> _restoreFromNativeDismiss({
    required int positionMs,
    required int durationMs,
    required bool wasPlaying,
  }) async {
    await _playbackNotifier.saveNativeProgress(
      positionMs: positionMs,
      durationMs: durationMs,
    );
    // Seek the paused FVP engine to where the native player left off.
    await _playbackNotifier.skipTo(Duration(milliseconds: positionMs));
    if (wasPlaying && mounted) {
      final PlayerEngine? engine = ref.read(playbackControllerProvider).engine;
      if (engine != null && !engine.state.value.isPlaying) {
        await _playbackNotifier.togglePlay();
      }
    }
  }

  // Enter the Windows mini-player: the DesktopPipController shrinks the
  // main window and flips _inPipMode via pipModeStream. Playback keeps going
  // in the existing engine — no handoff to a second engine.
  Future<void> _enterWindowPip() async {
    final PlayerEngine? engine = ref.read(playbackControllerProvider).engine;
    final double aspectRatio = (engine?.value.aspectRatio ?? 0) > 0
        ? engine!.value.aspectRatio
        : 16 / 9;
    await ref
        .read(pipControllerProvider)
        .enter(
          aspectRatio: aspectRatio,
          isPlaying: engine?.value.isPlaying ?? true,
          hasNext:
              !(ref.read(playbackControllerProvider).item?.ignoreProgress ??
                  false),
        );
  }

  // Restore the main window from the mini-player back to its previous size.
  Future<void> _exitWindowPip() async {
    await ref.read(pipControllerProvider).bringToForeground();
  }

  Future<void> _handOffToNativePip() async {
    if (NativePlayerService.isActive) return;
    final PlaybackState s = ref.read(playbackControllerProvider);
    final PlayerEngine? engine = s.engine;
    if (engine == null || !engine.state.value.isInitialized) return;

    final bool wasPlaying = engine.state.value.isPlaying;
    final int posMs = engine.state.value.position.inMilliseconds;
    final double rate = engine.state.value.playbackSpeed;

    final MediaServer? server = s.server;
    if (server == null) return;
    final StreamQuality? quality = s.quality;
    final String sourceUrl =
        quality != null && !quality.isAuto && quality.url.isNotEmpty
        ? quality.url
        : server.url;
    final Map<String, String> sourceHeaders =
        quality != null && quality.headers.isNotEmpty
        ? quality.headers
        : server.headers;
    final String url = engine.nativePlaybackUrl?.isNotEmpty == true
        ? engine.nativePlaybackUrl!
        : sourceUrl;
    final Map<String, String> nativeHeaders = engine.nativePlaybackHeaders;
    final Map<String, String> headers = nativeHeaders.isNotEmpty
        ? nativeHeaders
        : sourceHeaders;

    final SkipMarkers markers = _effectiveSkipMarkers(
      ref.read(skipMarkersProvider).value,
      s.item?.skipMarkers ?? const SkipMarkers(),
    );
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();

    // Pause FVP and show the "Playing in PiP" overlay.
    await _playbackNotifier.pause();
    if (mounted) setState(() => _nativePipActive = true);

    try {
      await NativePlayerService.present(
        url: url,
        headers: headers,
        positionMs: posMs,
        playbackRate: rate,
        wasPlaying: wasPlaying,
        title: s.item?.title ?? '',
        openingStartMs: markers.openingStart?.inMilliseconds,
        openingEndMs: markers.openingEnd?.inMilliseconds,
        endingStartMs: markers.endingStart?.inMilliseconds,
        endingEndMs: markers.endingEnd?.inMilliseconds,
        autoSkipOpening: settings.autoSkipOpening,
        autoSkipEnding: settings.autoSkipEnding,
      );
    } on PlatformException {
      if (mounted) setState(() => _nativePipActive = false);
      if (wasPlaying && mounted) await _playbackNotifier.togglePlay();
    } on MissingPluginException {
      if (mounted) setState(() => _nativePipActive = false);
      if (wasPlaying && mounted) await _playbackNotifier.togglePlay();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _tvObservedEngine?.state.removeListener(_onTvPlaybackTick);
    _nativePlayerSub?.cancel();
    _trailerCommandSub?.cancel();
    _pipSub?.cancel();
    _wakelockTimer?.cancel();
    unawaited(WakelockPlus.disable());
    _hideTimer?.cancel();
    _autoNextTimer?.cancel();
    _cancelSpaceHold(restoreSpeed: true);
    _playbackNotifier.setNextEpisodeHandler(null);
    unawaited(_stopPlayback());
    _playerFocusNode.dispose();
    _tvChromeSeedFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(
      _preserveFullscreenForNextRoute
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
    super.dispose();
  }

  bool get _shouldStartFullscreen => _isMobile || widget.startInFullscreen;

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted || _nativePipActive || event is! KeyDownEvent) return false;

    final PlaybackState state = ref.read(playbackControllerProvider);
    if (!_isYoutubeTrailerPlayback(state, widget.item)) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _handleTrailerFullscreenShortcut();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _handleTrailerEscapeShortcut();
      return true;
    }
    return false;
  }

  void _requestPlayerFocus() {
    if (!_playerFocusNode.hasFocus && _playerFocusNode.canRequestFocus) {
      _playerFocusNode.requestFocus();
    }
  }

  // Android TV: watch the active engine so pausing keeps the controls on screen
  // (and the D-pad can reach them), while resuming hands keys back to the
  // playback surface and re-arms the auto-hide. No-op on every other platform.
  void _syncTvPlaybackObserver(PlayerEngine? engine) {
    if (!_isTv || identical(_tvObservedEngine, engine)) return;
    _tvObservedEngine?.state.removeListener(_onTvPlaybackTick);
    _tvObservedEngine = engine;
    _tvObservedEngine?.state.addListener(_onTvPlaybackTick);
    _tvWasPlaying = engine?.state.value.isPlaying ?? true;
  }

  void _onTvPlaybackTick() {
    if (!mounted) return;
    final PlayerEngine? engine = _tvObservedEngine;
    if (engine == null) return;
    final bool isPlaying = engine.state.value.isPlaying;
    if (isPlaying == _tvWasPlaying) return;
    _tvWasPlaying = isPlaying;
    final PlaybackController notifier = ref.read(
      playbackControllerProvider.notifier,
    );
    if (!isPlaying) {
      notifier.setControlsVisible(true);
      _hideTimer?.cancel();
      // Land the D-pad on the centre play/pause button right away, so the
      // chrome is navigable without a "dead" first key press.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final PlayerEngine? current = _tvObservedEngine;
        if (current == null || current.state.value.isPlaying) return;
        if (_tvChromeSeedFocus.context != null &&
            _tvChromeSeedFocus.canRequestFocus) {
          _tvChromeSeedFocus.requestFocus();
        }
      });
    } else {
      _requestPlayerFocus();
      _scheduleHide();
    }
  }

  void _scheduleHide([Duration delay = _controlsHideDelay]) {
    _hideTimer?.cancel();
    // On Android TV keep the controls up while paused so the user can navigate
    // them with the D-pad; they only auto-hide again once playback resumes.
    if (_isTv && !(_tvObservedEngine?.state.value.isPlaying ?? true)) {
      return;
    }
    _hideTimer = Timer(delay, () {
      if (!mounted) return;
      // A seek-preview / scrub is in progress: keep the controls (and cursor)
      // visible and re-arm the timer instead of giving up. Otherwise a preview
      // that lingers would strand the chrome and cursor on screen until the
      // user toggles fullscreen, which is exactly the reported bug.
      if (ref.read(playbackControllerProvider).seekPreviewPosition != null) {
        _scheduleHide(delay);
        return;
      }
      ref.read(playbackControllerProvider.notifier).setControlsVisible(false);
    });
  }

  void _maybeScheduleAutoNext(PlaybackState state, PlayerSettings settings) {
    final bool shouldAutoNext =
        !_exitingPlayer &&
        isSamePlaybackRouteItem(state.item, widget.item) &&
        settings.autoplayNext &&
        state.autoNextVisible;
    if (shouldAutoNext && _autoNextTimer == null) {
      // ignore: avoid_print
      print('[DEBUG] auto-next: scheduling advance in 5s');
      _autoNextTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        final PlaybackState currentState = ref.read(playbackControllerProvider);
        if (!isSamePlaybackRouteItem(currentState.item, widget.item)) {
          _autoNextTimer?.cancel();
          _autoNextTimer = null;
          return;
        }
        _autoNextTimer?.cancel();
        _autoNextTimer = null;
        // ignore: avoid_print
        print('[DEBUG] auto-next: timer fired -> advancing to next episode');
        final PlaybackController notifier = ref.read(
          playbackControllerProvider.notifier,
        );
        notifier.dismissAutoNext();
        // Mark the finishing episode watched before advancing, so it is never
        // left unwatched when the next episode starts.
        unawaited(
          notifier.markCurrentEpisodeWatched().whenComplete(
            () => unawaited(_exitPlayer(playNext: true)),
          ),
        );
      });
    } else if (!shouldAutoNext && _autoNextTimer != null) {
      _autoNextTimer?.cancel();
      _autoNextTimer = null;
    }
  }

  void _showControls() {
    _requestPlayerFocus();
    ref.read(playbackControllerProvider.notifier).setControlsVisible(true);
    _scheduleHide();
  }

  void _showTrailerControls() {
    if (!mounted) return;
    ref.read(playbackControllerProvider.notifier).setControlsVisible(true);
    _scheduleHide(_trailerControlsHideDelay);
  }

  void _handleTrailerFullscreenShortcut() {
    if (!_acceptTrailerShortcut(ref.read(playbackControllerProvider))) return;
    _showTrailerControls();
    _toggleFullscreen();
  }

  void _handleTrailerEscapeShortcut() {
    if (!_acceptTrailerShortcut(
      ref.read(playbackControllerProvider),
      escape: true,
    )) {
      return;
    }
    _showTrailerControls();
    if (_isFullscreen) {
      unawaited(_setFullscreen(false));
    } else {
      _handleEscape();
    }
  }

  bool _acceptTrailerShortcut(PlaybackState state, {bool escape = false}) {
    if (!_isYoutubeTrailerPlayback(state, widget.item)) return false;
    final DateTime now = DateTime.now();
    final DateTime? last = escape
        ? _lastTrailerEscapeShortcutAt
        : _lastTrailerFullscreenShortcutAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 250)) {
      return false;
    }
    if (escape) {
      _lastTrailerEscapeShortcutAt = now;
    } else {
      _lastTrailerFullscreenShortcutAt = now;
    }
    return true;
  }

  void _attachTrailerCommands(PlayerEngine? engine) {
    if (_trailerCommandEngine == engine) return;
    unawaited(_trailerCommandSub?.cancel());
    _trailerCommandSub = null;
    _trailerCommandEngine = engine;
    if (engine != null) {
      _trailerCommandSub = engine.uiCommands.listen(_handleTrailerCommand);
      unawaited(engine.setHostFullscreen(_isFullscreen));
    }
  }

  void _handleTrailerCommand(PlayerEngineUiCommand command) {
    if (!mounted) return;
    switch (command) {
      case PlayerEngineUiCommand.showControls:
        _showTrailerControls();
        break;
      case PlayerEngineUiCommand.toggleFullscreen:
        _handleTrailerFullscreenShortcut();
        break;
      case PlayerEngineUiCommand.exitFullscreen:
        _handleTrailerEscapeShortcut();
        break;
      case PlayerEngineUiCommand.exitPlayer:
        _showTrailerControls();
        unawaited(_exitPlayer());
        break;
    }
  }

  void _hideControls() {
    _hideTimer?.cancel();
    ref.read(playbackControllerProvider.notifier).setControlsVisible(false);
    // Never leave the D-pad on a hidden chrome button.
    if (_isTv) _requestPlayerFocus();
  }

  void _toggleControls() {
    _requestPlayerFocus();
    if (ref.read(playbackControllerProvider).controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  Future<void> _stopPlayback() async {
    if (_stoppedPlayback) return;
    _stoppedPlayback = true;
    try {
      await _playbackNotifier.stop().timeout(_exitCleanupTimeout);
    } catch (_) {
      // Native players can reject teardown while the window is already closing.
    }
  }

  Future<void> _exitPlayer({
    bool playNext = false,
    String? selectEpisodeHref,
  }) async {
    if (_exitingPlayer) return;
    final bool advancing = playNext || selectEpisodeHref != null;
    final bool wasFullscreen = _isFullscreen;
    final bool shouldStartNextFullscreen =
        advancing && (wasFullscreen || _shouldStartFullscreen);
    final bool preserveFullscreenForNext =
        _isMobile && shouldStartNextFullscreen;
    _preserveFullscreenForNextRoute = preserveFullscreenForNext;
    setState(() {
      _exitingPlayer = true;
    });
    _hideTimer?.cancel();
    _autoNextTimer?.cancel();

    // When leaving the player while in PiP, restore the window / bring the app
    // to the foreground first so the window is not stranded in its shrunken
    // always-on-top state and navigation opens normally.
    if (_inPipMode) {
      await Future.any(<Future<void>>[
        ref.read(pipControllerProvider).bringToForeground(),
        Future<void>.delayed(const Duration(milliseconds: 700)),
      ]);
      if (advancing) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    if (preserveFullscreenForNext) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    } else {
      unawaited(
        Future.any(<Future<void>>[
          _setFullscreen(false),
          Future<void>.delayed(_exitCleanupTimeout),
        ]),
      );
    }
    final PlaybackState playbackState = ref.read(playbackControllerProvider);
    final Object? result = selectEpisodeHref != null
        ? PlayerEpisodeSelectionResult(
            episodeHref: selectEpisodeHref,
            startInFullscreen: shouldStartNextFullscreen,
          )
        : playNext
        ? PlayerNextEpisodeResult(
            startInFullscreen: shouldStartNextFullscreen,
            serverId: playbackState.server?.id,
            serverTitle: playbackState.server?.name,
            voiceoverId: playbackState.voiceover?.id,
            voiceoverLabel: playbackState.voiceover?.label,
          )
        : null;
    unawaited(_stopPlayback());

    setState(() {
      _allowRoutePop = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(result);
    } else {
      await Navigator.of(context).maybePop(result);
    }
  }

  Future<void> _syncFullscreenState() async {
    try {
      final bool? fullscreen = await _windowChannel.invokeMethod<bool>(
        'isFullscreen',
      );
      if (mounted && fullscreen != null) {
        setState(() => _isFullscreen = fullscreen);
        final PlayerEngine? engine = ref
            .read(playbackControllerProvider)
            .engine;
        if (engine != null &&
            _isYoutubeTrailerPlayback(
              ref.read(playbackControllerProvider),
              widget.item,
            )) {
          unawaited(engine.setHostFullscreen(fullscreen));
        }
      }
    } on MissingPluginException {
      // Non-desktop platforms do not need a native window toggle.
    } on PlatformException {
      // Keep the Flutter-side toggle usable if the native window rejects this.
    }
  }

  void _toggleFullscreen() {
    if (_isMobile) return;
    unawaited(_setFullscreen(!_isFullscreen));
  }

  // Escape priority: leave the Windows mini-player first, then drop out of
  // fullscreen, and only exit the player entirely when neither applies.
  void _handleEscape() {
    if (_inPipMode) {
      unawaited(_exitWindowPip());
      return;
    }
    // While the stream is still loading there is nothing to drop fullscreen out
    // to — back must exit the player directly instead of being swallowed.
    final bool engineReady =
        ref.read(playbackControllerProvider).engine?.value.isInitialized ??
        false;
    if (_isFullscreen && engineReady) {
      unawaited(_setFullscreen(false));
      return;
    }
    unawaited(_exitPlayer());
  }

  void _cancelSpaceHold({required bool restoreSpeed}) {
    _spaceHoldTimer?.cancel();
    _spaceHoldTimer = null;
    _spacePressed = false;
    final bool wasTemporarySpeed = _spaceTemporarySpeedActive;
    _spaceTemporarySpeedActive = false;
    if (restoreSpeed && wasTemporarySpeed) {
      unawaited(_playbackNotifier.endTemporarySpeed());
    }
  }

  KeyEventResult _handleSpaceKeyEvent(
    KeyEvent event,
    PlaybackController notifier,
  ) {
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      if (_spacePressed) return KeyEventResult.handled;
      _spacePressed = true;
      _spaceTemporarySpeedActive = false;
      _spaceHoldTimer?.cancel();
      _spaceHoldTimer = Timer(_spaceHoldSpeedDelay, () {
        if (!mounted || !_spacePressed) return;
        _spaceTemporarySpeedActive = true;
        unawaited(notifier.beginTemporarySpeed());
      });
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      final bool wasTemporarySpeed = _spaceTemporarySpeedActive;
      _cancelSpaceHold(restoreSpeed: wasTemporarySpeed);
      if (!wasTemporarySpeed) {
        unawaited(notifier.togglePlay());
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (mounted && _isFullscreen != fullscreen) {
      setState(() => _isFullscreen = fullscreen);
    }
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (fullscreen) {
      _scheduleFullscreenSystemUiReassert();
    }
    try {
      final bool? actualFullscreen = await _windowChannel.invokeMethod<bool>(
        'setFullscreen',
        fullscreen,
      );
      if (mounted && actualFullscreen != null) {
        setState(() => _isFullscreen = actualFullscreen);
      }
    } on MissingPluginException {
      // Mobile/web can still use SystemChrome above.
    } on PlatformException {
      // Leave the player usable even if native fullscreen fails.
    }
    if (mounted &&
        _isYoutubeTrailerPlayback(
          ref.read(playbackControllerProvider),
          widget.item,
        )) {
      final PlayerEngine? engine = ref.read(playbackControllerProvider).engine;
      if (engine != null) {
        unawaited(engine.setHostFullscreen(_isFullscreen));
      }
      _showTrailerControls();
    }
  }

  void _scheduleFullscreenSystemUiReassert() {
    for (final Duration delay in <Duration>[
      const Duration(milliseconds: 250),
      const Duration(milliseconds: 900),
    ]) {
      unawaited(
        Future<void>.delayed(delay, () async {
          if (!mounted || !_isFullscreen) return;
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
        }),
      );
    }
  }

  KeyEventResult _handlePlayerKeyEvent(
    KeyEvent event,
    PlaybackState state,
    PlayerSettings settings,
  ) {
    if (event is! KeyDownEvent &&
        event is! KeyRepeatEvent &&
        event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final LogicalKeyboardKey key = event.logicalKey;
    final PlaybackController notifier = ref.read(
      playbackControllerProvider.notifier,
    );

    if (_isTv) {
      // D-pad centre / OK toggles play & pause from the video surface. If a
      // chrome control owns focus, leave activation to that control.
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA) {
        if (state.controlsVisible &&
            !state.locked &&
            FocusManager.instance.primaryFocus != _playerFocusNode) {
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        unawaited(notifier.togglePlay());
        return KeyEventResult.handled;
      }
      final bool controlsVisible = state.controlsVisible && !state.locked;
      final bool isPlaying = state.engine?.state.value.isPlaying ?? false;
      final bool pausedChromeNavigation = controlsVisible && !isPlaying;
      // On Android TV, Up/Down are navigation, not volume. When the chrome is
      // visible, use them to move through controls; Left/Right keep seeking
      // during playback and only move focus while paused.
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        if (controlsVisible) {
          return _moveTvPlayerFocus(key, event);
        }
        if (!state.locked) {
          if (event is KeyDownEvent) _showControls();
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
      }
      if (pausedChromeNavigation &&
          (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight)) {
        return _moveTvPlayerFocus(key, event);
      }
    }

    if (key == LogicalKeyboardKey.space) {
      return _handleSpaceKeyEvent(event, notifier);
    }
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      unawaited(notifier.togglePlay());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(notifier.seekBy(-settings.seekInterval));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(notifier.seekBy(settings.seekInterval));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final double current = state.engine?.value.volume ?? 1.0;
      unawaited(notifier.setVolume((current + 0.1).clamp(0.0, 1.0)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final double current = state.engine?.value.volume ?? 1.0;
      unawaited(notifier.setVolume((current - 0.1).clamp(0.0, 1.0)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      final double current = state.engine?.value.volume ?? 1.0;
      unawaited(notifier.setVolume(current > 0 ? 0 : 1.0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(
        ref
            .read(playerSettingsProvider.notifier)
            .setSubtitlesEnabled(!settings.subtitlesEnabled),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE) {
      _showEpisodes(
        context,
        state.item,
        onSelect: (String href) =>
            unawaited(_exitPlayer(selectEpisodeHref: href)),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyQ) {
      _showQualityMenu(context, ref);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _handleEscape();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _moveTvPlayerFocus(LogicalKeyboardKey key, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.handled;
    // Keep the chrome up while navigating; _scheduleHide is a no-op while
    // paused and re-arms the auto-hide while playing.
    _scheduleHide();
    final FocusNode? primary = FocusManager.instance.primaryFocus;
    // From the bare video surface the first press seeds the chrome at the
    // centre play/pause button; after that the D-pad moves geometrically
    // (up/down between rows, left/right along a row).
    if (primary == null ||
        primary == _playerFocusNode ||
        primary is FocusScopeNode) {
      if (_tvChromeSeedFocus.context != null &&
          _tvChromeSeedFocus.canRequestFocus) {
        _tvChromeSeedFocus.requestFocus();
      } else {
        _playerFocusNode.nextFocus();
      }
      return KeyEventResult.handled;
    }
    final TraversalDirection direction = switch (key) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      _ => TraversalDirection.right,
    };
    primary.focusInDirection(direction);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackState state = ref.watch(playbackControllerProvider);
    _syncTvPlaybackObserver(state.engine);
    final PlayerSettings settings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    final SkipMarkers markers = _effectiveSkipMarkers(
      ref.watch(skipMarkersProvider).value,
      state.item?.skipMarkers ?? widget.item.skipMarkers,
    );
    final bool isYoutubeTrailer = _isYoutubeTrailerPlayback(state, widget.item);
    if (isYoutubeTrailer) {
      _attachTrailerCommands(state.engine);
      _autoNextTimer?.cancel();
      _autoNextTimer = null;
    } else {
      _attachTrailerCommands(null);
      _maybeScheduleAutoNext(state, settings);
    }

    // Opening a stream forces the controls visible (see _open). The one-shot
    // hide timer armed in initState races the source resolution and is already
    // spent by the time a (slow) stream finishes opening — which on an
    // auto-advance leaves the chrome + cursor stranded because there is no user
    // interaction to re-arm it. Re-arm the hide whenever a stream finishes
    // opening (loading: true -> false).
    ref.listen<bool>(
      playbackControllerProvider.select((PlaybackState s) => s.loading),
      (bool? previous, bool next) {
        if (previous == true && !next && mounted) {
          _scheduleHide(
            isYoutubeTrailer ? _trailerControlsHideDelay : _controlsHideDelay,
          );
        }
      },
    );

    // Keep PiP overlay actions in sync with playback state changes.
    if (_inPipMode) {
      final bool nowPlaying = state.engine?.value.isPlaying ?? false;
      if (_lastPipIsPlaying != nowPlaying) {
        _lastPipIsPlaying = nowPlaying;
        unawaited(
          ref
              .read(pipControllerProvider)
              .updateParams(isPlaying: nowPlaying, hasNext: true),
        );
      }
    } else {
      _lastPipIsPlaying = null;
    }

    final bool tvPausedChromeNavigation =
        _isTv &&
        state.controlsVisible &&
        !state.locked &&
        !(state.engine?.state.value.isPlaying ?? false);
    final playerShortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
      if (!tvPausedChromeNavigation) ...const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekIntent(
          backward: true,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): _SeekIntent(
          backward: false,
        ),
      },
      if (!_isTv) ...const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp): _VolumeIntent(up: true),
        SingleActivator(LogicalKeyboardKey.arrowDown): _VolumeIntent(up: false),
      },
      const SingleActivator(LogicalKeyboardKey.keyM): _MuteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS): _SubtitlesIntent(),
      const SingleActivator(LogicalKeyboardKey.keyE): _EpisodesIntent(),
      const SingleActivator(LogicalKeyboardKey.keyQ): _QualityIntent(),
      const SingleActivator(LogicalKeyboardKey.keyF): _FullscreenIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
    };

    return Shortcuts(
      shortcuts: isYoutubeTrailer
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyF): _FullscreenIntent(),
              SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
            }
          : playerShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
            onInvoke: (_) {
              ref.read(playbackControllerProvider.notifier).togglePlay();
              return null;
            },
          ),
          _SeekIntent: CallbackAction<_SeekIntent>(
            onInvoke: (_SeekIntent intent) {
              ref
                  .read(playbackControllerProvider.notifier)
                  .seekBy(
                    intent.backward
                        ? -settings.seekInterval
                        : settings.seekInterval,
                  );
              return null;
            },
          ),
          _VolumeIntent: CallbackAction<_VolumeIntent>(
            onInvoke: (_VolumeIntent intent) {
              final double current = state.engine?.value.volume ?? 1.0;
              final double next = (current + (intent.up ? 0.1 : -0.1)).clamp(
                0.0,
                1.0,
              );
              ref.read(playbackControllerProvider.notifier).setVolume(next);
              return null;
            },
          ),
          _MuteIntent: CallbackAction<_MuteIntent>(
            onInvoke: (_) {
              final double current = state.engine?.value.volume ?? 1.0;
              ref
                  .read(playbackControllerProvider.notifier)
                  .setVolume(current > 0 ? 0 : 1.0);
              return null;
            },
          ),
          _SubtitlesIntent: CallbackAction<_SubtitlesIntent>(
            onInvoke: (_) {
              ref
                  .read(playerSettingsProvider.notifier)
                  .setSubtitlesEnabled(!settings.subtitlesEnabled);
              return null;
            },
          ),
          _EpisodesIntent: CallbackAction<_EpisodesIntent>(
            onInvoke: (_) {
              _showEpisodes(
                context,
                state.item,
                onSelect: (String href) =>
                    unawaited(_exitPlayer(selectEpisodeHref: href)),
              );
              return null;
            },
          ),
          _QualityIntent: CallbackAction<_QualityIntent>(
            onInvoke: (_) {
              _showQualityMenu(context, ref);
              return null;
            },
          ),
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) {
              if (isYoutubeTrailer) {
                _handleTrailerEscapeShortcut();
              } else {
                _handleEscape();
              }
              return null;
            },
          ),
          _FullscreenIntent: CallbackAction<_FullscreenIntent>(
            onInvoke: (_) {
              if (isYoutubeTrailer) {
                _handleTrailerFullscreenShortcut();
              } else {
                _toggleFullscreen();
              }
              return null;
            },
          ),
          _NoopIntent: CallbackAction<_NoopIntent>(onInvoke: (_) => null),
        },
        child: PopScope<void>(
          canPop: _allowRoutePop,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) {
              unawaited(_stopPlayback());
              return;
            }
            // Standard TV pattern: BACK first dismisses the on-screen chrome,
            // a second BACK exits. While loading or on error the chrome is
            // force-visible, so BACK must still exit directly — and trailers
            // keep their single-BACK exit.
            final PlaybackState popState = ref.read(playbackControllerProvider);
            if (_isTv &&
                !_exitingPlayer &&
                !_isYoutubeTrailerPlayback(popState, widget.item) &&
                popState.controlsVisible &&
                !popState.loading &&
                popState.error == null) {
              _hideControls();
              return;
            }
            unawaited(_exitPlayer());
          },
          child: Focus(
            focusNode: _playerFocusNode,
            onFocusChange: (bool hasFocus) {
              if (!hasFocus) _cancelSpaceHold(restoreSpeed: true);
            },
            autofocus: !isYoutubeTrailer,
            canRequestFocus: !isYoutubeTrailer,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              if (_nativePipActive) return KeyEventResult.handled;
              if (isYoutubeTrailer) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.keyF) {
                  _handleTrailerFullscreenShortcut();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  _handleTrailerEscapeShortcut();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
              return _handlePlayerKeyEvent(event, state, settings);
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: ExcludeSemantics(
                child: Stack(
                  children: <Widget>[
                    if (isYoutubeTrailer)
                      _YoutubeTrailerSurface(
                        controller: _exitingPlayer ? null : state.engine,
                        loading: state.loading,
                        isFullscreen: _isFullscreen,
                        controlsVisible: state.controlsVisible,
                        showFlutterControls:
                            !(state.engine?.rendersOwnTrailerControls ?? false),
                        showFullscreenButton: !_isMobile,
                        onActivity: _showTrailerControls,
                        onExit: () {
                          _showTrailerControls();
                          unawaited(_exitPlayer());
                        },
                        onToggleFullscreen: () {
                          _showTrailerControls();
                          _toggleFullscreen();
                        },
                        fullscreenButtonRight: 29,
                        fullscreenButtonBottom: 85,
                      )
                    else
                      // Player + gesture layer — always present for native streams.
                      MouseRegion(
                        cursor: state.controlsVisible && !state.locked
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.none,
                        onHover: (_) => _showControls(),
                        onExit: (_) => _hideControls(),
                        child: GestureOverlay(
                          onTap: _toggleControls,
                          seekInterval: settings.seekInterval,
                          isMobile: _isMobile,
                          isZoomed: settings.verticalStretch,
                          enableGestures: !_inPipMode,
                          onToggleFullscreen: _toggleFullscreen,
                          onTogglePlay: () => ref
                              .read(playbackControllerProvider.notifier)
                              .togglePlay(),
                          onZoomChanged: (bool zoomed) {
                            unawaited(
                              ref
                                  .read(playerSettingsProvider.notifier)
                                  .setVerticalStretch(zoomed),
                            );
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              _VideoSurface(
                                controller: _exitingPlayer
                                    ? null
                                    : state.engine,
                                stretchVertical: settings.verticalStretch,
                              ),
                              // Auto-skip always runs (logic widget, no UI).
                              _AutoSkipWorker(
                                state: state,
                                settings: settings,
                                markers: markers,
                              ),
                              // Everything below is hidden in PiP – the window is too
                              // small to interact with and controls are via PiP actions.
                              if (!_inPipMode) ...<Widget>[
                                _SubtitleOverlay(
                                  state: state,
                                  settings: settings,
                                ),
                                if (state.loading &&
                                    !state.controlsVisible &&
                                    state.error == null)
                                  const Center(
                                    child: _PlayerLoadingIndicator(),
                                  ),
                                if (state.error == null)
                                  AnimatedOpacity(
                                    // Keep the chrome (incl. the back button)
                                    // visible & tappable while a stream is still
                                    // loading, so a stuck "00:00" load can always
                                    // be backed out of.
                                    opacity:
                                        (state.controlsVisible ||
                                                state.seekPreviewPosition !=
                                                    null ||
                                                state.loading) &&
                                            !state.locked
                                        ? 1
                                        : 0,
                                    duration: const Duration(milliseconds: 180),
                                    child: IgnorePointer(
                                      ignoring:
                                          (!state.controlsVisible &&
                                              !state.loading) ||
                                          state.locked,
                                      child: _PlayerChrome(
                                        isFullscreen: _isFullscreen,
                                        isMobile: _isMobile,
                                        tvSeedFocusNode: _isTv
                                            ? _tvChromeSeedFocus
                                            : null,
                                        onExit: () => unawaited(_exitPlayer()),
                                        onToggleFullscreen: _toggleFullscreen,
                                        onSelectEpisode: (String href) =>
                                            unawaited(
                                              _exitPlayer(
                                                selectEpisodeHref: href,
                                              ),
                                            ),
                                        onEnterNativePip: _nativePipSupported
                                            ? () => unawaited(
                                                _handOffToNativePip(),
                                              )
                                            : _windowPipSupported
                                            ? () => unawaited(_enterWindowPip())
                                            : null,
                                      ),
                                    ),
                                  ),
                                if (state.temporarySpeedActive)
                                  _TemporarySpeedBadge(
                                    speed: settings.playbackSpeed + 1,
                                    controlsVisible:
                                        state.controlsVisible && !state.locked,
                                  ),
                                if (state.error == null)
                                  _SkipButtons(item: state.item ?? widget.item),
                                if (state.lastSkippedFrom != null)
                                  Positioned(
                                    right: 24,
                                    bottom: 116,
                                    child: FilledButton.icon(
                                      style: _overlayActionButtonStyle(),
                                      onPressed: ref
                                          .read(
                                            playbackControllerProvider.notifier,
                                          )
                                          .undoSkip,
                                      icon: const Icon(Icons.undo_rounded),
                                      label: Text(context.t('Undo skip')),
                                    ),
                                  ),
                                if (state.autoNextVisible &&
                                    settings.showNextEpisodeButton &&
                                    !settings.autoplayNext)
                                  AutoNextOverlay(
                                    autoProceed: settings.autoplayNext,
                                    showButton: true,
                                    showCountdown: true,
                                    onProceed: () {
                                      ref
                                          .read(
                                            playbackControllerProvider.notifier,
                                          )
                                          .dismissAutoNext();
                                      unawaited(_exitPlayer(playNext: true));
                                    },
                                    onCancel: () => ref
                                        .read(
                                          playbackControllerProvider.notifier,
                                        )
                                        .dismissAutoNext(),
                                    onExpire: () {
                                      ref
                                          .read(
                                            playbackControllerProvider.notifier,
                                          )
                                          .dismissAutoNext();
                                      unawaited(_exitPlayer());
                                    },
                                  ),
                                if (state.error != null)
                                  _PlayerErrorOverlay(
                                    error: state.error!,
                                    onExit: () => unawaited(_exitPlayer()),
                                  ),
                              ],
                              // Mini-player controls (Windows PiP): a small
                              // always-visible strip so the user can play/pause
                              // and restore the window from the shrunken state.
                              if (_inPipMode && _windowPipSupported)
                                _WindowPipOverlay(
                                  isPlaying:
                                      state.engine?.value.isPlaying ?? false,
                                  controlsVisible: state.controlsVisible,
                                  aspectRatio:
                                      state.engine?.value.aspectRatio ?? 16 / 9,
                                  onTogglePlay: () => ref
                                      .read(playbackControllerProvider.notifier)
                                      .togglePlay(),
                                  onExpand: () => unawaited(_exitWindowPip()),
                                  onMoveStart: () => unawaited(
                                    ref
                                        .read(pipControllerProvider)
                                        .startWindowMove(),
                                  ),
                                  windowPhysicalRect: () => ref
                                      .read(pipControllerProvider)
                                      .windowPhysicalRect(),
                                  setWindowPhysicalRect:
                                      (
                                        double x,
                                        double y,
                                        double w,
                                        double h,
                                      ) => ref
                                          .read(pipControllerProvider)
                                          .setWindowPhysicalRect(x, y, w, h),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (isYoutubeTrailer && state.error != null)
                      _PlayerErrorOverlay(
                        error: state.error!,
                        onExit: () => unawaited(_exitPlayer()),
                      ),
                    // Native PiP overlay sits OUTSIDE GestureOverlay so AbsorbPointer
                    // actually blocks mouse events before they reach it.
                    if (_nativePipActive)
                      Positioned.fill(
                        child: _NativePipOverlay(onCancel: () {}),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isYoutubeTrailerPlayback(PlaybackState state, MediaPlaybackItem item) {
  if (state.server?.id == 'youtube-trailer') return true;
  return item.servers.any(
    (MediaServer server) => server.id == 'youtube-trailer',
  );
}

class _YoutubeTrailerSurface extends StatelessWidget {
  const _YoutubeTrailerSurface({
    required this.controller,
    required this.loading,
    required this.isFullscreen,
    required this.controlsVisible,
    required this.showFlutterControls,
    required this.showFullscreenButton,
    required this.onActivity,
    required this.onExit,
    required this.onToggleFullscreen,
    this.fullscreenButtonRight = 29,
    this.fullscreenButtonBottom = 85,
  });

  final PlayerEngine? controller;
  final bool loading;
  final bool isFullscreen;
  final bool controlsVisible;
  final bool showFlutterControls;
  final bool showFullscreenButton;
  final VoidCallback onActivity;
  final VoidCallback onExit;
  final VoidCallback onToggleFullscreen;
  final double fullscreenButtonRight;
  final double fullscreenButtonBottom;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.paddingOf(context);

    return MouseRegion(
      cursor: controlsVisible
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      onEnter: (_) => onActivity(),
      onHover: (_) => onActivity(),
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: (_) => onActivity(),
        onPointerSignal: (_) => onActivity(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _VideoSurface(
              controller: controller,
              stretchVertical: false,
              fillSurface: true,
            ),

            if (loading && controller == null)
              const Center(child: _PlayerLoadingIndicator()),

            if (showFlutterControls)
              AnimatedOpacity(
                opacity: controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Positioned(
                        top: padding.top + 16,
                        left: padding.left + 30,
                        child: _TrailerCircleButton(
                          tooltip: 'Back',
                          icon: Icons.arrow_back_rounded,
                          onPressed: onExit,
                        ),
                      ),
                      if (showFullscreenButton)
                        Positioned(
                          right: padding.right + fullscreenButtonRight,
                          bottom: padding.bottom + fullscreenButtonBottom,
                          child: _TrailerCircleButton(
                            tooltip: isFullscreen
                                ? 'Exit fullscreen'
                                : 'Fullscreen',
                            icon: isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            onPressed: onToggleFullscreen,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrailerCircleButton extends StatelessWidget {
  const _TrailerCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.controller,
    required this.stretchVertical,
    this.fillSurface = false,
  });

  final PlayerEngine? controller;
  final bool stretchVertical;
  final bool fillSurface;

  @override
  Widget build(BuildContext context) {
    final PlayerEngine? active = controller;
    if (active == null) {
      return const ColoredBox(color: Colors.black);
    }

    return ValueListenableBuilder<PlayerEngineState>(
      valueListenable: active.state,
      child: active.buildVideoSurface(context),
      builder:
          (
            BuildContext context,
            PlayerEngineState engineState,
            Widget? videoSurface,
          ) {
            if (!engineState.isInitialized) {
              return const ColoredBox(color: Colors.black);
            }
            if (fillSurface) {
              return videoSurface ?? const ColoredBox(color: Colors.black);
            }

            final Size videoSize = engineState.videoSize;
            final double fallbackAspectRatio = engineState.aspectRatio == 0
                ? 16 / 9
                : engineState.aspectRatio;
            final double videoWidth = videoSize.width > 0
                ? videoSize.width
                : 1920;
            final double videoHeight = videoSize.height > 0
                ? videoSize.height
                : videoWidth / fallbackAspectRatio;

            if (!stretchVertical) {
              return Center(
                child: AspectRatio(
                  aspectRatio: fallbackAspectRatio,
                  child: videoSurface,
                ),
              );
            }

            return ClipRect(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: videoWidth,
                    height: videoHeight,
                    child: videoSurface,
                  ),
                ),
              ),
            );
          },
    );
  }
}

SkipMarkers _effectiveSkipMarkers(SkipMarkers? resolved, SkipMarkers fallback) {
  if (!fallback.isEmpty) {
    return fallback;
  }
  if (resolved == null || resolved.isEmpty) {
    return fallback;
  }
  return fallback.withFallback(resolved);
}

bool _isPositionBuffered(PlayerEngine controller, Duration position) {
  final Duration duration = controller.value.duration;
  final int totalMs = duration.inMilliseconds;
  if (totalMs <= 0) return false;

  final int positionMs = position.inMilliseconds.clamp(0, totalMs).toInt();
  final int toleranceMs = const Duration(milliseconds: 850).inMilliseconds;
  for (final PlayerBufferedRange range in controller.value.buffered) {
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

class _AutoSkipWorker extends ConsumerStatefulWidget {
  const _AutoSkipWorker({
    required this.state,
    required this.settings,
    required this.markers,
  });

  final PlaybackState state;
  final PlayerSettings settings;
  final SkipMarkers markers;

  @override
  ConsumerState<_AutoSkipWorker> createState() => _AutoSkipWorkerState();
}

class _AutoSkipWorkerState extends ConsumerState<_AutoSkipWorker> {
  PlayerEngine? _attached;
  final Set<String> _skippedRanges = <String>{};
  String _itemKey = '';
  bool _skipInFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    _syncItemKey();
    _attachController(widget.state.engine);
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void didUpdateWidget(covariant _AutoSkipWorker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncItemKey();
    _attachController(widget.state.engine);
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void dispose() {
    _attached?.removeListener(_evaluate);
    super.dispose();
  }

  void _syncItemKey() {
    final MediaPlaybackItem? item = widget.state.item;
    final String next =
        '${item?.id ?? ''}|${item?.seasonNumber ?? 0}|'
        '${item?.episodeNumber ?? 0}|${item?.currentEpisodeId ?? ''}';
    if (next != _itemKey) {
      _itemKey = next;
      _skippedRanges.clear();
      _skipInFlight = false;
    }
  }

  void _attachController(PlayerEngine? next) {
    if (_attached == next) return;
    _attached?.removeListener(_evaluate);
    next?.addListener(_evaluate);
    _attached = next;
  }

  void _evaluate() {
    if (!mounted || _skipInFlight) return;
    final PlayerEngine? controller = widget.state.engine;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isPlaying) return;

    final Duration position = controller.value.position;
    if (position <= Duration.zero) return;
    final Duration duration = controller.value.duration;
    if (duration <= Duration.zero) return;

    final SkipMarkers markers = widget.markers;
    final PlayerSettings settings = widget.settings;
    if (_maybeSkip(
      kind: 'op',
      enabled: settings.autoSkipOpening,
      start: markers.openingStart,
      end: markers.openingEnd,
      position: position,
      duration: duration,
    )) {
      return;
    }
    _maybeSkip(
      kind: 'ed',
      enabled: settings.autoSkipEnding,
      start: markers.endingStart,
      end: markers.endingEnd,
      position: position,
      duration: duration,
    );
  }

  bool _maybeSkip({
    required String kind,
    required bool enabled,
    required Duration? start,
    required Duration? end,
    required Duration position,
    required Duration duration,
  }) {
    final Duration? target = autoSkipTarget(
      enabled: enabled,
      start: start,
      end: end,
      position: position,
      duration: duration,
    );
    if (target == null) return false;
    final Duration rangeStart = start!;
    final Duration rangeEnd = end!;

    final String key =
        '$_itemKey|$kind|${rangeStart.inMilliseconds}|${rangeEnd.inMilliseconds}';
    if (_skippedRanges.contains(key)) return false;
    _skippedRanges.add(key);
    _skipInFlight = true;
    // ignore: avoid_print
    print(
      '[DEBUG] auto-skip ($kind): position=$position -> target=$target range=$rangeStart-$rangeEnd',
    );
    unawaited(_skipTo(target));
    return true;
  }

  Future<void> _skipTo(Duration target) async {
    try {
      await ref.read(playbackControllerProvider.notifier).skipTo(target);
    } finally {
      if (mounted) {
        _skipInFlight = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PlayerLoadingIndicator extends StatelessWidget {
  const _PlayerLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
    );
  }
}

class _TemporarySpeedBadge extends StatelessWidget {
  const _TemporarySpeedBadge({
    required this.speed,
    required this.controlsVisible,
  });

  final double speed;
  final bool controlsVisible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + (controlsVisible ? 64 : 22),
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                _temporarySpeedLabel(speed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _temporarySpeedLabel(double speed) {
  final String value = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return 'x$value';
}

class _PlayerChrome extends ConsumerWidget {
  const _PlayerChrome({
    required this.isFullscreen,
    required this.isMobile,
    required this.onExit,
    required this.onToggleFullscreen,
    this.onSelectEpisode,
    this.onEnterNativePip,
    this.tvSeedFocusNode,
  });

  final bool isFullscreen;
  final bool isMobile;
  final VoidCallback onExit;
  final VoidCallback onToggleFullscreen;

  /// Plays the episode the user picks from the in-player Episodes sheet.
  final void Function(String href)? onSelectEpisode;
  final VoidCallback? onEnterNativePip;

  /// On Android TV: attached to the centre play/pause button so the page can
  /// land D-pad focus there when the chrome appears.
  final FocusNode? tvSeedFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackState state = ref.watch(playbackControllerProvider);
    final PlayerSettings settings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    final bool pipSupported = ref.watch(pipControllerProvider).isSupported;
    final bool castSupported = ref.watch(castControllerProvider).isSupported;
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? controller = state.engine;
    final SkipMarkers markers = _effectiveSkipMarkers(
      ref.watch(skipMarkersProvider).value,
      item?.skipMarkers ?? const SkipMarkers(),
    );
    final bool seekPreviewBuffered =
        controller != null &&
        state.seekPreviewPosition != null &&
        (state.seekPreviewBufferedEnd != null ||
            _isPositionBuffered(controller, state.seekPreviewPosition!));
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final double topScrimHeight = padding.top + 96;
    final double bottomScrimHeight = padding.bottom + 132;
    return _TvChromeFocusTheme(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topScrimHeight,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomScrimHeight,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: onExit,
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item?.title ?? 'MiruShin Player',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (item != null)
                              Text(
                                _episodeLabel(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .72),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 480) ...<Widget>[
                        _TopChip(label: state.server?.name ?? 'Server'),
                        const SizedBox(width: 8),
                        _TopChip(label: state.quality?.label ?? 'Auto'),
                      ],
                      if (onEnterNativePip != null)
                        IconButton(
                          tooltip: 'Picture in Picture',
                          onPressed: onEnterNativePip,
                          icon: const Icon(
                            Icons.picture_in_picture_alt_rounded,
                            color: Colors.white,
                          ),
                        )
                      else if (pipSupported)
                        IconButton(
                          onPressed: () {
                            final double rawAr =
                                controller?.value.aspectRatio ?? 0;
                            final double ar = rawAr > 0 ? rawAr : 16 / 9;
                            final bool playing =
                                controller?.value.isPlaying ?? true;
                            unawaited(
                              ref
                                  .read(pipControllerProvider)
                                  .enter(
                                    aspectRatio: ar,
                                    isPlaying: playing,
                                    hasNext: true,
                                  ),
                            );
                          },
                          icon: const Icon(
                            Icons.picture_in_picture_alt_rounded,
                            color: Colors.white,
                          ),
                        ),
                      if (castSupported)
                        IconButton(
                          onPressed: () =>
                              ref.read(castControllerProvider).startSession(),
                          icon: const Icon(
                            Icons.cast_rounded,
                            color: Colors.white,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => _showSettings(context, ref),
                        icon: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Listen to the engine state directly so the buffering spinner
                // clears the moment playback resumes. Reading controller.value
                // only on Riverpod rebuilds left a stale spinner spinning over a
                // stream that was already playing until the user toggled
                // play/pause or fullscreen.
                if (controller == null)
                  const _PlayerLoadingIndicator()
                else
                  ValueListenableBuilder<PlayerEngineState>(
                    valueListenable: controller.state,
                    builder:
                        (
                          BuildContext context,
                          PlayerEngineState engineState,
                          Widget? _,
                        ) {
                          final bool showLoading =
                              state.loading ||
                              !engineState.isInitialized ||
                              (engineState.isBuffering && !seekPreviewBuffered);
                          if (showLoading) {
                            return const _PlayerLoadingIndicator();
                          }
                          if (isMobile) {
                            return _CenterPlayPauseButton(
                              controller: controller,
                              focusNode: tvSeedFocusNode,
                            );
                          }
                          return const SizedBox.shrink();
                        },
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    children: <Widget>[
                      if (controller != null)
                        _PositionBar(
                          controller: controller,
                          skipMarkers: markers,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          _BottomLeftControls(
                            controller: controller,
                            isMobile: isMobile,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: LayoutBuilder(
                              builder:
                                  (
                                    BuildContext context,
                                    BoxConstraints constraints,
                                  ) {
                                    final double width = constraints.maxWidth;
                                    final bool compactStreams = width < 650;
                                    final bool compactEpisodes = width < 585;
                                    final bool compactSubs = width < 505;
                                    final bool compactZoom = width < 460;
                                    final bool compactSpeed = width < 390;
                                    final bool compactQuality = width < 340;
                                    final String speedLabel =
                                        '${settings.playbackSpeed.toStringAsFixed(settings.playbackSpeed == settings.playbackSpeed.roundToDouble() ? 0 : 2)}x';

                                    return Align(
                                      alignment: Alignment.centerRight,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        reverse: true,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            _ChromeButton(
                                              icon: Icons.dns_rounded,
                                              label: 'Streams',
                                              showLabel: !compactStreams,
                                              onTap: () => _showStreamsMenu(
                                                context,
                                                ref,
                                              ),
                                            ),
                                            if (item != null &&
                                                item.seasons.isNotEmpty)
                                              _ChromeButton(
                                                icon:
                                                    Icons.video_library_rounded,
                                                label: 'Episodes',
                                                showLabel: !compactEpisodes,
                                                onTap: () => _showEpisodes(
                                                  context,
                                                  item,
                                                  onSelect: onSelectEpisode,
                                                ),
                                              ),
                                            _ChromeButton(
                                              icon: Icons.subtitles_rounded,
                                              label: 'Subs',
                                              showLabel: !compactSubs,
                                              onTap: () => _showSubtitleMenu(
                                                context,
                                                ref,
                                              ),
                                            ),
                                            _ChromeButton(
                                              icon: settings.verticalStretch
                                                  ? Icons
                                                        .fullscreen_exit_rounded
                                                  : Icons.zoom_out_map_rounded,
                                              label: settings.verticalStretch
                                                  ? 'Normal'
                                                  : 'Zoom',
                                              showLabel: !compactZoom,
                                              onTap: () => ref
                                                  .read(
                                                    playerSettingsProvider
                                                        .notifier,
                                                  )
                                                  .setVerticalStretch(
                                                    !settings.verticalStretch,
                                                  ),
                                            ),
                                            _ChromeButton(
                                              icon: Icons.speed_rounded,
                                              label: speedLabel,
                                              showLabel: !compactSpeed,
                                              onTap: () =>
                                                  _showSpeedMenu(context, ref),
                                            ),
                                            _ChromeButton(
                                              icon: Icons.high_quality_rounded,
                                              label: 'Quality',
                                              showLabel: !compactQuality,
                                              onTap: () => _showQualityMenu(
                                                context,
                                                ref,
                                              ),
                                            ),
                                            if (!isMobile)
                                              _ChromeIconButton(
                                                icon: isFullscreen
                                                    ? Icons
                                                          .fullscreen_exit_rounded
                                                    : Icons.fullscreen_rounded,
                                                tooltip: isFullscreen
                                                    ? 'Exit fullscreen'
                                                    : 'Fullscreen',
                                                onTap: onToggleFullscreen,
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// On Android TV, gives every chrome button a clearly visible focus state
/// (accent ring + fill) so the D-pad position is readable from the couch.
/// Everywhere else it is a no-op.
class _TvChromeFocusTheme extends StatelessWidget {
  const _TvChromeFocusTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TvPlatform.isAndroidTv) return child;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ButtonStyle style = ButtonStyle(
      overlayColor: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => states.contains(WidgetState.focused)
            ? scheme.primary.withValues(alpha: 0.45)
            : null,
      ),
      side: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => states.contains(WidgetState.focused)
            ? BorderSide(color: scheme.primary, width: 2.5)
            : null,
      ),
    );
    return IconButtonTheme(
      data: IconButtonThemeData(style: style),
      child: TextButtonTheme(
        data: TextButtonThemeData(style: style),
        child: FilledButtonTheme(
          data: FilledButtonThemeData(style: style),
          child: child,
        ),
      ),
    );
  }
}

String _episodeLabel(MediaPlaybackItem item) {
  final int ep = item.episodeNumber.round();
  final String title = item.subtitle;
  if (ep <= 0) return title;
  final String prefix = 'Ep. $ep';
  if (title.isEmpty) return prefix;
  return '$prefix · $title';
}

class _PositionLabel extends ConsumerStatefulWidget {
  const _PositionLabel({required this.controller, this.style});

  final PlayerEngine? controller;
  final TextStyle? style;

  @override
  ConsumerState<_PositionLabel> createState() => _PositionLabelState();
}

class _PositionLabelState extends ConsumerState<_PositionLabel> {
  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    widget.controller?.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant _PositionLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_tick);
      widget.controller?.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackState state = ref.watch(playbackControllerProvider);
    final Duration? previewPosition = state.engine == widget.controller
        ? state.seekPreviewPosition
        : null;
    return Text(
      _label(widget.controller, previewPosition),
      style: widget.style ?? const TextStyle(color: Colors.white70),
    );
  }

  String _label(PlayerEngine? controller, Duration? previewPosition) {
    if (controller == null || !controller.value.isInitialized) {
      return '00:00 / 00:00';
    }
    final Duration shownPosition = previewPosition ?? controller.value.position;
    return '${_fmt(shownPosition)} / ${_fmt(controller.value.duration)}';
  }

  String _fmt(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _CenterPlayPauseButton extends ConsumerWidget {
  const _CenterPlayPauseButton({required this.controller, this.focusNode});

  final PlayerEngine? controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool enabled = controller?.value.isInitialized == true;
    final bool playing = controller?.value.isPlaying == true;
    return IconButton(
      tooltip: playing ? 'Pause' : 'Play',
      iconSize: 56,
      padding: EdgeInsets.zero,
      color: Colors.white,
      disabledColor: Colors.white38,
      focusNode: focusNode,
      onPressed: enabled
          ? ref.read(playbackControllerProvider.notifier).togglePlay
          : null,
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );
  }
}

class _BottomLeftControls extends StatelessWidget {
  const _BottomLeftControls({required this.controller, this.isMobile = false});

  final PlayerEngine? controller;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!isMobile) _PlayPauseButton(controller: controller),
        if (!isMobile) const SizedBox(width: 8),
        _InlineVolumeControl(controller: controller),
        const SizedBox(width: 10),
        _PositionLabel(
          controller: controller,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _PlayPauseButton extends ConsumerStatefulWidget {
  const _PlayPauseButton({required this.controller});

  final PlayerEngine? controller;

  @override
  ConsumerState<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends ConsumerState<_PlayPauseButton> {
  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    widget.controller?.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant _PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_tick);
      widget.controller?.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEngine? controller = widget.controller;
    final bool enabled = controller?.value.isInitialized == true;
    final bool playing = controller?.value.isPlaying == true;
    return IconButton(
      tooltip: playing ? 'Pause' : 'Play',
      iconSize: 24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 36),
      color: Colors.white,
      disabledColor: Colors.white38,
      onPressed: enabled
          ? ref.read(playbackControllerProvider.notifier).togglePlay
          : null,
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
    );
  }
}

class _InlineVolumeControl extends ConsumerStatefulWidget {
  const _InlineVolumeControl({required this.controller});

  final PlayerEngine? controller;

  @override
  ConsumerState<_InlineVolumeControl> createState() =>
      _InlineVolumeControlState();
}

class _InlineVolumeControlState extends ConsumerState<_InlineVolumeControl> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final PlayerEngine? controller =
        ref.watch(playbackControllerProvider).engine ?? widget.controller;
    final double volume = (controller?.value.volume ?? 1).clamp(0, 1);
    final IconData icon = volume <= 0
        ? Icons.volume_off_rounded
        : volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Volume',
            iconSize: 24,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 36),
            color: Colors.white,
            onPressed: () => ref
                .read(playbackControllerProvider.notifier)
                .setVolume(volume > 0 ? 0 : 1),
            icon: Icon(icon),
          ),
          // While collapsed (width 0) the slider is invisible but would still
          // be focusable — on TV that makes the D-pad vanish into it and the
          // slider then eats all four arrow keys. Keep it out of focus until
          // it is actually shown.
          ExcludeFocus(
            excluding: !_hovered,
            child: ClipRect(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _hovered ? 96 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: _hovered ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8),
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withValues(
                          alpha: 0.35,
                        ),
                        thumbColor: Colors.white,
                        overlayColor: Colors.white.withValues(alpha: 0.12),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                      ),
                      child: Slider(
                        value: volume,
                        onChanged: (double next) => ref
                            .read(playbackControllerProvider.notifier)
                            .setVolume(next),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionBar extends ConsumerStatefulWidget {
  const _PositionBar({required this.controller, this.skipMarkers});
  final PlayerEngine controller;
  final SkipMarkers? skipMarkers;

  @override
  ConsumerState<_PositionBar> createState() => _PositionBarState();
}

class _PositionBarState extends ConsumerState<_PositionBar> {
  double? _dragValue;
  Duration? _lastDragPosition;

  Duration _positionFromValue(Duration duration, double value) {
    return Duration(milliseconds: (duration.inMilliseconds * value).round());
  }

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    widget.controller.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant _PositionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_tick);
      widget.controller.addListener(_tick);
      _dragValue = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() => mounted ? setState(() {}) : null;

  double _bufferedValue(
    List<PlayerBufferedRange> ranges,
    Duration duration,
    Duration position,
  ) {
    final int totalMs = duration.inMilliseconds;
    if (totalMs <= 0 || ranges.isEmpty) return 0;

    final int positionMs = position.inMilliseconds.clamp(0, totalMs).toInt();
    final int beforeToleranceMs = const Duration(seconds: 1).inMilliseconds;
    final int afterToleranceMs = const Duration(seconds: 4).inMilliseconds;
    int bufferedEndMs = positionMs;
    for (final PlayerBufferedRange range in ranges) {
      final int startMs = range.start.inMilliseconds.clamp(0, totalMs).toInt();
      final int endMs = range.end.inMilliseconds.clamp(0, totalMs).toInt();
      if (endMs <= startMs) continue;
      final bool isCurrentRange =
          startMs <= positionMs + afterToleranceMs &&
          endMs >= positionMs - beforeToleranceMs;
      if (isCurrentRange && endMs > bufferedEndMs) {
        bufferedEndMs = endMs;
      }
    }

    return (bufferedEndMs / totalMs).clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackState playback = ref.watch(playbackControllerProvider);
    final Duration duration = widget.controller.value.duration;
    final bool seekPreviewActive =
        playback.engine == widget.controller &&
        playback.seekPreviewPosition != null;
    final Duration position = seekPreviewActive
        ? playback.seekPreviewPosition!
        : widget.controller.value.position;
    final double engineValue = duration.inMilliseconds <= 0
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds)
              .clamp(0, 1)
              .toDouble();
    final double value = _dragValue ?? engineValue;
    final bool isInteracting = _dragValue != null || seekPreviewActive;
    final double bufferedValue =
        seekPreviewActive && playback.seekPreviewBufferedEnd != null
        ? _bufferedValueFromEnd(duration, playback.seekPreviewBufferedEnd!)
        : _bufferedValue(widget.controller.value.buffered, duration, position);
    final SliderThemeData sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      activeTrackColor: Colors.white.withValues(alpha: 0.9),
      secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.45),
      inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
      thumbColor: Colors.white,
      overlayColor: Colors.white.withValues(alpha: 0.12),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
    );
    final bool showBubble = _dragValue != null;
    final Duration bubblePosition = _lastDragPosition ?? position;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Flutter Slider internal horizontal padding = max(overlayRadius, thumbRadius) = max(10, 6) = 10
        const double thumbHPad = 10.0;
        final double trackWidth = (constraints.maxWidth - 2 * thumbHPad).clamp(
          0.0,
          double.infinity,
        );
        final double thumbCenterX = thumbHPad + value * trackWidth;
        final double bubbleWidth = _SeekPreviewBubble.timecodeWidthFor(
          context,
          bubblePosition,
        );
        final double bubbleLeft = (thumbCenterX - bubbleWidth / 2).clamp(
          0.0,
          (constraints.maxWidth - bubbleWidth).clamp(0.0, double.infinity),
        );
        final double bubbleArrowX = (thumbCenterX - bubbleLeft).clamp(
          8.0,
          bubbleWidth - 8.0,
        );
        return SizedBox(
          height: 10,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              if (widget.skipMarkers != null && duration.inMilliseconds > 0)
                Positioned.fill(
                  child: Padding(
                    // Slider internal track padding = max(overlayRadius, thumbRadius) = max(10, 6) = 10
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: CustomPaint(
                      painter: _SkipMarkerPainter(
                        markers: widget.skipMarkers!,
                        totalMs: duration.inMilliseconds,
                      ),
                    ),
                  ),
                ),
              // On TV the timeline is driven with Left/Right seek on the
              // playback surface; a focused Slider would swallow every arrow
              // key and strand the D-pad, so keep it out of traversal there.
              ExcludeFocus(
                excluding: TvPlatform.isAndroidTv,
                child: SliderTheme(
                  data: sliderTheme,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: value),
                    duration: isInteracting
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    curve: Curves.linear,
                    builder:
                        (
                          BuildContext context,
                          double animatedValue,
                          Widget? child,
                        ) {
                          final double displayedValue = isInteracting
                              ? value
                              : animatedValue.clamp(0, 1).toDouble();
                          return TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: bufferedValue),
                            duration: isInteracting
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            builder:
                                (
                                  BuildContext context,
                                  double animatedBufferedValue,
                                  Widget? child,
                                ) {
                                  final double displayedBufferedValue =
                                      animatedBufferedValue
                                          .clamp(0, 1)
                                          .toDouble();
                                  return Slider(
                                    value: displayedValue,
                                    secondaryTrackValue:
                                        displayedBufferedValue > displayedValue
                                        ? displayedBufferedValue
                                        : null,
                                    onChangeStart: duration.inMilliseconds <= 0
                                        ? null
                                        : (double startValue) {
                                            final Duration pos =
                                                _positionFromValue(
                                                  duration,
                                                  startValue,
                                                );
                                            setState(() {
                                              _dragValue = startValue;
                                              _lastDragPosition = pos;
                                            });
                                            final PlaybackController notifier =
                                                ref.read(
                                                  playbackControllerProvider
                                                      .notifier,
                                                );
                                            notifier.beginSeekPreview();
                                            notifier.previewSeekTo(pos);
                                          },
                                    onChanged: duration.inMilliseconds <= 0
                                        ? null
                                        : (double v) {
                                            final Duration pos =
                                                _positionFromValue(duration, v);
                                            setState(() {
                                              _dragValue = v;
                                              _lastDragPosition = pos;
                                            });
                                            ref
                                                .read(
                                                  playbackControllerProvider
                                                      .notifier,
                                                )
                                                .previewSeekTo(pos);
                                          },
                                    onChangeEnd: duration.inMilliseconds <= 0
                                        ? null
                                        : (double v) {
                                            final Duration pos =
                                                _positionFromValue(duration, v);
                                            setState(() {
                                              _dragValue = null;
                                              _lastDragPosition = pos;
                                            });
                                            final PlaybackController notifier =
                                                ref.read(
                                                  playbackControllerProvider
                                                      .notifier,
                                                );
                                            notifier.seekTo(pos);
                                            notifier.endSeekPreview();
                                          },
                                  );
                                },
                          );
                        },
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: bubbleLeft,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showBubble ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeInOut,
                    child: AnimatedScale(
                      scale: showBubble ? 1.0 : 0.82,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeInOut,
                      alignment: Alignment.bottomCenter,
                      child: _SeekPreviewBubble(
                        position: bubblePosition,
                        controller: null,
                        ready: false,
                        width: bubbleWidth,
                        arrowX: bubbleArrowX,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _bufferedValueFromEnd(Duration duration, Duration bufferedEnd) {
    final int totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return 0;
    return (bufferedEnd.inMilliseconds / totalMs).clamp(0, 1).toDouble();
  }
}

class _SkipMarkerPainter extends CustomPainter {
  const _SkipMarkerPainter({required this.markers, required this.totalMs});
  final SkipMarkers markers;
  final int totalMs;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;

    void drawTicks(Duration start, Duration end, Color color) {
      final int startMs = start.inMilliseconds.clamp(0, totalMs).toInt();
      final int endMs = end.inMilliseconds.clamp(0, totalMs).toInt();
      if (endMs <= startMs) return;

      final double x1 = (startMs / totalMs) * size.width;
      final double x2 = (endMs / totalMs * size.width)
          .clamp(0, size.width)
          .toDouble();
      final Paint tickPaint = Paint()
        ..color = color.withValues(alpha: 0.92)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x1, cy - 1), Offset(x1, cy + 1), tickPaint);
      canvas.drawLine(Offset(x2, cy - 1), Offset(x2, cy + 1), tickPaint);
    }

    if (markers.hasOpening) {
      drawTicks(
        markers.openingStart!,
        markers.openingEnd!,
        const Color(0xFFFFAB00),
      );
    }
    if (markers.hasEnding) {
      drawTicks(
        markers.endingStart!,
        markers.endingEnd!,
        const Color(0xFFBB44FF),
      );
    }
  }

  @override
  bool shouldRepaint(_SkipMarkerPainter old) =>
      old.markers != markers || old.totalMs != totalMs;
}

class _SeekPreviewBubble extends StatelessWidget {
  const _SeekPreviewBubble({
    required this.position,
    required this.controller,
    required this.ready,
    required this.width,
    required this.arrowX,
  });
  final Duration position;
  final PlayerEngine? controller;
  final bool ready;
  final double width;
  final double arrowX;

  static const double _previewWidth = 160.0;
  static const EdgeInsets _timecodePadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 6,
  );
  static const TextStyle _timecodeStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    height: 1,
  );

  static double timecodeWidthFor(BuildContext context, Duration position) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: _format(position), style: _timecodeStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return (painter.width + _timecodePadding.horizontal + 8).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final PlayerEngine? preview = controller;
    if (preview == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: width,
            padding: _timecodePadding,
            decoration: BoxDecoration(
              color: const Color(0xE8111111),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.5,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x60000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              _format(position),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
              style: _timecodeStyle,
            ),
          ),
          SizedBox(
            width: width,
            height: 5,
            child: CustomPaint(
              painter: _SeekBubbleArrowPainter(arrowCenterX: arrowX),
            ),
          ),
        ],
      );
    }

    final double ar = preview.value.aspectRatio;
    final double safeAr = (ar > 0.2 && ar < 5.0 && ar.isFinite)
        ? ar
        : 16.0 / 9.0;
    final double previewHeight = (_previewWidth / safeAr).clamp(40.0, 140.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: _previewWidth,
          height: previewHeight,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x60000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (!ready)
                const _SeekPreviewPlaceholder(loading: true)
              else
                ValueListenableBuilder<PlayerEngineState>(
                  valueListenable: preview.state,
                  builder:
                      (
                        BuildContext context,
                        PlayerEngineState value,
                        Widget? child,
                      ) {
                        if (value.hasError) {
                          return const _SeekPreviewPlaceholder(loading: false);
                        }
                        if (!value.isInitialized) {
                          return const _SeekPreviewPlaceholder(loading: false);
                        }
                        if (!value.hasVideoSurface) {
                          return const _SeekPreviewPlaceholder(loading: false);
                        }
                        return preview.buildVideoSurface(context);
                      },
                ),
              // Time label gradient overlay at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: <Color>[Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                  child: Text(
                    _format(position),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: _previewWidth,
          height: 5,
          child: CustomPaint(
            painter: _SeekBubbleArrowPainter(
              arrowCenterX: arrowX.clamp(8.0, _previewWidth - 8.0),
            ),
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _SeekPreviewPlaceholder extends StatelessWidget {
  const _SeekPreviewPlaceholder({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF080808),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            : const Icon(
                Icons.movie_filter_outlined,
                size: 22,
                color: Colors.white38,
              ),
      ),
    );
  }
}

class _SeekBubbleArrowPainter extends CustomPainter {
  const _SeekBubbleArrowPainter({required this.arrowCenterX});

  final double arrowCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = arrowCenterX.clamp(5.0, size.width - 5.0);
    final Path path = Path()
      ..moveTo(centerX - 5, 0)
      ..lineTo(centerX + 5, 0)
      ..lineTo(centerX, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xE8111111));
  }

  @override
  bool shouldRepaint(_SeekBubbleArrowPainter old) =>
      old.arrowCenterX != arrowCenterX;
}

class _SubtitleOverlay extends StatefulWidget {
  const _SubtitleOverlay({required this.state, required this.settings});
  final PlaybackState state;
  final PlayerSettings settings;

  @override
  State<_SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<_SubtitleOverlay> {
  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    widget.state.engine?.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant _SubtitleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.engine != widget.state.engine) {
      oldWidget.state.engine?.removeListener(_tick);
      widget.state.engine?.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.state.engine?.removeListener(_tick);
    super.dispose();
  }

  void _tick() => mounted ? setState(() {}) : null;

  @override
  Widget build(BuildContext context) {
    final PlayerEngine? controller = widget.state.engine;
    if (!widget.settings.subtitlesEnabled ||
        controller == null ||
        widget.state.subtitleCues.isEmpty) {
      return const SizedBox.shrink();
    }
    final Duration position = controller.value.position;
    final String text = widget.state.subtitleCues
        .where(
          (SubtitleCue cue) =>
              cue.contains(position, widget.settings.subtitleDelay),
        )
        .map((SubtitleCue cue) => cue.text)
        .join('\n');
    if (text.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 24,
      right: 24,
      bottom: widget.settings.subtitleBottomOffset,
      child: IgnorePointer(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(widget.settings.subtitleTextColor),
            fontSize: widget.settings.subtitleFontSize,
            fontWeight: FontWeight.w700,
            shadows: widget.settings.subtitleHasBackground
                ? null
                : const <Shadow>[Shadow(offset: Offset(0, 1.5), blurRadius: 4)],
            backgroundColor: widget.settings.subtitleHasBackground
                ? Colors.black.withValues(
                    alpha: widget.settings.subtitleBackgroundOpacity,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _SkipButtons extends ConsumerStatefulWidget {
  const _SkipButtons({required this.item});
  final MediaPlaybackItem item;

  @override
  ConsumerState<_SkipButtons> createState() => _SkipButtonsState();
}

class _SkipButtonsState extends ConsumerState<_SkipButtons> {
  PlayerEngine? _attached;
  DateTime? _opWindowStart;
  DateTime? _edWindowStart;
  Timer? _opHideTimer;
  Timer? _edHideTimer;
  bool _lastInOp = false;
  bool _lastInEd = false;

  void _tick() {
    if (!mounted) return;
    final _SkipWindowFlags flags = _currentWindowFlags();
    _updateWindowState(flags);
    setState(() {});
  }

  void _attachController(PlayerEngine? next) {
    if (_attached == next) return;
    _attached?.removeListener(_tick);
    next?.addListener(_tick);
    _attached = next;
  }

  @override
  void dispose() {
    _attached?.removeListener(_tick);
    _opHideTimer?.cancel();
    _edHideTimer?.cancel();
    super.dispose();
  }

  _SkipWindowFlags _currentWindowFlags() {
    final PlaybackState state = ref.read(playbackControllerProvider);
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final SkipMarkers markers = _effectiveSkipMarkers(
      ref.read(skipMarkersProvider).value,
      widget.item.skipMarkers,
    );
    final PlayerEngine? controller = state.engine;
    if (controller == null) {
      return const _SkipWindowFlags(inOp: false, inEd: false);
    }
    final Duration p = controller.value.position;
    final bool inOp =
        settings.showSkipOpeningButton &&
        !settings.autoSkipOpening &&
        markers.hasOpening &&
        p >= markers.openingStart! &&
        p < markers.openingEnd!;
    final bool inEd =
        settings.showSkipEndingButton &&
        !settings.autoSkipEnding &&
        markers.hasEnding &&
        p >= markers.endingStart! &&
        p < markers.endingEnd!;
    return _SkipWindowFlags(inOp: inOp, inEd: inEd);
  }

  void _updateWindowState(_SkipWindowFlags flags) {
    final DateTime now = DateTime.now();
    if (flags.inOp && !_lastInOp) {
      _opWindowStart = now;
      _opHideTimer?.cancel();
      _opHideTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        _opWindowStart = null;
        setState(() {});
      });
    } else if (!flags.inOp) {
      _opWindowStart = null;
      _opHideTimer?.cancel();
      _opHideTimer = null;
    }

    if (flags.inEd && !_lastInEd) {
      _edWindowStart = now;
      _edHideTimer?.cancel();
      _edHideTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        _edWindowStart = null;
        setState(() {});
      });
    } else if (!flags.inEd) {
      _edWindowStart = null;
      _edHideTimer?.cancel();
      _edHideTimer = null;
    }

    _lastInOp = flags.inOp;
    _lastInEd = flags.inEd;
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackState state = ref.watch(playbackControllerProvider);
    final PlayerSettings settings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    final SkipMarkers markers = _effectiveSkipMarkers(
      ref.watch(skipMarkersProvider).value,
      widget.item.skipMarkers,
    );

    _attachController(state.engine);

    final _SkipWindowFlags flags = _currentWindowFlags();
    if (flags.inOp != _lastInOp || flags.inEd != _lastInEd) {
      _updateWindowState(flags);
    }

    final PlayerEngine? controller = state.engine;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    final DateTime now = DateTime.now();
    final Duration p = controller.value.position;
    Duration? target;
    String? label;

    final bool showOp =
        settings.showSkipOpeningButton &&
        !settings.autoSkipOpening &&
        markers.hasOpening &&
        p >= markers.openingStart! &&
        p < markers.openingEnd! &&
        _opWindowStart != null &&
        now.difference(_opWindowStart!) <= const Duration(seconds: 5);
    final bool showEd =
        settings.showSkipEndingButton &&
        !settings.autoSkipEnding &&
        markers.hasEnding &&
        p >= markers.endingStart! &&
        p < markers.endingEnd! &&
        _edWindowStart != null &&
        now.difference(_edWindowStart!) <= const Duration(seconds: 5);

    if (showOp) {
      target = markers.openingEnd;
      label = 'Skip Opening';
    } else if (showEd) {
      target = markers.endingEnd;
      label = 'Skip Ending';
    }
    if (target == null) return const SizedBox.shrink();
    return Positioned(
      right: 24,
      bottom: 116,
      child: FilledButton.icon(
        style: _overlayActionButtonStyle(),
        onPressed: () =>
            ref.read(playbackControllerProvider.notifier).skipTo(target!),
        icon: const Icon(Icons.skip_next_rounded),
        label: Text(label!),
      ),
    );
  }
}

class _PlayerErrorOverlay extends ConsumerWidget {
  const _PlayerErrorOverlay({required this.error, required this.onExit});

  final PlayerError error;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlaybackState state = ref.watch(playbackControllerProvider);
    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final bool canTryNextServer =
        item != null && server != null && item.servers.length > 1;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ModalBarrier(
          color: Colors.black.withValues(alpha: .48),
          dismissible: false,
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        error.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.message,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          TextButton.icon(
                            onPressed: onExit,
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: Text(context.t('Back')),
                          ),
                          if (canTryNextServer)
                            FilledButton.tonalIcon(
                              onPressed: () {
                                final List<MediaServer> servers = item.servers;
                                final int current = servers.indexWhere(
                                  (MediaServer s) => s.id == server.id,
                                );
                                final int next =
                                    (current < 0 ? 0 : current + 1) %
                                    servers.length;
                                ref
                                    .read(playbackControllerProvider.notifier)
                                    .switchServer(servers[next]);
                              },
                              icon: const Icon(Icons.dns_rounded),
                              label: Text(context.t('Try next')),
                            ),
                          if (error.canRetry)
                            FilledButton.icon(
                              onPressed: ref
                                  .read(playbackControllerProvider.notifier)
                                  .retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(context.t('Retry')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SkipWindowFlags {
  const _SkipWindowFlags({required this.inOp, required this.inEd});

  final bool inOp;
  final bool inEd;
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return IconButton(
        tooltip: context.t(label),
        onPressed: onTap,
        color: Colors.white,
        icon: Icon(icon),
      );
    }

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
      label: Text(
        context.t(label),
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.t(tooltip),
      onPressed: onTap,
      color: Colors.white,
      icon: Icon(icon),
    );
  }
}

class _TopChip extends StatelessWidget {
  const _TopChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MenuSectionHeader extends StatelessWidget {
  const _MenuSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        context.t(label),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

Future<void> _showStreamsMenu(BuildContext context, WidgetRef ref) async {
  final NavigatorState navigator = Navigator.of(context);
  final PlaybackState state = ref.read(playbackControllerProvider);
  final List<MediaServer> servers =
      state.item?.servers ?? const <MediaServer>[];
  final List<VoiceOverTrack> voiceovers =
      state.server?.voiceovers ?? const <VoiceOverTrack>[];
  await _showMenuSheet(context, 'Streams', <Widget>[
    const _MenuSectionHeader('Servers'),
    for (final MediaServer server in servers)
      ListTile(
        selected: server.id == state.server?.id,
        leading: const Icon(Icons.dns_rounded),
        title: Text(server.name),
        subtitle: Text(server.sourceName),
        onTap: () {
          navigator.pop();
          ref.read(playbackControllerProvider.notifier).switchServer(server);
        },
      ),
    if (voiceovers.isNotEmpty) ...<Widget>[
      const _MenuSectionHeader('Voiceovers'),
      for (final VoiceOverTrack track in voiceovers)
        ListTile(
          selected: track.id == state.voiceover?.id,
          leading: const Icon(Icons.record_voice_over_rounded),
          title: Text(track.label),
          onTap: () {
            navigator.pop();
            ref
                .read(playbackControllerProvider.notifier)
                .switchVoiceover(track);
          },
        ),
    ],
  ]);
}

Future<void> _showQualityMenu(BuildContext context, WidgetRef ref) async {
  final NavigatorState navigator = Navigator.of(context);
  final PlaybackState state = ref.read(playbackControllerProvider);
  final List<StreamQuality> qualities =
      state.server?.qualities.isNotEmpty == true
      ? state.server!.qualities
      : <StreamQuality>[StreamQuality.auto];
  await _showMenuSheet(context, 'Quality', <Widget>[
    for (final StreamQuality quality in qualities)
      ListTile(
        selected: quality.id == state.quality?.id,
        leading: const Icon(Icons.high_quality_rounded),
        title: Text(quality.label),
        onTap: () {
          navigator.pop();
          ref.read(playbackControllerProvider.notifier).switchQuality(quality);
        },
      ),
  ]);
}

Future<void> _showSubtitleMenu(BuildContext context, WidgetRef ref) async {
  final NavigatorState navigator = Navigator.of(context);
  final PlaybackState state = ref.read(playbackControllerProvider);
  final List<SubtitleTrack> tracks =
      state.server?.subtitles ?? const <SubtitleTrack>[];
  await _showMenuSheet(context, 'Subtitles', <Widget>[
    const _MenuSectionHeader('Track'),
    ListTile(
      selected: state.subtitle == null,
      leading: const Icon(Icons.subtitles_off_rounded),
      title: Text(context.t('Off')),
      onTap: () {
        navigator.pop();
        ref
            .read(playbackControllerProvider.notifier)
            .selectSubtitle(null, const <SubtitleCue>[]);
      },
    ),
    for (final SubtitleTrack track in tracks)
      ListTile(
        selected: state.subtitle?.id == track.id,
        leading: const Icon(Icons.subtitles_rounded),
        title: Text(track.label),
        subtitle: track.language.isNotEmpty ? Text(track.language) : null,
        onTap: () async {
          navigator.pop();
          unawaited(
            ref.read(playerSettingsProvider.notifier).setSubtitlesEnabled(true),
          );
          final List<SubtitleCue> cues = await _loadSubtitleCues(track);
          ref
              .read(playbackControllerProvider.notifier)
              .selectSubtitle(track, cues);
        },
      ),
    const _SubtitleAppearanceTiles(),
  ]);
}

Future<List<SubtitleCue>> _loadSubtitleCues(SubtitleTrack track) async {
  try {
    final Response<String> response = await Dio().get<String>(
      track.url,
      options: track.headers.isNotEmpty
          ? Options(headers: track.headers)
          : null,
    );
    return const SubtitleParser().parse(response.data ?? '');
  } on Object {
    return const <SubtitleCue>[];
  }
}

Future<void> _showSpeedMenu(BuildContext context, WidgetRef ref) async {
  final NavigatorState navigator = Navigator.of(context);
  final List<double> speeds = <double>[
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    1.75,
    2,
    2.5,
    3,
  ];
  final double active =
      ref.read(playerSettingsProvider).value?.playbackSpeed ?? 1;
  await _showMenuSheet(context, 'Speed', <Widget>[
    for (final double speed in speeds)
      ListTile(
        selected: active == speed,
        leading: const Icon(Icons.speed_rounded),
        title: Text(speed == 1 ? context.t('Default') : '${speed}x'),
        onTap: () {
          navigator.pop();
          ref.read(playbackControllerProvider.notifier).setSpeed(speed);
        },
      ),
  ]);
}

Future<void> _showEpisodes(
  BuildContext context,
  MediaPlaybackItem? item, {
  void Function(String href)? onSelect,
}) async {
  final NavigatorState navigator = Navigator.of(context);
  final String? currentHref = item?.externalIds['sora_episode_href'];
  await _showMenuSheet(context, 'Episodes', <Widget>[
    if (item == null || item.seasons.isEmpty)
      ListTile(title: Text(context.t('No episode data was provided.'))),
    for (final Season season in item?.seasons ?? const <Season>[])
      ExpansionTile(
        initiallyExpanded:
            item!.seasons.length == 1 ||
            season.episodes.any((Episode e) => e.id == currentHref),
        title: Text(season.title),
        children: <Widget>[
          for (final Episode episode in season.episodes)
            ListTile(
              selected: episode.id == currentHref,
              leading: CircleAvatar(child: Text(episode.number.toString())),
              title: Text(episode.title),
              subtitle: episode.progress > Duration.zero
                  ? Text(
                      context.tf('Progress {minutes} min', <String, Object?>{
                        'minutes': episode.progress.inMinutes,
                      }),
                    )
                  : null,
              trailing: episode.id == currentHref
                  ? const Icon(Icons.play_arrow_rounded)
                  : null,
              onTap: onSelect == null || episode.id == currentHref
                  ? null
                  : () {
                      navigator.pop();
                      onSelect(episode.id);
                    },
            ),
        ],
      ),
  ]);
}

Future<void> _showSettings(BuildContext context, WidgetRef ref) async {
  await _showMenuSheet(context, 'Player Settings', <Widget>[
    const _PlayerSettingsTiles(),
  ]);
}

class _PlayerSettingsTiles extends ConsumerWidget {
  const _PlayerSettingsTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerSettings settings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    final List<PlayerBackend> backends = availablePlayerBackends();
    final PlayerBackend selectedBackend = visiblePlayerBackend(
      settings.playerBackend,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.smart_display_rounded),
          title: Text(context.t('Player engine')),
          subtitle: Text(
            '${context.t(selectedBackend.title)} · '
            'Reloads current stream.',
          ),
          onTap: () async {
            final PlayerBackend? picked = await showDialog<PlayerBackend>(
              context: context,
              builder: (BuildContext context) => SimpleDialog(
                title: Text(context.t('Player engine')),
                children: <Widget>[
                  RadioGroup<PlayerBackend>(
                    groupValue: selectedBackend,
                    onChanged: (PlayerBackend? value) =>
                        Navigator.pop(context, value),
                    child: Column(
                      children: backends
                          .map(
                            (PlayerBackend backend) =>
                                RadioListTile<PlayerBackend>(
                                  value: backend,
                                  title: Text(context.t(backend.title)),
                                  subtitle: Text(
                                    context.t(backend.description),
                                  ),
                                ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            );
            if (picked != null) {
              await ref
                  .read(playbackControllerProvider.notifier)
                  .reloadWithBackend(picked);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_rounded),
          title: Text(context.t('Keyboard shortcuts')),
          subtitle: Text(context.t('Keys & touch gestures')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showMenuSheet(
            context,
            'Player controls',
            <Widget>[
              PlayerShortcutsView(seekSeconds: settings.seekInterval.inSeconds),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(context.t('Close')),
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          value: settings.useAniSkip,
          secondary: const Icon(Icons.av_timer_rounded),
          title: Text(context.t('Use AniSkip')),
          subtitle: Text(context.t('Fetch OP/ED times from AniSkip & Anira')),
          onChanged: (bool value) =>
              ref.read(playerSettingsProvider.notifier).setUseAniSkip(value),
        ),
        if (settings.useAniSkip)
          ListTile(
            leading: const Icon(Icons.source_rounded),
            title: Text(context.t('Skip marks source')),
            subtitle: Text(
              settings.skipMarkersSource == SkipMarkersSource.addon
                  ? context.t('Addon')
                  : context.t('MiruShin (AniSkip & Anira)'),
            ),
            onTap: () async {
              final SkipMarkersSource?
              picked = await showDialog<SkipMarkersSource>(
                context: context,
                builder: (BuildContext context) => SimpleDialog(
                  title: Text(context.t('Primary skip marks source')),
                  children: <Widget>[
                    RadioGroup<SkipMarkersSource>(
                      groupValue: settings.skipMarkersSource,
                      onChanged: (SkipMarkersSource? v) =>
                          Navigator.pop(context, v),
                      child: Column(
                        children: <Widget>[
                          RadioListTile<SkipMarkersSource>(
                            value: SkipMarkersSource.addon,
                            title: Text(context.t('Addon')),
                            subtitle: Text(
                              context.t(
                                'Addon data takes priority; AniSkip & Anira fill gaps',
                              ),
                            ),
                          ),
                          RadioListTile<SkipMarkersSource>(
                            value: SkipMarkersSource.mirushin,
                            title: Text(context.t('MiruShin')),
                            subtitle: Text(
                              context.t(
                                'AniSkip & Anira take priority; addon fills gaps',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (picked != null) {
                await ref
                    .read(playerSettingsProvider.notifier)
                    .setSkipMarkersSource(picked);
              }
            },
          ),
        SwitchListTile(
          value: settings.autoSkipOpening,
          secondary: const Icon(Icons.skip_next_rounded),
          title: Text(context.t('Auto-skip OP')),
          onChanged: (bool value) => ref
              .read(playerSettingsProvider.notifier)
              .setAutoSkipOpening(value),
        ),
        if (!settings.autoSkipOpening)
          SwitchListTile(
            value: settings.showSkipOpeningButton,
            secondary: const Icon(Icons.fast_forward_rounded),
            title: Text(context.t('Skip OP button')),
            onChanged: (bool value) => ref
                .read(playerSettingsProvider.notifier)
                .setShowSkipOpeningButton(value),
          ),
        SwitchListTile(
          value: settings.autoSkipEnding,
          secondary: const Icon(Icons.skip_next_rounded),
          title: Text(context.t('Auto-skip ED')),
          onChanged: (bool value) => ref
              .read(playerSettingsProvider.notifier)
              .setAutoSkipEnding(value),
        ),
        if (!settings.autoSkipEnding)
          SwitchListTile(
            value: settings.showSkipEndingButton,
            secondary: const Icon(Icons.last_page_rounded),
            title: Text(context.t('Skip ED button')),
            onChanged: (bool value) => ref
                .read(playerSettingsProvider.notifier)
                .setShowSkipEndingButton(value),
          ),
        SwitchListTile(
          value: settings.autoplayNext,
          secondary: const Icon(Icons.play_circle_outline_rounded),
          title: Text(context.t('Auto next episode')),
          onChanged: (bool value) =>
              ref.read(playerSettingsProvider.notifier).setAutoplayNext(value),
        ),
        if (!settings.autoplayNext)
          SwitchListTile(
            value: settings.showNextEpisodeButton,
            secondary: const Icon(Icons.skip_next_rounded),
            title: Text(context.t('Next episode button')),
            onChanged: (bool value) => ref
                .read(playerSettingsProvider.notifier)
                .setShowNextEpisodeButton(value),
          ),
        if (DiscordRpcService.isSupported)
          SwitchListTile(
            value: settings.discordRpcEnabled,
            secondary: const Icon(Icons.hub_rounded),
            title: Text(context.t('Discord RPC')),
            subtitle: Text(
              context.t(
                'Share this playback to Discord while the app setting is enabled',
              ),
            ),
            onChanged: (bool value) => ref
                .read(playerSettingsProvider.notifier)
                .setDiscordRpcEnabled(value),
          ),
        if (ref.watch(catalogModeProvider) == CatalogMode.anilist)
          SwitchListTile(
            value: settings.autoAnilistSync,
            secondary: const Icon(Icons.sync_rounded),
            title: Text(context.t('Auto AniList progress')),
            subtitle: Text(
              context.t('Sync episode progress to AniList at 85%'),
            ),
            onChanged: (bool value) => ref
                .read(playerSettingsProvider.notifier)
                .setAutoAnilistSync(value),
          ),
        ListTile(
          leading: const Icon(Icons.keyboard_double_arrow_right_rounded),
          title: Text(context.t('Seek interval')),
          subtitle: Text('${settings.seekInterval.inSeconds}s'),
          onTap: () async {
            final int? seconds = await showDialog<int>(
              context: context,
              builder: (BuildContext context) => SimpleDialog(
                title: Text(context.t('Seek interval')),
                children: <Widget>[
                  for (final int value in <int>[5, 10, 15, 30, 60])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, value),
                      child: Text('${value}s'),
                    ),
                ],
              ),
            );
            if (seconds != null) {
              await ref
                  .read(playerSettingsProvider.notifier)
                  .setSeekInterval(Duration(seconds: seconds));
            }
          },
        ),
      ],
    );
  }
}

class _SubtitleAppearanceTiles extends ConsumerWidget {
  const _SubtitleAppearanceTiles();

  static const List<(String, int)> _presetColors = <(String, int)>[
    ('White', 0xFFFFFFFF),
    ('Yellow', 0xFFFFF176),
    ('Cyan', 0xFF80DEEA),
    ('Green', 0xFFA5D6A7),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerSettings s =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    final PlayerSettingsController ctrl = ref.read(
      playerSettingsProvider.notifier,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Divider(height: 24),
        const _MenuSectionHeader('Appearance'),
        ListTile(
          leading: const Icon(Icons.format_size_rounded),
          title: Text(context.t('Font size')),
          trailing: _StepRow(
            value: '${s.subtitleFontSize.round()}px',
            onDecrement: s.subtitleFontSize > 12
                ? () => ctrl.setSubtitleFontSize(s.subtitleFontSize - 2)
                : null,
            onIncrement: s.subtitleFontSize < 48
                ? () => ctrl.setSubtitleFontSize(s.subtitleFontSize + 2)
                : null,
          ),
        ),
        // A focused Slider consumes every D-pad arrow, so on TV the slider
        // tiles become +/- steppers instead.
        if (TvPlatform.isAndroidTv)
          ListTile(
            leading: const Icon(Icons.vertical_align_bottom_rounded),
            title: Text(context.t('Position')),
            trailing: _StepRow(
              value: s.subtitleBottomOffset.round().toString(),
              onDecrement: s.subtitleBottomOffset > 20
                  ? () => ctrl.setSubtitleBottomOffset(
                      (s.subtitleBottomOffset - 10).clamp(20.0, 300.0),
                    )
                  : null,
              onIncrement: s.subtitleBottomOffset < 300
                  ? () => ctrl.setSubtitleBottomOffset(
                      (s.subtitleBottomOffset + 10).clamp(20.0, 300.0),
                    )
                  : null,
            ),
          )
        else
          ListTile(
            leading: const Icon(Icons.vertical_align_bottom_rounded),
            title: Text(context.t('Position')),
            subtitle: Slider(
              value: s.subtitleBottomOffset.clamp(20.0, 300.0),
              min: 20,
              max: 300,
              divisions: 28,
              label: s.subtitleBottomOffset.round().toString(),
              onChanged: (double v) => ctrl.setSubtitleBottomOffset(v),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.palette_rounded),
          title: Text(context.t('Text color')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: _presetColors
                .map(((String, int) c) {
                  final bool selected = s.subtitleTextColor == c.$2;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: TvFocusable(
                      onTap: () => ctrl.setSubtitleTextColor(c.$2),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Color(c.$2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white30,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.opacity_rounded),
          title: Text(context.t('Text background')),
          value: s.subtitleHasBackground,
          onChanged: (bool v) => ctrl.setSubtitleHasBackground(v),
        ),
        if (s.subtitleHasBackground && TvPlatform.isAndroidTv)
          ListTile(
            leading: const Icon(Icons.blur_on_rounded),
            title: Text(context.t('Background opacity')),
            trailing: _StepRow(
              value: '${(s.subtitleBackgroundOpacity * 100).round()}%',
              onDecrement: s.subtitleBackgroundOpacity > 0
                  ? () => ctrl.setSubtitleBackgroundOpacity(
                      (s.subtitleBackgroundOpacity - 0.05).clamp(0.0, 1.0),
                    )
                  : null,
              onIncrement: s.subtitleBackgroundOpacity < 1
                  ? () => ctrl.setSubtitleBackgroundOpacity(
                      (s.subtitleBackgroundOpacity + 0.05).clamp(0.0, 1.0),
                    )
                  : null,
            ),
          )
        else if (s.subtitleHasBackground)
          ListTile(
            leading: const Icon(Icons.blur_on_rounded),
            title: Text(context.t('Background opacity')),
            subtitle: Slider(
              value: s.subtitleBackgroundOpacity.clamp(0.0, 1.0),
              divisions: 20,
              label: '${(s.subtitleBackgroundOpacity * 100).round()}%',
              onChanged: (double v) => ctrl.setSubtitleBackgroundOpacity(v),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.schedule_rounded),
          title: Text(context.t('Delay')),
          trailing: _StepRow(
            value: '${s.subtitleDelay.inMilliseconds}ms',
            onDecrement: () => ctrl.setSubtitleDelay(
              Duration(milliseconds: s.subtitleDelay.inMilliseconds - 500),
            ),
            onIncrement: () => ctrl.setSubtitleDelay(
              Duration(milliseconds: s.subtitleDelay.inMilliseconds + 500),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: onDecrement,
            iconSize: 18,
            padding: EdgeInsets.zero,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: onIncrement,
            iconSize: 18,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

Future<void> _showMenuSheet(
  BuildContext context,
  String title,
  List<Widget> children,
) {
  Widget sheet = SafeArea(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 560),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: <Widget>[
          Text(
            context.t(title),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
  if (TvPlatform.isAndroidTv) {
    sheet = _TvMenuSheetFocus(child: sheet);
  }
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    builder: (BuildContext context) => sheet,
  );
}

class _TvMenuSheetFocus extends StatefulWidget {
  const _TvMenuSheetFocus({required this.child});

  final Widget child;

  @override
  State<_TvMenuSheetFocus> createState() => _TvMenuSheetFocusState();
}

class _TvMenuSheetFocusState extends State<_TvMenuSheetFocus> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TvPlayerMenuSheet');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _focusNode.nextFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool forward =
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight;
    final bool backward =
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft;
    if (!forward && !backward) return KeyEventResult.ignored;

    final FocusNode? primary = FocusManager.instance.primaryFocus;
    final bool moved = forward
        ? (primary?.nextFocus() ?? node.nextFocus())
        : (primary?.previousFocus() ?? node.previousFocus());
    if (moved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? focusedContext =
            FocusManager.instance.primaryFocus?.context;
        if (focusedContext == null) return;
        Scrollable.ensureVisible(
          focusedContext,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          alignmentPolicy: forward
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: widget.child,
      ),
    );
  }
}

class _NativePipOverlay extends StatelessWidget {
  const _NativePipOverlay({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, _) => KeyEventResult.handled,
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: Colors.white54,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Playing in Picture-in-Picture',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Close the PiP window to resume here',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PipCorner { topLeft, topRight, bottomLeft, bottomRight }

// Mini-player controls for the Windows borderless PiP. Mirrors the main
// player's hover show/hide behaviour: an exit button in the top-left corner
// and a large play/pause button in the centre, both fading in/out together
// with `controlsVisible` (driven by the surrounding MouseRegion hover logic).
//
// Grabbing anywhere on the surface moves the window (macOS-style); the four
// corners are invisible resize handles (always active) that sit above the drag
// layer, and the buttons sit above everything so they never start a drag.
class _WindowPipOverlay extends StatelessWidget {
  const _WindowPipOverlay({
    required this.isPlaying,
    required this.controlsVisible,
    required this.aspectRatio,
    required this.onTogglePlay,
    required this.onExpand,
    required this.onMoveStart,
    required this.windowPhysicalRect,
    required this.setWindowPhysicalRect,
  });

  final bool isPlaying;
  final bool controlsVisible;
  final double aspectRatio;
  final VoidCallback onTogglePlay;
  final VoidCallback onExpand;
  final VoidCallback onMoveStart;
  final Future<({double x, double y, double width, double height})?> Function()
  windowPhysicalRect;
  final void Function(double x, double y, double width, double height)
  setWindowPhysicalRect;

  @override
  Widget build(BuildContext context) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Whole surface is a drag handle — grab anywhere to move the window.
          Listener(
            onPointerDown: (_) => onMoveStart(),
            behavior: HitTestBehavior.translucent,
          ),
          // Invisible corner resize handles (always active, on top of drag).
          for (final _PipCorner corner in _PipCorner.values)
            _PipResizeHandle(
              corner: corner,
              aspectRatio: aspectRatio,
              devicePixelRatio: dpr,
              windowPhysicalRect: windowPhysicalRect,
              setWindowPhysicalRect: setWindowPhysicalRect,
            ),
          // Buttons + scrim, fading with hover. On top so taps never drag.
          AnimatedOpacity(
            opacity: controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !controlsVisible,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Dim scrim so the buttons stay legible over bright video.
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x66000000),
                            Color(0x22000000),
                            Color(0x66000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Exit PiP — top-left corner.
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _MiniButton(
                      icon: Icons.close_rounded,
                      size: 20,
                      onPressed: onExpand,
                    ),
                  ),
                  // Play / pause — centre, like the original player.
                  Center(
                    child: _MiniButton(
                      icon: isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 44,
                      onPressed: onTogglePlay,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatefulWidget {
  const _MiniButton({
    required this.icon,
    required this.onPressed,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  State<_MiniButton> createState() => _MiniButtonState();
}

class _MiniButtonState extends State<_MiniButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = _pressed
        ? Colors.white.withValues(alpha: 0.24)
        : _hovered
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() {
          _hovered = false;
          _pressed = false;
        });
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          width: widget.size >= 40 ? 72 : 36,
          height: widget.size >= 40 ? 72 : 36,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(widget.size >= 40 ? 999 : 12),
          ),
          child: Center(
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: widget.size,
              shadows: const <Shadow>[
                Shadow(color: Colors.black54, blurRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Invisible corner resize handle for the borderless mini-player. Pans are
// applied as a new window rect anchored to the opposite corner, preserving the
// video aspect ratio. No icon is drawn — only the cursor hints at resizing.
class _PipResizeHandle extends StatefulWidget {
  const _PipResizeHandle({
    required this.corner,
    required this.aspectRatio,
    required this.devicePixelRatio,
    required this.windowPhysicalRect,
    required this.setWindowPhysicalRect,
  });

  static const double _hitSize = 22;

  final _PipCorner corner;
  final double aspectRatio;
  final double devicePixelRatio;
  final Future<({double x, double y, double width, double height})?> Function()
  windowPhysicalRect;
  final void Function(double x, double y, double width, double height)
  setWindowPhysicalRect;

  @override
  State<_PipResizeHandle> createState() => _PipResizeHandleState();
}

class _PipResizeHandleState extends State<_PipResizeHandle> {
  // Fixed screen edge (physical px) the resize anchors to: the right edge for
  // left handles, the bottom edge for top handles, etc.
  double? _anchorX;
  double? _anchorY;
  // The window's current left edge in physical px, tracked across frames so the
  // pointer's true screen X can be reconstructed even while the window is moving
  // (left handles). Accumulating window-relative deltas instead feeds the
  // window's own movement back into the next delta -> jitter.
  double _curX = 0;

  bool get _isLeft =>
      widget.corner == _PipCorner.topLeft ||
      widget.corner == _PipCorner.bottomLeft;
  bool get _isTop =>
      widget.corner == _PipCorner.topLeft ||
      widget.corner == _PipCorner.topRight;

  Future<void> _onPanStart(DragStartDetails _) async {
    final ({double x, double y, double width, double height})? rect =
        await widget.windowPhysicalRect();
    if (rect == null) {
      _anchorX = null;
      _anchorY = null;
      return;
    }
    _curX = rect.x;
    _anchorX = _isLeft ? rect.x + rect.width : rect.x;
    _anchorY = _isTop ? rect.y + rect.height : rect.y;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final double? anchorX = _anchorX;
    final double? anchorY = _anchorY;
    if (anchorX == null || anchorY == null) return;
    final double dpr = widget.devicePixelRatio;
    final double ar = widget.aspectRatio > 0 ? widget.aspectRatio : 16 / 9;

    // Reconstruct the pointer's absolute screen X from the window's tracked
    // position (globalPosition is relative to the moving window's client area).
    final double pointerX = _curX + details.globalPosition.dx * dpr;

    final double rawWidth = _isLeft ? anchorX - pointerX : pointerX - anchorX;
    final double width = rawWidth.clamp(280.0, 1280.0);
    final double height = width / ar;

    final double x = _isLeft ? anchorX - width : anchorX;
    final double y = _isTop ? anchorY - height : anchorY;

    widget.setWindowPhysicalRect(x, y, width, height);
    _curX = x;
  }

  MouseCursor get _cursor =>
      _isLeft ==
          _isTop // topLeft / bottomRight
      ? SystemMouseCursors.resizeUpLeftDownRight
      : SystemMouseCursors.resizeUpRightDownLeft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _isLeft ? 0 : null,
      right: _isLeft ? null : 0,
      top: _isTop ? 0 : null,
      bottom: _isTop ? null : 0,
      width: _PipResizeHandle._hitSize,
      height: _PipResizeHandle._hitSize,
      child: MouseRegion(
        cursor: _cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
        ),
      ),
    );
  }
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _FullscreenIntent extends Intent {
  const _FullscreenIntent();
}

class _NoopIntent extends Intent {
  const _NoopIntent();
}

class _SeekIntent extends Intent {
  const _SeekIntent({required this.backward});
  final bool backward;
}

class _VolumeIntent extends Intent {
  const _VolumeIntent({required this.up});
  final bool up;
}

class _MuteIntent extends Intent {
  const _MuteIntent();
}

class _SubtitlesIntent extends Intent {
  const _SubtitlesIntent();
}

class _EpisodesIntent extends Intent {
  const _EpisodesIntent();
}

class _QualityIntent extends Intent {
  const _QualityIntent();
}
