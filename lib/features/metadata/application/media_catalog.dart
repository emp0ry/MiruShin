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
}
