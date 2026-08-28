import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/data/cloudflare_challenge.dart';

void main() {
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
  });
}
