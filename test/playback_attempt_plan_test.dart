import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/playback_attempt_plan.dart';
import 'package:mirushin/features/player/domain/player_models.dart';

void main() {
  List<String> labels(List<PlaybackAttempt> attempts) {
    return attempts.map((PlaybackAttempt attempt) => attempt.label).toList();
  }

  test('Auto uses the exact MPV then FVP proxy/direct order', () {
    final List<PlaybackAttempt> attempts = buildPlaybackAttemptPlan(
      preference: PlayerBackend.auto,
      mpvAvailable: true,
      fvpAvailable: true,
      proxyEligible: true,
      directEligible: true,
    );

    expect(labels(attempts), <String>[
      'MPV + local proxy',
      'MPV + direct',
      'FVP + local proxy',
      'FVP + direct',
    ]);
  });

  test('Auto skips MPV when the platform does not provide it', () {
    final List<PlaybackAttempt> attempts = buildPlaybackAttemptPlan(
      preference: PlayerBackend.auto,
      mpvAvailable: false,
      fvpAvailable: true,
      proxyEligible: true,
      directEligible: true,
    );

    expect(labels(attempts), <String>['FVP + local proxy', 'FVP + direct']);
  });

  test('an explicit backend does not silently switch backend', () {
    final List<PlaybackAttempt> attempts = buildPlaybackAttemptPlan(
      preference: PlayerBackend.fvp,
      mpvAvailable: true,
      fvpAvailable: true,
      proxyEligible: true,
      directEligible: true,
    );

    expect(labels(attempts), <String>['FVP + local proxy', 'FVP + direct']);
  });

  test('routes that cannot be used by the source are omitted', () {
    final List<PlaybackAttempt> directOnly = buildPlaybackAttemptPlan(
      preference: PlayerBackend.auto,
      mpvAvailable: true,
      fvpAvailable: true,
      proxyEligible: false,
      directEligible: true,
    );
    final List<PlaybackAttempt> proxyOnly = buildPlaybackAttemptPlan(
      preference: PlayerBackend.auto,
      mpvAvailable: true,
      fvpAvailable: true,
      proxyEligible: true,
      directEligible: false,
    );

    expect(labels(directOnly), <String>['MPV + direct', 'FVP + direct']);
    expect(labels(proxyOnly), <String>[
      'MPV + local proxy',
      'FVP + local proxy',
    ]);
  });

  test('backend-specific route capabilities omit impossible fallbacks', () {
    final List<PlaybackAttempt> attempts = buildPlaybackAttemptPlan(
      preference: PlayerBackend.auto,
      mpvAvailable: false,
      fvpAvailable: true,
      proxyEligible: true,
      directEligible: true,
      fvpProxyEligible: true,
      fvpDirectEligible: false,
    );

    expect(labels(attempts), <String>['FVP + local proxy']);
  });

  test('web receives one browser-native direct attempt', () {
    final List<PlaybackAttempt> attempts = buildPlaybackAttemptPlan(
      preference: PlayerBackend.auto,
      mpvAvailable: false,
      fvpAvailable: false,
      proxyEligible: false,
      directEligible: true,
      usesBrowserBackend: true,
    );

    expect(labels(attempts), <String>['browser + direct']);
  });
}
