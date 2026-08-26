import 'package:flutter/services.dart';

class PlayerFullscreenTransfer {
  const PlayerFullscreenTransfer._();

  static const MethodChannel _windowChannel = MethodChannel('mirushin/window');

  /// Restores ordinary page chrome when an intended player-to-player advance
  /// cannot produce another player route.
  static Future<void> exitToPage() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await _windowChannel.invokeMethod<bool>('setFullscreen', false);
    } on MissingPluginException {
      // Non-desktop platforms only need the SystemChrome call above.
    } on PlatformException {
      // The native window may already have left fullscreen mode.
    }
  }
}
