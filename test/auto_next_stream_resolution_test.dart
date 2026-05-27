import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/watch/application/watch_session.dart';

void main() {
  test('stale auto-next stream keys cannot consume current request state', () {
    final AutoNextStreamResolutionState state = AutoNextStreamResolutionState();

    state.begin('episode-1', autoNext: true);
    state.begin('episode-2', autoNext: false);

    expect(state.isCurrent('episode-1'), isFalse);
    expect(state.takeAutoNext('episode-1'), isTrue);
    expect(state.isCurrent('episode-2'), isTrue);
    expect(state.takeAutoNext('episode-2'), isFalse);
    expect(state.activeKey, isNull);
  });

  test('current auto-next request is consumed exactly once', () {
    final AutoNextStreamResolutionState state = AutoNextStreamResolutionState();

    state.begin('episode-3', autoNext: true);

    expect(state.isCurrent('episode-3'), isTrue);
    expect(state.takeAutoNext('episode-3'), isTrue);
    expect(state.takeAutoNext('episode-3'), isFalse);
    expect(state.activeKey, isNull);
  });
}
