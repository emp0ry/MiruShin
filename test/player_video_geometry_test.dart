import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';

void main() {
  group('videoDisplayAspectRatio', () {
    test('applies non-square pixel aspect metadata', () {
      expect(
        videoDisplayAspectRatio(
          codedWidth: 640,
          codedHeight: 480,
          pixelAspectRatio: 4 / 3,
        ),
        closeTo(16 / 9, 0.0001),
      );
    });

    test('keeps ordinary square-pixel video unchanged', () {
      expect(
        videoDisplayAspectRatio(codedWidth: 1920, codedHeight: 1080),
        closeTo(16 / 9, 0.0001),
      );
    });

    test('accounts for video rotation', () {
      expect(
        videoDisplayAspectRatio(
          codedWidth: 1920,
          codedHeight: 1080,
          rotationDegrees: 90,
        ),
        closeTo(9 / 16, 0.0001),
      );
    });
  });
}
