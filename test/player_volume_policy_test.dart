import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_volume_policy.dart';

void main() {
  group('player volume policy', () {
    test('uses system-only volume on Android and iOS phones', () {
      expect(
        usesSystemVolumeOnly(
          isWeb: false,
          platform: TargetPlatform.android,
          isAndroidTv: false,
        ),
        isTrue,
      );
      expect(
        usesSystemVolumeOnly(
          isWeb: false,
          platform: TargetPlatform.iOS,
          isAndroidTv: false,
        ),
        isTrue,
      );
    });

    test('keeps player volume controls on desktop, web, and Android TV', () {
      expect(
        usesSystemVolumeOnly(
          isWeb: false,
          platform: TargetPlatform.macOS,
          isAndroidTv: false,
        ),
        isFalse,
      );
      expect(
        usesSystemVolumeOnly(
          isWeb: true,
          platform: TargetPlatform.android,
          isAndroidTv: false,
        ),
        isFalse,
      );
      expect(
        usesSystemVolumeOnly(
          isWeb: false,
          platform: TargetPlatform.android,
          isAndroidTv: true,
        ),
        isFalse,
      );
    });

    test('forces player output to 100 percent in system-only mode', () {
      expect(
        effectivePlayerOutputVolume(
          configuredVolume: 0.25,
          systemVolumeOnly: true,
        ),
        1,
      );
      expect(
        effectivePlayerOutputVolume(
          configuredVolume: 0.25,
          systemVolumeOnly: false,
        ),
        0.25,
      );
    });
  });
}
