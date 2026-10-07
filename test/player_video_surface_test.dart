import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/presentation/widgets/player_video_surface.dart';

void main() {
  Widget surface(
    _TestEngine? engine, {
    bool stretch = false,
    bool fill = false,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: PlayerVideoSurface(
      controller: engine,
      stretchVertical: stretch,
      fillSurface: fill,
    ),
  );

  testWidgets('clock and buffer ticks retain layout and native surface', (
    tester,
  ) async {
    final engine = _TestEngine();
    addTearDown(engine.notifier.dispose);
    await tester.pumpWidget(surface(engine));
    final layout = tester.widget<AspectRatio>(find.byType(AspectRatio));
    final video = tester.widget(find.byKey(engine.surfaceKey));

    for (int tick = 1; tick <= 20; tick++) {
      engine.notifier.value = engine.value.copyWith(
        position: Duration(milliseconds: tick * 120),
        buffered: [
          PlayerBufferedRange(
            start: Duration(milliseconds: tick * 120),
            end: const Duration(seconds: 30),
          ),
        ],
        isPlaying: tick.isEven,
        isBuffering: tick.isOdd,
      );
      await tester.pump();
      expect(tester.widget(find.byType(AspectRatio)), same(layout));
      expect(tester.widget(find.byKey(engine.surfaceKey)), same(video));
    }
    expect(engine.surfaceBuilds, 1);

    engine.notifier.value = engine.value.copyWith(
      aspectRatio: 4 / 3,
      videoSize: const Size(1440, 1080),
    );
    await tester.pump();
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      4 / 3,
    );
    expect(tester.widget(find.byKey(engine.surfaceKey)), same(video));
    expect(engine.surfaceBuilds, 1);
    await tester.pumpWidget(const SizedBox());
    expect(engine.listeners, 0);
  });

  testWidgets(
    'initialization, replacement and disposal keep listeners scoped',
    (tester) async {
      final old = _TestEngine(initialized: false);
      final replacement = _TestEngine();
      addTearDown(old.notifier.dispose);
      addTearDown(replacement.notifier.dispose);
      await tester.pumpWidget(surface(old));
      expect(find.byKey(old.surfaceKey), findsNothing);
      expect(old.listeners, 1);
      old.notifier.value = old.value.copyWith(isInitialized: true);
      await tester.pump();
      expect(find.byKey(old.surfaceKey), findsOneWidget);

      await tester.pumpWidget(surface(replacement));
      expect(old.listeners, 0);
      expect(replacement.listeners, 1);
      old.notifier.value = old.value.copyWith(isInitialized: false);
      await tester.pump();
      expect(find.byKey(replacement.surfaceKey), findsOneWidget);

      await tester.pumpWidget(surface(null));
      expect(replacement.listeners, 0);
      replacement.notifier.value = replacement.value.copyWith(
        isInitialized: false,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stretch and trailer fill retain their original fitting modes', (
    tester,
  ) async {
    final engine = _TestEngine();
    addTearDown(engine.notifier.dispose);
    await tester.pumpWidget(surface(engine, stretch: true));
    expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.cover);
    expect(find.byType(AspectRatio), findsNothing);
    await tester.pumpWidget(surface(engine, fill: true));
    expect(find.byType(FittedBox), findsNothing);
    expect(find.byType(AspectRatio), findsNothing);
    expect(find.byKey(engine.surfaceKey), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _TestEngine extends PlayerEngine {
  _TestEngine({bool initialized = true})
    : notifier = ValueNotifier(
        PlayerEngineState(
          isInitialized: initialized,
          videoSize: const Size(1920, 1080),
        ),
      );

  final ValueNotifier<PlayerEngineState> notifier;
  final surfaceKey = UniqueKey();
  int listeners = 0;
  int surfaceBuilds = 0;

  @override
  ValueListenable<PlayerEngineState> get state => notifier;
  @override
  void addListener(VoidCallback listener) {
    listeners++;
    notifier.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    notifier.removeListener(listener);
  }

  @override
  Widget buildVideoSurface(BuildContext context) {
    surfaceBuilds++;
    return SizedBox(key: surfaceKey);
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setPlaybackSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}
