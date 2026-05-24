import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final defaultFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String message = details.exceptionAsString();
    if (message.contains('A KeyDownEvent is dispatched') &&
        message.contains('physical key is already pressed')) {
      debugPrint('Suppressed duplicate hardware key-down event from macOS.');
      return;
    }
    if (message.contains('A KeyUpEvent is dispatched') &&
        message.contains('physical key is not pressed')) {
      debugPrint('Suppressed duplicate hardware key-up event from macOS.');
      return;
    }
    if (defaultFlutterError != null) {
      defaultFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  fvp.registerWith(
    options: const <String, Object>{
      'fastSeek': false,
      'player': <String, String>{
        'buffer': '3000+60000',
        'demux.buffer.ranges': '8',
        'demux.buffer.protocols': 'file,http,https',
      },
    },
  );
  runApp(const ProviderScope(child: MiruShinApp()));
}
