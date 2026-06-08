import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/addons/domain/sora_parsers.dart';

void main() {
  test('search parser handles stringified JSON and scores title matches', () {
    final List<SoraSearchResult> results = parseSoraSearchResults(
      payload:
          '[{"title":"Frieren Beyond Journey End","image":"poster.jpg","href":"/frieren"}]',
      addonId: 'addon',
      addonName: 'Demo',
      languageCode: 'en',
      query: 'Frieren',
      titleVariants: const <SoraTitleVariant>[
        SoraTitleVariant(languageCode: 'en', title: 'Frieren'),
      ],
    );

    expect(results, hasLength(1));
    expect(results.single.href, '/frieren');
    expect(results.single.score, greaterThan(0.8));
  });

  test('episode parser sorts episodes and keeps metadata', () {
    final List<SoraEpisode> episodes = parseSoraEpisodes(<String, dynamic>{
      'episodes': <Map<String, dynamic>>[
        <String, dynamic>{
          'number': 2,
          'href': 'ep-2',
          'title': 'Second',
          'description': 'Mini description',
        },
        <String, dynamic>{'number': 1, 'href': 'ep-1', 'title': 'First'},
      ],
    });

    expect(episodes.map((SoraEpisode episode) => episode.href), <String>[
      'ep-1',
      'ep-2',
    ]);
    expect(episodes.last.description, 'Mini description');
  });

  test('episode parser preserves source order when episode numbers reset', () {
    final List<SoraEpisode> episodes = parseSoraEpisodes(<String, dynamic>{
      'episodes': <Map<String, dynamic>>[
        <String, dynamic>{'number': 1, 'href': 's1-e1'},
        <String, dynamic>{'number': 2, 'href': 's1-e2'},
        <String, dynamic>{'number': 1, 'href': 's2-e1'},
        <String, dynamic>{'number': 2, 'href': 's2-e2'},
      ],
    });

    expect(episodes.map((SoraEpisode episode) => episode.href), <String>[
      's1-e1',
      's1-e2',
      's2-e1',
      's2-e2',
    ]);
  });

  test('stream parser accepts streams, headers, and subtitles', () {
    final List<SoraStreamCandidate> streams = parseSoraStreamCandidates(
      <String, dynamic>{
        'streams': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': 'Server A',
            'streamUrl': 'https://cdn.example.com/video.m3u8',
            'headers': <String, dynamic>{'Referer': 'https://source.example'},
            'subtitles': <Map<String, dynamic>>[
              <String, dynamic>{
                'url': 'https://cdn.example.com/en.vtt',
                'language': 'en',
                'label': 'English',
              },
            ],
          },
        ],
      },
    );

    expect(streams, hasLength(1));
    expect(streams.single.url, contains('.m3u8'));
    expect(streams.single.headers['Referer'], 'https://source.example');
    expect(streams.single.subtitles.single.label, 'English');
  });

  test('title similarity prefers exact and contains matches', () {
    expect(soraTitleSimilarity('Spirited Away', 'Spirited Away'), 1);
    expect(
      soraTitleSimilarity('Spirited Away Movie 2001', 'Spirited Away'),
      greaterThan(0.8),
    );
    expect(
      soraTitleSimilarity('Completely Different', 'Spirited Away'),
      lessThan(0.5),
    );
  });
}
