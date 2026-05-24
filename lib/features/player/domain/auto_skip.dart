const Duration autoSkipTriggerLead = Duration(milliseconds: 900);
const Duration autoSkipMinimumJump = Duration(milliseconds: 250);

Duration? autoSkipTarget({
  required bool enabled,
  required Duration? start,
  required Duration? end,
  required Duration position,
  required Duration duration,
  Duration triggerLead = autoSkipTriggerLead,
}) {
  if (!enabled || start == null || end == null || end <= start) return null;
  if (duration <= Duration.zero) return null;

  final Duration triggerStart = start > triggerLead
      ? start - triggerLead
      : Duration.zero;
  if (position < triggerStart || position >= end) return null;

  final Duration target = end > duration ? duration : end;
  if (target <= position + autoSkipMinimumJump) return null;
  return target;
}
