import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class PipController {
  bool get isSupported;
  bool get isInPipMode;
  Stream<bool> get pipModeStream;

  Future<void> enter({
    double aspectRatio = 16 / 9,
    bool isPlaying = true,
    bool hasNext = false,
  });

  Future<void> updateParams({
    required bool isPlaying,
    required bool hasNext,
  });

  Future<void> bringToForeground();
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
  void dispose() {
    _pipModeCtrl.close();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final Provider<PipController> pipControllerProvider =
    Provider<PipController>((Ref ref) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final AndroidPipController ctrl = AndroidPipController();
    ref.onDispose(ctrl.dispose);
    return ctrl;
  }
  return const UnsupportedPipController();
});
