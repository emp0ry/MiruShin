import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/addons/domain/sora_parsers.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('manifest parser accepts scriptURL and preserves unknown fields', () {
    final SoraAddonManifest manifest = SoraAddonManifest.fromJson(
      <String, dynamic>{
        'sourceName': 'Luna Demo',
        'iconUrl': 'https://example.com/icon.png',
        'author': <String, dynamic>{
          'name': 'Author',
          'icon': 'https://example.com/author.png',
        },
        'version': '1.2.3',
        'language': 'en',
        'streamType': 'HLS',
        'quality': '1080p',
        'baseUrl': 'https://example.com',
        'searchBaseUrl': 'https://example.com/search',
        'scriptURL': './module.js',
        'type': 'anime',
        'downloadSupport': 'true',
        'softsub': true,
        'customFlag': 'kept',
      },
    );

    expect(manifest.scriptUrl, './module.js');
    expect(manifest.downloadSupport, isTrue);
    expect(manifest.raw['customFlag'], 'kept');
    expect(manifest.validationErrors(), isEmpty);
    expect(manifest.supportsMediaType(MediaType.anime), isTrue);
    expect(manifest.supportsMediaType(MediaType.movie), isFalse);
  });

  test('manifest validation reports required fields', () {
    final SoraAddonManifest manifest = SoraAddonManifest.fromJson(
      <String, dynamic>{'sourceName': 'Broken'},
    );

    expect(manifest.validationErrors(), contains('scriptUrl is required'));
    expect(() => manifest.validate(), throwsA(isA<SoraAddonException>()));
  });

  test('episode parser carries OP and ED markers into playback item', () {
    final List<SoraEpisode> episodes = parseSoraEpisodes(<Map<String, Object?>>[
      <String, Object?>{
        'number': 1,
        'href': '/episode-1',
        'title': 'Episode 1',
        'opening': <String, Object?>{'start': 90, 'stop': 180},
        'ending': <String, Object?>{'start': '22:10', 'end': '23:40'},
      },
    ]);

    final SoraEpisode episode = episodes.single;
    expect(episode.openingStart, 90);
    expect(episode.openingEnd, 180);
    expect(episode.endingStart, 1330);
    expect(episode.endingEnd, 1420);

    const NormalizedServer server = NormalizedServer(
      id: 'server',
      title: 'Server',
      streamUrl: 'https://cdn.example.com/video.m3u8',
    );
    final MediaPlaybackItem playbackItem = MediaPlaybackItem.fromBundle(
      NormalizedStreamBundle(
        addonId: 'demo',
        episode: episode,
        selectedServer: server,
        availableServers: const <NormalizedServer>[server],
      ),
      const MediaItem(
        id: 'tmdb:anime:1',
        title: 'Demo',
        originalTitle: 'Demo',
        overview: '',
        type: MediaType.anime,
        year: 2026,
        posterUrl: '',
        backdropUrl: '',
        rating: 0,
        genres: <String>[],
        sourceProvider: 'test',
        externalIds: <String, String>{'mal': '1'},
        statusLabel: '',
      ),
      1,
    );

    expect(playbackItem.skipMarkers.openingStart, const Duration(seconds: 90));
    expect(playbackItem.skipMarkers.openingEnd, const Duration(seconds: 180));
    expect(playbackItem.skipMarkers.endingStart, const Duration(seconds: 1330));
    expect(playbackItem.skipMarkers.endingEnd, const Duration(seconds: 1420));
  });

  test('stream parser carries addon-provided OP and ED markers', () {
    const SoraEpisode episode = SoraEpisode(
      number: 1,
      href: '/episode-1',
      title: 'Episode 1',
      image: '',
      description: '',
      duration: '',
    );
    final Map<String, Object?> payload = <String, Object?>{
      'opening': <String, Object?>{'start': 65, 'end': 154},
      'ending': <String, Object?>{'start': 1320, 'stop': 1410},
      'streams': <Map<String, Object?>>[
        <String, Object?>{
          'title': 'Default',
          'streamUrl': 'https://cdn.example.com/video.m3u8',
        },
      ],
    };

    final NormalizedStreamBundle bundle = parseSoraStreamBundle(
      SoraResolvedStreams(
        addonId: 'demo',
        episode: episode,
        candidates: parseSoraStreamCandidates(payload),
        raw: payload,
      ),
    );

    expect(bundle.openingStart, 65);
    expect(bundle.openingEnd, 154);
    expect(bundle.endingStart, 1320);
    expect(bundle.endingEnd, 1410);
  });
}
