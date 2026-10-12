import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/google_drive_sync_controller.dart';
import 'package:mirushin/features/library/application/local_library_provider.dart';
import 'package:mirushin/features/player/application/playback_activity.dart';
import 'package:mirushin/features/player/application/playback_controller.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';
import 'package:mirushin/shared/models/library_item.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'actual load and stop cover the session, including failed stream open',
    () async {
      final container = ProviderContainer(
        overrides: [
          playbackControllerProvider.overrideWith(_NoEnginePlayback.new),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(playbackControllerProvider.notifier);
      const item = MediaPlaybackItem(
        id: 'test',
        title: 'Test',
        mediaType: MediaType.anime,
        servers: [],
      );
      await controller.load(item);
      expect(container.read(playbackActivityProvider), isTrue);
      // Switching to the next item must not briefly release background work.
      await controller.load(item);
      expect(container.read(playbackActivityProvider), isTrue);
      await controller.stop();
      expect(container.read(playbackActivityProvider), isFalse);
    },
  );

  test(
    'manual, local and remote sync defer, then coalesce into one idle pass',
    () async {
      final controller = _TestDriveController();
      final container = ProviderContainer(
        overrides: [
          googleDriveSyncControllerProvider.overrideWith(() => controller),
        ],
      );
      addTearDown(container.dispose);
      await container.read(googleDriveSyncControllerProvider.future);
      final activity = container.read(playbackActivityProvider.notifier);
      activity.setActive(true);
      await controller.syncNow();
      await controller.syncNow(background: true, localChangesOnly: true);
      await controller.syncNow(background: true, remoteChangesOnly: true);
      final deferred = container
          .read(googleDriveSyncControllerProvider)
          .requireValue;
      expect(deferred.deferredForPlayback, isTrue);
      expect(deferred.syncing, isFalse);
      expect(deferred.checking, isFalse);
      expect(deferred.lastError, isNull);
      expect(controller.idleRequests, 0);
      // The session stays active throughout pause / the next episode.
      activity.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.idleRequests, 0);
      activity.setActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.idleRequests, 0);
      // Simulate a route transition during auto-next: no work escapes the gap.
      activity.setActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.idleRequests, 0);
      activity.setActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 8100));
      expect(controller.idleRequests, 1);
      activity.setActive(false);
      await Future<void>.delayed(Duration.zero);
      expect(controller.idleRequests, 1);
    },
  );

  test('old teardown cannot release a new load waiting for progress', () async {
    final library = _SlowProgressLibrary();
    final container = ProviderContainer(
      overrides: [
        playbackControllerProvider.overrideWith(_NoEnginePlayback.new),
        localLibraryProvider.overrideWith(() => library),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playbackControllerProvider.notifier);
    final stopping = controller.stop();
    final loading = controller.load(
      const MediaPlaybackItem(
        id: 'next',
        title: 'Next',
        mediaType: MediaType.anime,
        servers: [
          MediaServer(
            id: 'fixture',
            name: 'Fixture',
            sourceName: 'Fixture',
            url: 'https://example.invalid/video',
            streamType: StreamType.mp4,
          ),
        ],
      ),
    );
    final failedLoad = expectLater(loading, throwsStateError);
    await library.started.future;
    await stopping;
    expect(container.read(playbackControllerProvider).item, isNull);
    expect(container.read(playbackActivityProvider), isTrue);
    // No engine or network is opened in this test.
    library.progress.completeError(StateError('cancel fixture load'));
    await failedLoad;
    await controller.stop();
    expect(container.read(playbackActivityProvider), isFalse);
  });

  test('shutdown does not restart deferred work after playback ends', () async {
    final controller = _TestDriveController();
    final container = ProviderContainer(
      overrides: [
        googleDriveSyncControllerProvider.overrideWith(() => controller),
      ],
    );
    addTearDown(container.dispose);
    await container.read(googleDriveSyncControllerProvider.future);
    final activity = container.read(playbackActivityProvider.notifier);
    activity.setActive(true);
    await controller.syncNow();
    await controller.prepareForExit();
    activity.setActive(false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.idleRequests, 0);
  });

  test('manual sync after exit consumes the deferred timer once', () async {
    final controller = _TestDriveController();
    final container = ProviderContainer(
      overrides: [
        googleDriveSyncControllerProvider.overrideWith(() => controller),
      ],
    );
    addTearDown(container.dispose);
    await container.read(googleDriveSyncControllerProvider.future);
    final activity = container.read(playbackActivityProvider.notifier);
    activity.setActive(true);
    await controller.syncNow(background: true, localChangesOnly: true);
    activity.setActive(false);
    await controller.syncNow(background: true, remoteChangesOnly: true);
    final quiet = container
        .read(googleDriveSyncControllerProvider)
        .requireValue;
    expect(quiet.connected, isTrue);
    expect(quiet.deferredForPlayback, isTrue);
    expect(quiet.checking || quiet.syncing, isFalse);
    await controller.syncNow();
    // The quiet poll was requested but did not start the credential check.
    expect(controller.idleRequests, 2);
    expect(
      container
          .read(googleDriveSyncControllerProvider)
          .requireValue
          .deferredForPlayback,
      isFalse,
    );
    await Future<void>.delayed(const Duration(milliseconds: 8100));
    expect(controller.idleRequests, 2);
  });
}

class _NoEnginePlayback extends PlaybackController {
  @override
  PlaybackState build() => const PlaybackState();
}

class _SlowProgressLibrary extends LocalLibraryController {
  final started = Completer<void>();
  final progress = Completer<EpisodeProgress?>();

  @override
  List<LibraryItem> build() => const [];

  @override
  Future<EpisodeProgress?> loadEpisodeProgress(
    String mediaId,
    int season,
    double episode,
  ) {
    if (!started.isCompleted) started.complete();
    return progress.future;
  }
}

class _TestDriveController extends GoogleDriveSyncController {
  int idleRequests = 0;

  @override
  Future<GoogleDriveSyncState> build() async {
    // Install the actual lifecycle listener, but never provide credentials or
    // call a remote API. The resumed pass terminates at the token check.
    await super.build();
    return const GoogleDriveSyncState(configured: true, connected: true);
  }

  @override
  Future<void> syncNow({
    bool background = false,
    bool localChangesOnly = false,
    bool remoteChangesOnly = false,
    bool automaticRetry = false,
  }) {
    if (!ref.read(playbackActivityProvider)) idleRequests++;
    return super.syncNow(
      background: background,
      localChangesOnly: localChangesOnly,
      remoteChangesOnly: remoteChangesOnly,
      automaticRetry: automaticRetry,
    );
  }
}
