import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'bootstrap/mirushin_fvp_bootstrap.dart';
import 'core/constants/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConstants.init();
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
  configureMiruShinFvp();
  runApp(const ProviderScope(child: MiruShinApp()));
}
