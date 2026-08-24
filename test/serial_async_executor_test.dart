import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/utils/serial_async_executor.dart';

void main() {
  test('operations never overlap and retain submission order', () async {
    final SerialAsyncExecutor executor = SerialAsyncExecutor();
    final Completer<void> releaseFirst = Completer<void>();
    final List<String> events = <String>[];

    final Future<void> first = executor.run(() async {
      events.add('first-start');
      await releaseFirst.future;
      events.add('first-end');
    });
    final Future<void> second = executor.run(() async {
      events.add('second-start');
      events.add('second-end');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first-start']);

    releaseFirst.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(events, <String>[
      'first-start',
      'first-end',
      'second-start',
      'second-end',
    ]);
  });

  test('a failed operation does not poison later work', () async {
    final SerialAsyncExecutor executor = SerialAsyncExecutor();
    final Future<void> failed = executor.run(() async {
      throw StateError('expected failure');
    });
    final Future<int> next = executor.run(() async => 42);

    await expectLater(failed, throwsStateError);
    await expectLater(next, completion(42));
  });
}
