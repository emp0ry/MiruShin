import 'package:flutter/material.dart';

/// Adds an iOS-style "swipe from the left edge to go back" gesture on top of
/// [child].
///
/// The app's routes use a custom fade/slide transition (see `_fadePage` in the
/// router) rather than [CupertinoPageRoute], so Flutter's built-in interactive
/// back-swipe is not available. This widget restores that affordance on touch
/// devices: a horizontal drag that *starts* within [edgeWidth] of the left edge
/// and travels far enough (or fast enough) to the right invokes [onBack].
///
/// Only the thin left-edge strip claims the horizontal-drag gesture, so
/// horizontally scrolling content (carousels, sliders) elsewhere on the page is
/// left untouched.
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    required this.child,
    required this.onBack,
    this.enabled = true,
    this.edgeWidth = 24,
    super.key,
  });

  final Widget child;

  /// Invoked once when a completed edge swipe should navigate back.
  final VoidCallback onBack;

  /// When false the gesture strip is not installed and [child] is returned
  /// as-is (e.g. on desktop/TV where pointers aren't touch).
  final bool enabled;

  /// Width of the left-edge region in which a back swipe may begin.
  final double edgeWidth;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  // Distance (logical px) the swipe must travel rightwards to count as a back.
  static const double _distanceThreshold = 80;
  // …or this much horizontal velocity for a quick flick to count.
  static const double _velocityThreshold = 700;

  double _dragExtent = 0;
  bool _tracking = false;

  void _onStart(DragStartDetails details) {
    _tracking = true;
    _dragExtent = 0;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_tracking) _dragExtent += details.delta.dx;
  }

  void _onEnd(DragEndDetails details) {
    if (!_tracking) return;
    _tracking = false;
    final double velocity = details.velocity.pixelsPerSecond.dx;
    final bool farEnough = _dragExtent >= _distanceThreshold;
    final bool fastEnough =
        velocity >= _velocityThreshold && _dragExtent > 0;
    if (farEnough || fastEnough) {
      widget.onBack();
    }
    _dragExtent = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: widget.edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: () => _tracking = false,
          ),
        ),
      ],
    );
  }
}
