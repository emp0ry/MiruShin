import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Detects whether the app is running on an Android TV (leanback) device and
/// exposes the result to the widget tree.
///
/// The native side ([MainActivity]) answers a one-shot `isTelevision` call over
/// the `mirushin/device` method channel. We resolve it once during startup (see
/// [ensureInitialized]) so the value is available synchronously while building
/// the first frame — this avoids a layout flash between the phone and TV shells.
class TvPlatform {
  TvPlatform._();

  static const MethodChannel _channel = MethodChannel('mirushin/device');

  static bool _isAndroidTv = false;

  /// Whether the current device is an Android TV / leanback device.
  ///
  /// Always `false` until [ensureInitialized] has completed, and always
  /// `false` on non-Android platforms.
  static bool get isAndroidTv => _isAndroidTv;

  static bool get _isAndroidHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Resolves [isAndroidTv]. Call once before `runApp`. Safe (and a no-op) on
  /// every non-Android platform.
  static Future<void> ensureInitialized() async {
    if (!_isAndroidHost) {
      _isAndroidTv = false;
      return;
    }
    try {
      final bool? result = await _channel.invokeMethod<bool>('isTelevision');
      _isAndroidTv = result ?? false;
    } catch (_) {
      _isAndroidTv = false;
    }
  }
}

/// `true` when the app is running on an Android TV (leanback) device.
///
/// Resolved at startup, so reads are synchronous and stable for the whole
/// session. Override in tests via `ProviderScope(overrides: ...)`.
final Provider<bool> isAndroidTvProvider = Provider<bool>(
  (Ref ref) => TvPlatform.isAndroidTv,
);
