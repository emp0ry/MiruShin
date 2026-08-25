import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'bootstrap/mirushin_fvp_bootstrap.dart';
import 'bootstrap/mirushin_media_kit_bootstrap.dart';
import 'core/constants/app_constants.dart';
import 'core/persistence/shared_preferences_recovery.dart';
import 'core/platform/single_instance_guard.dart';
import 'core/platform/tv_platform.dart';
import 'core/utils/settings_preferences.dart';
import 'features/settings/application/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bool isPrimaryInstance = await acquireMiruShinSingleInstanceLock();
  if (!isPrimaryInstance) {
    debugPrint('MiruShin is already running; exiting duplicate instance.');
    return;
  }
  await AppConstants.init();
  await TvPlatform.ensureInitialized();
  final SharedPreferences prefs = await MiruShinPreferences.initialize();
  final String initialRoute = await _loadInitialRoute(prefs);
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
  final bool Function(Object, StackTrace)? previousPlatformError =
      PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (_isRecoverableEmbeddedBrowserStartupError(error)) {
      debugPrint('Embedded browser startup failed safely: $error');
      return true;
    }
    return previousPlatformError?.call(error, stack) ?? false;
  };

  configureMiruShinMediaKit();
  configureMiruShinFvp();
  runApp(ProviderScope(child: MiruShinApp(initialRoute: initialRoute)));
}

bool _isRecoverableEmbeddedBrowserStartupError(Object error) {
  if (error is! PlatformException) return false;
  final String message = '${error.code} ${error.message ?? ''} $error'
      .toLowerCase();
  return message.contains('cannot create the inappwebview instance') ||
      message.contains('coinitialize has not been called');
}

Future<String> _loadInitialRoute(SharedPreferences preferences) async {
  final Object? storedRoute = preferences.get(
    SettingsPreferences.startupPageKey,
  );
  if (storedRoute != null && storedRoute is! String) {
    debugPrint(
      'Ignoring invalid startup-page preference of type '
      '${storedRoute.runtimeType}.',
    );
    await preferences.remove(SettingsPreferences.startupPageKey);
  }
  return AppStartupPage.fromName(
    storedRoute is String ? storedRoute : null,
  ).route;
}
