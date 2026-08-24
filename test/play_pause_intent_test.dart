import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/local_library_provider.dart';
import 'package:mirushin/features/player/application/playback_controller.dart';
import 'package:mirushin/features/player/application/player_settings.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer container() {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('PlaybackController play/pause intent', () {
    test(
      'rapid play then pause applies only the latest desired state',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final Completer<void> playGate = Completer<void>();
        final _FakePlayerEngine engine = _FakePlayerEngine(
          PlayerEngineState(
            isInitialized: true,
            position: const Duration(seconds: 10),
            duration: const Duration(minutes: 24),
          ),
          onPlay: () => playGate.future,
        );
        controller.debugSetPlaybackState(
          PlaybackState(engine: engine, desiredPlaying: false),
        );

        final Future<void> play = controller.togglePlay();
        await Future<void>.delayed(Duration.zero);
        expect(c.read(playbackControllerProvider).desiredPlaying, isTrue);

        final Future<void> pause = controller.pause();
        await Future<void>.delayed(Duration.zero);
        expect(c.read(playbackControllerProvider).desiredPlaying, isFalse);

        playGate.complete();
        await Future.wait(<Future<void>>[play, pause]);

        expect(engine.playCalls, 1);
        expect(engine.pauseCalls, 1);
        expect(engine.value.isPlaying, isFalse);
        expect(c.read(playbackControllerProvider).desiredPlaying, isFalse);
        expect(
          c.read(playbackControllerProvider).playPauseOperationInFlight,
          isFalse,
        );
        expect(c.read(playbackControllerProvider).resumeStabilizing, isFalse);
      },
    );

    test(
      'stable resume clears resumeStabilizing without another play',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final _FakePlayerEngine engine = _FakePlayerEngine(
          PlayerEngineState(
            isInitialized: true,
            position: const Duration(seconds: 10),
            duration: const Duration(minutes: 24),
          ),
        );
        controller.debugSetPlaybackState(
          PlaybackState(engine: engine, desiredPlaying: false),
        );

        await controller.togglePlay();
        await controller.applyRemotePlay();
        expect(engine.playCalls, 1);
        expect(c.read(playbackControllerProvider).resumeStabilizing, isTrue);

        engine.setPosition(const Duration(milliseconds: 10300));
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(c.read(playbackControllerProvider).desiredPlaying, isTrue);
        expect(c.read(playbackControllerProvider).resumeStabilizing, isFalse);
        expect(engine.playCalls, 1);
      },
    );

    test('remote play does not rebroadcast to sync sink', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(isInitialized: true),
      );
      final _FakePlaybackSyncSink sink = _FakePlaybackSyncSink();
      controller
        ..debugSetPlaybackState(
          PlaybackState(engine: engine, desiredPlaying: false),
        )
        ..setPlaybackSyncSink(sink);

      await controller.applyRemotePlay();

      expect(engine.playCalls, 1);
      expect(sink.playCalls, 0);
      expect(sink.pauseCalls, 0);
    });

    test(
      'resume recovery retries seek and user pause cancels recovery',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final _FakePlayerEngine engine = _FakePlayerEngine(
          PlayerEngineState(
            isInitialized: true,
            hasError: true,
            position: const Duration(seconds: 10),
            duration: const Duration(minutes: 24),
          ),
        );
        controller.debugSetPlaybackState(
          PlaybackState(engine: engine, desiredPlaying: false),
        );

        await controller.togglePlay();
        await Future<void>.delayed(const Duration(milliseconds: 450));

        expect(engine.seekCalls, 1);
        await controller.pause();
        await Future<void>.delayed(const Duration(milliseconds: 450));

        expect(c.read(playbackControllerProvider).desiredPlaying, isFalse);
        expect(c.read(playbackControllerProvider).resumeStabilizing, isFalse);
        expect(engine.playCalls, 1);
      },
    );

    test('stop tears down only the session it captured', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem oldItem = _testPlaybackItem('old');
      final MediaPlaybackItem newItem = _testPlaybackItem('new');
      final _FakePlayerEngine oldEngine = _FakePlayerEngine(
        PlayerEngineState(
          isInitialized: true,
          position: const Duration(minutes: 3),
          duration: const Duration(minutes: 24),
        ),
      );
      final _FakePlayerEngine newEngine = _FakePlayerEngine(
        PlayerEngineState(
          isInitialized: true,
          position: const Duration(seconds: 15),
          duration: const Duration(minutes: 24),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(item: oldItem, engine: oldEngine, desiredPlaying: true),
      );

      final Future<void> stopFuture = controller.stop();
      controller.debugSetPlaybackState(
        PlaybackState(item: newItem, engine: newEngine, desiredPlaying: true),
      );
      await stopFuture;

      expect(oldEngine.disposeCalls, 1);
      expect(newEngine.pauseCalls, 0);
      expect(newEngine.disposeCalls, 0);
      expect(c.read(playbackControllerProvider).engine, same(newEngine));
    });

    test('stop saves high-water position when engine snaps to zero', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('high-water');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          position: Duration.zero,
          duration: Duration(minutes: 24),
        ),
      );
      controller
        ..debugSetPlaybackState(PlaybackState(item: item, engine: engine))
        ..debugSetMaxObservedPosition(const Duration(minutes: 4, seconds: 12));

      await controller.stop();

      final progress = await c
          .read(localLibraryProvider.notifier)
          .loadEpisodeProgress(item.id, 1, 1.0);
      expect(progress?.positionSeconds, 252);
      expect(progress?.completed, isFalse);
    });

    test('skip is committed only after the native seek completes', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final Completer<void> seekGate = Completer<void>();
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 77),
          duration: Duration(minutes: 24),
        ),
        onSeek: (_) => seekGate.future,
      );
      controller.debugSetPlaybackState(
        PlaybackState(engine: engine, desiredPlaying: true),
      );

      final Future<bool> skip = controller.skipTo(const Duration(seconds: 166));
      await Future<void>.delayed(Duration.zero);

      expect(engine.seekCalls, 1);
      expect(c.read(playbackControllerProvider).lastSkippedFrom, isNull);
      expect(
        c.read(playbackControllerProvider).seekPreviewPosition,
        const Duration(seconds: 166),
      );

      seekGate.complete();
      expect(await skip, isTrue);
      expect(
        c.read(playbackControllerProvider).lastSkippedFrom,
        const Duration(seconds: 77),
      );
    });

    test('failed skip is not marked completed and clears preview', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 77),
          duration: Duration(minutes: 24),
        ),
        onSeek: (_) => Future<void>.error(StateError('native seek failed')),
      );
      controller.debugSetPlaybackState(
        PlaybackState(engine: engine, desiredPlaying: true),
      );

      expect(await controller.skipTo(const Duration(seconds: 166)), isFalse);
      expect(c.read(playbackControllerProvider).lastSkippedFrom, isNull);
      expect(c.read(playbackControllerProvider).seekPreviewPosition, isNull);
    });

    test('mobile playback controller keeps app-side volume at 100%', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ProviderContainer c = container();
      await c.read(playerSettingsProvider.future);
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(isInitialized: true, volume: 0.25),
      );
      controller.debugSetPlaybackState(PlaybackState(engine: engine));

      await controller.setVolume(0.2);

      expect(engine.lastSetVolume, 1);
      expect(c.read(playerSettingsProvider).value?.volume, 1);
    });

    test('unmute restores the last audible volume', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ProviderContainer c = container();
      await c.read(playerSettingsProvider.future);
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(isInitialized: true, volume: 0.37),
      );
      controller.debugSetPlaybackState(PlaybackState(engine: engine));
      await controller.setVolume(0.37);

      await controller.toggleMute();

      expect(engine.lastSetVolume, 0);
      expect(c.read(playerSettingsProvider).value?.volume, 0);
      expect(c.read(playerSettingsProvider).value?.lastAudibleVolume, 0.37);

      await controller.toggleMute();

      expect(engine.lastSetVolume, 0.37);
      expect(c.read(playerSettingsProvider).value?.volume, 0.37);
      expect(c.read(playerSettingsProvider).value?.lastAudibleVolume, 0.37);
    });
  });
}

MediaPlaybackItem _testPlaybackItem(String id) {
  return MediaPlaybackItem(
    id: id,
    title: 'Test $id',
    mediaType: MediaType.anime,
    servers: const <MediaServer>[
      MediaServer(
        id: 'server',
        name: 'Server',
        sourceName: 'Test',
        url: 'https://example.invalid/video.m3u8',
        streamType: StreamType.hls,
      ),
    ],
  );
}

class _FakePlayerEngine extends PlayerEngine {
  _FakePlayerEngine(this.initialState, {this.onPlay, this.onSeek})
    : _state = ValueNotifier<PlayerEngineState>(initialState);

  final PlayerEngineState initialState;
  final Future<void> Function()? onPlay;
  final Future<void> Function(Duration position)? onSeek;
  final ValueNotifier<PlayerEngineState> _state;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int disposeCalls = 0;
  double? lastSetVolume;

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
    playCalls += 1;
    await onPlay?.call();
    _state.value = _state.value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    _state.value = _state.value.copyWith(isPlaying: false, isBuffering: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekCalls += 1;
    await onSeek?.call(position);
    _state.value = _state.value.copyWith(position: position);
  }

  void setPosition(Duration position) {
    _state.value = _state.value.copyWith(position: position);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {
    lastSetVolume = volume;
    _state.value = _state.value.copyWith(volume: volume);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _state.dispose();
  }
}

class _FakePlaybackSyncSink implements PlaybackSyncSink {
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  void onHostPause(Duration position, double speed) {
    pauseCalls += 1;
  }

  @override
  void onHostPlay(Duration position, double speed) {
    playCalls += 1;
  }

  @override
  void onHostSeek(Duration position, double speed, bool playing) {}

  @override
  void onHostSourceChanged() {}

  @override
  void onHostSpeed(
    double speed,
    Duration position,
    bool playing, {
    bool temporary = false,
  }) {}
}
