import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/tv_platform.dart';

abstract class PipController {
  bool get isSupported;
  bool get isInPipMode;
  Stream<bool> get pipModeStream;

  Future<void> enter({
    double aspectRatio = 16 / 9,
    bool isPlaying = true,
    bool hasNext = false,
  });

  Future<void> updateParams({required bool isPlaying, required bool hasNext});

  Future<void> bringToForeground();

  /// Begin an OS-driven move of the mini-player window (desktop PiP only).
  Future<void> startWindowMove() async {}

  /// Current window rect in physical pixels, or null if unavailable.
  Future<({double x, double y, double width, double height})?>
  windowPhysicalRect() async => null;

  /// Move + resize the mini-player window (physical pixels). Desktop PiP only.
  Future<void> setWindowPhysicalRect(
    double x,
    double y,
    double width,
    double height,
  ) async {}

  void dispose();
}

// ── Unsupported stub ────────────────────────────────────────────────────────

class UnsupportedPipController implements PipController {
  const UnsupportedPipController();

  @override
  bool get isSupported => false;

  @override
  bool get isInPipMode => false;

  @override
  Stream<bool> get pipModeStream => const Stream<bool>.empty();

  @override
  Future<void> enter({
    double aspectRatio = 16 / 9,
    bool isPlaying = true,
    bool hasNext = false,
  }) async {}

  @override
  Future<void> updateParams({
    required bool isPlaying,
    required bool hasNext,
  }) async {}

  @override
  Future<void> bringToForeground() async {}

  @override
  Future<void> startWindowMove() async {}

  @override
  Future<({double x, double y, double width, double height})?>
  windowPhysicalRect() async => null;

  @override
  Future<void> setWindowPhysicalRect(
    double x,
    double y,
    double width,
    double height,
  ) async {}

  @override
  void dispose() {}
}

// ── Android implementation ──────────────────────────────────────────────────

class AndroidPipController implements PipController {
  static const MethodChannel _ch = MethodChannel('mirushin/pip');

  final StreamController<bool> _pipModeCtrl =
      StreamController<bool>.broadcast();
  bool _inPip = false;

  AndroidPipController() {
    _ch.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'pipModeChanged') {
        _inPip = call.arguments == true;
        _pipModeCtrl.add(_inPip);
      }
    });
  }

  // Picture-in-Picture is intentionally disabled on Android TV: the leanback
  // experience is full-screen and a floating PiP window is undesirable there.
  // Regular Android phones/tablets keep PiP.
  @override
  bool get isSupported => !TvPlatform.isAndroidTv;

  @override
  bool get isInPipMode => _inPip;

  @override
  Stream<bool> get pipModeStream => _pipModeCtrl.stream;

  @override
  Future<void> enter({
    double aspectRatio = 16 / 9,
    bool isPlaying = true,
    bool hasNext = false,
  }) async {
    if (TvPlatform.isAndroidTv) return;
    // Clamp to Android's valid Rational range (1–239 for both w/h).
    // We express the ratio as (ratio*100 / 100) to get integer numerator/denom.
    final int w = (aspectRatio * 100).round().clamp(1, 23900);
    const int h = 100;
    try {
      await _ch.invokeMethod<void>('enter', <String, Object>{
        'ratioW': w,
        'ratioH': h,
        'isPlaying': isPlaying,
        'hasNext': hasNext,
      });
    } on PlatformException {
      // Silently ignore – PiP not available or denied.
    }
  }

  @override
  Future<void> updateParams({
    required bool isPlaying,
    required bool hasNext,
  }) async {
    try {
      await _ch.invokeMethod<void>('updateParams', <String, Object>{
        'isPlaying': isPlaying,
        'hasNext': hasNext,
      });
    } on PlatformException {
      // Ignore.
    }
  }

  @override
  Future<void> bringToForeground() async {
    try {
      await _ch.invokeMethod<void>('bringToForeground');
    } on PlatformException {
      // Ignore.
    }
  }

  @override
  Future<void> startWindowMove() async {}

  @override
  Future<({double x, double y, double width, double height})?>
  windowPhysicalRect() async => null;

  @override
  Future<void> setWindowPhysicalRect(
    double x,
    double y,
    double width,
    double height,
  ) async {}

  @override
  void dispose() {
    _pipModeCtrl.close();
  }
}

// ── Desktop (Windows) implementation ────────────────────────────────────────
//
// There is no OS-level PiP on Windows, so instead of spinning up a
// second video engine, we shrink the *main* application window into a small
// always-on-top "mini player". The same current engine keeps decoding —
// exactly like OS PiP reuses the one player. All window manipulation goes
// through the existing `mirushin/window` MethodChannel implemented natively.

class DesktopPipController implements PipController {
  static const MethodChannel _win = MethodChannel('mirushin/window');

  // Mini-player width in logical/device pixels; height derives from aspect.
  static const int _miniWidth = 480;

  final StreamController<bool> _pipModeCtrl =
      StreamController<bool>.broadcast();
  bool _inPip = false;

  // Saved window state to restore on exit.
  Map<String, int>? _savedRect;
  bool _wasFullscreen = false;

  @override
  bool get isSupported => true;

  @override
  bool get isInPipMode => _inPip;

  @override
  Stream<bool> get pipModeStream => _pipModeCtrl.stream;

  @override
  Future<void> enter({
    double aspectRatio = 16 / 9,
    bool isPlaying = true,
    bool hasNext = false,
  }) async {
    if (_inPip) return;
    try {
      // Leave fullscreen first; a fullscreen window cannot be made small.
      _wasFullscreen = await _win.invokeMethod<bool>('isFullscreen') ?? false;
      if (_wasFullscreen) {
        await _win.invokeMethod<void>('setFullscreen', false);
      }

      // Remember where the window was so we can put it back.
      final Map<Object?, Object?>? rect = await _win
          .invokeMethod<Map<Object?, Object?>>('getWindowRect');
      if (rect != null) {
        _savedRect = <String, int>{
          'x': (rect['x'] as num?)?.toInt() ?? 0,
          'y': (rect['y'] as num?)?.toInt() ?? 0,
          'width': (rect['width'] as num?)?.toInt() ?? _miniWidth,
          'height': (rect['height'] as num?)?.toInt() ?? 270,
        };
      }

      // Strip the title bar / window frame first so the mini-player is a clean
      // borderless video surface, then size it to the client area.
      await _win.invokeMethod<void>('setBorderless', true);

      final double ar = aspectRatio > 0 ? aspectRatio : 16 / 9;
      final int miniHeight = (_miniWidth / ar).round().clamp(160, 2160);
      await _win.invokeMethod<void>('setWindowSize', <String, int>{
        'width': _miniWidth,
        'height': miniHeight,
      });
      await _win.invokeMethod<void>('moveToCorner');
      await _win.invokeMethod<void>('setAlwaysOnTop', true);

      _inPip = true;
      _pipModeCtrl.add(true);
    } on PlatformException {
      // Window manipulation unavailable — stay in normal mode.
    } on MissingPluginException {
      // Channel not wired on this platform.
    }
  }

  @override
  Future<void> updateParams({
    required bool isPlaying,
    required bool hasNext,
  }) async {
    // Desktop mini-player has no separate OS control surface to update.
  }

  @override
  Future<void> bringToForeground() async {
    if (!_inPip) return;
    try {
      await _win.invokeMethod<void>('setAlwaysOnTop', false);
      // Restore the title bar / window frame before putting the window back.
      await _win.invokeMethod<void>('setBorderless', false);
      final Map<String, int>? rect = _savedRect;
      if (rect != null) {
        await _win.invokeMethod<void>('setWindowRect', rect);
      }
      if (_wasFullscreen) {
        await _win.invokeMethod<void>('setFullscreen', true);
      }
    } on PlatformException {
      // Ignore — best effort restore.
    } on MissingPluginException {
      // Ignore.
    } finally {
      _savedRect = null;
      _wasFullscreen = false;
      _inPip = false;
      _pipModeCtrl.add(false);
    }
  }

  @override
  Future<void> startWindowMove() async {
    if (!_inPip) return;
    try {
      await _win.invokeMethod<void>('startWindowDrag');
    } on PlatformException {
      // Ignore — best effort.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  Future<({double x, double y, double width, double height})?>
  windowPhysicalRect() async {
    try {
      final Map<Object?, Object?>? rect = await _win
          .invokeMethod<Map<Object?, Object?>>('getWindowRect');
      if (rect == null) return null;
      final double x = (rect['x'] as num?)?.toDouble() ?? 0;
      final double y = (rect['y'] as num?)?.toDouble() ?? 0;
      final double w = (rect['width'] as num?)?.toDouble() ?? 0;
      final double h = (rect['height'] as num?)?.toDouble() ?? 0;
      if (w <= 0 || h <= 0) return null;
      return (x: x, y: y, width: w, height: h);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> setWindowPhysicalRect(
    double x,
    double y,
    double width,
    double height,
  ) async {
    if (!_inPip) return;
    try {
      await _win.invokeMethod<void>('setWindowRect', <String, int>{
        'x': x.round(),
        'y': y.round(),
        'width': width.round().clamp(240, 7680),
        'height': height.round().clamp(135, 4320),
      });
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  @override
  void dispose() {
    _pipModeCtrl.close();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final Provider<PipController> pipControllerProvider = Provider<PipController>((
  Ref ref,
) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final AndroidPipController ctrl = AndroidPipController();
    ref.onDispose(ctrl.dispose);
    return ctrl;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    final DesktopPipController ctrl = DesktopPipController();
    ref.onDispose(ctrl.dispose);
    return ctrl;
  }
  return const UnsupportedPipController();
});
