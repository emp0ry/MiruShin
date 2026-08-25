import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/offline_stall_recovery.dart';

void main() {
  group('playbackCompletionIsCredible', () {
    test('rejects the false first-segment completion from offline HLS', () {
      expect(
        playbackCompletionIsCredible(
          isCompleted: true,
          isOfflineLocalSegmentedMedia: true,
          duration: const Duration(seconds: 7),
          maxObservedPosition: const Duration(seconds: 7),
        ),
        isFalse,
      );
    });

    test('accepts offline HLS completion after the full duration is known', () {
      expect(
        playbackCompletionIsCredible(
          isCompleted: true,
          isOfflineLocalSegmentedMedia: true,
          duration: const Duration(minutes: 24),
          maxObservedPosition: const Duration(minutes: 24),
        ),
        isTrue,
      );
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
