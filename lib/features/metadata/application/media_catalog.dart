import '../../../shared/models/media_item.dart';

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

  MediaItem? get hero =>
      recentMovies.firstOrNull ??
      recentSeries.firstOrNull ??
      topAnime.firstOrNull;

  /// Selects a stable hero from the first [candidateLimit] entries of the
  /// catalog's primary rail. AniList uses Top Anime; TMDB can prefer recently
  /// released movies. The caller owns the seed so rebuilds keep the same hero.
  MediaItem? heroForSeed(
    int seed, {
    int candidateLimit = 20,
    bool preferRecentMovies = false,
  }) {
    final List<MediaItem> source = preferRecentMovies
        ? (recentMovies.isNotEmpty
              ? recentMovies
              : <MediaItem>[...recentSeries, ...topAnime])
        : (topAnime.isNotEmpty
              ? topAnime
              : <MediaItem>[...recentMovies, ...recentSeries]);
    if (source.isEmpty) return null;

    final int limit = candidateLimit.clamp(1, source.length);
    return source[seed % limit];
  }
}
