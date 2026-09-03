import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link_service.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('MiruShin media deep links', () {
    final Map<String, String> appLinkCases = <String, String>{
      'mirushin://anilist/anime/21': 'anilist:21',
      'mirushin://anilist/manga/30013': 'anilist:manga:30013',
      'mirushin://tmdb/movie/550': 'tmdb:movie:550',
      'mirushin://tmdb/tv/1399': 'tmdb:tv:1399',
    };

    for (final MapEntry<String, String> entry in appLinkCases.entries) {
      test('parses ${entry.key}', () {
        final MiruShinDeepLink? parsed = MiruShinDeepLink.tryParse(entry.key);
        expect(parsed, isA<MiruShinMediaDeepLink>());
        expect((parsed! as MiruShinMediaDeepLink).internalMediaId, entry.value);
      });
    }

    test('parses all canonical public media URLs', () {
      const Map<String, String> publicCases = <String, String>{
        'https://mirushin.emp0ry.com/anilist/anime/21': 'anilist:21',
        'https://mirushin.emp0ry.com/anilist/manga/30013':
            'anilist:manga:30013',
        'https://mirushin.emp0ry.com/tmdb/movie/550': 'tmdb:movie:550',
        'https://mirushin.emp0ry.com/tmdb/tv/1399': 'tmdb:tv:1399',
      };
      for (final MapEntry<String, String> entry in publicCases.entries) {
        final MiruShinDeepLink? parsed = MiruShinDeepLink.tryParse(entry.key);
        expect(parsed, isA<MiruShinMediaDeepLink>(), reason: entry.key);
        expect((parsed! as MiruShinMediaDeepLink).internalMediaId, entry.value);
      }
    });

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
        'https://evil.example/anilist/anime/21',
        'http://mirushin.emp0ry.com/anilist/anime/21',
        'https://mirushin.emp0ry.com/anilist/anime/0',
        'https://mirushin.emp0ry.com/anilist/anime/-1',
        'https://mirushin.emp0ry.com/anilist/anime/2147483648',
        'https://mirushin.emp0ry.com/anilist/anime/not-a-number',
        'https://mirushin.emp0ry.com/anilist/movie/21',
        'https://mirushin.emp0ry.com/tmdb/anime/21',
        'https://mirushin.emp0ry.com/tmdb/movie/21?redirect=evil',
        'https://mirushin.emp0ry.com/tmdb/movie/21#fragment',
        'https://mirushin.emp0ry.com:444/tmdb/movie/21',
        'javascript:alert(1)',
        'data:text/html,hello',
        'file:///anilist/anime/21',
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

    test('generates canonical public HTTPS URLs for sharing', () {
      final Map<String, String> openCases = <String, String>{
        'mirushin://anilist/anime/207141':
            'https://mirushin.emp0ry.com/anilist/anime/207141',
        'mirushin://anilist/manga/30013':
            'https://mirushin.emp0ry.com/anilist/manga/30013',
        'mirushin://tmdb/movie/550':
            'https://mirushin.emp0ry.com/tmdb/movie/550',
        'mirushin://tmdb/tv/1399': 'https://mirushin.emp0ry.com/tmdb/tv/1399',
      };
      for (final MapEntry<String, String> entry in openCases.entries) {
        final MiruShinMediaDeepLink link =
            MiruShinDeepLink.tryParse(entry.key)! as MiruShinMediaDeepLink;
        expect(link.shareUri.toString(), entry.value);
        expect(link.webOpenUri, link.shareUri);
      }
    });

    test(
      'keeps legacy opener URLs parseable and canonicalizes their model',
      () {
        const String legacy =
            'https://mirushin.emp0ry.com/open.html?target='
            'mirushin%3A%2F%2Fanilist%2Fanime%2F21';
        final MiruShinMediaDeepLink link =
            MiruShinDeepLink.tryParse(legacy)! as MiruShinMediaDeepLink;
        expect(link.uri.toString(), 'mirushin://anilist/anime/21');
        expect(
          link.shareUri.toString(),
          'https://mirushin.emp0ry.com/anilist/anime/21',
        );
        expect(link.legacyWebOpenUri.toString(), legacy);
      },
    );

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
    final MiruShinDeepLink? sharedDefaultParty = MiruShinDeepLink.tryParse(
      'https://mirushin.emp0ry.com/open.html?target='
      'mirushin%3A%2F%2Fwatch-party%2Fjoin%3Fcode%3DABC123',
    );
    expect(sharedDefaultParty, isA<MiruShinWatchPartyDeepLink>());
    expect(
      (sharedDefaultParty! as MiruShinWatchPartyDeepLink).invite.roomId,
      'ABC123',
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
