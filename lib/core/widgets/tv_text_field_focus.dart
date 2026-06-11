import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets the D-pad / arrow keys escape a **single-line** text field vertically.
///
/// A focused text field normally swallows Up/Down to move the caret, so on a TV
/// remote there is no way to leave the field and reach the widgets above or
/// below it. This wraps the field in a non-focusable [Focus] whose `onKeyEvent`
/// re-routes Up/Down to directional focus traversal. Only use this around
/// single-line inputs — a multi-line field genuinely needs Up/Down.
class TvTextFieldFocus extends StatefulWidget {
  const TvTextFieldFocus({
    required this.child,
    this.releaseHorizontal = false,
    super.key,
  });

  final Widget child;

  /// Also let Left/Right leave the text field. Use this for search rows where
  /// D-pad right should reach filter/sort buttons; keep false for fields where
  /// editing the caret with Left/Right is more important.
  final bool releaseHorizontal;

  @override
  State<TvTextFieldFocus> createState() => _TvTextFieldFocusState();
}

class _TvTextFieldFocusState extends State<TvTextFieldFocus> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    super.dispose();
  }

  bool _containsPrimaryFocus() {
    final BuildContext? focusedContext =
        FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    if (focusedContext == context) return true;

    bool found = false;
    (focusedContext as Element).visitAncestorElements((Element ancestor) {
      if (ancestor == context) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  TraversalDirection? _directionForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
    if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
    if (!widget.releaseHorizontal) return null;
    if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
    if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
    return null;
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || !_containsPrimaryFocus()) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final FocusNode? primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;

    final TraversalDirection? direction = _directionForKey(event.logicalKey);
    if (direction == null) return false;
    return primary.focusInDirection(direction);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final FocusNode? primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;

    final TraversalDirection? direction = _directionForKey(event.logicalKey);
    if (direction == null) return KeyEventResult.ignored;
    return primary.focusInDirection(direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
