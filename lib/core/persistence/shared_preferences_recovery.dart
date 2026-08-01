import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'shared_preferences_recovery_stub.dart'
    if (dart.library.io) 'shared_preferences_recovery_io.dart';

/// Initializes the app-wide preferences store without allowing a damaged or
/// unavailable persistence backend to prevent MiruShin from starting.
abstract final class MiruShinPreferences {
  static Future<SharedPreferences>? _initialization;
  static Future<bool> Function() _quarantine = quarantineCorruptPreferences;

  static Future<SharedPreferences> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<SharedPreferences> _initialize() async {
    try {
      return await SharedPreferences.getInstance();
    } on Object catch (error, stackTrace) {
      _logLoadFailure(error, stackTrace);

      if (_indicatesCorruptData(error)) {
        final bool quarantined = await _quarantine();
        if (quarantined) {
          final SharedPreferences? recovered = await _retryAfterRepair(
            'quarantining the corrupt preferences file',
          );
          if (recovered != null) return recovered;
        } else if (await _clearPlatformPreferences()) {
          final SharedPreferences? recovered = await _retryAfterRepair(
            'clearing corrupt platform preferences',
          );
          if (recovered != null) return recovered;
        }
      }

      return _useInMemoryFallback();
    }
  }

  static bool _indicatesCorruptData(Object error) {
    if (error is FormatException || error is TypeError) return true;

    // Method-channel backends can wrap the original parsing exception.
    final String message = error.toString().toLowerCase();
    return message.contains('formatexception') ||
        message.contains('unexpected character') ||
        message.contains('invalid json') ||
        message.contains('is not a subtype of');
  }

  static Future<bool> _clearPlatformPreferences() async {
    try {
      return await SharedPreferencesStorePlatform.instance.clear();
    } on Object catch (error, stackTrace) {
      debugPrint('Unable to clear corrupt SharedPreferences: $error');
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }

  static Future<SharedPreferences?> _retryAfterRepair(String repair) async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      debugPrint('SharedPreferences recovered after $repair.');
      return preferences;
    } on Object catch (error, stackTrace) {
      debugPrint('SharedPreferences still unavailable after $repair: $error');
      if (kDebugMode) {
        debugPrint(stackTrace.toString());
      }
      return null;
    }
  }

  static Future<SharedPreferences> _useInMemoryFallback() async {
    debugPrint(
      'Using session-only SharedPreferences so MiruShin can continue. '
      'Persistent preferences will be retried on the next launch.',
    );
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    return SharedPreferences.getInstance();
  }

  static void _logLoadFailure(Object error, StackTrace stackTrace) {
    debugPrint('Failed to load SharedPreferences: $error');
    if (kDebugMode) {
      debugPrint(stackTrace.toString());
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialization = null;
    _quarantine = quarantineCorruptPreferences;
  }

  @visibleForTesting
  static set quarantineForTesting(Future<bool> Function() quarantine) {
    _quarantine = quarantine;
  }
}
