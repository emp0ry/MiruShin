import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_models.dart';

void main() {
  group('PlayerSettings horizontal swipe seeking', () {
    test('stays enabled when loading settings saved by an older version', () {
      final PlayerSettings settings = PlayerSettings.fromJson(
        const <String, Object?>{},
      );

      expect(settings.horizontalSwipeSeekEnabled, isTrue);
    });

    test('round-trips a disabled preference', () {
      final PlayerSettings disabled = const PlayerSettings().copyWith(
        horizontalSwipeSeekEnabled: false,
      );
      final PlayerSettings restored = PlayerSettings.fromJson(
        disabled.toJson(),
      );

      expect(restored.horizontalSwipeSeekEnabled, isFalse);
    });
  });

  group('PlayerSettings seek preview mode', () {
    test('keeps progress previews enabled for existing users', () {
      final PlayerSettings settings = PlayerSettings.fromJson(
        const <String, Object?>{},
      );

      expect(settings.seekPreviewsEnabled, isTrue);
    });

    test('round-trips a disabled progress preview preference', () {
      final PlayerSettings restored = PlayerSettings.fromJson(
        const PlayerSettings(seekPreviewsEnabled: false).toJson(),
      );

      expect(restored.seekPreviewsEnabled, isFalse);
    });

    test('defaults older settings to progressive timeline generation', () {
      final PlayerSettings settings = PlayerSettings.fromJson(
        const <String, Object?>{},
      );

      expect(settings.seekPreviewMode, SeekPreviewMode.progressive);
    });

    test('round-trips the existing on-demand behavior', () {
      final PlayerSettings restored = PlayerSettings.fromJson(
        const PlayerSettings(
          seekPreviewMode: SeekPreviewMode.onDemand,
        ).toJson(),
      );

      expect(restored.seekPreviewMode, SeekPreviewMode.onDemand);
    });
  });

  group('PlayerSettings volume memory', () {
    test('migrates an older audible volume into the unmute value', () {
      final PlayerSettings settings = PlayerSettings.fromJson(
        const <String, Object?>{'volume': 0.37},
      );

      expect(settings.volume, 0.37);
      expect(settings.lastAudibleVolume, 0.37);
    });

    test('round-trips current and last audible volumes independently', () {
      final PlayerSettings restored = PlayerSettings.fromJson(
        const PlayerSettings(volume: 0, lastAudibleVolume: 0.42).toJson(),
      );

      expect(restored.volume, 0);
      expect(restored.lastAudibleVolume, 0.42);
    });
  });

  group('Player backend availability', () {
    test('Linux hides MPV because this build does not support it there', () {
      expect(
        availablePlayerBackends(platform: TargetPlatform.linux),
        const <PlayerBackend>[PlayerBackend.auto, PlayerBackend.fvp],
      );
    });

    test('Windows keeps MPV available', () {
      expect(
        availablePlayerBackends(platform: TargetPlatform.windows),
        PlayerBackend.values,
      );
    });
  });
}
