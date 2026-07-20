import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/platform/tv_platform.dart';
import '../features/addons/application/cloudflare_challenge_service.dart';
import '../features/addons/application/sora_addons_provider.dart';
import '../features/addons/presentation/cloudflare_challenge_page.dart';
import '../features/player/application/playback_controller.dart';
import 'app_routes.dart';
import '../features/profile/application/anilist_user_settings_provider.dart';
import '../features/settings/presentation/settings_state.dart';
import '../features/tracking/application/anilist_library_provider.dart';
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
  static const Duration _exitPlaybackCleanupTimeout = Duration(seconds: 2);

  late final GoRouter _router;
  late final AppLifecycleListener _lifecycleListener;
  late final PlaybackController _playbackController;
  Future<void>? _exitPlaybackCleanup;

  @override
  void initState() {
    super.initState();
    _playbackController = ref.read(playbackControllerProvider.notifier);
    _router = buildAppRouter(widget.initialRoute);
    _lifecycleListener = AppLifecycleListener(
      onDetach: () => unawaited(_cleanupPlaybackForExit()),
      onExitRequested: () async {
        await _cleanupPlaybackForExit();
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
    _lifecycleListener.dispose();
    unawaited(_cleanupPlaybackForExit());
    CloudflareChallengeService.instance.registerSolver(null);
    super.dispose();
  }

  Future<void> _cleanupPlaybackForExit() {
    final Future<void>? cleanup = _exitPlaybackCleanup;
    if (cleanup != null) return cleanup;

    return _exitPlaybackCleanup = _playbackController
        .stop()
        .timeout(_exitPlaybackCleanupTimeout)
        .catchError((_) {
          // During process teardown the native player may already be half gone.
        });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = ref.watch(settingsProvider);
    ref.watch(soraAddonsProvider);
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        settings.cacheLimitMb * 1024 * 1024;
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
/// is available on this platform. Linux has no implementation that can read the
/// HttpOnly `cf_clearance` cookie, so the solver is left unregistered there and
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
/// its own routes when it finishes — which would tear a pushed challenge page
/// down before the user solves it. An overlay sits outside the navigation stack,
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

  Future<void> _warmMediaType(
    int generation,
    String key, {
    required String mediaType,
    required bool wantsRussianTitles,
  }) async {
    if (mediaType == 'MANGA') {
      await _settle(ref.read(anilistMangaPreviewListProvider.future));
      if (!_isActiveGeneration(generation, key)) return;
      await _settle(ref.read(anilistMangaListProvider.future));
      return;
    }

    await _settle(ref.read(anilistAnimePreviewListProvider.future));
    if (!_isActiveGeneration(generation, key)) return;
    final Future<void> fullList = _settle(
      ref.read(anilistAnimeListProvider.future),
    );
    if (wantsRussianTitles) {
      await Future.wait<void>(<Future<void>>[
        _settle(ref.read(anilistAnimePreviewRussianListProvider.future)),
        fullList,
      ]);
      if (!_isActiveGeneration(generation, key)) return;
      unawaited(_settle(ref.read(anilistAnimeRussianListProvider.future)));
      return;
    }
    await fullList;
  }

  void _scheduleWarmup(String key, bool wantsRussianTitles) {
    final int generation = ++_warmupGeneration;
    Future<void>.microtask(() async {
      if (!_isActiveGeneration(generation, key)) return;
      await Future.wait<void>(<Future<void>>[
        _warmMediaType(
          generation,
          key,
          mediaType: 'ANIME',
          wantsRussianTitles: wantsRussianTitles,
        ),
        _warmMediaType(
          generation,
          key,
          mediaType: 'MANGA',
          wantsRussianTitles: false,
        ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = ref.watch(settingsProvider);
    final bool wantsRussianTitles =
        ref.watch(aniListEffectiveTitleLanguageProvider) == 'RUSSIAN';
    if (!settings.hasAniListSession || settings.anilistViewerId == null) {
      _warmupKey = null;
      _warmupGeneration++;
      return const SizedBox.shrink();
    }

    final String nextKey =
        '${settings.anilistViewerId}:${settings.anilistAccessToken.trim()}:${wantsRussianTitles ? 'RUSSIAN' : 'BASE'}';
    if (_warmupKey != nextKey) {
      _warmupKey = nextKey;
      _scheduleWarmup(nextKey, wantsRussianTitles);
    }

    return const SizedBox.shrink();
  }
}
