import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/media_details/data/anime_themes_client.dart';

void main() {
  group('AnimeThemesAnime.fromJson', () {
    test('parses theme cards from the AnimeThemes anime response', () {
      final AnimeThemesAnime anime = AnimeThemesAnime.fromJson(
        <String, dynamic>{
          'name': 'Test Anime',
          'slug': 'test-anime',
          'year': 2026,
          'images': <Map<String, dynamic>>[
            <String, dynamic>{
              'facet': 'Small Cover',
              'link': 'https://cdn.example/small.jpg',
            },
            <String, dynamic>{
              'facet': 'Large Cover',
              'link': 'https://cdn.example/large.jpg',
            },
          ],
          'animethemes': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'ED',
              'sequence': 1,
              'slug': 'ED1',
              'song': <String, dynamic>{'title': 'Ending Song'},
              'animethemeentries': <Map<String, dynamic>>[
                <String, dynamic>{
                  'episodes': '1-12',
                  'nsfw': false,
                  'spoiler': false,
                  'videos': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'tags': 'NCBD1080',
                      'link': 'https://v.animethemes.moe/Test-ED1.webm',
                    },
                  ],
                },
              ],
            },
            <String, dynamic>{
              'type': 'OP',
              'sequence': 1,
              'slug': 'OP1',
              'song': <String, dynamic>{'title': 'Opening Song'},
              'animethemeentries': <Map<String, dynamic>>[
                <String, dynamic>{
                  'episodes': '1-6',
                  'nsfw': false,
                  'spoiler': false,
                  'videos': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'tags': 'NCBD1080',
                      'link': 'https://v.animethemes.moe/Test-OP1.webm',
                    },
                  ],
                },
                <String, dynamic>{
                  'episodes': '7-12',
                  'nsfw': false,
                  'spoiler': true,
                  'videos': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'tags': 'NCBD1080',
                      'link': 'https://v.animethemes.moe/Test-OP1v2.webm',
                    },
                  ],
                },
              ],
            },
          ],
        },
      );

      expect(anime.name, 'Test Anime');
      expect(anime.year, 2026);
      expect(anime.imageUrl, 'https://cdn.example/large.jpg');
      expect(anime.pageUrl, 'https://animethemes.moe/anime/test-anime');
      expect(anime.themes.map((AnimeThemeInfo theme) => theme.label), <String>[
        'OP1',
        'ED1',
      ]);

      final AnimeThemeInfo op = anime.themes.first;
      expect(op.songTitle, 'Opening Song');
      expect(op.imageUrl, 'https://cdn.example/large.jpg');
      expect(
        op.openUrl,
        'https://animethemes.moe/anime/test-anime/OP1-NCBD1080',
      );
      expect(op.videoUrl, 'https://v.animethemes.moe/Test-OP1.webm');
      expect(op.episodes, '1-6, 7-12');
      expect(op.versionCount, 2);
      expect(op.nsfw, isFalse);
      expect(op.spoiler, isTrue);
    });

    test(
      'uses fallback labels and artwork when optional fields are missing',
      () {
        final AnimeThemesAnime anime = AnimeThemesAnime.fromJson(
          <String, dynamic>{
            'name': 'Fallback Anime',
            'slug': '',
            'animethemes': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'OP',
                'sequence': 2,
                'animethemeentries': const <Map<String, dynamic>>[],
              },
            ],
          },
          fallbackImageUrl: 'https://cdn.example/poster.jpg',
        );

        expect(anime.imageUrl, 'https://cdn.example/poster.jpg');
        expect(anime.pageUrl, 'https://animethemes.moe');
        expect(anime.themes.single.label, 'OP2');
        expect(anime.themes.single.songTitle, 'OP2');
        expect(anime.themes.single.openUrl, 'https://animethemes.moe');
      },
    );
  });
}
