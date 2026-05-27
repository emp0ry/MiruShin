import 'dart:async';

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
    required this.onToggleFullscreen,
    required this.onTogglePlay,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final Duration seekInterval;
  final bool isMobile;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onTogglePlay;

  @override
  ConsumerState<GestureOverlay> createState() => _GestureOverlayState();
}

class _GestureOverlayState extends ConsumerState<GestureOverlay> {
  static const Duration _singleTapDelay = Duration(milliseconds: 220);
  static const Duration _multiTapSeekWindow = Duration(milliseconds: 900);

  String? _chip;
  String? _seekText;
  Alignment _seekAlignment = Alignment.centerRight;
  Timer? _chipTimer;
  Timer? _singleTapTimer;
  Duration _seekChipAccum = Duration.zero;
  double _hAccum = 0;
  double _vAccum = 0;
  double _vStartVolume = 1.0;
  bool _vRight = false;
  bool _temporarySpeedActive = false;
  bool? _pendingTapBackward;
  DateTime? _pendingTapAt;
  bool? _lastSeekBackward;
  DateTime? _lastSeekTapAt;

  @override
  void dispose() {
    _chipTimer?.cancel();
    _singleTapTimer?.cancel();
    if (_temporarySpeedActive) {
      unawaited(
        ref.read(playbackControllerProvider.notifier).endTemporarySpeed(),
      );
    }
    super.dispose();
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
    if (_temporarySpeedActive) return;
    _temporarySpeedActive = true;
    unawaited(
      ref.read(playbackControllerProvider.notifier).beginTemporarySpeed(),
    );
  }

  void _endTemporarySpeed() {
    if (!_temporarySpeedActive) return;
    _temporarySpeedActive = false;
    unawaited(
      ref.read(playbackControllerProvider.notifier).endTemporarySpeed(),
    );
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isMobile ? null : widget.onTogglePlay,
      onTapUp: widget.isMobile ? _handleMobileTap : null,
      onLongPressStart: (_) => _startTemporarySpeed(),
      onLongPressEnd: (_) => _endTemporarySpeed(),
      onLongPressCancel: _endTemporarySpeed,
      onDoubleTap: widget.isMobile ? null : widget.onToggleFullscreen,
      onHorizontalDragStart: (_) => _hAccum = 0,
      onHorizontalDragUpdate: (DragUpdateDetails d) {
        _hAccum += d.delta.dx;
        final int secs = (_hAccum / 8).round() * 2;
        _showChip(secs >= 0 ? '+${secs}s' : '${secs}s');
      },
      onHorizontalDragEnd: (_) {
        final int secs = (_hAccum / 8).round() * 2;
        if (secs != 0) {
          ref
              .read(playbackControllerProvider.notifier)
              .seekBy(Duration(seconds: secs));
        }
        _hAccum = 0;
      },
      onVerticalDragStart: (DragStartDetails d) {
        final double width = MediaQuery.sizeOf(context).width;
        _vRight = d.localPosition.dx > width / 2;
        _vAccum = 0;
        final PlayerEngine? ctrl = ref.read(playbackControllerProvider).engine;
        _vStartVolume = ctrl?.value.volume ?? 1.0;
      },
      onVerticalDragUpdate: (DragUpdateDetails d) {
        if (!_vRight) return;
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
    );
  }
}
