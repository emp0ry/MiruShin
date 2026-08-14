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
}
