import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/fvp_player_engine.dart';

void main() {
  group('FVP seek-aware native completion', () {
    test('suppresses END while a native seek is active or pending', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: true,
          nativeSeekPending: false,
          completionSuppressed: true,
          completionRearmReady: true,
          acceptedPositionMatches: true,
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
          completionRearmReady: true,
          acceptedPositionMatches: true,
        ),
        isFalse,
      );
    });

    test('requires accepted post-seek position and re-arm evidence', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          completionRearmReady: false,
          acceptedPositionMatches: true,
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
          completionRearmReady: true,
          acceptedPositionMatches: false,
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
          completionRearmReady: true,
          acceptedPositionMatches: true,
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
          completionRearmReady: false,
          acceptedPositionMatches: false,
        ),
        isTrue,
      );
    });
  });
}
