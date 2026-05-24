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
  String? _chip;
  Timer? _chipTimer;
  Duration _seekChipAccum = Duration.zero;
  double _hAccum = 0;
  double _vAccum = 0;
  double _vStartVolume = 1.0;
  bool _vRight = false;
  bool _temporarySpeedActive = false;

  @override
  void dispose() {
    _chipTimer?.cancel();
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
    setState(() => _chip = text);
    _chipTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _chip = null);
    });
  }

  void _showSeekChip(Duration delta) {
    _chipTimer?.cancel();
    _seekChipAccum += delta;
    final int seconds = _seekChipAccum.inSeconds.abs();
    final String sign;
    if (seconds == 0) {
      sign = '';
    } else {
      sign = _seekChipAccum.isNegative ? '-' : '+';
    }
    setState(() => _chip = '$sign${seconds}s');
    _chipTimer = Timer(const Duration(milliseconds: 900), () {
      _seekChipAccum = Duration.zero;
      if (mounted) setState(() => _chip = null);
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isMobile ? widget.onTap : widget.onTogglePlay,
      onLongPressStart: (_) => _startTemporarySpeed(),
      onLongPressEnd: (_) => _endTemporarySpeed(),
      onLongPressCancel: _endTemporarySpeed,
      onDoubleTap: widget.isMobile ? null : widget.onToggleFullscreen,
      onDoubleTapDown: widget.isMobile
          ? (TapDownDetails details) {
              final double width = MediaQuery.sizeOf(context).width;
              final bool backward = details.localPosition.dx < width / 2;
              final Duration delta =
                  backward ? -widget.seekInterval : widget.seekInterval;
              ref.read(playbackControllerProvider.notifier).seekBy(delta);
              _showSeekChip(delta);
            }
          : null,
      onHorizontalDragStart: (_) => _hAccum = 0,
      onHorizontalDragUpdate: (DragUpdateDetails d) {
        _hAccum += d.delta.dx;
        final int secs = (_hAccum / 8).round();
        _showChip(secs >= 0 ? '+${secs}s' : '${secs}s');
      },
      onHorizontalDragEnd: (_) {
        final int secs = (_hAccum / 8).round();
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
        ],
      ),
    );
  }
}
