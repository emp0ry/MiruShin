import 'dart:async';

import 'package:flutter/gestures.dart';
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
  static const double _edgeWidth = 32;
  static const double _triggerDistance = 72;
  static const double _minFlingDistance = 18;
  static const double _minFlingVelocity = 620;

  bool _startedFromTouchEdge = false;
  bool _triggered = false;
  double _dragDistance = 0;

  void _handlePointerDown(PointerDownEvent event) {
    _startedFromTouchEdge =
        widget.enabled &&
        event.kind == PointerDeviceKind.touch &&
        event.localPosition.dx <= _edgeWidth;
    _triggered = false;
    _dragDistance = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_startedFromTouchEdge || _triggered) return;
    final double delta = details.primaryDelta ?? 0;
    _dragDistance = (_dragDistance + delta).clamp(0, double.infinity);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_startedFromTouchEdge || _triggered) {
      _resetGesture();
      return;
    }

    final double velocity = details.primaryVelocity ?? 0;
    final bool crossedDistance = _dragDistance >= _triggerDistance;
    final bool flungRight =
        velocity >= _minFlingVelocity && _dragDistance >= _minFlingDistance;
    if (crossedDistance || flungRight) {
      _triggered = true;
      goBackOrGo(context, AppRoutes.board);
    }
    _resetGesture();
  }

  void _resetGesture() {
    _startedFromTouchEdge = false;
    _dragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        widget.child,
        if (widget.enabled)
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: _edgeWidth,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerCancel: (_) => _resetGesture(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                dragStartBehavior: DragStartBehavior.start,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                onHorizontalDragCancel: _resetGesture,
              ),
            ),
          ),
      ],
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
