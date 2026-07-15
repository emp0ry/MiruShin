bool seekHasSettled({
  required Duration position,
  required Duration target,
  required Duration? from,
  required Duration tolerance,
  Duration? forwardTolerance,
}) {
  final int diffMs = (position.inMilliseconds - target.inMilliseconds).abs();
  if (diffMs <= tolerance.inMilliseconds) return true;

  final Duration? start = from;
  if (start == null || target <= start) return false;

  // Forward seeks can land on a nearby keyframe and then immediately continue
  // playing. Once playback is close to or past the requested target, retrying
  // the same seek only pulls the stream backwards and makes the clock bounce.
  final Duration acceptedForwardLag = forwardTolerance ?? tolerance;
  return position + acceptedForwardLag >= target;
}
