import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/auto_skip.dart';

void main() {
  test('autoSkipTarget triggers just before and during a skip window', () {
    const Duration duration = Duration(minutes: 24);
    const Duration start = Duration(seconds: 90);
    const Duration end = Duration(seconds: 180);

    expect(
      autoSkipTarget(
        enabled: true,
        start: start,
        end: end,
        position: const Duration(milliseconds: 89150),
        duration: duration,
      ),
      end,
    );

    expect(
      autoSkipTarget(
        enabled: true,
        start: start,
        end: end,
        position: const Duration(seconds: 100),
        duration: duration,
      ),
      end,
    );
  });

  test(
    'autoSkipTarget does not skip when disabled, too early, or already past',
    () {
      const Duration duration = Duration(minutes: 24);
      const Duration start = Duration(seconds: 90);
      const Duration end = Duration(seconds: 180);

      expect(
        autoSkipTarget(
          enabled: false,
          start: start,
          end: end,
          position: const Duration(seconds: 100),
          duration: duration,
        ),
        isNull,
      );
      expect(
        autoSkipTarget(
          enabled: true,
          start: start,
          end: end,
          position: const Duration(seconds: 88),
          duration: duration,
        ),
        isNull,
      );
      expect(
        autoSkipTarget(
          enabled: true,
          start: start,
          end: end,
          position: const Duration(seconds: 180),
          duration: duration,
        ),
        isNull,
      );
    },
  );
}
