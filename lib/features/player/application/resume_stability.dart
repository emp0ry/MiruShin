import '../engine/player_engine.dart';

enum ResumeStabilityDecision { stable, waiting, recover, canceled }

Duration bufferedAheadForPosition(
  Iterable<PlayerBufferedRange> ranges,
  Duration position,
) {
  Duration bufferedAhead = Duration.zero;
  for (final PlayerBufferedRange range in ranges) {
    if (position < range.start || position > range.end) continue;
    final Duration ahead = range.end - position;
    if (ahead > bufferedAhead) bufferedAhead = ahead;
  }
  return bufferedAhead;
}

bool resumeHasProgressed({
  required Duration position,
  required Duration resumeFrom,
  Duration tolerance = const Duration(milliseconds: 200),
}) {
  return position >= resumeFrom + tolerance;
}

bool resumePositionNeedsCorrection({
  required Duration position,
  required Duration resumeFrom,
  Duration tolerance = const Duration(milliseconds: 1500),
}) {
  return position + tolerance < resumeFrom;
}

ResumeStabilityDecision resumeStabilityDecision({
  required bool desiredPlaying,
  required bool isInitialized,
  required bool isBuffering,
  required bool hasError,
  required Duration position,
  required Duration resumeFrom,
  required Duration bufferedAhead,
  required Duration elapsed,
  Duration progressTolerance = const Duration(milliseconds: 200),
  Duration normalTimeout = const Duration(milliseconds: 2600),
  Duration bufferedTimeout = const Duration(milliseconds: 5200),
  Duration bufferedAheadThreshold = const Duration(seconds: 2),
}) {
  if (!desiredPlaying) return ResumeStabilityDecision.canceled;
  if (hasError) return ResumeStabilityDecision.recover;
  if (resumeHasProgressed(
    position: position,
    resumeFrom: resumeFrom,
    tolerance: progressTolerance,
  )) {
    return ResumeStabilityDecision.stable;
  }

  final Duration timeout =
      isBuffering && bufferedAhead >= bufferedAheadThreshold
      ? bufferedTimeout
      : normalTimeout;
  if (!isInitialized || elapsed < timeout) {
    return ResumeStabilityDecision.waiting;
  }
  return ResumeStabilityDecision.recover;
}
