class AnimeEpisodeMetadataBundle {
  const AnimeEpisodeMetadataBundle({
    required this.anilistId,
    required this.languageCode,
    required this.episodes,
  });

  final int anilistId;
  final String languageCode;
  final Map<int, AnimeEpisodeMetadata> episodes;

  static const AnimeEpisodeMetadataBundle empty = AnimeEpisodeMetadataBundle(
    anilistId: 0,
    languageCode: '',
    episodes: <int, AnimeEpisodeMetadata>{},
  );

  bool get isEmpty => episodes.isEmpty;

  AnimeEpisodeMetadata? forNumber(double number) {
    if (number <= 0) return null;
    if (number == number.roundToDouble()) {
      return episodes[number.round()];
    }
    return episodes[int.tryParse(number.toString())];
  }
}

class AnimeEpisodeMetadata {
  const AnimeEpisodeMetadata({
    this.aniZipImage = '',
    this.aniZipTitle = '',
    this.aniListThumbnail = '',
    this.aniListTitle = '',
    this.tvdbTitle = '',
  });

  final String aniZipImage;
  final String aniZipTitle;
  final String aniListThumbnail;
  final String aniListTitle;
  final String tvdbTitle;

  String get preferredImage =>
      aniZipImage.isNotEmpty ? aniZipImage : aniListThumbnail;

  String cardTitle(double number) {
    for (final String title in <String>[aniZipTitle, aniListTitle]) {
      if (title.isNotEmpty && !isGenericEpisodeTitle(title, number)) {
        return title;
      }
    }
    return '';
  }

  String fallbackTitle(double number) {
    for (final String title in <String>[aniZipTitle, aniListTitle]) {
      if (title.isNotEmpty && !isGenericEpisodeTitle(title, number)) {
        return title;
      }
    }
    return '';
  }

  AnimeEpisodeMetadata copyWith({
    String? aniZipImage,
    String? aniZipTitle,
    String? aniListThumbnail,
    String? aniListTitle,
    String? tvdbTitle,
  }) {
    return AnimeEpisodeMetadata(
      aniZipImage: aniZipImage ?? this.aniZipImage,
      aniZipTitle: aniZipTitle ?? this.aniZipTitle,
      aniListThumbnail: aniListThumbnail ?? this.aniListThumbnail,
      aniListTitle: aniListTitle ?? this.aniListTitle,
      tvdbTitle: tvdbTitle ?? this.tvdbTitle,
    );
  }
}

String bestPlayerEpisodeTitle({
  required String moduleTitle,
  required String tvdbTitle,
  required String metadataTitle,
  required double number,
}) {
  final String module = moduleTitle.trim();
  if (module.isNotEmpty && !isGenericEpisodeTitle(module, number)) {
    return module;
  }

  final String tvdb = tvdbTitle.trim();
  if (tvdb.isNotEmpty && !isGenericEpisodeTitle(tvdb, number)) {
    return tvdb;
  }

  final String metadata = metadataTitle.trim();
  if (metadata.isNotEmpty && !isGenericEpisodeTitle(metadata, number)) {
    return metadata;
  }

  return '';
}

bool isGenericEpisodeTitle(String title, double number) {
  final String normalized = _normalizeEpisodeTitle(title);
  if (normalized.isEmpty) return true;

  final String numberText = episodeNumberText(number);
  if (numberText.isNotEmpty) {
    final String n = RegExp.escape(_normalizeEpisodeTitle(numberText));
    final List<RegExp> exactPatterns = <RegExp>[
      RegExp('^(episode|ep|e) 0*$n\$'),
      RegExp('^(серия|серія|эпизод) 0*$n\$'),
      RegExp('^(#|no|№)? ?0*$n\$'),
      RegExp('^s0*[0-9]+e0*$n\$'),
      RegExp('^第 ?0*$n ?(話|话|集)\$'),
    ];
    if (exactPatterns.any((RegExp pattern) => pattern.hasMatch(normalized))) {
      return true;
    }
  }

  return RegExp(r'^(episode|ep|e) [0-9]+$').hasMatch(normalized) ||
      RegExp(r'^(серия|серія|эпизод) [0-9]+$').hasMatch(normalized) ||
      RegExp(r'^(#|no|№)? ?[0-9]+$').hasMatch(normalized) ||
      RegExp(r'^s0*[0-9]+e0*[0-9]+$').hasMatch(normalized) ||
      RegExp(r'^第 ?[0-9]+ ?(話|话|集)$').hasMatch(normalized);
}

String episodeNumberText(double number) {
  if (number <= 0) return '';
  if (number == number.roundToDouble()) return number.round().toString();
  return number.toString().replaceFirst(RegExp(r'\.0+$'), '');
}

String _normalizeEpisodeTitle(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s._:・\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
