import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('MiruShin media deep links', () {
    final Map<String, String> cases = <String, String>{
      'mirushin://anilist/anime/21': 'anilist:21',
      'mirushin://anilist/manga/30013': 'anilist:manga:30013',
      'mirushin://tmdb/movie/550': 'tmdb:movie:550',
      'mirushin://tmdb/tv/1399': 'tmdb:tv:1399',
    };

    for (final MapEntry<String, String> entry in cases.entries) {
      test('parses ${entry.key}', () {
        final MiruShinDeepLink? parsed = MiruShinDeepLink.tryParse(entry.key);
        expect(parsed, isA<MiruShinMediaDeepLink>());
        expect((parsed! as MiruShinMediaDeepLink).internalMediaId, entry.value);
      });
    }

    test('rejects malformed and unsupported media links', () {
      for (final String value in <String>[
        'https://anilist.co/anime/21',
        'mirushin://anilist/anime/0',
        'mirushin://anilist/anime/-1',
        'mirushin://anilist/movie/21',
        'mirushin://tmdb/anime/21',
        'mirushin://tmdb/movie/21?catalog=tmdb',
        'mirushin://tmdb/movie/not-a-number',
        'mirushin://unknown/movie/21',
      ]) {
        expect(MiruShinDeepLink.tryParse(value), isNull, reason: value);
      }
    });

    test('generates exact provider links without a catalog parameter', () {
      expect(
        mirushinMediaUri(
          internalId: 'anilist:86',
          mediaType: MediaType.anime,
        ).toString(),
        'mirushin://anilist/anime/86',
      );
      expect(
        mirushinMediaUri(
          internalId: 'tmdb:movie:550',
          mediaType: MediaType.movie,
        ).toString(),
        'mirushin://tmdb/movie/550',
      );
    });
  });

  test('watch-party links become typed activations', () {
    final MiruShinDeepLink? defaultParty = MiruShinDeepLink.tryParse(
      'mirushin://watch-party/join?code=ABC123',
    );
    expect(defaultParty, isA<MiruShinWatchPartyDeepLink>());
    expect(
      (defaultParty! as MiruShinWatchPartyDeepLink).invite.mode,
      WatchPartyConnectionMode.defaultConnection,
    );

    const String relayInvite =
        'https://relay.example.com/join?room=AbCdEfGhIjKlMnOp'
        '&token=guest_join_token_1234567890';
    final String bridge = Uri(
      scheme: 'mirushin',
      host: 'watch-party',
      path: '/join',
      queryParameters: const <String, String>{'invite': relayInvite},
    ).toString();
    final MiruShinWatchPartyDeepLink relay =
        MiruShinDeepLink.tryParse(bridge)! as MiruShinWatchPartyDeepLink;
    expect(relay.invite.mode, WatchPartyConnectionMode.selfHostedRelay);
    expect(relay.invite.relayUrl.toString(), 'https://relay.example.com');
  });
}
