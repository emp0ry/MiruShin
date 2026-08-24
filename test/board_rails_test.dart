import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/metadata/application/media_catalog.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('BoardRails hero selection', () {
    test('selects from the first twenty Top Anime entries', () {
      final BoardRails rails = BoardRails(
        topAnime: List<MediaItem>.generate(25, _anime),
      );

      expect(rails.heroForSeed(19)?.id, 'anime:19');
      expect(rails.heroForSeed(20)?.id, 'anime:0');
      expect(rails.heroForSeed(24)?.id, 'anime:4');
    });

    test('uses other board entries when Top Anime is unavailable', () {
      final BoardRails rails = BoardRails(
        recentMovies: <MediaItem>[_anime(40), _anime(41)],
      );

      expect(rails.heroForSeed(1)?.id, 'anime:41');
    });

    test('can prefer recent movies for a TMDB hero', () {
      final BoardRails rails = BoardRails(
        recentMovies: <MediaItem>[_movie(40), _movie(41)],
        topAnime: <MediaItem>[_anime(0), _anime(1)],
      );

      expect(rails.heroForSeed(1, preferRecentMovies: true)?.id, 'movie:41');
    });

    test('returns null for an empty board', () {
      expect(BoardRails.empty().heroForSeed(3), isNull);
    });
  });
}

MediaItem _anime(int index) {
  return MediaItem(
    id: 'anime:$index',
    title: 'Anime $index',
    originalTitle: 'Anime $index',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const <String>[],
    sourceProvider: 'test',
    externalIds: const <String, String>{},
    statusLabel: '',
  );
}

MediaItem _movie(int index) {
  return MediaItem(
    id: 'movie:$index',
    title: 'Movie $index',
    originalTitle: 'Movie $index',
    overview: '',
    type: MediaType.movie,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const <String>[],
    sourceProvider: 'test',
    externalIds: const <String, String>{},
    statusLabel: '',
  );
}
