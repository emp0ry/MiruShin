import 'dart:io';

import 'package:media_kit/media_kit.dart' as mk;

class MediaKitRuntime {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    if (Platform.isLinux) {
      throw UnsupportedError(
        'MediaKit/mpv is disabled on Linux; use the FVP backend instead.',
      );
    }
    mk.MediaKit.ensureInitialized();
    _initialized = true;
  }
}
