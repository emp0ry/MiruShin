import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/player_buffer_ranges.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';

void main() {
  group('absolute buffer endpoints', () {
    test('never adds the playhead to an absolute endpoint', () {
      final range = rangesFromAbsoluteBufferEnd(
        position: const Duration(seconds: 600),
        bufferEnd: const Duration(seconds: 620),
        duration: Duration.zero,
      ).single;
      expect(range.start.inSeconds, 600);
      expect(range.end.inSeconds, 620);
    });
    test('missing, equal or behind endpoints clear forward cache', () {
      for (final end in [0, 598, 600]) {
        expect(
          rangesFromAbsoluteBufferEnd(
            position: const Duration(seconds: 600),
            bufferEnd: Duration(seconds: end),
            duration: const Duration(seconds: 1200),
          ),
          isEmpty,
        );
      }
    });
    test('clamps to known duration without inventing data at EOF', () {
      expect(
        rangesFromAbsoluteBufferEnd(
          position: const Duration(seconds: 1190),
          bufferEnd: const Duration(seconds: 1500),
          duration: const Duration(seconds: 1200),
        ).single.end.inSeconds,
        1200,
      );
      expect(
        rangesFromAbsoluteBufferEnd(
          position: const Duration(seconds: 1200),
          bufferEnd: const Duration(seconds: 1500),
          duration: const Duration(seconds: 1200),
        ),
        isEmpty,
      );
    });
  });

  test('equal native snapshots do not notify repeatedly', () {
    final notifier = ValueNotifier(const PlayerEngineState());
    addTearDown(notifier.dispose);
    int notifications = 0;
    notifier.addListener(() => notifications++);
    for (int i = 0; i < 100; i++) {
      notifier.value = notifier.value.copyWith(buffered: []);
    }
    expect(notifications, 0);
    notifier.value = notifier.value.copyWith(
      position: const Duration(seconds: 1),
    );
    notifier.value = notifier.value.copyWith(isBuffering: true);
    notifier.value = notifier.value.copyWith(isCompleted: true);
    expect(notifications, 3);
  });

  test('state equality includes every presentation and control field', () {
    const base = PlayerEngineState();
    for (final changed in [
      base.copyWith(position: const Duration(seconds: 1)),
      base.copyWith(duration: const Duration(seconds: 1)),
      base.copyWith(volume: 0.5),
      base.copyWith(playbackSpeed: 1.5),
      base.copyWith(aspectRatio: 1.5),
      base.copyWith(videoSize: const Size(10, 10)),
      base.copyWith(
        buffered: [
          const PlayerBufferedRange(
            start: Duration.zero,
            end: Duration(seconds: 1),
          ),
        ],
      ),
      base.copyWith(isInitialized: true),
      base.copyWith(isPlaying: true),
      base.copyWith(isBuffering: true),
      base.copyWith(isCompleted: true),
      base.copyWith(hasVideoSurface: true),
      base.copyWith(hasError: true),
      base.copyWith(errorDescription: 'error'),
    ]) {
      expect(changed, isNot(base));
    }
    final one = base.copyWith(
      buffered: [
        const PlayerBufferedRange(
          start: Duration.zero,
          end: Duration(seconds: 1),
        ),
      ],
    );
    final two = base.copyWith(
      buffered: [
        const PlayerBufferedRange(
          start: Duration.zero,
          end: Duration(seconds: 1),
        ),
      ],
    );
    expect(one, two);
    expect(one.hashCode, two.hashCode);
  });
}
