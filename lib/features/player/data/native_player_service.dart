import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class NativePlayerEvent {
  const NativePlayerEvent();
}

final class NativePlayerDismissed extends NativePlayerEvent {
  const NativePlayerDismissed({
    required this.positionMs,
    required this.durationMs,
    required this.wasPlaying,
  });
  final int positionMs;
  final int durationMs;
  final bool wasPlaying;
}

final class NativePlayerCompleted extends NativePlayerEvent {
  const NativePlayerCompleted({
    required this.positionMs,
    required this.durationMs,
  });
  final int positionMs;
  final int durationMs;
}

// Fires when the user exits PiP and the native player is restored to fullscreen.
// The native player is still running — only save progress, don't touch FVP.
final class NativePlayerPipRestored extends NativePlayerEvent {
  const NativePlayerPipRestored({
    required this.positionMs,
    required this.durationMs,
  });
  final int positionMs;
  final int durationMs;
}

class NativePlayerService {
  NativePlayerService._();

  static const MethodChannel _ch = MethodChannel('mirushin/native_player');
  static bool _active = false;
  static bool get isActive => _active;

  static final StreamController<NativePlayerEvent> _eventCtrl =
      StreamController<NativePlayerEvent>.broadcast();
  static Stream<NativePlayerEvent> get events => _eventCtrl.stream;

  // iOS/macOS use the OS-native AVPlayer PiP, which reuses a single player and
  // is rock solid. Windows/Linux used to spin up a *second* MDK video engine in
  // a floating window, which collided with the main mpv decoder on the GPU and
  // crashed; those platforms now use the window-resize mini-player in
  // DesktopPipController instead, so they are intentionally excluded here.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static void init() {
    _ch.setMethodCallHandler(_handleCall);
  }

  static Future<dynamic> _handleCall(MethodCall call) async {
    final Map<String, dynamic> args =
        (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    final int posMs =
        ((args['positionMs'] as num?)?.toDouble() ?? 0.0).round();
    final int durMs =
        ((args['durationMs'] as num?)?.toDouble() ?? 0.0).round();

    switch (call.method) {
      case 'dismissed':
        _active = false;
        _eventCtrl.add(NativePlayerDismissed(
          positionMs: posMs,
          durationMs: durMs,
          wasPlaying: args['wasPlaying'] as bool? ?? false,
        ));
      case 'completed':
        _active = false;
        _eventCtrl.add(NativePlayerCompleted(
          positionMs: posMs,
          durationMs: durMs,
        ));
      case 'pipRestored':
        // _active stays true — native player is still running
        _eventCtrl.add(NativePlayerPipRestored(
          positionMs: posMs,
          durationMs: durMs,
        ));
    }
  }

  static Future<void> present({
    required String url,
    required Map<String, String> headers,
    required int positionMs,
    required double playbackRate,
    required bool wasPlaying,
    required String title,
    int? openingStartMs,
    int? openingEndMs,
    int? endingStartMs,
    int? endingEndMs,
    bool autoSkipOpening = false,
    bool autoSkipEnding = false,
  }) async {
    if (_active) return;
    _active = true;
    try {
      await _ch.invokeMethod<void>('present', <String, Object?>{
        'url': url,
        'headers': headers,
        'positionMs': positionMs.toDouble(),
        'playbackRate': playbackRate,
        'wasPlaying': wasPlaying,
        'title': title,
        'openingStartMs': openingStartMs?.toDouble(),
        'openingEndMs': openingEndMs?.toDouble(),
        'endingStartMs': endingStartMs?.toDouble(),
        'endingEndMs': endingEndMs?.toDouble(),
        'autoSkipOpening': autoSkipOpening,
        'autoSkipEnding': autoSkipEnding,
      });
    } on PlatformException {
      _active = false;
      rethrow;
    } on MissingPluginException {
      _active = false;
      rethrow;
    }
  }
}
