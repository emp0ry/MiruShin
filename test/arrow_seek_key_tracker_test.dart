import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/presentation/player_page.dart';

void main() {
  group('ArrowSeekKeyTracker', () {
    test('short tap seeks exactly once on release', () {
      final ArrowSeekKeyTracker tracker = ArrowSeekKeyTracker();

      expect(tracker.handle(1, ArrowSeekKeyPhase.down), isNull);
      expect(tracker.handle(1, ArrowSeekKeyPhase.up), 1);
    });

    test('hold starts seeking with repeats and adds nothing on release', () {
      final ArrowSeekKeyTracker tracker = ArrowSeekKeyTracker();
      final List<int> seeks = <int>[];

      final int? initial = tracker.handle(1, ArrowSeekKeyPhase.down);
      if (initial != null) seeks.add(initial);
      for (int i = 0; i < 3; i += 1) {
        final int? repeated = tracker.handle(1, ArrowSeekKeyPhase.repeat);
        if (repeated != null) seeks.add(repeated);
      }
      final int? released = tracker.handle(1, ArrowSeekKeyPhase.up);
      if (released != null) seeks.add(released);

      expect(seeks, <int>[1, 1, 1]);
    });

    test('rapid taps remain independent seeks', () {
      final ArrowSeekKeyTracker tracker = ArrowSeekKeyTracker();
      final List<int> seeks = <int>[];

      for (int i = 0; i < 3; i += 1) {
        expect(tracker.handle(-1, ArrowSeekKeyPhase.down), isNull);
        final int? released = tracker.handle(-1, ArrowSeekKeyPhase.up);
        if (released != null) seeks.add(released);
      }

      expect(seeks, <int>[-1, -1, -1]);
    });

    test('reset prevents a stale release from seeking', () {
      final ArrowSeekKeyTracker tracker = ArrowSeekKeyTracker();

      expect(tracker.handle(1, ArrowSeekKeyPhase.down), isNull);
      tracker.reset();

      expect(tracker.handle(1, ArrowSeekKeyPhase.up), isNull);
    });
  });
}
