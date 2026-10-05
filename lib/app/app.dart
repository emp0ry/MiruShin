import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/cache/artwork_cache_manager.dart';
import '../core/constants/app_constants.dart';
import '../core/platform/native_exit_handshake.dart';
import '../core/platform/tv_platform.dart';
import '../features/addons/application/cloudflare_challenge_service.dart';
import '../features/addons/application/sora_addons_provider.dart';
import '../features/addons/data/sora_js_runtime.dart';
import '../features/addons/presentation/cloudflare_challenge_page.dart';
import '../features/catalog/application/catalog_mode.dart';
import '../features/library/application/canonical_library_repository.dart';
import '../features/library/application/google_drive_sync_controller.dart';
import '../features/metadata/application/metadata_cache_provider.dart';
import '../features/player/application/playback_controller.dart';
import '../features/settings/application/settings_state.dart';
import '../features/tracking/application/tracker_library_provider.dart';
import '../features/tracking/application/tracker_reconciliation_lifecycle.dart';
import '../features/tracking/application/tracker_sync_coordinator.dart';
import '../features/watch/application/stream_selection_preferences.dart';
import 'app_routes.dart';
import 'deep_links/mirushin_deep_link_service.dart';
import 'localization/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class MiruShinApp extends ConsumerStatefulWidget {
  const MiruShinApp({super.key, this.initialRoute = AppRoutes.board});

  final String initialRoute;

  @override
  ConsumerState<MiruShinApp> createState() => _MiruShinAppState();
}

class _MiruShinAppState extends ConsumerState<MiruShinApp> {
  static const Duration _exitWebViewCleanupTimeout = Duration(seconds: 2);

  late final GoRouter _router;
  late final AppLifecycleListener _lifecycleListener;
  late final PlaybackController _playbackController;
  late final SoraJsRuntime _soraRuntime;
  late final GoogleDriveSyncController _googleDriveSyncController;
  late final CanonicalLibraryDatabaseRegistry _libraryDatabaseRegistry;
  late final TrackerSyncCoordinatorRegistry _trackerCoordinatorRegistry;
  late final VoidCallback _stopDriveLifecycle;
  late final Future<void> Function() _stopTrackerReconciliation;
  final NativeExitHandshake _nativeExitHandshake = NativeExitHandshake();
  Future<void>? _exitCleanup;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      _nativeExitHandshake.attach(_cleanupForExit);
    }
    _playbackController = ref.read(playbackControllerProvider.notifier);
    _soraRuntime = ref.read(soraJsRuntimeProvider);
    _googleDriveSyncController = ref.read(
      googleDriveSyncControllerProvider.notifier,
    );
    _libraryDatabaseRegistry = ref.read(
      canonicalLibraryDatabaseRegistryProvider,
    );
    _trackerCoordinatorRegistry = ref.read(
      trackerSyncCoordinatorRegistryProvider,
    );
    _stopDriveLifecycle = ref.read(googleDriveSyncLifecycleProvider);
    _stopTrackerReconciliation = ref.read(
      trackerReconciliationLifecycleProvider,
    );
    _router = buildAppRouter(widget.initialRoute);
    MiruShinDeepLinkService.instance.attachRouter(
      _router,
      setCatalogMode: (CatalogMode mode) =>
          ref.read(catalogModeProvider.notifier).setMode(mode),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MiruShinDeepLinkService.instance.markNavigationReady(_router);
    });
    _lifecycleListener = AppLifecycleListener(
      onDetach: () => unawaited(_cleanupForExit()),
      onExitRequested: () async {
        await _cleanupForExit();
        return AppExitResponse.exit;
      },
    );
    if (_cloudflareWebViewSupported) {
      CloudflareChallengeService.instance.registerSolver(
        _solveCloudflareChallenge,
      );
    }
  }

  @override
  void dispose() {
    MiruShinDeepLinkService.instance.detachRouter(_router);
    _lifecycleListener.dispose();
    unawaited(_cleanupForExit().then((_) => _nativeExitHandshake.detach()));
    CloudflareChallengeService.instance.registerSolver(null);
    super.dispose();
  }

  Future<void> _cleanupForExit() {
    final Future<void>? cleanup = _exitCleanup;
    if (cleanup != null) return cleanup;

    return _exitCleanup = () async {
      _stopDriveLifecycle();
      final trackerReconciliationStopped = _stopTrackerReconciliation();
      final driveStopped = _googleDriveSyncController.prepareForExit();
      // Do not time out persistence: a timeout leaves SQLite writes running
      // while the native engine tears down. Save the player's final checkpoint
      // before stopping the local mutation lane.
      await _playbackController.prepareForExit();
      await Future.wait<void>(<Future<void>>[
        driveStopped,
        _trackerCoordinatorRegistry.prepareForExit(),
        trackerReconciliationStopped,
        _soraRuntime.shutdown().timeout(_exitWebViewCleanupTimeout).catchError((
          _,
        ) {
          // Native WebView teardown is best-effort during process exit.
        }),
      ]);
      // This must be the final step: all sync/database users are stopped first,
      // then Drift is closed and awaited before Flutter tears down the Dart VM.
      await _libraryDatabaseRegistry.closeAll();
    }();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = ref.watch(settingsProvider);
    final metadataCache = ref.watch(metadataCacheStoreProvider);
    ref.watch(soraAddonsProvider);
    ref.watch(googleDriveSyncLifecycleProvider);
    ref.watch(trackerReconciliationLifecycleProvider);
    ref.watch(streamSelectionMigrationProvider);
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        settings.cacheLimitMb * 1024 * 1024;
    configureMiruShinArtworkCache(
      maxCacheBytes: settings.cacheLimitMb * 1024 * 1024,
      retention: settings.cacheRetention.duration,
      otherCacheSizeBytes: metadataCache.cacheSizeBytes,
    );
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      builder: (BuildContext context, Widget? child) {
        Widget content = Shortcuts(
          // Map the Android TV remote's centre/select key (and gamepad A) to
          // the standard "activate" action, so a D-pad press triggers the
          // focused button/card exactly like Enter does. Arrow-key directional
          // focus and Enter/Space activation already come from WidgetsApp
          // defaults; unmatched keys fall through to those.
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          },
          child: Stack(
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              const _AniListLibraryWarmup(),
            ],
          ),
        );
        if (TvPlatform.isAndroidTv) {
          // Some TVs apply a large system font scale that blows the 10-foot UI
          // up; pin text to 1.0x so layout stays predictable on television.
          content = MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: content,
          );
        }
        return content;
      },
      theme: AppTheme.light(accent: settings.accentColor),
      darkTheme: settings.themeMode == AppThemeMode.oled
          ? AppTheme.oled(accent: settings.accentColor)
          : AppTheme.dark(accent: settings.accentColor),
      themeMode: settings.themeMode.materialThemeMode,
      locale: settings.appLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scrollBehavior: _MouseDragScrollBehavior(),
      routerConfig: _router,
    );
  }
}

/// Whether an interactive Cloudflare challenge WebView (flutter_inappwebview)
/// is available on this platform. Linux has no embedded WebView implementation
/// for the browser-context retry, so the solver is left unregistered there and
/// challenged fetches surface their error instead of opening a broken WebView.
bool get _cloudflareWebViewSupported {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// Shows the interactive challenge page in the root overlay and returns the
/// captured cookies. Registered into [CloudflareChallengeService] at app start.
///
/// An overlay entry (rather than a pushed route) is deliberate: a Sora source
/// can fire many parallel fetches, and the flow that triggered them often pops
/// its own routes when it finishes. Popping those routes would tear down a
/// challenge page before the user solves it. An overlay sits outside the navigation stack,
/// so it survives until the user solves or cancels.
Future<CloudflareSolveResult?> _solveCloudflareChallenge({
  required Uri url,
  required String userAgent,
}) {
  final OverlayState? overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return Future<CloudflareSolveResult?>.value();

  final Completer<CloudflareSolveResult?> completer =
      Completer<CloudflareSolveResult?>();
  late final OverlayEntry entry;

  void close(CloudflareSolveResult? result) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (_) => CloudflareChallengePage(url: url, onResult: close),
  );
  overlay.insert(entry);
  return completer.future;
}

class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class _AniListLibraryWarmup extends ConsumerStatefulWidget {
  const _AniListLibraryWarmup();

  @override
  ConsumerState<_AniListLibraryWarmup> createState() =>
      _AniListLibraryWarmupState();
}

class _AniListLibraryWarmupState extends ConsumerState<_AniListLibraryWarmup> {
  String? _warmupKey;
  int _warmupGeneration = 0;

  bool _isActiveGeneration(int generation, String key) {
    return mounted && _warmupGeneration == generation && _warmupKey == key;
  }

  Future<void> _settle(Future<Object?> future) async {
    try {
      await future;
    } catch (_) {}
  }

  void _scheduleWarmup(String key) {
    final int generation = ++_warmupGeneration;
    Future<void>.microtask(() async {
      if (!_isActiveGeneration(generation, key)) return;
      await Future.wait<void>(<Future<void>>[
        _settle(ref.read(trackerLocalAnimeLibraryProvider.future)),
        _settle(ref.read(trackerLocalMangaLibraryProvider.future)),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = ref.watch(settingsProvider);
    final String nextKey =
        '${settings.anilistViewerId ?? 'local'}:${settings.malViewerId ?? '-'}:${settings.shikimoriViewerId ?? '-'}';
    if (_warmupKey != nextKey) {
      _warmupKey = nextKey;
      _scheduleWarmup(nextKey);
    }

    return const SizedBox.shrink();
  }
}
