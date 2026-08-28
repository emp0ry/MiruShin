import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/player/application/playback_controller.dart';
import 'package:mirushin/features/player/data/pip_controller.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/presentation/player_page.dart';
import 'package:mirushin/features/watch_party/application/watch_party_controller.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel windowChannel = MethodChannel('mirushin/window');

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.appLanguage': 'en',
      'mirushin.player.settings': jsonEncode(
        const PlayerSettings(autoplayNext: false).toJson(),
      ),
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  test('desktop continuation inherits the last actual fullscreen state', () {
    for (final ({bool routeStart, bool current}) scenario
        in <({bool routeStart, bool current})>[
          (routeStart: false, current: false),
          (routeStart: true, current: false),
          (routeStart: false, current: true),
          (routeStart: true, current: true),
        ]) {
      expect(
        playerContinuationStartsFullscreen(
          advancing: true,
          isMobile: false,
          currentFullscreen: scenario.current,
        ),
        scenario.current,
        reason:
            'routeStart=${scenario.routeStart} must not override '
            'current=${scenario.current}',
      );
    }
    expect(
      playerContinuationStartsFullscreen(
        advancing: false,
        isMobile: false,
        currentFullscreen: true,
      ),
      isFalse,
    );
    expect(
      playerContinuationStartsFullscreen(
        advancing: true,
        isMobile: true,
        currentFullscreen: false,
      ),
      isTrue,
      reason: 'mobile immersive continuation keeps its existing semantics',
    );
  });

  testWidgets(
    'release sequence carries start fullscreen through player exit and next result',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      bool nativeFullscreen = false;
      final Completer<bool> fullscreenSync = Completer<bool>();
      final List<bool> setFullscreenCalls = <bool>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
        MethodCall call,
      ) async {
        if (call.method == 'isFullscreen') return fullscreenSync.future;
        if (call.method == 'setFullscreen') {
          nativeFullscreen = call.arguments! as bool;
          setFullscreenCalls.add(nativeFullscreen);
          return nativeFullscreen;
        }
        return null;
      });
      final _FullscreenTestEngine engine = _FullscreenTestEngine();
      final _FullscreenTestPlaybackController controller =
          _FullscreenTestPlaybackController(_item, engine);
      Object? routeResult;
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                FilledButton(
                  onPressed: () async {
                    routeResult = await context.push<Object?>('/player');
                  },
                  child: const Text('Open player'),
                ),
          ),
          GoRoute(
            path: '/player',
            builder: (BuildContext context, GoRouterState state) =>
                const PlayerPage(item: _item, startInFullscreen: true),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(engine.disposeNotifier);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackControllerProvider.overrideWith(() => controller),
            watchPartyProvider.overrideWith(_IdleWatchPartyController.new),
            pipControllerProvider.overrideWithValue(
              const UnsupportedPipController(),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open player'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // The route started fullscreen, then the native window reported that it
      // had left fullscreen before the user advanced.
      expect(setFullscreenCalls, contains(true));
      nativeFullscreen = false;
      fullscreenSync.complete(false);
      await tester.pump();
      expect(nativeFullscreen, isFalse);

      controller.showAutoNext();
      await tester.pump();
      final Finder nextButton = find.widgetWithText(FilledButton, 'Next');
      expect(nextButton, findsOneWidget);
      tester.widget<FilledButton>(nextButton).onPressed!();
      await tester.pump(const Duration(milliseconds: 100));

      expect(routeResult, isA<PlayerNextEpisodeResult>());
      expect(
        (routeResult! as PlayerNextEpisodeResult).startInFullscreen,
        isFalse,
      );
      expect(controller.stopCalls, greaterThanOrEqualTo(1));
      expect(setFullscreenCalls, contains(true));
      await tester.pump(const Duration(seconds: 3));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('auto-next timer cannot start before confirmed end', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.appLanguage': 'en',
      'mirushin.player.settings': jsonEncode(
        const PlayerSettings(autoplayNext: true).toJson(),
      ),
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
      MethodCall call,
    ) async {
      if (call.method == 'isFullscreen' || call.method == 'setFullscreen') {
        return false;
      }
      return null;
    });

    final _FullscreenTestEngine engine = _FullscreenTestEngine();
    final _FullscreenTestPlaybackController controller =
        _FullscreenTestPlaybackController(_item, engine);
    Object? routeResult;
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => FilledButton(
            onPressed: () async {
              routeResult = await context.push<Object?>('/player');
            },
            child: const Text('Open player'),
          ),
        ),
        GoRoute(
          path: '/player',
          builder: (BuildContext context, GoRouterState state) =>
              const PlayerPage(item: _item),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(engine.disposeNotifier);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackControllerProvider.overrideWith(() => controller),
          watchPartyProvider.overrideWith(_IdleWatchPartyController.new),
          pipControllerProvider.overrideWithValue(
            const UnsupportedPipController(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();

    // Even an inconsistent state from a stale callback cannot start the timer
    // without the controller's confirmed-end latch.
    controller.showFalseAutoNext();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(routeResult, isNull);

    controller.showAutoNext();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4900));
    expect(find.byType(PlayerPage), findsOneWidget);
    controller.bumpPlaybackGeneration();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(routeResult, isNull);

    controller.showFalseAutoNext();
    await tester.pump();
    controller.showAutoNext();
    controller.showAutoNext();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(routeResult, isA<PlayerNextEpisodeResult>());
    expect(controller.markWatchedCalls, 1);
    expect(controller.stopCalls, 1);
    await tester.pump(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
  });
}

class _IdleWatchPartyController extends WatchPartyController {
  @override
  WatchPartyRoomState build() => WatchPartyRoomState.idle;
}

class _FullscreenTestPlaybackController extends PlaybackController {
  _FullscreenTestPlaybackController(this.item, this.engine);

  final MediaPlaybackItem item;
  final PlayerEngine engine;
  int stopCalls = 0;
  int markWatchedCalls = 0;
  int testPlaybackGeneration = 0;

  @override
  int get playbackGeneration => testPlaybackGeneration;

  @override
  PlaybackState build() => PlaybackState(
    item: item,
    engine: engine,
    server: item.servers.single,
    quality: StreamQuality.auto,
    controlsVisible: true,
    desiredPlaying: true,
  );

  void showAutoNext() {
    state = state.copyWith(autoNextVisible: true, confirmedEnded: true);
  }

  void showFalseAutoNext() {
    state = state.copyWith(autoNextVisible: true, confirmedEnded: false);
  }

  void bumpPlaybackGeneration() {
    testPlaybackGeneration += 1;
  }

  @override
  Future<void> load(MediaPlaybackItem item) async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> markCurrentEpisodeWatched() async {
    markWatchedCalls += 1;
  }

  @override
  void dismissAutoNext() {
    state = state.copyWith(autoNextVisible: false);
  }

  @override
  void setNextEpisodeHandler(void Function()? handler) {}
}

class _FullscreenTestEngine extends PlayerEngine {
  _FullscreenTestEngine()
    : _state = ValueNotifier<PlayerEngineState>(
        const PlayerEngineState(
          position: Duration(minutes: 20),
          duration: Duration(minutes: 24),
          isInitialized: true,
          isPlaying: true,
          hasVideoSurface: true,
        ),
      );

  final ValueNotifier<PlayerEngineState> _state;

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = false,
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

  void disposeNotifier() => _state.dispose();
}

const MediaPlaybackItem _item = MediaPlaybackItem(
  id: 'episode-1',
  title: 'Release transition test',
  mediaType: MediaType.anime,
  servers: <MediaServer>[
    MediaServer(
      id: 'server',
      name: 'Server',
      sourceName: 'Test',
      url: 'https://example.invalid/video.m3u8',
      streamType: StreamType.hls,
    ),
  ],
  seasons: <Season>[
    Season(
      number: 1,
      title: 'Season 1',
      episodes: <Episode>[Episode(id: '1_1', number: 1, title: 'Episode 1')],
    ),
  ],
  currentEpisodeId: '1_1',
  seasonNumber: 1,
  episodeNumber: 1,
);
