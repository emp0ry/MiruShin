import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/fvp_player_engine.dart';

void main() {
  group('FVP staged startup speed', () {
    test('waits for initialization, settled seek, and moving native clock', () {
      bool shouldApply({
        bool initialized = true,
        bool settled = true,
        bool playing = true,
        int previous = 1000,
        int current = 1250,
      }) => shouldApplyFvpStartupPlaybackSpeed(
        initialized: initialized,
        initialPositionSettled: settled,
        nativePlaying: playing,
        previousPositionMs: previous,
        currentPositionMs: current,
      );

      expect(shouldApply(), isTrue);
      expect(shouldApply(initialized: false), isFalse);
      expect(shouldApply(settled: false), isFalse);
      expect(shouldApply(playing: false), isFalse);
      expect(shouldApply(current: 1000), isFalse);
    });
  });

  group('FVP native completion plausibility', () {
    test('suppresses a local HLS END far from its authoritative end', () {
      expect(
        isPlausibleFvpNativeCompletion(
          nativeEnded: true,
          position: const Duration(seconds: 1182),
          authoritativeLocalDuration: const Duration(seconds: 1422),
        ),
        isFalse,
      );
    });

    test('keeps real local and duration-unknown completions visible', () {
      expect(
        isPlausibleFvpNativeCompletion(
          nativeEnded: true,
          position: const Duration(seconds: 1418),
          authoritativeLocalDuration: const Duration(seconds: 1422),
        ),
        isTrue,
      );
      expect(
        isPlausibleFvpNativeCompletion(
          nativeEnded: true,
          position: const Duration(seconds: 20),
          authoritativeLocalDuration: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('FVP seek-aware native completion', () {
    test('suppresses END while a native seek is active or pending', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: true,
          nativeSeekPending: false,
          completionSuppressed: true,
          freshNativeEndAfterSeek: true,
          nativeSeekAccepted: true,
        ),
        isFalse,
      );
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: true,
          completionSuppressed: true,
          freshNativeEndAfterSeek: true,
          nativeSeekAccepted: true,
        ),
        isFalse,
      );
    });

    test('requires accepted native seek and a fresh END transition', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          freshNativeEndAfterSeek: false,
          nativeSeekAccepted: true,
        ),
        isFalse,
      );
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          freshNativeEndAfterSeek: true,
          nativeSeekAccepted: false,
        ),
        isFalse,
      );
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          freshNativeEndAfterSeek: true,
          nativeSeekAccepted: true,
        ),
        isTrue,
      );
    });

    test('normal later END remains available after suppression clears', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: false,
          freshNativeEndAfterSeek: false,
          nativeSeekAccepted: false,
        ),
        isTrue,
      );
    });

    test('keeps an END latched through the seek suppressed', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          freshNativeEndAfterSeek: false,
          nativeSeekAccepted: true,
        ),
        isFalse,
        reason:
            'time passing or playback progress must not turn the same native '
            'END into a new completion event',
      );
    });
  });
}
