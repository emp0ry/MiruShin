import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/startup_seek.dart';

void main() {
  test('startup seek is skipped after playback reaches requested position', () {
    expect(
      startupSeekNeeded(
        requested: const Duration(seconds: 55),
        current: const Duration(seconds: 54),
      ),
      isFalse,
    );
    expect(
      startupSeekNeeded(
        requested: const Duration(seconds: 55),
        current: const Duration(seconds: 60),
      ),
      isFalse,
    );
  });

  test('startup seek remains necessary while playback is behind', () {
    expect(
      startupSeekNeeded(
        requested: const Duration(seconds: 130),
        current: const Duration(seconds: 25),
      ),
      isTrue,
    );
    expect(
      startupSeekNeeded(
        requested: Duration.zero,
        current: const Duration(seconds: 8),
      ),
      isFalse,
    );
  });
}
