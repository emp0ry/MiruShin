import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/offline_stall_recovery.dart';
import 'package:mirushin/features/player/domain/playback_end_decision.dart';

void main() {
  group('evaluatePlaybackEnd', () {
    PlaybackEndEvaluation evaluate({
      required int positionSeconds,
      required int durationSeconds,
      bool completed = true,
      bool authoritative = true,
      PlaybackMediaKind kind = PlaybackMediaKind.segmented,
      int? highWaterSeconds,
    }) {
      return evaluatePlaybackEnd(
        backendCompleted: completed,
        durationIsAuthoritative: authoritative,
        mediaKind: kind,
        position: Duration(seconds: positionSeconds),
        maxObservedPosition: Duration(
          seconds: highWaterSeconds ?? positionSeconds,
        ),
        duration: Duration(seconds: durationSeconds),
      );
    }

    test('rejects every captured early EOF gap', () {
      expect(
        evaluate(positionSeconds: 1403, durationSeconds: 1434).decision,
        PlaybackEndDecision.prematureBackendEof,
      );
      expect(
        evaluate(positionSeconds: 1194, durationSeconds: 1246).decision,
        PlaybackEndDecision.prematureBackendEof,
      );
      expect(
        evaluate(positionSeconds: 1264, durationSeconds: 1305).decision,
        PlaybackEndDecision.prematureBackendEof,
      );
    });

    test('rejects required direct and segmented false EOF matrix', () {
      expect(
        evaluate(
          positionSeconds: 1374,
          durationSeconds: 1434,
          kind: PlaybackMediaKind.direct,
        ).decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'online direct 60 seconds early',
      );
      expect(
        evaluate(
          positionSeconds: 1403,
          durationSeconds: 1434,
          kind: PlaybackMediaKind.direct,
        ).decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'online direct 31 seconds early',
      );
      expect(
        evaluate(positionSeconds: 1414, durationSeconds: 1434).decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'online HLS 20 seconds early',
      );
      expect(
        evaluate(
          positionSeconds: 1194,
          durationSeconds: 1246,
          kind: PlaybackMediaKind.direct,
        ).decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'offline MP4 52 seconds early',
      );
      expect(
        evaluate(positionSeconds: 1264, durationSeconds: 1305).decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'offline HLS 41 seconds early',
      );
      expect(
        evaluate(positionSeconds: 1414, durationSeconds: 1434).decision,
        PlaybackEndDecision.prematureBackendEof,
        reason: 'offline DASH 20 seconds early',
      );
    });

    test('accepts only the final seconds for direct and segmented media', () {
      expect(
        evaluate(
          positionSeconds: 1432,
          durationSeconds: 1434,
          kind: PlaybackMediaKind.direct,
        ).decision,
        PlaybackEndDecision.confirmedEnded,
      );
      expect(
        evaluate(positionSeconds: 1430, durationSeconds: 1434).decision,
        PlaybackEndDecision.confirmedEnded,
      );
    });

    test('high-water validates backend reset to zero at real end', () {
      expect(
        evaluate(
          positionSeconds: 0,
          highWaterSeconds: 1432,
          durationSeconds: 1434,
          kind: PlaybackMediaKind.direct,
        ).decision,
        PlaybackEndDecision.confirmedEnded,
      );
    });

    test('backend reset to zero still rejects a premature high-water', () {
      expect(
        evaluate(
          positionSeconds: 0,
          highWaterSeconds: 1403,
          durationSeconds: 1434,
          kind: PlaybackMediaKind.direct,
        ).decision,
        PlaybackEndDecision.prematureBackendEof,
      );
    });

    test('unknown duration cannot authorize backend completion', () {
      expect(
        evaluate(
          positionSeconds: 1403,
          durationSeconds: 0,
          authoritative: false,
        ).decision,
        PlaybackEndDecision.durationUnreliable,
      );
    });

    test('85 percent watched remains separate from real completion', () {
      final PlaybackEndEvaluation result = evaluate(
        positionSeconds: 1224,
        durationSeconds: 1440,
        completed: false,
      );
      expect(result.watchedThresholdReached, isTrue);
      expect(result.decision, PlaybackEndDecision.notEnded);
      expect(result.confirmedEnded, isFalse);
    });
  });

  group('PlaybackDurationEvidence', () {
    test('rejects tiny duration and requires stable online data', () {
      final PlaybackDurationEvidence evidence = PlaybackDurationEvidence();
      evidence.observe(const Duration(seconds: 7));
      expect(
        evidence.isAuthoritative(
          isOffline: true,
          mediaKind: PlaybackMediaKind.segmented,
        ),
        isFalse,
      );

      evidence
        ..reset()
        ..observe(const Duration(seconds: 1434));
      expect(
        evidence.isAuthoritative(
          isOffline: false,
          mediaKind: PlaybackMediaKind.segmented,
        ),
        isFalse,
      );
      evidence.observe(const Duration(seconds: 1434));
      expect(
        evidence.isAuthoritative(
          isOffline: false,
          mediaKind: PlaybackMediaKind.segmented,
        ),
        isTrue,
      );

      evidence
        ..reset()
        ..observe(const Duration(seconds: 1434));
      expect(
        evidence.isAuthoritative(
          isOffline: false,
          mediaKind: PlaybackMediaKind.direct,
        ),
        isFalse,
        reason: 'online direct duration must stabilize too',
      );
      evidence.observe(const Duration(seconds: 1434));
      expect(
        evidence.isAuthoritative(
          isOffline: false,
          mediaKind: PlaybackMediaKind.direct,
        ),
        isTrue,
      );
    });

    test('reports material duration growth', () {
      final PlaybackDurationEvidence evidence = PlaybackDurationEvidence();
      expect(evidence.observe(const Duration(seconds: 1400)), isFalse);
      expect(evidence.observe(const Duration(seconds: 1400)), isFalse);
      expect(evidence.observe(const Duration(seconds: 1434)), isTrue);
      expect(evidence.maximum, const Duration(seconds: 1434));
    });
  });

  group('offlinePlaybackStallDecision', () {
    test('recovers when requested playback has stopped progressing', () {
      expect(
        offlinePlaybackStallDecision(
          desiredPlaying: true,
          isInitialized: true,
          isCompleted: false,
          hasError: false,
          interactionInProgress: false,
          isNearEnd: false,
          position: const Duration(seconds: 7),
          observedPosition: const Duration(seconds: 7),
          stalledFor: const Duration(seconds: 4),
        ),
        OfflinePlaybackStallDecision.recover,
      );
    });

    test('waits before the recovery threshold', () {
      expect(
        offlinePlaybackStallDecision(
          desiredPlaying: true,
          isInitialized: true,
          isCompleted: false,
          hasError: false,
          interactionInProgress: false,
          isNearEnd: false,
          position: const Duration(seconds: 7),
          observedPosition: const Duration(seconds: 7),
          stalledFor: const Duration(seconds: 3),
        ),
        OfflinePlaybackStallDecision.waiting,
      );
    });

    test('resets the observation when playback advances', () {
      expect(
        offlinePlaybackStallDecision(
          desiredPlaying: true,
          isInitialized: true,
          isCompleted: false,
          hasError: false,
          interactionInProgress: false,
          isNearEnd: false,
          position: const Duration(milliseconds: 7300),
          observedPosition: const Duration(seconds: 7),
          stalledFor: const Duration(seconds: 5),
        ),
        OfflinePlaybackStallDecision.progressed,
      );
    });

    test('does not interfere with intentional or terminal states', () {
      OfflinePlaybackStallDecision decide({
        bool desiredPlaying = true,
        bool isInitialized = true,
        bool isCompleted = false,
        bool hasError = false,
        bool interactionInProgress = false,
        bool isNearEnd = false,
      }) {
        return offlinePlaybackStallDecision(
          desiredPlaying: desiredPlaying,
          isInitialized: isInitialized,
          isCompleted: isCompleted,
          hasError: hasError,
          interactionInProgress: interactionInProgress,
          isNearEnd: isNearEnd,
          position: const Duration(seconds: 7),
          observedPosition: const Duration(seconds: 7),
          stalledFor: const Duration(seconds: 5),
        );
      }

      expect(
        decide(desiredPlaying: false),
        OfflinePlaybackStallDecision.inactive,
      );
      expect(
        decide(isInitialized: false),
        OfflinePlaybackStallDecision.inactive,
      );
      expect(decide(isCompleted: true), OfflinePlaybackStallDecision.inactive);
      expect(decide(hasError: true), OfflinePlaybackStallDecision.inactive);
      expect(
        decide(interactionInProgress: true),
        OfflinePlaybackStallDecision.inactive,
      );
      expect(decide(isNearEnd: true), OfflinePlaybackStallDecision.inactive);
    });
  });
}
