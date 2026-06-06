import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('playback route key distinguishes adjacent Sora episodes', () {
    final MediaPlaybackItem episode1 = _item(
      episodeNumber: 1,
      episodeHref: '/watch/episode-1',
    );
    final MediaPlaybackItem episode2 = _item(
      episodeNumber: 2,
      episodeHref: '/watch/episode-2',
    );

    expect(isSamePlaybackRouteItem(episode1, episode2), isFalse);
  });

  test(
    'playback route key treats the same Sora episode as current route item',
    () {
      final MediaPlaybackItem current = _item(
        episodeNumber: 12,
        episodeHref: '/watch/episode-12',
      );
      final MediaPlaybackItem routeItem = _item(
        episodeNumber: 12,
        episodeHref: '/watch/episode-12',
      );

      expect(isSamePlaybackRouteItem(current, routeItem), isTrue);
    },
  );
}

MediaPlaybackItem _item({
  required double episodeNumber,
  required String episodeHref,
}) {
  return MediaPlaybackItem(
    id: 'anilist:1',
    title: 'Test Anime',
    mediaType: MediaType.anime,
    servers: const <MediaServer>[],
    externalIds: <String, String>{
      'sora_addon_id': 'test-addon',
      'sora_episode_href': episodeHref,
    },
    currentEpisodeId: '1_$episodeNumber',
    seasonNumber: 1,
    episodeNumber: episodeNumber,
  );
}
