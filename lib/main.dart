import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'bootstrap/mirushin_fvp_bootstrap.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/settings_preferences.dart';
import 'features/settings/presentation/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConstants.init();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String initialRoute = AppStartupPage.fromName(
    prefs.getString(SettingsPreferences.startupPageKey),
  ).route;
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
  // NOTE: MediaKit/mpv is NOT initialized here. It is initialized lazily in
  // MediaKitPlayerEngine the first time a player is created, so libmpv is never
  // loaded while only browsing/searching. Eager init at startup loaded mpv into
  // the process and deterministically crashed the flutter_js QuickJS addon
  // runtime on Linux.
  configureMiruShinFvp();
  runApp(ProviderScope(child: MiruShinApp(initialRoute: initialRoute)));
}
