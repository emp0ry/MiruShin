import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/application/resume_stability.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';

void main() {
  group('resume stability helpers', () {
    test('calculates buffered duration ahead of the current position', () {
      expect(
        bufferedAheadForPosition(const <PlayerBufferedRange>[
          PlayerBufferedRange(
            start: Duration(seconds: 4),
            end: Duration(seconds: 8),
          ),
          PlayerBufferedRange(
            start: Duration(seconds: 10),
            end: Duration(seconds: 20),
          ),
        ], const Duration(seconds: 12)),
        const Duration(seconds: 8),
      );
    });

    test('treats forward movement after resume as stable', () {
      expect(
        resumeStabilityDecision(
          desiredPlaying: true,
          isInitialized: true,
          isBuffering: false,
          hasError: false,
          position: const Duration(milliseconds: 10300),
          resumeFrom: const Duration(seconds: 10),
          bufferedAhead: Duration.zero,
          elapsed: const Duration(milliseconds: 400),
        ),
        ResumeStabilityDecision.stable,
      );
    });

    test('recovers after buffering without movement exceeds timeout', () {
      expect(
        resumeStabilityDecision(
          desiredPlaying: true,
          isInitialized: true,
          isBuffering: true,
          hasError: false,
          position: const Duration(seconds: 10),
          resumeFrom: const Duration(seconds: 10),
          bufferedAhead: Duration.zero,
          elapsed: const Duration(seconds: 3),
        ),
        ResumeStabilityDecision.recover,
      );
    });

    test('allows buffered streams extra time before recovery', () {
      expect(
        resumeStabilityDecision(
          desiredPlaying: true,
          isInitialized: true,
          isBuffering: true,
          hasError: false,
          position: const Duration(seconds: 10),
          resumeFrom: const Duration(seconds: 10),
          bufferedAhead: const Duration(seconds: 4),
          elapsed: const Duration(seconds: 3),
        ),
        ResumeStabilityDecision.waiting,
      );
    });

    test('detects backward drift that needs correction', () {
      expect(
        resumePositionNeedsCorrection(
          position: const Duration(seconds: 5),
          resumeFrom: const Duration(seconds: 10),
        ),
        isTrue,
      );
    });
  });
}
