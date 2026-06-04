import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_routes.dart';
import '../../app/navigation_helpers.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../features/catalog/application/catalog_mode.dart';
import '../../features/settings/presentation/startup_update_popup.dart';
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
        final WindowSizeClass sizeClass = AppBreakpoints.classify(
          constraints.maxWidth,
        );

        return DecoratedBox(
          decoration: BoxDecoration(gradient: palette.shellGradient),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              bottom: sizeClass != WindowSizeClass.compact,
              child: Row(
                children: <Widget>[
                  if (sizeClass != WindowSizeClass.compact)
                    AdaptiveNavigation(
                      items: items,
                      currentLocation: currentLocation,
                      onDestinationSelected: onDestinationSelected,
                      sizeClass: sizeClass,
                      catalogMode: catalogMode,
                      onLogoPressed: switchCatalogMode,
                    ),
                  Expanded(
                    child: _MobileBackSwipeRegion(
                      enabled: sizeClass == WindowSizeClass.compact,
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
                  ),
                ],
              ),
            ),
            bottomNavigationBar: sizeClass == WindowSizeClass.compact
                ? AdaptiveNavigation(
                    items: items,
                    currentLocation: currentLocation,
                    onDestinationSelected: onDestinationSelected,
                    sizeClass: sizeClass,
                    catalogMode: catalogMode,
                    onLogoPressed: switchCatalogMode,
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _MobileBackSwipeRegion extends StatefulWidget {
  const _MobileBackSwipeRegion({required this.child, required this.enabled});

  final Widget child;
  final bool enabled;

  @override
  State<_MobileBackSwipeRegion> createState() => _MobileBackSwipeRegionState();
}

class _MobileBackSwipeRegionState extends State<_MobileBackSwipeRegion> {
  static const double _edgeWidth = 72;
  static const double _triggerDistance = 72;
  static const double _minHorizontalBias = 1.2;

  int? _activePointer;
  Offset? _startPosition;
  bool _triggered = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled ||
        _activePointer != null ||
        event.localPosition.dx > _edgeWidth) {
      return;
    }
    _activePointer = event.pointer;
    _startPosition = event.localPosition;
    _triggered = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _triggered) return;
    final Offset? start = _startPosition;
    if (start == null) return;

    final Offset delta = event.localPosition - start;
    if (delta.dx < _triggerDistance) return;

    final bool mostlyHorizontal =
        delta.dx > delta.dy.abs() * _minHorizontalBias;
    if (!mostlyHorizontal) return;

    _triggered = true;
    goBackOrGo(context, AppRoutes.board);
    _resetGesture(event.pointer);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _resetGesture(event.pointer);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _resetGesture(event.pointer);
  }

  void _resetGesture(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    _startPosition = null;
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
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
