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

  /// Selects a stable hero from the first [candidateLimit] Top Anime entries.
  /// The caller owns the seed so normal widget rebuilds do not change artwork.
  MediaItem? heroForSeed(int seed, {int candidateLimit = 20}) {
    final List<MediaItem> source = topAnime.isNotEmpty
        ? topAnime
        : <MediaItem>[...recentMovies, ...recentSeries];
    if (source.isEmpty) return null;

    final int limit = candidateLimit.clamp(1, source.length);
    return source[seed % limit];
  }
}
