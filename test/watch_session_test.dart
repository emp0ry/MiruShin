import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/watch/application/watch_session.dart';
import 'package:mirushin/features/watch/domain/title_variants.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('TMDB initial session starts at source search', () {
    final WatchSession session = WatchSession.initial(
      _item(<MediaSeason>[
        _season(1, 'Blue Box'),
        _season(2, 'Blue Box Season 2'),
      ]),
    );

    expect(session.step, WatchStep.pickSource);
    expect(session.seasonNumber, 1);
  });

  test('TMDB initial session still defaults to the first known season', () {
    final WatchSession session = WatchSession.initial(
      _item(<MediaSeason>[
        _season(2, 'Blue Box Season 2'),
        _season(1, 'Blue Box'),
      ]),
    );

    expect(session.step, WatchStep.pickSource);
    expect(session.seasonNumber, 1);
  });

  test('TMDB initial session keeps isolated season 2 as the default', () {
    final WatchSession session = WatchSession.initial(
      _item(<MediaSeason>[_season(2, 'Blue Box Season 2')]),
    );

    expect(session.step, WatchStep.pickSource);
    expect(session.seasonNumber, 2);
  });

  test('initial session can auto-skip a single complete season 1', () {
    final WatchSession session = WatchSession.initial(
      _item(<MediaSeason>[_season(1, 'Blue Box')]),
    );

    expect(session.step, WatchStep.pickSource);
    expect(session.seasonNumber, 1);
  });

  test('AniList season entries stay source-first', () {
    final WatchSession session = WatchSession.initial(
      _anilistItem(<MediaSeason>[
        _season(1, 'Blue Box'),
        _season(2, 'Blue Box Season 2'),
      ]),
    );

    expect(session.step, WatchStep.pickSource);
    expect(session.seasonNumber, 1);
  });

  test('resync returns stale TMDB season 2 to source search default', () {
    const WatchSession stale = WatchSession(
      step: WatchStep.pickSource,
      seasonNumber: 2,
    );

    final WatchSession synced = stale.resyncForItem(
      _item(<MediaSeason>[
        _season(1, 'Blue Box'),
        _season(2, 'Blue Box Season 2'),
      ]),
    );

    expect(synced.step, WatchStep.pickSource);
    expect(synced.seasonNumber, 1);
    expect(synced.seasonPicked, isFalse);
  });

  test('resync preserves an explicit user season pick', () {
    const WatchSession picked = WatchSession(
      step: WatchStep.pickSource,
      seasonNumber: 2,
      seasonPicked: true,
    );

    final WatchSession synced = picked.resyncForItem(
      _item(<MediaSeason>[
        _season(1, 'Blue Box'),
        _season(2, 'Blue Box Season 2'),
      ]),
    );

    expect(synced.step, WatchStep.pickSource);
    expect(synced.seasonNumber, 2);
    expect(synced.seasonPicked, isTrue);
  });

  test('title variants do not append synthetic season suffixes', () {
    final List<String> titles = buildTitleVariants(
      _item(<MediaSeason>[
        _season(1, 'Blue Box'),
        _season(2, 'Blue Box Season 2'),
      ]),
      2,
    ).map((variant) => variant.title).toList(growable: false);

    expect(titles, isNot(contains('Blue Box Season 2')));
    expect(titles, isNot(contains('Blue Box S2')));
  });
}

MediaItem _anilistItem(List<MediaSeason> seasons) {
  return MediaItem(
    id: 'anilist:123',
    title: 'Blue Box',
    originalTitle: 'Ao no Hako',
    overview: '',
    type: MediaType.anime,
    year: 2024,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const <String>[],
    sourceProvider: 'AniList',
    externalIds: const <String, String>{},
    episodeCount: seasons.fold<int>(
      0,
      (int sum, MediaSeason season) => sum + season.episodeCount,
    ),
    seasons: seasons,
    statusLabel: '',
  );
}

MediaItem _item(List<MediaSeason> seasons) {
  return MediaItem(
    id: 'tmdb:anime:207347',
    title: 'Blue Box',
    originalTitle: 'Ao no Hako',
    overview: '',
    type: MediaType.anime,
    year: 2024,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const <String>[],
    sourceProvider: 'tmdb',
    externalIds: const <String, String>{},
    episodeCount: seasons.fold<int>(
      0,
      (int sum, MediaSeason season) => sum + season.episodeCount,
    ),
    seasons: seasons,
    statusLabel: '',
  );
}

MediaSeason _season(int number, String name) {
  return MediaSeason(
    seasonNumber: number,
    name: name,
    episodeCount: number == 1 ? 25 : 0,
    posterUrl: '',
    overview: '',
  );
}
