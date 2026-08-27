enum PlaybackEndDecision {
  notEnded,
  confirmedEnded,
  prematureBackendEof,
  durationUnreliable,
}

enum PlaybackMediaKind { direct, segmented }

class PlaybackEndEvaluation {
  const PlaybackEndEvaluation({
    required this.decision,
    required this.observedPosition,
    required this.authoritativeDuration,
    required this.watchedThresholdReached,
  });

  final PlaybackEndDecision decision;
  final Duration observedPosition;
  final Duration? authoritativeDuration;
  final bool watchedThresholdReached;

  bool get confirmedEnded => decision == PlaybackEndDecision.confirmedEnded;
}

/// Decides whether playback really reached the end.
///
/// The watched threshold and the end threshold deliberately answer different
/// questions. Crossing 85% may mark an episode watched, but it never confirms
/// EOF, resets resume progress, or permits auto-next.
PlaybackEndEvaluation evaluatePlaybackEnd({
  required bool backendCompleted,
  required bool durationIsAuthoritative,
  required PlaybackMediaKind mediaKind,
  required Duration position,
  required Duration maxObservedPosition,
  required Duration duration,
  double watchedFraction = 0.85,
}) {
  final Duration observedPosition = position > maxObservedPosition
      ? position
      : maxObservedPosition;
  final Duration? authoritativeDuration =
      durationIsAuthoritative && duration > Duration.zero ? duration : null;

  if (authoritativeDuration == null) {
    return PlaybackEndEvaluation(
      decision: backendCompleted
          ? PlaybackEndDecision.durationUnreliable
          : PlaybackEndDecision.notEnded,
      observedPosition: observedPosition,
      authoritativeDuration: null,
      watchedThresholdReached: false,
    );
  }

  final bool watchedThresholdReached =
      authoritativeDuration >= const Duration(minutes: 2) &&
      observedPosition.inMilliseconds >=
          authoritativeDuration.inMilliseconds * watchedFraction;
  final Duration endTolerance = switch (mediaKind) {
    PlaybackMediaKind.direct => const Duration(seconds: 2),
    PlaybackMediaKind.segmented => const Duration(seconds: 4),
  };
  final bool reachedRealEnd =
      observedPosition >= authoritativeDuration - endTolerance;

  return PlaybackEndEvaluation(
    decision: reachedRealEnd
        ? PlaybackEndDecision.confirmedEnded
        : backendCompleted
        ? PlaybackEndDecision.prematureBackendEof
        : PlaybackEndDecision.notEnded,
    observedPosition: observedPosition,
    authoritativeDuration: authoritativeDuration,
    watchedThresholdReached: watchedThresholdReached,
  );
}

/// Accumulates duration evidence without allowing a temporary, tiny segmented
/// manifest duration to become authoritative.
class PlaybackDurationEvidence {
  Duration _maximum = Duration.zero;
  int _matchingObservations = 0;

  Duration get maximum => _maximum;

  void reset() {
    _maximum = Duration.zero;
    _matchingObservations = 0;
  }

  /// Returns true only when a previously known duration grew materially.
  bool observe(Duration duration) {
    if (duration <= Duration.zero) return false;
    if (_maximum == Duration.zero) {
      _maximum = duration;
      _matchingObservations = 1;
      return false;
    }
    if (duration > _maximum + const Duration(seconds: 1)) {
      _maximum = duration;
      _matchingObservations = 1;
      return true;
    }
    if ((duration - _maximum).abs() <= const Duration(seconds: 1)) {
      _matchingObservations++;
      if (duration > _maximum) _maximum = duration;
    }
    return false;
  }

  bool isAuthoritative({
    required bool isOffline,
    required PlaybackMediaKind mediaKind,
  }) {
    if (_maximum < const Duration(seconds: 30)) return false;
    if (isOffline) return true;
    // Network decoders and manifests can publish a provisional duration while
    // opening. A repeated observation is cheap evidence that parsing settled,
    // for both direct media and segmented HLS/DASH.
    return _matchingObservations >= 2;
  }
}
