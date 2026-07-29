import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/downloads/application/download_episode_availability.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 29, 12);

  test('caps downloads before the next AniList airing episode', () {
    final MediaItem item = _item(
      nextEpisode: 5,
      airingAt: now.add(const Duration(days: 1)),
    );
    final List<SoraEpisode> available = airedDownloadEpisodes(
      _episodes(12),
      item,
      now: now,
    );

    expect(available.map((SoraEpisode episode) => episode.number), <double>[
      1,
      2,
      3,
      4,
    ]);
  });

  test('includes the next episode once its airing time has passed', () {
    final MediaItem item = _item(
      nextEpisode: 5,
      airingAt: now.subtract(const Duration(minutes: 1)),
    );

    expect(anilistAiredEpisodeLimit(item, now: now), 5);
  });

  test('caps offline page placeholders to aired episodes', () {
    final MediaItem item = _item(
      nextEpisode: 5,
      airingAt: now.add(const Duration(days: 1)),
    );

    expect(airedDownloadEpisodeTotal(item, 12, now: now), 4);
  });

  test('leaves non-AniList episode lists unchanged', () {
    final List<SoraEpisode> episodes = _episodes(12);
    final MediaItem item = _item(nextEpisode: null, airingAt: null);

    expect(airedDownloadEpisodes(episodes, item, now: now), same(episodes));
  });
}

MediaItem _item({required int? nextEpisode, required DateTime? airingAt}) {
  return MediaItem(
    id: 'anilist:1',
    title: 'Test',
    originalTitle: 'Test',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const <String>[],
    sourceProvider: 'AniList',
    externalIds: <String, String>{
      'anilist': '1',
      if (nextEpisode != null)
        anilistNextAiringEpisodeKey: nextEpisode.toString(),
      if (airingAt != null)
        anilistNextAiringAtKey: (airingAt.millisecondsSinceEpoch ~/ 1000)
            .toString(),
    },
    statusLabel: 'RELEASING',
  );
}

List<SoraEpisode> _episodes(int count) {
  return List<SoraEpisode>.generate(
    count,
    (int index) => SoraEpisode(
      number: (index + 1).toDouble(),
      href: '/${index + 1}',
      title: '',
      image: '',
      description: '',
      duration: '',
    ),
  );
}
