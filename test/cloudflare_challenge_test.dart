import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/application/cloudflare_challenge_service.dart';
import 'package:mirushin/features/addons/data/cloudflare_challenge.dart';

void main() {
  group('CloudflareChallenge.isChallenge', () {
    test('recognizes a managed Cloudflare challenge', () {
      expect(
        CloudflareChallenge.isChallenge(
          403,
          <String, dynamic>{'server': 'cloudflare'},
          '<title>Just a moment...</title>'
          '<script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script>',
        ),
        isTrue,
      );
    });

    test('keeps a Cloudflare block detectable so the solver can open', () {
      expect(
        CloudflareChallenge.isChallenge(
          403,
          <String, dynamic>{'server': 'cloudflare'},
          '<title>Attention Required! | Cloudflare</title>'
          '<h1>Sorry, you have been blocked</h1>'
          '<h2>You are unable to access example.com</h2>'
          '<script src="/cdn-cgi/challenge-platform/scripts/precursor/main.js"></script>',
        ),
        isTrue,
      );
    });
  });

  group('CloudflareChallenge.isChallengeDocument', () {
    test('recognizes a challenge from the title before a DOM probe', () {
      expect(
        CloudflareChallenge.isChallengeDocument(
          title: 'Just a moment...',
          url: 'https://example.com/',
        ),
        isTrue,
      );
    });

    test('recognizes challenge navigation and widget markers', () {
      expect(
        CloudflareChallenge.isChallengeDocument(
          url: 'https://example.com/?__cf_chl_rt_tk=token',
        ),
        isTrue,
      );
      expect(
        CloudflareChallenge.isChallengeDocument(hasSelector: true),
        isTrue,
      );
    });

    test('keeps a normal completed document clean', () {
      expect(
        CloudflareChallenge.isChallengeDocument(
          title: 'Anime catalog',
          url: 'https://example.com/',
          text: 'Latest episodes',
          html: '<main>Latest episodes</main>',
        ),
        isFalse,
      );
    });

    test('can ignore a stale interstitial title after verification', () {
      expect(
        CloudflareChallenge.isChallengeDocument(
          title: 'Just a moment...',
          url: 'https://example.com/',
          text: 'Latest episodes',
          html: '<main>Latest episodes</main>',
          trustTitle: false,
        ),
        isFalse,
      );
    });

    test('still recognizes live challenge DOM when title is untrusted', () {
      expect(
        CloudflareChallenge.isChallengeDocument(
          title: 'Just a moment...',
          url: 'https://example.com/',
          html: '<form action="/__cf_chl_f_tk=test"></form>',
          trustTitle: false,
        ),
        isTrue,
      );
    });

    test('can ignore passive Cloudflare scripts only for Apple WebKit', () {
      const String passiveDocument =
          '<main>Latest episodes</main>'
          '<script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script>';

      // The default preserves the existing Windows/WebView2 classification.
      expect(
        CloudflareChallenge.isChallengeDocument(
          title: 'Anime catalog',
          url: 'https://example.com/',
          text: 'Latest episodes',
          html: passiveDocument,
        ),
        isTrue,
      );
      expect(
        CloudflareChallenge.isChallengeDocument(
          title: 'Anime catalog',
          url: 'https://example.com/',
          text: 'Latest episodes',
          html: passiveDocument,
          trustPassiveChallengeScript: false,
        ),
        isFalse,
      );
    });
  });

  group('CloudflareChallenge.hasBlockingChallengeSelector', () {
    test('strong interstitial structure always remains blocking', () {
      expect(
        CloudflareChallenge.hasBlockingChallengeSelector(
          hasStrongSelector: true,
          hasTurnstileSelector: true,
          turnstileSolved: true,
          navigatedAfterChallenge: true,
        ),
        isTrue,
      );
    });

    test('an unsolved generic Turnstile remains blocking', () {
      expect(
        CloudflareChallenge.hasBlockingChallengeSelector(
          hasStrongSelector: false,
          hasTurnstileSelector: true,
          turnstileSolved: false,
          navigatedAfterChallenge: false,
        ),
        isTrue,
      );
    });

    test('a retained Turnstile stops blocking after completion', () {
      expect(
        CloudflareChallenge.hasBlockingChallengeSelector(
          hasStrongSelector: false,
          hasTurnstileSelector: true,
          turnstileSolved: true,
          navigatedAfterChallenge: false,
        ),
        isFalse,
      );
      expect(
        CloudflareChallenge.hasBlockingChallengeSelector(
          hasStrongSelector: false,
          hasTurnstileSelector: true,
          turnstileSolved: false,
          navigatedAfterChallenge: true,
        ),
        isFalse,
      );
    });
  });

  test('service reports an interactive solve while it is in flight', () async {
    final CloudflareChallengeService service =
        CloudflareChallengeService.instance;
    final Completer<CloudflareSolveResult?> gate =
        Completer<CloudflareSolveResult?>();
    service.registerSolver(
      ({required Uri url, required String userAgent}) => gate.future,
    );
    addTearDown(() => service.registerSolver(null));

    final Future<CloudflareSolveResult?> solve = service.solve(
      url: Uri.parse('https://active-solve.example.test/api'),
      userAgent: 'test-agent',
    );
    expect(service.hasActiveSolve, isTrue);

    gate.complete(null);
    await solve;
    expect(service.hasActiveSolve, isFalse);
  });
}
