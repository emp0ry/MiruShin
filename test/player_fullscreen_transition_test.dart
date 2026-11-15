import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/player/application/playback_controller.dart';
import 'package:mirushin/features/player/application/player_settings.dart';
import 'package:mirushin/features/player/data/pip_controller.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/presentation/player_page.dart';
import 'package:mirushin/features/player/presentation/widgets/player_video_surface.dart';
import 'package:mirushin/features/watch_party/application/watch_party_controller.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel windowChannel = MethodChannel('mirushin/window');
  const MethodChannel nativePlayerChannel = MethodChannel(
    'mirushin/native_player',
  );

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

  test('timeline hover and drag ownership are released independently', () {
    int activeChanges = 0;
    final TimelineInteractionTracker tracker = TimelineInteractionTracker(
      () => activeChanges += 1,
    );
    final Object hoverOwner = Object();
    final Object dragOwner = Object();

    tracker.setHovered(hoverOwner, true);
    tracker.setDragging(dragOwner, true);
    expect(tracker.isHovered, isTrue);
    expect(tracker.isDragging, isTrue);
    expect(tracker.isActive, isTrue);

    tracker.clearHovered();
    expect(tracker.isHovered, isFalse);
    expect(tracker.isDragging, isTrue);
    expect(tracker.isActive, isTrue);

    tracker.release(dragOwner);
    expect(tracker.isActive, isFalse);

    tracker.setHovered(hoverOwner, true);
    tracker.release(hoverOwner);
    expect(tracker.isActive, isFalse);
    expect(activeChanges, 4);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets(
      'edge-to-edge setting, safe controls and zoom stay scoped to macOS ($platform)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'settings.appLanguage': 'en',
          'mirushin.player.settings': jsonEncode(
            const PlayerSettings(
              autoplayNext: false,
              macosEdgeToEdgeFullscreen: true,
            ).toJson(),
          ),
        });
        var nativeFullscreen = false;
        var edgeEnabled = false;
        final configurations = <Map<Object?, Object?>>[];
        final ended = <String>[];
        Map<String, Object> layout() => {
          'fullscreen': nativeFullscreen,
          'edgeToEdge': nativeFullscreen && edgeEnabled,
          'top': nativeFullscreen && edgeEnabled ? 38.0 : 0.0,
        };
        binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
          call,
        ) async {
          switch (call.method) {
            case 'configurePlayerFullscreen':
              final args = call.arguments as Map<Object?, Object?>;
              configurations.add(args);
              edgeEnabled = args['enabled'] == true;
              return layout();
            case 'getFullscreenLayout':
              return layout();
            case 'isFullscreen':
              return nativeFullscreen;
            case 'setFullscreen':
              nativeFullscreen = call.arguments as bool;
              return nativeFullscreen;
            case 'endPlayerFullscreen':
              ended.add((call.arguments as Map)['session'] as String);
              return layout();
          }
          return null;
        });
        final engine = _FullscreenTestEngine();
        final controller = _FullscreenTestPlaybackController(_item, engine);
        final container = ProviderContainer(
          overrides: [
            playbackControllerProvider.overrideWith(() => controller),
            watchPartyProvider.overrideWith(_IdleWatchPartyController.new),
            pipControllerProvider.overrideWithValue(
              const UnsupportedPipController(),
            ),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(engine.disposeNotifier);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const PlayerPage(item: _item, startInFullscreen: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        PlayerVideoSurface surface() =>
            tester.widget<PlayerVideoSurface>(find.byType(PlayerVideoSurface));
        final mac = platform == TargetPlatform.macOS;
        expect(surface().stretchVertical, mac);
        expect(
          tester.getSize(find.byType(PlayerVideoSurface)),
          const Size(1100, 800),
          reason: 'Only chrome is inset; video keeps the camera row',
        );
        expect(
          container.read(playerSettingsProvider).value!.verticalStretch,
          isFalse,
        );
        if (mac) {
          expect(
            tester.getTopLeft(find.byIcon(Icons.arrow_back_rounded)).dy,
            greaterThanOrEqualTo(38),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
          await tester.pumpAndSettle();
          expect(surface().stretchVertical, isFalse);
          expect(
            container.read(playerSettingsProvider).value!.verticalStretch,
            isFalse,
            reason:
                'Fullscreen zoom must not replace the normal-window preference',
          );
          var pipPresented = false;
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            nativePlayerChannel,
            (call) async {
              if (call.method == 'present') {
                expect(
                  nativeFullscreen,
                  isFalse,
                  reason:
                      'Restore the normal desktop before handing off to PiP',
                );
                pipPresented = true;
              }
              return null;
            },
          );
          addTearDown(
            () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
              nativePlayerChannel,
              null,
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
          await tester.pumpAndSettle();
          expect(pipPresented, isTrue);
          expect(nativeFullscreen, isFalse);
          final reply = Completer<ByteData?>();
          binding.defaultBinaryMessenger.handlePlatformMessage(
            nativePlayerChannel.name,
            nativePlayerChannel.codec.encodeMethodCall(
              const MethodCall('dismissed', {
                'positionMs': 1234,
                'durationMs': 1440000,
                'wasPlaying': true,
              }),
            ),
            reply.complete,
          );
          await reply.future;
          await tester.pumpAndSettle();
          expect(nativeFullscreen, isTrue);
          expect(
            surface().stretchVertical,
            isFalse,
            reason: 'PiP return preserves the user-selected fit mode',
          );
          expect(controller.lastNativePosition, 1234);
          expect(controller.lastSeek, const Duration(milliseconds: 1234));
        }
        await tester.tap(find.byIcon(Icons.settings_rounded));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final toggle = find.text('Use the entire display in fullscreen');
        expect(toggle, mac ? findsOneWidget : findsNothing);
        if (mac) {
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(
            container
                .read(playerSettingsProvider)
                .value!
                .macosEdgeToEdgeFullscreen,
            isFalse,
          );
          expect(configurations.last['enabled'], isFalse);
          Navigator.of(tester.element(toggle)).pop();
          await tester.pumpAndSettle();
          await container
              .read(playerSettingsProvider.notifier)
              .setMacosEdgeToEdgeFullscreen(true);
          await tester.pumpAndSettle();
          final preferences = await SharedPreferences.getInstance();
          expect(
            (jsonDecode(preferences.getString('mirushin.player.settings')!)
                as Map)['macosEdgeToEdgeFullscreen'],
            isTrue,
            reason: 'The switch must survive restarting the application',
          );
          expect(surface().stretchVertical, isTrue);
          expect(
            controller.loadCalls,
            1,
            reason: 'A fullscreen preference must not reload the stream',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(nativeFullscreen, isFalse);
          expect(surface().stretchVertical, isFalse);
          expect(find.byType(PlayerPage), findsOneWidget);
        } else {
          expect(configurations, isEmpty);
          Navigator.of(tester.element(find.text('Player Settings'))).pop();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (mac) expect(ended, [configurations.last['session']]);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

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
      controller.provenRouteForTest = const PlaybackRouteHint(
        backend: PlayerBackend.fvp,
        direct: true,
      );
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
      final PlayerNextEpisodeResult nextResult =
          routeResult! as PlayerNextEpisodeResult;
      expect(nextResult.serverId, 'server');
      expect(nextResult.serverTitle, 'Server');
      expect(nextResult.qualityId, 'auto');
      expect(nextResult.qualityLabel, 'Auto');
      expect(nextResult.playbackRouteHint?.backend, PlayerBackend.fvp);
      expect(nextResult.playbackRouteHint?.direct, isTrue);
      expect(controller.stopCalls, greaterThanOrEqualTo(1));
      expect(setFullscreenCalls, contains(true));
      await tester.pump(const Duration(seconds: 3));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('next route waits for the confirmed native fullscreen exit', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    bool nativeFullscreen = true;
    final Completer<bool> exitCompletion = Completer<bool>();
    final List<bool> setFullscreenCalls = <bool>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
      MethodCall call,
    ) async {
      if (call.method == 'isFullscreen') return nativeFullscreen;
      if (call.method == 'setFullscreen') {
        final bool target = call.arguments! as bool;
        setFullscreenCalls.add(target);
        if (target) return true;
        final bool result = await exitCompletion.future;
        nativeFullscreen = result;
        return result;
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

    controller.showAutoNext();
    await tester.pump();
    final Finder nextButton = find.widgetWithText(FilledButton, 'Next');
    expect(nextButton, findsOneWidget);
    tester.widget<FilledButton>(nextButton).onPressed!();
    await tester.pump(const Duration(milliseconds: 100));

    expect(setFullscreenCalls, contains(false));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsWidgets);
    expect(routeResult, isNull);
    expect(controller.stopCalls, 0);

    exitCompletion.complete(false);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
    expect(routeResult, isA<PlayerNextEpisodeResult>());
    expect((routeResult! as PlayerNextEpisodeResult).startInFullscreen, isTrue);
    expect(controller.stopCalls, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('timeline hover lifetime controls auto-hide ownership', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
      MethodCall call,
    ) async {
      if (call.method == 'isFullscreen') return false;
      if (call.method == 'setFullscreen') return call.arguments! as bool;
      return null;
    });
    final _FullscreenTestEngine engine = _FullscreenTestEngine();
    final _FullscreenTestPlaybackController controller =
        _FullscreenTestPlaybackController(_item, engine);
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
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const PlayerPage(item: _item),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final Finder timeline = find.byType(Slider).first;
    expect(timeline, findsOneWidget);
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(timeline));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isTrue);

    await mouse.moveTo(tester.getCenter(find.byType(PlayerPage)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isFalse);

    controller.setControlsVisible(true);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(timeline));
    await tester.pump();
    await mouse.down(tester.getCenter(timeline));
    await tester.pump();
    await mouse.moveTo(const Offset(-20, -20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isTrue);
    await mouse.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isFalse);

    controller.setControlsVisible(true);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(timeline));
    await tester.pump();
    controller.removeEngine();
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isFalse);

    await mouse.removePointer();
    debugDefaultTargetPlatformOverride = null;
  });

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
  int loadCalls = 0;
  int? lastNativePosition;
  Duration? lastSeek;
  int markWatchedCalls = 0;
  int testPlaybackGeneration = 0;
  PlaybackRouteHint? provenRouteForTest;

  @override
  PlaybackRouteHint? get provenPlaybackRoute => provenRouteForTest;

  @override
  int get playbackGeneration => testPlaybackGeneration;

  bool get controlsVisible => state.controlsVisible;

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

  void removeEngine() {
    state = state.copyWith(clearEngine: true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(desiredPlaying: false);
    await engine.pause();
  }

  @override
  Future<void> togglePlay() async {
    state = state.copyWith(desiredPlaying: !state.desiredPlaying);
    if (state.desiredPlaying) {
      await engine.play();
    } else {
      await engine.pause();
    }
  }

  @override
  Future<bool> skipTo(Duration target) async {
    lastSeek = target;
    await engine.seekTo(target);
    return true;
  }

  @override
  Future<void> saveNativeProgress({
    required int positionMs,
    required int durationMs,
    bool completed = false,
  }) async {
    lastNativePosition = positionMs;
  }

  @override
  Future<void> load(
    MediaPlaybackItem item, {
    PlaybackRouteHint? preferredPlaybackRoute,
  }) async {
    loadCalls++;
  }

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
  Future<void> play() async {
    _state.value = _state.value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    _state.value = _state.value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    _state.value = _state.value.copyWith(position: position);
  }

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
