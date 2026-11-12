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

  testWidgets('UI timeout keeps one queued read and accepts its late result', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<TrackerLibrarySnapshot>();
    final refresh = LibraryRefreshController((_, _) {
      calls++;
      return gate.future;
    }, now: tester.binding.clock.now);
    final first = refresh.refresh('anime');
    expect(identical(first, refresh.refresh('anime')), isTrue);
    final failure = expectLater(first, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 30));
    await failure;

    final retry = refresh.refresh('anime');
    await tester.pump();
    expect(calls, 1, reason: 'Retry joins the existing queued source read');
    gate.complete(const TrackerLibrarySnapshot(folders: [], fromCache: false));
    await tester.pump();
    await retry;
    await refresh.refresh('anime', force: false);
    expect(calls, 1, reason: 'A late successful result is still fresh');
    await refresh.refresh('anime');
    expect(
      calls,
      2,
      reason: 'Manual refresh can start after the read finishes',
    );
  });

  testWidgets('late failure after timeout releases work for the next attempt', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<TrackerLibrarySnapshot>();
    final refresh = LibraryRefreshController((_, _) {
      calls++;
      return calls == 1
          ? gate.future
          : Future.value(
              const TrackerLibrarySnapshot(folders: [], fromCache: false),
            );
    });
    final failure = expectLater(
      refresh.refresh('anime'),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 30));
    await failure;
    gate.completeError(StateError('late source failure'));
    await tester.pump();
    await refresh.refresh('anime');
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
