import 'package:flutter/services.dart';

/// The macOS window and Quit menu await this reply before destroying Flutter.
/// Install before opening any native database and retain it through cleanup.
class NativeExitHandshake {
  NativeExitHandshake({
    MethodChannel channel = const MethodChannel('mirushin/lifecycle'),
  }) : _channel = channel;

  final MethodChannel _channel;

  void attach(Future<void> Function() prepareForExit) {
    Future<void>? cleanup;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'prepareForExit') {
        throw MissingPluginException();
      }
      await (cleanup ??= prepareForExit());
      return true;
    });
  }

  void detach() => _channel.setMethodCallHandler(null);
}
