import '../../../shared/models/media_item.dart';
import '../data/anime_resolver.dart';
import '../data/tmdb_metadata_provider.dart';

class BoardRails {
  const BoardRails({
    this.recentMovies = const <MediaItem>[],
    this.recentSeries = const <MediaItem>[],
    this.topAnime = const <MediaItem>[],
  });

  final List<MediaItem> recentMovies;
  final List<MediaItem> recentSeries;
  final List<MediaItem> topAnime;

  factory BoardRails.empty() => const BoardRails();

  bool get isEmpty =>
      recentMovies.isEmpty && recentSeries.isEmpty && topAnime.isEmpty;

  MediaItem? get hero =>
      recentMovies.firstOrNull ??
      recentSeries.firstOrNull ??
      topAnime.firstOrNull;
}

class MediaCatalog {
  const MediaCatalog({required this.tmdb, this.animeResolver});

  final TmdbMetadataProvider tmdb;
  final AnimeResolver? animeResolver;

  Future<BoardRails> boardRails() async {
    final List<List<MediaItem>> results =
        await Future.wait(<Future<List<MediaItem>>>[
          tmdb.getPopular(MediaType.movie),
          tmdb.getPopular(MediaType.series),
          tmdb.getPopular(MediaType.anime),
        ]);
    return BoardRails(
      recentMovies: results[0],
      recentSeries: results[1],
      topAnime: results[2],
    );
  }

  Future<List<MediaItem>> discover({
    required String? search,
    required MediaType? type,
    required int page,
  }) async {
    final String trimmed = search?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return tmdb.search(trimmed, page: page);
    }
    return tmdb.discoverPage(filter: 'popular', type: type, page: page);
  }

  Future<MediaItem?> details(String id) async {
    final MediaItem? item = await tmdb.getDetails(id);
    if (item == null) return null;
    if (item.type == MediaType.anime && animeResolver != null) {
      return animeResolver!.enrich(item);
    }
    return item;
  }
}
