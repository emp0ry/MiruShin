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
          completionRearmReady: true,
          nativeSeekAccepted: true,
        ),
        isFalse,
      );
    });

    test('requires accepted native seek and re-arm evidence', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          completionRearmReady: false,
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
          completionRearmReady: true,
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
          completionRearmReady: true,
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
          completionRearmReady: false,
          nativeSeekAccepted: false,
        ),
        isTrue,
      );
    });

    test('re-arms a latched END after playback advances past seek result', () {
      expect(
        shouldExposeFvpNativeCompletion(
          nativeEnded: true,
          initialized: true,
          nativeSeekActive: false,
          nativeSeekPending: false,
          completionSuppressed: true,
          completionRearmReady: true,
          nativeSeekAccepted: true,
        ),
        isTrue,
        reason:
            'native acceptance belongs to the seek result; the later position '
            'must not keep completion suppressed forever',
      );
    });
  });
}
