enum OfflinePlaybackStallDecision { inactive, progressed, waiting, recover }

OfflinePlaybackStallDecision offlinePlaybackStallDecision({
  required bool desiredPlaying,
  required bool isInitialized,
  required bool isCompleted,
  required bool hasError,
  required bool interactionInProgress,
  required bool isNearEnd,
  required Duration position,
  required Duration observedPosition,
  required Duration stalledFor,
  Duration progressTolerance = const Duration(milliseconds: 250),
  Duration recoveryThreshold = const Duration(seconds: 4),
}) {
  if (!desiredPlaying ||
      !isInitialized ||
      isCompleted ||
      hasError ||
      interactionInProgress ||
      isNearEnd) {
    return OfflinePlaybackStallDecision.inactive;
  }

  if ((position - observedPosition).abs() >= progressTolerance) {
    return OfflinePlaybackStallDecision.progressed;
  }
  if (stalledFor < recoveryThreshold) {
    return OfflinePlaybackStallDecision.waiting;
  }
  return OfflinePlaybackStallDecision.recover;
}
