import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Desktop Picture-in-Picture via the existing `mirushin/window` method channel.
///
/// When the user enters PiP the main Flutter window is resized to a small
/// always-on-top tile and moved to the bottom-right corner of the screen.
/// The existing FVP engine keeps playing — no second player is created.
/// Exiting PiP restores the saved window bounds and clears the always-on-top
/// flag.
class DesktopPipService {
  DesktopPipService._();

  static const MethodChannel _ch = MethodChannel('mirushin/window');

  static bool _active = false;

  // Outer window rect (x, y, width, height) saved before entering PiP.
  static Map<String, dynamic>? _savedRect;

  static final StreamController<bool> _events =
      StreamController<bool>.broadcast();

  /// Fires true when entering PiP, false when exiting.
  static Stream<bool> get events => _events.stream;

  /// PiP is supported on Windows and Linux desktop builds.
  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  static bool get isActive => _active;

  // PiP window outer dimensions sent to the native layer.
  // On Windows these are physical screen pixels; on Linux GTK logical pixels.
  // Either way a 640 × 400 outer frame gives a comfortable 16:9 video area.
  static const int _pipW = 640;
  static const int _pipH = 400;

  /// Shrink the main window to a small always-on-top overlay.
  static Future<void> enter() async {
    if (_active || !isSupported) return;
    try {
      final Map<Object?, Object?>? raw =
          await _ch.invokeMapMethod<Object?, Object?>('getWindowRect');
      if (raw != null) {
        _savedRect = raw.map(
          (k, v) => MapEntry<String, dynamic>(k.toString(), v),
        );
      }
      await _ch.invokeMethod<void>(
        'setWindowSize',
        <String, int>{'width': _pipW, 'height': _pipH},
      );
      await _ch.invokeMethod<void>('moveToCorner');
      await _ch.invokeMethod<void>('setAlwaysOnTop', true);
      _active = true;
      _events.add(true);
    } on PlatformException {
      // Channel method not available on this build — ignore.
    }
  }

  /// Restore the window to its pre-PiP bounds.
  static Future<void> exit() async {
    if (!_active || !isSupported) return;
    try {
      await _ch.invokeMethod<void>('setAlwaysOnTop', false);
      final Map<String, dynamic>? saved = _savedRect;
      if (saved != null) {
        await _ch.invokeMethod<void>('setWindowRect', saved);
        _savedRect = null;
      }
    } on PlatformException {
      // Ignore.
    } finally {
      _active = false;
      _events.add(false);
    }
  }
}
