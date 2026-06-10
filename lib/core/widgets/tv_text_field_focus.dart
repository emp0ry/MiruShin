import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets the D-pad / arrow keys escape a **single-line** text field vertically.
///
/// By default a focused text field swallows Up/Down to move the caret, so on a
/// TV remote there is no way to leave the field and reach the widgets above or
/// below it. Wrapping the field re-maps Up/Down to directional focus traversal
/// (Left/Right still edit the text). Only use this around single-line inputs —
/// a multi-line field genuinely needs Up/Down for caret movement.
class TvTextFieldFocus extends StatelessWidget {
  const TvTextFieldFocus({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
        ),
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
        ),
      },
      child: child,
    );
  }
}
