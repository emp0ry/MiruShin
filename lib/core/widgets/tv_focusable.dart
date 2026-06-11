import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_radius.dart';

/// Wraps an interactive child with a prominent, D-pad-friendly focus indicator:
/// a gentle scale-up plus an accent ring and glow when the child holds focus.
///
/// Designed for the 10-foot (Android TV) experience, but harmless everywhere
/// else: the highlight is driven by [FocusableActionDetector.onShowFocusHighlight],
/// which only fires for keyboard / remote ("directional") focus — pointer taps
/// and touches never trigger the ring.
///
/// The wrapper owns the focus node and maps [ActivateIntent] (the D-pad center /
/// Enter / Space / gamepad-A keys) to [onTap]. By default it also handles
/// pointer taps itself, so it can be a drop-in replacement for a bare
/// `GestureDetector`. When the child already provides its own pointer handler
/// (e.g. an [InkWell] kept for its ripple), pass `interactPointer: false` so
/// taps aren't delivered twice.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius,
    this.scale = 1.04,
    this.enabled = true,
    this.interactPointer = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius? borderRadius;

  /// Scale applied to [child] while focused. Set to `1` to disable the zoom.
  final double scale;
  final bool enabled;

  /// Whether this widget should handle pointer taps itself. Set to `false` when
  /// an inner widget (e.g. [InkWell]) already handles them.
  final bool interactPointer;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  // Hold-to-long-press on the D-pad centre / Enter: a held activate key fires
  // [TvFocusable.onLongPress] after the standard long-press timeout, a short
  // press fires [TvFocusable.onTap] on release.
  Timer? _holdTimer;
  bool _holdFired = false;
  bool _keyHeld = false;

  static final Set<LogicalKeyboardKey> _activateKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  bool get _hasAction =>
      widget.onTap != null ||
      widget.onLongPress != null ||
      widget.onSecondaryTap != null;

  bool get _isEnabled => widget.enabled && _hasAction;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _handleFocusHighlight(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _keyHeld = false;
    _holdFired = false;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Only take over the activate keys when a long-press action exists;
    // otherwise the default ActivateIntent path handles the tap.
    if (!_isEnabled || widget.onLongPress == null) {
      return KeyEventResult.ignored;
    }
    if (!_activateKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (_keyHeld) return KeyEventResult.handled;
      _keyHeld = true;
      _holdFired = false;
      _holdTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _holdFired = true;
        widget.onLongPress?.call();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final bool fired = _holdFired;
      _cancelHold();
      if (!fired) widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final BorderRadius radius =
        widget.borderRadius ?? AppRadius.all(AppRadius.lg);

    Widget content = AnimatedScale(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      scale: _focused ? widget.scale : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _focused ? accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: _focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: widget.child,
      ),
    );

    if (widget.interactPointer && _isEnabled) {
      content = GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        child: content,
      );
    }

    // The outer Focus sees activate keys before the app-level ActivateIntent
    // shortcut, which is what makes hold-to-long-press possible; it never
    // takes focus itself.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: FocusableActionDetector(
        enabled: _isEnabled,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        mouseCursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onShowFocusHighlight: _handleFocusHighlight,
        onFocusChange: (bool focused) {
          if (!focused) _cancelHold();
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: content,
      ),
    );
  }
}
