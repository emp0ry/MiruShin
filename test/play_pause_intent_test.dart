import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/local_library_provider.dart';
import 'package:mirushin/features/player/application/playback_controller.dart';
import 'package:mirushin/features/player/application/player_settings.dart';
import 'package:mirushin/features/player/domain/playback_end_decision.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';
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

    test(
      'natural premature EOF is bounded and never exposes auto-next',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final MediaPlaybackItem item = _testPlaybackItem('premature-eof');
        final _FakePlayerEngine engine = _FakePlayerEngine(
          const PlayerEngineState(
            isInitialized: true,
            isPlaying: true,
            position: Duration(seconds: 1403),
            duration: Duration(seconds: 1434),
          ),
        );
        controller.debugSetPlaybackState(
          PlaybackState(
            item: item,
            engine: engine,
            server: item.servers.first,
            desiredPlaying: true,
          ),
        );
        controller.debugEvaluatePlaybackProgress(engine);
        controller.debugEvaluatePlaybackProgress(engine);
        engine.setState(engine.value.copyWith(isCompleted: true));
        controller.debugEvaluatePlaybackProgress(engine);

        await Future<void>.delayed(const Duration(milliseconds: 900));

        final PlaybackState state = c.read(playbackControllerProvider);
        expect(state.confirmedEnded, isFalse);
        expect(state.autoNextVisible, isFalse);
        expect(state.error, isNull);
        expect(engine.seekCalls, 1);
        expect(engine.disposeCalls, 0);
      },
    );

    test('manual seek keeps 1419 when backend END remains asserted', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('seek-1419');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(
              position: position,
              isCompleted: position == const Duration(seconds: 1419),
              hasError: false,
            ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(seconds: 1419));
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(engine.seekCalls, 1);
      expect(engine.value.position, const Duration(seconds: 1419));
      expect(engine.value.isCompleted, isTrue);
      expect(state.error, isNull);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      expect(
        engine.disposeCalls,
        0,
        reason: 'a seek must not reopen the source',
      );
    });

    test('seek to 24:00 of 24:34 never rolls back to old position', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('seek-1416');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(minutes: 10),
          duration: Duration(minutes: 24, seconds: 34),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(
              position: position,
              isCompleted: true,
              hasError: false,
            ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(minutes: 24));
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      controller.debugEvaluatePlaybackProgress(engine);

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(engine.seekCalls, 1);
      expect(engine.value.position, const Duration(minutes: 24));
      expect(state.error, isNull);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      expect(engine.disposeCalls, 0);
    });

    test('near-end seek that keeps playing needs no fallback', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('seek-playing');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(
              position: position,
              isCompleted: false,
              hasError: false,
            ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(seconds: 1419));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(engine.seekCalls, 1);
      expect(engine.value.position, const Duration(seconds: 1419));
      expect(c.read(playbackControllerProvider).error, isNull);
      expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);
    });

    test('timeline seek from 10:00 to 18:00 remains authoritative', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('seek-10-to-18');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(minutes: 10),
          duration: Duration(minutes: 24, seconds: 34),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );

      await controller.seekTo(const Duration(minutes: 18));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(engine.seekCalls, 1);
      expect(engine.value.position, const Duration(minutes: 18));
      expect(controller.currentEnginePosition, const Duration(minutes: 18));
      expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);
    });

    test(
      'paused backward and repeated seeks preserve the latest target',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final MediaPlaybackItem item = _testPlaybackItem('repeated-seeks');
        final _FakePlayerEngine engine = _FakePlayerEngine(
          const PlayerEngineState(
            isInitialized: true,
            isPlaying: false,
            position: Duration(minutes: 18),
            duration: Duration(minutes: 24),
          ),
        );
        controller.debugSetPlaybackState(
          PlaybackState(
            item: item,
            engine: engine,
            server: item.servers.first,
            desiredPlaying: false,
          ),
        );

        for (final Duration target in <Duration>[
          const Duration(minutes: 8),
          const Duration(minutes: 20),
          const Duration(minutes: 6),
          const Duration(minutes: 19),
        ]) {
          await controller.seekTo(target);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(engine.seekCalls, 4);
        expect(engine.value.position, const Duration(minutes: 19));
        expect(engine.playCalls, 0);
        expect(c.read(playbackControllerProvider).autoNextVisible, isFalse);
      },
    );

    test('seek to the actual final second may confirm real end', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('seek-real-end');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(position: position, isCompleted: true),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(milliseconds: 1433500));
      controller.debugEvaluatePlaybackProgress(engine);
      expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);
      expect(c.read(playbackControllerProvider).autoNextVisible, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      engine.setState(engine.value.copyWith(isCompleted: true));
      controller.debugEvaluatePlaybackProgress(engine);

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(engine.seekCalls, 1);
      expect(state.confirmedEnded, isTrue);
      expect(state.autoNextVisible, isTrue);
    });

    test(
      'confirmed end after near-end seek cannot remain quarantined',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final MediaPlaybackItem item = _testPlaybackItem(
          'seek-quarantine-real-end',
        );
        final _FakePlayerEngine engine = _FakePlayerEngine(
          const PlayerEngineState(
            isInitialized: true,
            isPlaying: true,
            position: Duration(seconds: 1100),
            duration: Duration(seconds: 1249),
          ),
          stateAfterSeek: (PlayerEngineState current, Duration position) =>
              current.copyWith(position: position, isCompleted: true),
        );
        controller.debugSetPlaybackState(
          PlaybackState(
            item: item,
            engine: engine,
            server: item.servers.first,
            desiredPlaying: true,
          ),
        );
        controller.debugEvaluatePlaybackProgress(engine);
        controller.debugEvaluatePlaybackProgress(engine);

        await controller.seekTo(const Duration(seconds: 1247));
        await Future<void>.delayed(const Duration(milliseconds: 1700));

        final PlaybackState state = c.read(playbackControllerProvider);
        expect(controller.debugManualSeekOwnsBackendEof(engine), isFalse);
        expect(state.confirmedEnded, isTrue);
        expect(state.autoNextVisible, isTrue);
        expect(engine.seekCalls, 1);
        expect(engine.pauseCalls, 0);
        expect(engine.playCalls, 0);
      },
    );

    test(
      'offline near-end seek reaches true EOF without interaction',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        const MediaServer offlineServer = MediaServer(
          id: 'offline',
          name: 'Downloaded',
          sourceName: 'Offline',
          url: 'file:///downloaded/episode.m3u8',
          streamType: StreamType.hls,
        );
        const MediaPlaybackItem item = MediaPlaybackItem(
          id: 'offline-seek-quarantine-real-end',
          title: 'Offline seek quarantine real end',
          mediaType: MediaType.anime,
          servers: <MediaServer>[offlineServer],
        );
        final _FakePlayerEngine engine = _FakePlayerEngine(
          const PlayerEngineState(
            isInitialized: true,
            isPlaying: true,
            position: Duration(seconds: 1100),
            duration: Duration(seconds: 1249),
          ),
          stateAfterSeek: (PlayerEngineState current, Duration position) =>
              current.copyWith(position: position, isCompleted: true),
        );
        controller.debugSetPlaybackState(
          PlaybackState(
            item: item,
            engine: engine,
            server: offlineServer,
            desiredPlaying: true,
          ),
        );
        controller.debugEvaluatePlaybackProgress(engine);

        await controller.seekTo(const Duration(seconds: 1247));
        await Future<void>.delayed(const Duration(milliseconds: 1700));

        final PlaybackState state = c.read(playbackControllerProvider);
        expect(controller.debugManualSeekOwnsBackendEof(engine), isFalse);
        expect(state.confirmedEnded, isTrue);
        expect(state.autoNextVisible, isTrue);
        expect(engine.seekCalls, 1);
        expect(engine.pauseCalls, 0);
        expect(engine.playCalls, 0);
      },
    );

    test('far-from-end seek quarantine expires without rollback', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem(
        'seek-quarantine-premature-end',
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1200),
          duration: Duration(seconds: 1477),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(position: position, isCompleted: true),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(seconds: 1401));
      await Future<void>.delayed(const Duration(milliseconds: 1700));

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(controller.debugManualSeekOwnsBackendEof(engine), isFalse);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      expect(engine.value.position, const Duration(seconds: 1401));
      expect(engine.seekCalls, 1);
    });

    test('stale completed callback during seek is quarantined', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('stale-seek-eof');
      final Completer<void> seekGate = Completer<void>();
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        onSeek: (_) => seekGate.future,
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(position: position, isCompleted: false),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(seconds: 1419));
      await Future<void>.delayed(Duration.zero);
      engine.setState(engine.value.copyWith(isCompleted: true));
      controller.debugEvaluatePlaybackProgress(engine);
      expect(engine.seekCalls, 1);
      expect(c.read(playbackControllerProvider).error, isNull);

      seekGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.seekCalls, 1);
      expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);
      expect(c.read(playbackControllerProvider).autoNextVisible, isFalse);
    });

    test(
      'newest user seek wins while the previous native seek is pending',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final MediaPlaybackItem item = _testPlaybackItem(
          'seek-cancels-fallback',
        );
        final Completer<void> firstSeekGate = Completer<void>();
        final _FakePlayerEngine engine = _FakePlayerEngine(
          const PlayerEngineState(
            isInitialized: true,
            isPlaying: true,
            position: Duration(seconds: 1300),
            duration: Duration(seconds: 1434),
          ),
          onSeek: (Duration position) {
            if (position == const Duration(seconds: 1419)) {
              return firstSeekGate.future;
            }
            return Future<void>.value();
          },
          stateAfterSeek: (PlayerEngineState current, Duration position) =>
              current.copyWith(
                position: position,
                isCompleted: position == const Duration(seconds: 1419),
              ),
        );
        controller.debugSetPlaybackState(
          PlaybackState(
            item: item,
            engine: engine,
            server: item.servers.first,
            desiredPlaying: true,
          ),
        );
        controller.debugEvaluatePlaybackProgress(engine);
        controller.debugEvaluatePlaybackProgress(engine);

        await controller.seekTo(const Duration(seconds: 1419));
        await Future<void>.delayed(Duration.zero);
        await controller.seekTo(const Duration(seconds: 1000));
        expect(engine.seekCalls, 1);
        firstSeekGate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(engine.seekCalls, 2);
        expect(engine.value.position, const Duration(seconds: 1000));
        expect(engine.value.isCompleted, isFalse);
        expect(c.read(playbackControllerProvider).error, isNull);
        expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);
      },
    );

    test('engine change rejects queued seeks from the old player', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem oldItem = _testPlaybackItem(
        'seek-fallback-old-source',
      );
      final MediaPlaybackItem newItem = _testPlaybackItem(
        'seek-fallback-new-source',
      );
      final Completer<void> oldSeekGate = Completer<void>();
      final _FakePlayerEngine oldEngine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        onSeek: (Duration position) {
          if (position == const Duration(seconds: 1419)) {
            return oldSeekGate.future;
          }
          return Future<void>.value();
        },
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(position: position, isCompleted: true),
      );
      final _FakePlayerEngine newEngine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 20),
          duration: Duration(seconds: 1200),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: oldItem,
          engine: oldEngine,
          server: oldItem.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(oldEngine);
      controller.debugEvaluatePlaybackProgress(oldEngine);

      await controller.seekTo(const Duration(seconds: 1419));
      await Future<void>.delayed(Duration.zero);
      await controller.seekTo(const Duration(seconds: 1000));
      controller.debugSetPlaybackState(
        PlaybackState(
          item: newItem,
          engine: newEngine,
          server: newItem.servers.first,
          desiredPlaying: true,
        ),
      );
      oldSeekGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.item, same(newItem));
      expect(state.engine, same(newEngine));
      expect(state.error, isNull);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      expect(newEngine.seekCalls, 0);
      expect(newEngine.playCalls, 0);
      expect(newEngine.disposeCalls, 0);
    });

    test('offline seek-induced EOF cannot request continuation', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      const MediaServer offlineServer = MediaServer(
        id: 'offline',
        name: 'Downloaded',
        sourceName: 'Offline',
        url: 'file:///downloaded/episode.m3u8',
        streamType: StreamType.hls,
      );
      const MediaPlaybackItem item = MediaPlaybackItem(
        id: 'offline-seek-eof',
        title: 'Offline seek EOF',
        mediaType: MediaType.anime,
        servers: <MediaServer>[offlineServer],
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(
              position: position,
              isCompleted: position == const Duration(seconds: 1419),
              hasError: false,
            ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: offlineServer,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(seconds: 1419));
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.error, isNull);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      expect(engine.disposeCalls, 0);
    });

    test('natural premature EOF recovery can resume playback', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('natural-recovered');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1300),
          duration: Duration(seconds: 1434),
        ),
        stateAfterSeek: (PlayerEngineState current, Duration position) =>
            current.copyWith(position: position, isCompleted: false),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);
      engine.setState(engine.value.copyWith(isCompleted: true));
      controller.debugEvaluatePlaybackProgress(engine);

      await Future<void>.delayed(const Duration(milliseconds: 900));

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(engine.seekCalls, 1);
      expect(engine.value.position, const Duration(seconds: 1300));
      expect(engine.value.isCompleted, isFalse);
      expect(state.error, isNull);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
    });

    test('false EOF recovery can later confirm exactly the real end', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('recovered-real-eof');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1130),
          duration: Duration(seconds: 1200),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);
      engine.setState(engine.value.copyWith(isCompleted: true));
      controller.debugEvaluatePlaybackProgress(engine);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);

      engine.setState(
        engine.value.copyWith(
          position: const Duration(milliseconds: 1199500),
          isCompleted: true,
          hasError: false,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.confirmedEnded, isTrue);
      expect(state.autoNextVisible, isTrue);
    });

    test('failed near-end seek intent cannot authorize auto-next', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('failed-end-seek');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          isPlaying: true,
          position: Duration(seconds: 1403),
          duration: Duration(seconds: 1434),
        ),
        onSeek: (_) => Future<void>.error(StateError('seek rejected')),
      );
      controller.debugSetPlaybackState(
        PlaybackState(
          item: item,
          engine: engine,
          server: item.servers.first,
          desiredPlaying: true,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      await controller.seekTo(const Duration(seconds: 1433));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
    });

    test('watched final stretch resumes there until real EOF', () {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('watched-resume');

      final Duration resume = controller.debugSafeResumePosition(
        item,
        EpisodeProgress(
          positionSeconds: 1418,
          durationSeconds: 1434,
          updatedAt: DateTime(2026),
          completed: true,
        ),
      );

      expect(resume, const Duration(seconds: 1418));
    });

    test(
      'playback start policy separates resume, beginning, and exact start',
      () {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final EpisodeProgress saved = EpisodeProgress(
          positionSeconds: 440,
          durationSeconds: 1200,
          updatedAt: DateTime(2026),
          completed: false,
        );

        expect(
          controller.debugSafeResumePosition(
            _testPlaybackItem(
              'resume-policy',
              startPosition: const Duration(seconds: 300),
            ),
            saved,
          ),
          const Duration(seconds: 440),
        );
        expect(
          controller.debugSafeResumePosition(
            _testPlaybackItem(
              'force-policy',
              startPosition: const Duration(seconds: 300),
              startPolicy: PlaybackStartPolicy.forceBeginning,
            ),
            saved,
          ),
          Duration.zero,
        );
        expect(
          controller.debugSafeResumePosition(
            _testPlaybackItem(
              'exact-policy',
              startPosition: const Duration(seconds: 125),
              startPolicy: PlaybackStartPolicy.explicitPosition,
            ),
            saved,
          ),
          const Duration(seconds: 125),
        );
      },
    );

    test('forceBeginning playback still saves new progress normally', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem(
        'force-progress-save',
        startPolicy: PlaybackStartPolicy.forceBeginning,
      );
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          position: Duration(seconds: 120),
          duration: Duration(seconds: 1200),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(item: item, engine: engine, server: item.servers.first),
      );

      await controller.stop();

      final EpisodeProgress? progress = await c
          .read(localLibraryProvider.notifier)
          .loadEpisodeProgress(item.id, 1, 1.0);
      expect(progress?.positionSeconds, 120);
      expect(progress?.completed, isFalse);
    });

    test(
      'forceBeginning selection does not delete prior saved progress',
      () async {
        final ProviderContainer c = container();
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final MediaPlaybackItem item = _testPlaybackItem(
          'force-keeps-history',
          startPolicy: PlaybackStartPolicy.forceBeginning,
        );
        await c
            .read(localLibraryProvider.notifier)
            .saveEpisodeProgress(
              mediaId: item.id,
              season: 1,
              episode: 1,
              positionSeconds: 440,
              durationSeconds: 1200,
              completed: false,
            );

        expect(
          controller.debugSafeResumePosition(
            item,
            EpisodeProgress(
              positionSeconds: 440,
              durationSeconds: 1200,
              updatedAt: DateTime(2026),
              completed: false,
            ),
          ),
          Duration.zero,
        );
        final EpisodeProgress? preserved = await c
            .read(localLibraryProvider.notifier)
            .loadEpisodeProgress(item.id, 1, 1.0);
        expect(preserved?.positionSeconds, 440);
        expect(preserved?.completed, isFalse);
      },
    );

    test('premature native completion saves resumable progress', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('native-premature');
      controller.debugSetPlaybackState(PlaybackState(item: item));

      await controller.saveNativeProgress(
        positionMs: 600000,
        durationMs: 1200000,
        completed: false,
      );

      final EpisodeProgress? progress = await c
          .read(localLibraryProvider.notifier)
          .loadEpisodeProgress(item.id, 1, 1.0);
      expect(progress?.positionSeconds, 600);
      expect(progress?.completed, isFalse);
      expect(c.read(playbackControllerProvider).confirmedEnded, isFalse);
    });

    test('genuine native completion saves strict completed state', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('native-genuine');
      controller.debugSetPlaybackState(PlaybackState(item: item));

      await controller.saveNativeProgress(
        positionMs: 1199000,
        durationMs: 1200000,
        completed: true,
      );

      final EpisodeProgress? progress = await c
          .read(localLibraryProvider.notifier)
          .loadEpisodeProgress(item.id, 1, 1.0);
      expect(progress?.positionSeconds, 0);
      expect(progress?.completed, isTrue);
      expect(c.read(playbackControllerProvider).confirmedEnded, isTrue);
    });

    test('native completion uses the same strict end decision', () {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );

      expect(
        controller
            .evaluateNativePlaybackEnd(
              positionMs: 1403000,
              durationMs: 1434000,
              backendCompleted: true,
            )
            .confirmedEnded,
        isFalse,
      );
      expect(
        controller
            .evaluateNativePlaybackEnd(
              positionMs: 1433000,
              durationMs: 1434000,
              backendCompleted: true,
            )
            .confirmedEnded,
        isTrue,
      );

      controller.debugSetMaxObservedPosition(const Duration(seconds: 1433));
      expect(
        controller
            .evaluateNativePlaybackEnd(
              positionMs: 0,
              durationMs: 1434000,
              backendCompleted: true,
            )
            .confirmedEnded,
        isTrue,
        reason: 'genuine native EOF may snap the current position to zero',
      );

      controller.debugSetMaxObservedPosition(const Duration(seconds: 1403));
      expect(
        controller
            .evaluateNativePlaybackEnd(
              positionMs: 0,
              durationMs: 1434000,
              backendCompleted: true,
            )
            .decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'a premature native snap must remain rejected',
      );
    });

    test('real segmented end confirms and exposes auto-next', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('real-end');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          position: Duration(seconds: 1430),
          duration: Duration(seconds: 1434),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(item: item, engine: engine, server: item.servers.first),
      );

      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.confirmedEnded, isTrue);
      expect(state.autoNextVisible, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('85 percent watched does not confirm end or auto-next', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('watched-not-ended');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          position: Duration(seconds: 1224),
          duration: Duration(seconds: 1440),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(item: item, engine: engine, server: item.servers.first),
      );

      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('duration growth invalidates a previously confirmed end', () async {
      final ProviderContainer c = container();
      final PlaybackController controller = c.read(
        playbackControllerProvider.notifier,
      );
      final MediaPlaybackItem item = _testPlaybackItem('duration-growth');
      final _FakePlayerEngine engine = _FakePlayerEngine(
        const PlayerEngineState(
          isInitialized: true,
          position: Duration(seconds: 1430),
          duration: Duration(seconds: 1434),
        ),
      );
      controller.debugSetPlaybackState(
        PlaybackState(item: item, engine: engine, server: item.servers.first),
      );
      controller.debugEvaluatePlaybackProgress(engine);
      controller.debugEvaluatePlaybackProgress(engine);
      expect(c.read(playbackControllerProvider).confirmedEnded, isTrue);

      engine.setState(
        engine.value.copyWith(
          position: const Duration(seconds: 1430),
          duration: const Duration(seconds: 1450),
          isCompleted: false,
        ),
      );
      controller.debugEvaluatePlaybackProgress(engine);

      final PlaybackState state = c.read(playbackControllerProvider);
      expect(state.confirmedEnded, isFalse);
      expect(state.autoNextVisible, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
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

    for (final double speed in <double>[2.25, 2.75]) {
      test('$speed speed persists exactly and reaches the engine', () async {
        final ProviderContainer c = container();
        await c.read(playerSettingsProvider.future);
        final PlaybackController controller = c.read(
          playbackControllerProvider.notifier,
        );
        final _FakePlayerEngine engine = _FakePlayerEngine(
          const PlayerEngineState(isInitialized: true),
        );
        controller.debugSetPlaybackState(PlaybackState(engine: engine));

        await controller.setSpeed(speed);

        expect(engine.lastSetSpeed, speed);
        expect(c.read(playerSettingsProvider).value?.playbackSpeed, speed);
        final PlayerSettings restored = PlayerSettings.fromJson(
          c.read(playerSettingsProvider).requireValue.toJson(),
        );
        expect(restored.playbackSpeed, speed);
      });
    }
  });
}

MediaPlaybackItem _testPlaybackItem(
  String id, {
  PlaybackStartPolicy startPolicy = PlaybackStartPolicy.resumeSaved,
  Duration startPosition = Duration.zero,
}) {
  return MediaPlaybackItem(
    id: id,
    title: 'Test $id',
    mediaType: MediaType.anime,
    startPolicy: startPolicy,
    startPosition: startPosition,
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
  _FakePlayerEngine(
    this.initialState, {
    this.onPlay,
    this.onSeek,
    this.stateAfterSeek,
  }) : _state = ValueNotifier<PlayerEngineState>(initialState);

  final PlayerEngineState initialState;
  final Future<void> Function()? onPlay;
  final Future<void> Function(Duration position)? onSeek;
  final PlayerEngineState Function(
    PlayerEngineState current,
    Duration position,
  )?
  stateAfterSeek;
  final ValueNotifier<PlayerEngineState> _state;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int disposeCalls = 0;
  double? lastSetVolume;
  double? lastSetSpeed;

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
    _state.value =
        stateAfterSeek?.call(_state.value, position) ??
        _state.value.copyWith(position: position);
  }

  void setPosition(Duration position) {
    _state.value = _state.value.copyWith(position: position);
  }

  void setState(PlayerEngineState value) {
    _state.value = value;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    lastSetSpeed = speed;
    _state.value = _state.value.copyWith(playbackSpeed: speed);
  }

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
