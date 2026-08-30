import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link_service.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
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

    test('exposes the matching provider page for sharing', () {
      final Map<String, String> providerCases = <String, String>{
        'mirushin://anilist/anime/16498': 'https://anilist.co/anime/16498',
        'mirushin://anilist/manga/30013': 'https://anilist.co/manga/30013',
        'mirushin://tmdb/movie/550': 'https://www.themoviedb.org/movie/550',
        'mirushin://tmdb/tv/1399': 'https://www.themoviedb.org/tv/1399',
      };
      for (final MapEntry<String, String> entry in providerCases.entries) {
        final MiruShinMediaDeepLink link =
            MiruShinDeepLink.tryParse(entry.key)! as MiruShinMediaDeepLink;
        expect(link.providerUri.toString(), entry.value);
      }
    });

    test('wraps app URIs in the public HTTPS opener for sharing', () {
      final Map<String, String> openCases = <String, String>{
        'mirushin://anilist/anime/207141':
            'https://mirushin.emp0ry.com/open.html?target='
            'mirushin%3A%2F%2Fanilist%2Fanime%2F207141',
        'mirushin://tmdb/movie/550':
            'https://mirushin.emp0ry.com/open.html?target='
            'mirushin%3A%2F%2Ftmdb%2Fmovie%2F550',
      };
      for (final MapEntry<String, String> entry in openCases.entries) {
        final MiruShinMediaDeepLink link =
            MiruShinDeepLink.tryParse(entry.key)! as MiruShinMediaDeepLink;
        expect(link.webOpenUri.toString(), entry.value);
      }
    });

    test('selects the catalog named by the media-link provider', () {
      final Map<String, CatalogMode> catalogCases = <String, CatalogMode>{
        'mirushin://anilist/anime/207141': CatalogMode.anilist,
        'mirushin://anilist/manga/30013': CatalogMode.anilist,
        'mirushin://tmdb/movie/550': CatalogMode.tmdb,
        'mirushin://tmdb/tv/1399': CatalogMode.tmdb,
      };
      for (final MapEntry<String, CatalogMode> entry in catalogCases.entries) {
        final MiruShinMediaDeepLink link =
            MiruShinDeepLink.tryParse(entry.key)! as MiruShinMediaDeepLink;
        expect(catalogModeForMediaDeepLink(link), entry.value);
      }
    });

    test('external AniList manga identity produces a manga app link', () {
      final MiruShinMediaDeepLink link = mirushinMediaLink(
        internalId: 'local:unknown',
        mediaType: MediaType.anime,
        externalIds: const <String, String>{
          'anilist': '30013',
          'anilist_type': 'MANGA',
        },
      )!;
      expect(link.uri.toString(), 'mirushin://anilist/manga/30013');
      expect(link.providerUri.toString(), 'https://anilist.co/manga/30013');
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
