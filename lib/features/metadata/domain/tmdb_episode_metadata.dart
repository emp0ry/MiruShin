class TmdbSeasonEpisodeMetadataBundle {
  const TmdbSeasonEpisodeMetadataBundle({
    required this.seasonNumber,
    required this.episodes,
  });

  static const TmdbSeasonEpisodeMetadataBundle empty =
      TmdbSeasonEpisodeMetadataBundle(
        seasonNumber: 0,
        episodes: <int, TmdbEpisodeMetadata>{},
      );

  final int seasonNumber;
  final Map<int, TmdbEpisodeMetadata> episodes;

  bool get isEmpty => episodes.isEmpty;

  TmdbEpisodeMetadata? forNumber(double number) {
    if (number <= 0) return null;
    return episodes[number.round()];
  }
}

class TmdbEpisodeMetadata {
  const TmdbEpisodeMetadata({
    required this.number,
    required this.title,
    required this.overview,
    required this.imageUrl,
    this.runtimeMinutes,
  });

  final int number;
  final String title;
  final String overview;
  final String imageUrl;
  final int? runtimeMinutes;

  String get durationLabel {
    final int? minutes = runtimeMinutes;
    return minutes == null || minutes <= 0 ? '' : '$minutes min';
  }
}
