import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets the D-pad / arrow keys escape a **single-line** text field vertically.
///
/// A focused text field normally swallows Up/Down to move the caret, so on a TV
/// remote there is no way to leave the field and reach the widgets above or
/// below it. This wraps the field in a non-focusable [Focus] whose `onKeyEvent`
/// runs *before* the global text-editing shortcuts, re-routing Up/Down to
/// directional focus traversal (Left/Right still edit the text). Only use this
/// around single-line inputs — a multi-line field genuinely needs Up/Down.
class TvTextFieldFocus extends StatelessWidget {
  const TvTextFieldFocus({required this.child, super.key});

  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final FocusNode? primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      primary.focusInDirection(TraversalDirection.up);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
