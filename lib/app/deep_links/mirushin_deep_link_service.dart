import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../features/catalog/application/catalog_mode.dart';
import '../app_routes.dart';
import 'mirushin_deep_link.dart';
import 'mirushin_deep_link_queue.dart';

typedef MiruShinCatalogModeSetter = Future<void> Function(CatalogMode mode);

class MiruShinDeepLinkService {
  MiruShinDeepLinkService._();

  static final MiruShinDeepLinkService instance = MiruShinDeepLinkService._();

  static const MethodChannel _windowChannel = MethodChannel('mirushin/window');

  late final MiruShinDeepLinkQueue _queue = MiruShinDeepLinkQueue(
    dispatch: _dispatch,
  );
  StreamSubscription<String>? _subscription;
  GoRouter? _router;
  MiruShinCatalogModeSetter? _setCatalogMode;
  int _activation = 0;

  void initialize() {
    _subscription ??= AppLinks().stringLinkStream.listen(
      accept,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('A platform deep-link activation could not be read.');
      },
    );
  }

  @visibleForTesting
  void accept(String raw) => _queue.accept(raw);

  void attachRouter(
    GoRouter router, {
    required MiruShinCatalogModeSetter setCatalogMode,
  }) {
    _queue.markNotReady();
    _router = router;
    _setCatalogMode = setCatalogMode;
  }

  void markNavigationReady(GoRouter router) {
    if (!identical(_router, router)) return;
    _queue.markReady();
  }

  void detachRouter(GoRouter router) {
    if (!identical(_router, router)) return;
    _router = null;
    _setCatalogMode = null;
    _queue.markNotReady();
  }

  void _dispatch(MiruShinDeepLink link) {
    final GoRouter? router = _router;
    if (router == null) return;
    _activation++;
    switch (link) {
      case MiruShinMediaDeepLink():
        final MiruShinCatalogModeSetter? setCatalogMode = _setCatalogMode;
        if (setCatalogMode != null) {
          unawaited(setCatalogMode(catalogModeForMediaDeepLink(link)));
        }
        router.go(AppRoutes.mediaDetailsPath(link.internalMediaId));
      case MiruShinWatchPartyDeepLink():
        router.go(
          '${AppRoutes.watchPartyJoin}?activation=$_activation',
          extra: link.invite,
        );
    }
    unawaited(_foregroundWindow());
  }

  Future<void> _foregroundWindow() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.windows &&
            defaultTargetPlatform != TargetPlatform.linux &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return;
    }
    try {
      await _windowChannel.invokeMethod<void>('foreground');
    } on MissingPluginException {
      // Older portable builds can still route the activation.
    } on PlatformException {
      // Foregrounding is best-effort; never discard an otherwise valid link.
    }
  }
}

CatalogMode catalogModeForMediaDeepLink(MiruShinMediaDeepLink link) =>
    switch (link.provider) {
      MiruShinMediaProvider.tmdb => CatalogMode.tmdb,
      MiruShinMediaProvider.anilist => CatalogMode.anilist,
    };
