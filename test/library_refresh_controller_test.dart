import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/library_refresh_controller.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';

void main() {
  test(
    'gesture and button share work; lifecycle uses a per-kind freshness window',
    () async {
      var now = DateTime.utc(2026);
      final gate = Completer<TrackerLibrarySnapshot>();
      final calls = <(String, bool)>[];
      final refresh = LibraryRefreshController((kind, force) {
        calls.add((kind, force));
        return gate.future;
      }, now: () => now);
      final first = refresh.refresh('anime');
      expect(identical(first, refresh.refresh('anime')), isTrue);
      gate.complete(
        const TrackerLibrarySnapshot(folders: [], fromCache: false),
      );
      await first;
      await refresh.refresh('anime', force: false);
      expect(calls, [('anime', true)]);
      await refresh.refresh('manga', force: false);
      expect(calls.last, ('manga', false));
      now = now.add(const Duration(minutes: 1));
      await refresh.refresh('anime', force: false);
      expect(calls.length, 3);
      await refresh.refresh('anime');
      expect(calls.length, 4);
    },
  );

  test(
    'failed reads release the refresh and never mark cached data as fresh',
    () async {
      var calls = 0;
      final refresh = LibraryRefreshController((_, _) async {
        calls++;
        return const TrackerLibrarySnapshot(folders: [], fromCache: true);
      });
      for (var i = 0; i < 2; i++) {
        await expectLater(
          refresh.refresh('anime', force: false),
          throwsA(isA<LibraryRefreshUnavailable>()),
        );
      }
      expect(calls, 2);
    },
  );
}
