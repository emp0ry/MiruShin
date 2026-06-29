import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/playback_controller.dart';
import '../../engine/player_engine.dart';

class GestureOverlay extends ConsumerStatefulWidget {
  const GestureOverlay({
    required this.child,
    required this.onTap,
    required this.seekInterval,
    required this.isMobile,
    required this.isZoomed,
    required this.onToggleFullscreen,
    required this.onTogglePlay,
    required this.onZoomChanged,
    this.enableGestures = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final Duration seekInterval;
  final bool isMobile;
  final bool isZoomed;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onTogglePlay;
  final ValueChanged<bool> onZoomChanged;

  /// When false (e.g. Windows mini-player PiP) all tap/drag/double-tap/seek/
  /// volume gestures are disabled so the surface can be used purely to drag and
  /// resize the small window.
  final bool enableGestures;

  @override
  ConsumerState<GestureOverlay> createState() => _GestureOverlayState();
}

class _GestureOverlayState extends ConsumerState<GestureOverlay> {
  static const Duration _singleTapDelay = Duration(milliseconds: 220);
  static const Duration _multiTapSeekWindow = Duration(milliseconds: 900);
  static const Duration _pinchSuppressDelay = Duration(milliseconds: 120);
  static const double _pinchActivationScale = 1.14;

  String? _chip;
  String? _seekText;
  Alignment _seekAlignment = Alignment.centerRight;
  Timer? _chipTimer;
  Timer? _singleTapTimer;
  Timer? _pinchSuppressTimer;
  Duration _seekChipAccum = Duration.zero;
  double _hAccum = 0;
  double _vAccum = 0;
  double _vStartVolume = 1.0;
  bool _vRight = false;
  bool _temporarySpeedActive = false;
  bool _temporarySpeedPressing = false;
  bool _pinchActive = false;
  bool _pinchHandled = false;
  bool _suppressPointerGestures = false;
  bool? _pendingTapBackward;
  DateTime? _pendingTapAt;
  bool? _lastSeekBackward;
  DateTime? _lastSeekTapAt;
  double? _pinchStartDistance;
  double _trackpadPinchScale = 1.0;
  final Map<int, Offset> _activePinchPointers = <int, Offset>{};

  @override
  void dispose() {
    _chipTimer?.cancel();
    _singleTapTimer?.cancel();
    _pinchSuppressTimer?.cancel();
    if (_temporarySpeedActive) {
      unawaited(
        ref.read(playbackControllerProvider.notifier).endTemporarySpeed(),
      );
    }
    super.dispose();
  }

  bool _isTouchPointer(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      kind == PointerDeviceKind.unknown;

  void _cancelPendingTap() {
    _singleTapTimer?.cancel();
    _pendingTapBackward = null;
    _pendingTapAt = null;
    _lastSeekBackward = null;
    _lastSeekTapAt = null;
  }

  void _showChip(String text) {
    _chipTimer?.cancel();
    _seekChipAccum = Duration.zero;
    setState(() {
      _chip = text;
      _seekText = null;
    });
    _chipTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _chip = null);
    });
  }

  void _showSeekText(Duration delta, {required bool backward}) {
    _chipTimer?.cancel();
    _seekChipAccum += delta;
    final int seconds = _seekChipAccum.inSeconds.abs();
    final String sign;
    if (seconds == 0) {
      sign = '';
    } else {
      sign = _seekChipAccum.isNegative ? '-' : '+';
    }
    setState(() {
      _chip = null;
      _seekText = '$sign${seconds}s';
      _seekAlignment = backward
          ? const Alignment(-0.72, 0)
          : const Alignment(0.72, 0);
    });
    _chipTimer = Timer(const Duration(milliseconds: 900), () {
      _seekChipAccum = Duration.zero;
      if (mounted) setState(() => _seekText = null);
    });
  }

  void _startTemporarySpeed() {
    if (_temporarySpeedActive || _temporarySpeedPressing) return;
    _temporarySpeedPressing = true;
    unawaited(
      ref.read(playbackControllerProvider.notifier).beginTemporarySpeed().then((
        bool started,
      ) {
        if (!mounted || !started || !_temporarySpeedPressing) {
          if (started) {
            unawaited(
              ref.read(playbackControllerProvider.notifier).endTemporarySpeed(),
            );
          }
          return;
        }
        _temporarySpeedActive = true;
      }),
    );
  }

  void _endTemporarySpeed() {
    _temporarySpeedPressing = false;
    if (!_temporarySpeedActive) return;
    _temporarySpeedActive = false;
    unawaited(
      ref.read(playbackControllerProvider.notifier).endTemporarySpeed(),
    );
  }

  void _beginPinchGesture() {
    _pinchSuppressTimer?.cancel();
    _pinchActive = true;
    _pinchHandled = false;
    _suppressPointerGestures = true;
    _cancelPendingTap();
    _endTemporarySpeed();
  }

  void _endPinchGesture() {
    _pinchActive = false;
    _pinchHandled = false;
    _pinchStartDistance = null;
    _trackpadPinchScale = 1.0;
    _pinchSuppressTimer?.cancel();
    _pinchSuppressTimer = Timer(_pinchSuppressDelay, () {
      if (mounted) {
        _suppressPointerGestures = false;
      }
    });
  }

  double? _currentTouchPinchDistance() {
    if (_activePinchPointers.length < 2) return null;
    final Iterator<Offset> points = _activePinchPointers.values.iterator;
    points.moveNext();
    final Offset first = points.current;
    points.moveNext();
    return (points.current - first).distance;
  }

  void _handlePinchScale(double scale) {
    if (_pinchHandled) return;
    if (scale >= _pinchActivationScale) {
      _applyZoomGesture(zoomed: true);
    } else if (scale <= 1 / _pinchActivationScale) {
      _applyZoomGesture(zoomed: false);
    }
  }

  void _applyZoomGesture({required bool zoomed}) {
    _pinchHandled = true;
    if (widget.isZoomed != zoomed) {
      widget.onZoomChanged(zoomed);
    }
    _showChip(zoomed ? 'Zoom' : 'Normal');
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isTouchPointer(event.kind)) return;
    _activePinchPointers[event.pointer] = event.localPosition;
    if (_activePinchPointers.length == 2) {
      _pinchStartDistance = _currentTouchPinchDistance();
      _beginPinchGesture();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePinchPointers.containsKey(event.pointer)) return;
    _activePinchPointers[event.pointer] = event.localPosition;
    final double? startDistance = _pinchStartDistance;
    final double? currentDistance = _currentTouchPinchDistance();
    if (startDistance == null ||
        currentDistance == null ||
        startDistance < 16) {
      return;
    }
    _handlePinchScale(currentDistance / startDistance);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (!_activePinchPointers.containsKey(event.pointer)) return;
    _activePinchPointers.remove(event.pointer);
    if (_activePinchPointers.length >= 2) {
      _pinchStartDistance = _currentTouchPinchDistance();
      _pinchHandled = false;
      return;
    }
    if (_pinchActive) {
      _endPinchGesture();
    }
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadPinchScale = 1.0;
    _beginPinchGesture();
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _trackpadPinchScale = event.scale;
    _handlePinchScale(_trackpadPinchScale);
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (_pinchActive) {
      _endPinchGesture();
    }
  }

  void _performMobileSeek({required bool backward}) {
    final Duration delta = backward
        ? -widget.seekInterval
        : widget.seekInterval;
    ref
        .read(playbackControllerProvider.notifier)
        .seekBy(delta, flushDelay: Duration.zero);
    _lastSeekBackward = backward;
    _lastSeekTapAt = DateTime.now();
    _pendingTapBackward = null;
    _pendingTapAt = null;
    _showSeekText(delta, backward: backward);
  }

  void _handleMobileTap(TapUpDetails details) {
    if (_suppressPointerGestures) return;
    final double width = MediaQuery.sizeOf(context).width;
    final bool backward = details.localPosition.dx < width / 2;
    final DateTime now = DateTime.now();
    final DateTime? lastSeekAt = _lastSeekTapAt;
    final bool continuesSeek =
        _lastSeekBackward == backward &&
        lastSeekAt != null &&
        now.difference(lastSeekAt) <= _multiTapSeekWindow;
    if (continuesSeek) {
      _singleTapTimer?.cancel();
      _performMobileSeek(backward: backward);
      return;
    }

    final DateTime? pendingAt = _pendingTapAt;
    final bool completesDoubleTap =
        _pendingTapBackward == backward &&
        pendingAt != null &&
        now.difference(pendingAt) <= _singleTapDelay;
    if (completesDoubleTap) {
      _singleTapTimer?.cancel();
      _performMobileSeek(backward: backward);
      return;
    }

    _singleTapTimer?.cancel();
    _pendingTapBackward = backward;
    _pendingTapAt = now;
    _singleTapTimer = Timer(_singleTapDelay, () {
      _pendingTapBackward = null;
      _pendingTapAt = null;
      _lastSeekBackward = null;
      _lastSeekTapAt = null;
      if (mounted) widget.onTap();
    });
  }

  void _handleDesktopTap() {
    if (_suppressPointerGestures) return;
    widget.onTogglePlay();
  }

  void _handleDesktopDoubleTap() {
    if (_suppressPointerGestures) return;
    widget.onToggleFullscreen();
  }

  @override
  Widget build(BuildContext context) {
    // Long press is disabled when controls are visible so the gesture recognizer
    // doesn't enter the arena against the seek slider's drag recognizer (which
    // would cancel the slider drag after 500 ms hold).
    final bool controlsVisible = ref
        .watch(playbackControllerProvider)
        .controlsVisible;
    if (!widget.enableGestures) {
      // PiP mini-player: no player gestures — the child layer owns drag/resize.
      return widget.child;
    }
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      onPointerPanZoomStart: _handlePointerPanZoomStart,
      onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
      onPointerPanZoomEnd: _handlePointerPanZoomEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.isMobile ? null : _handleDesktopTap,
        onTapUp: widget.isMobile ? _handleMobileTap : null,
        onLongPressStart: controlsVisible
            ? null
            : (_) {
                if (!_suppressPointerGestures) {
                  _startTemporarySpeed();
                }
              },
        onLongPressEnd: controlsVisible ? null : (_) => _endTemporarySpeed(),
        onLongPressCancel: controlsVisible ? null : _endTemporarySpeed,
        onDoubleTap: widget.isMobile ? null : _handleDesktopDoubleTap,
        onHorizontalDragStart: (_) {
          if (_suppressPointerGestures) return;
          _hAccum = 0;
        },
        onHorizontalDragUpdate: (DragUpdateDetails d) {
          if (_suppressPointerGestures) return;
          _hAccum += d.delta.dx;
          final int secs = (_hAccum / 8).round() * 2;
          _showChip(secs >= 0 ? '+${secs}s' : '${secs}s');
        },
        onHorizontalDragEnd: (_) {
          if (_suppressPointerGestures) {
            _hAccum = 0;
            return;
          }
          final int secs = (_hAccum / 8).round() * 2;
          if (secs != 0) {
            ref
                .read(playbackControllerProvider.notifier)
                .seekBy(Duration(seconds: secs));
          }
          _hAccum = 0;
        },
        onVerticalDragStart: (DragStartDetails d) {
          if (_suppressPointerGestures) return;
          final double width = MediaQuery.sizeOf(context).width;
          _vRight = d.localPosition.dx > width / 2;
          _vAccum = 0;
          final PlayerEngine? ctrl = ref
              .read(playbackControllerProvider)
              .engine;
          _vStartVolume = ctrl?.value.volume ?? 1.0;
        },
        onVerticalDragUpdate: (DragUpdateDetails d) {
          if (_suppressPointerGestures || !_vRight) return;
          _vAccum -= d.delta.dy;
          final double height = MediaQuery.sizeOf(context).height;
          final double newVol = (_vStartVolume + _vAccum / height * 3).clamp(
            0.0,
            1.0,
          );
          ref.read(playbackControllerProvider.notifier).setVolume(newVol);
          _showChip('Vol ${(newVol * 100).round()}%');
        },
        onVerticalDragEnd: (_) {
          _vAccum = 0;
          _vRight = false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.child,
            if (_chip != null)
              Center(
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _chip!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            if (_seekText != null)
              Positioned.fill(
                child: Align(
                  alignment: _seekAlignment,
                  child: IgnorePointer(
                    child: Text(
                      _seekText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
