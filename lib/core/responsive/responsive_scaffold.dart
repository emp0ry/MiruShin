import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_routes.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../features/catalog/application/catalog_mode.dart';
import '../../features/settings/presentation/startup_update_popup.dart';
import '../platform/tv_platform.dart';
import 'adaptive_navigation.dart';
import 'app_breakpoints.dart';
import 'app_navigation_item.dart';

class ResponsiveScaffold extends ConsumerWidget {
  const ResponsiveScaffold({
    required this.child,
    required this.currentLocation,
    required this.onDestinationSelected,
    super.key,
  });

  final Widget child;
  final String currentLocation;
  final ValueChanged<String> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final CatalogMode catalogMode = ref.watch(catalogModeProvider);
    final bool isTv = ref.watch(isAndroidTvProvider);
    final List<AppNavigationItem> items = appNavigationItemsForMode(
      catalogMode,
    );
    void switchCatalogMode() {
      final CatalogMode next = ref.read(catalogModeProvider).toggled;
      unawaited(ref.read(catalogModeProvider.notifier).setMode(next));
      _showCatalogSwitchBanner(context, next);
      if (currentLocation.startsWith('/media') ||
          currentLocation.startsWith('/watch')) {
        onDestinationSelected('/board');
      } else if (next == CatalogMode.tmdb &&
          currentLocation.startsWith(AppRoutes.profile)) {
        onDestinationSelected(AppRoutes.settings);
      }
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // On Android TV always use the labelled sidebar (the 10-foot nav) and
        // never the bottom bar, regardless of the reported window width.
        final WindowSizeClass sizeClass = isTv
            ? WindowSizeClass.expanded
            : AppBreakpoints.classify(constraints.maxWidth);

        final Widget bodyRow = Row(
          children: <Widget>[
            if (sizeClass != WindowSizeClass.compact)
              AdaptiveNavigation(
                items: items,
                currentLocation: currentLocation,
                onDestinationSelected: onDestinationSelected,
                sizeClass: sizeClass,
                catalogMode: catalogMode,
                onLogoPressed: switchCatalogMode,
                isTv: isTv,
              ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  child,
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: StartupUpdatePopup(),
                  ),
                ],
              ),
            ),
          ],
        );

        final GoRouter router = GoRouter.of(context);
        final bool atHome =
            currentLocation == AppRoutes.board || currentLocation == '/';

        return PopScope<void>(
          // Only let the system pop (which exits the app) when we are on the
          // home tab with nothing pushed on top. Everywhere else, BACK navigates
          // within the app — pop the pushed route, otherwise return to the home
          // tab — instead of jumping straight to the Android TV launcher.
          canPop: atHome && !router.canPop(),
          onPopInvokedWithResult: (bool didPop, void result) {
            if (didPop) return;
            if (router.canPop()) {
              router.pop();
            } else if (!atHome) {
              onDestinationSelected(AppRoutes.board);
            }
          },
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: palette.shellGradient),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                bottom: sizeClass != WindowSizeClass.compact,
                // Keep content inside the TV-safe (overscan) area so nothing is
                // clipped by the bezel on televisions that still overscan.
                child: isTv
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.xl,
                          AppSpacing.lg,
                        ),
                        child: bodyRow,
                      )
                    : bodyRow,
              ),
              bottomNavigationBar: sizeClass == WindowSizeClass.compact
                  ? AdaptiveNavigation(
                      items: items,
                      currentLocation: currentLocation,
                      onDestinationSelected: onDestinationSelected,
                      sizeClass: sizeClass,
                      catalogMode: catalogMode,
                      onLogoPressed: switchCatalogMode,
                      isTv: isTv,
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}

void _showCatalogSwitchBanner(BuildContext context, CatalogMode mode) {
  final OverlayState? overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext context) {
      final ColorScheme scheme = Theme.of(context).colorScheme;
      return Positioned(
        top: MediaQuery.paddingOf(context).top + 12,
        left: 24,
        right: 24,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.inverseSurface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Text(
                  'Switched to ${mode.label}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  Future<void>.delayed(const Duration(seconds: 3), () {
    if (entry.mounted) entry.remove();
  });
}
