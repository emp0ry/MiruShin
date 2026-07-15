import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/seek_settle.dart';

void main() {
  group('seekHasSettled', () {
    test('accepts positions within tolerance', () {
      expect(
        seekHasSettled(
          position: const Duration(milliseconds: 145800),
          target: const Duration(milliseconds: 145000),
          from: const Duration(seconds: 100),
          tolerance: const Duration(milliseconds: 1200),
        ),
        isTrue,
      );
    });

    test('accepts forward seeks after playback crosses the target', () {
      expect(
        seekHasSettled(
          position: const Duration(milliseconds: 146400),
          target: const Duration(milliseconds: 145000),
          from: const Duration(seconds: 90),
          tolerance: const Duration(milliseconds: 1200),
        ),
        isTrue,
      );
    });

    test('accepts forward seeks that land just before the target', () {
      expect(
        seekHasSettled(
          position: const Duration(milliseconds: 143000),
          target: const Duration(milliseconds: 145000),
          from: const Duration(seconds: 90),
          tolerance: const Duration(milliseconds: 1200),
          forwardTolerance: const Duration(milliseconds: 2500),
        ),
        isTrue,
      );
    });

    test(
      'does not accept backward seeks that keep playing after the target',
      () {
        expect(
          seekHasSettled(
            position: const Duration(milliseconds: 146400),
            target: const Duration(milliseconds: 145000),
            from: const Duration(seconds: 180),
            tolerance: const Duration(milliseconds: 1200),
            forwardTolerance: const Duration(milliseconds: 2500),
          ),
          isFalse,
        );
      },
    );

    test('does not accept out-of-range positions without a forward seek', () {
      expect(
        seekHasSettled(
          position: const Duration(milliseconds: 143400),
          target: const Duration(milliseconds: 145000),
          from: null,
          tolerance: const Duration(milliseconds: 1200),
        ),
        isFalse,
      );
    });
  });
}
