const Duration startupSeekTolerance = Duration(milliseconds: 1500);

/// Returns true only while playback is still meaningfully behind the position
/// requested when the media was opened.
///
/// Native players can begin advancing before their manifest is fully seekable.
/// Once that clock has reached (or passed) the requested point, issuing the old
/// startup seek would only replay content the viewer has already seen.
bool startupSeekNeeded({
  required Duration requested,
  required Duration current,
  Duration tolerance = startupSeekTolerance,
}) {
  if (requested <= Duration.zero) return false;
  return current + tolerance < requested;
}
