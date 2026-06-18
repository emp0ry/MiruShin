import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Re-routes the D-pad / arrow-key Up/Down on a TV into **reading-order**
/// focus traversal (`previousFocus`/`nextFocus`) instead of Flutter's default
/// *geometric* directional focus.
///
/// Geometric directional focus is unreliable on dense browse layouts: a button
/// that happens to sit above or between the posters (a section's "see more"
/// link in the header, or a centred "Load more" that is geometrically closer
/// than an off-screen poster row) wins the nearest-neighbour search, so the
/// D-pad lands on the button and the posters become unreachable. Reading-order
/// traversal walks the focusables in document order, so every poster is reached
/// before the trailing "see more" / "Load more" button.
///
/// Each move is followed by [Scrollable.ensureVisible] so the newly focused
/// item is scrolled into the viewport. Left/Right are intentionally left
/// untouched so they keep the framework's geometric behaviour (move within a
/// grid row / scroll a horizontal rail) and so the shell can still bounce a
/// left-edge press back to the navigation sidebar.
class TvDirectionalFocus extends StatelessWidget {
  const TvDirectionalFocus({required this.child, super.key});

  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final bool forward = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final bool backward = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!forward && !backward) return KeyEventResult.ignored;

    final FocusNode? primary = FocusManager.instance.primaryFocus;
    final bool moved = forward
        ? (primary?.nextFocus() ?? node.nextFocus())
        : (primary?.previousFocus() ?? node.previousFocus());
    if (moved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? focusedContext =
            FocusManager.instance.primaryFocus?.context;
        if (focusedContext == null) return;
        Scrollable.ensureVisible(
          focusedContext,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignmentPolicy: forward
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: child,
    );
  }
}
