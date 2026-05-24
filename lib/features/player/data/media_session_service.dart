import 'dart:async';
import 'package:flutter/services.dart';

typedef MediaSessionSeekCallback = void Function(Duration position);

class MediaSessionService {
  MediaSessionService._();

  static const MethodChannel _ch = MethodChannel('mirushin/media_session');
  static bool _listening = false;

  static void Function()? _onPlay;
  static void Function()? _onPause;
  static void Function()? _onTogglePlay;
  static void Function()? _onNext;
  static MediaSessionSeekCallback? _onSeekTo;

  static void init({
    required void Function() onPlay,
    required void Function() onPause,
    required void Function() onTogglePlay,
    void Function()? onNext,
    MediaSessionSeekCallback? onSeekTo,
  }) {
    _onPlay = onPlay;
    _onPause = onPause;
    _onTogglePlay = onTogglePlay;
    _onNext = onNext;
    _onSeekTo = onSeekTo;
    if (!_listening) {
      _listening = true;
      _ch.setMethodCallHandler(_handleNativeCall);
    }
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'play':
        _onPlay?.call();
      case 'pause':
        _onPause?.call();
      case 'togglePlay':
        _onTogglePlay?.call();
      case 'next':
        _onNext?.call();
      case 'seekTo':
        final Object? arg = call.arguments;
        if (arg is int) _onSeekTo?.call(Duration(milliseconds: arg));
      case 'audioRouteChanged':
        if (call.arguments == true) _onPause?.call();
      case 'audioInterruption':
        if (call.arguments == true) _onPause?.call();
    }
  }

  static Future<void> updateNowPlaying({
    required String title,
    String subtitle = '',
    String artworkUrl = '',
    required Duration position,
    required Duration duration,
    required bool isPlaying,
    double playbackRate = 1.0,
    bool hasNext = false,
  }) async {
    try {
      await _ch.invokeMethod<void>('updateNowPlaying', <String, Object>{
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'isPlaying': isPlaying,
        'playbackRate': playbackRate,
        'hasNext': hasNext,
      });
    } on MissingPluginException {
      // Platform has no native implementation – skip silently.
    } on PlatformException {
      // Native error – skip silently.
    }
  }

  static Future<void> clearNowPlaying() async {
    try {
      await _ch.invokeMethod<void>('clearNowPlaying');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }
}
