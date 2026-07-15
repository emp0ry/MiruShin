import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/media_item.dart';

final Provider<AnimeThemesClient> animeThemesClientProvider =
    Provider<AnimeThemesClient>((Ref ref) => AnimeThemesClient());

class AnimeThemesClient {
  AnimeThemesClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.animethemes.moe',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              headers: const <String, String>{'Accept': 'application/json'},
            ),
          );

  static const String _include =
      'resources,images,animethemes.song,animethemes.animethemeentries.videos';

  final Dio _dio;

  Future<AnimeThemesAnime?> findForMediaItem(MediaItem item) async {
    if (item.type != MediaType.anime) return null;

    final List<String> queries = _titleQueries(item);
    if (queries.isEmpty) return null;

    for (final String query in queries) {
      final Response<Object?> response = await _dio.get<Object?>(
        '/anime/',
        queryParameters: <String, Object?>{
          'q': query,
          'page[size]': 5,
          'include': _include,
        },
      );
      final AnimeThemesAnime? anime = _bestAnime(response.data, item);
      if (anime != null && anime.themes.isNotEmpty) return anime;
    }

    return null;
  }

  AnimeThemesAnime? _bestAnime(Object? data, MediaItem item) {
    if (data is! Map) return null;
    final Object? rawAnime = data['anime'];
    final List<Object?> animeList = switch (rawAnime) {
      List list => list.cast<Object?>(),
      Map map => <Object?>[map],
      _ => const <Object?>[],
    };

    AnimeThemesAnime? best;
    int bestScore = -1;
    for (final Object? raw in animeList) {
      if (raw is! Map) continue;
      final Map<String, dynamic> json = raw.cast<String, dynamic>();
      final AnimeThemesAnime anime = AnimeThemesAnime.fromJson(
        json,
        fallbackImageUrl: item.posterUrl,
      );
      final int score = _scoreAnime(json, anime, item);
      if (score > bestScore) {
        bestScore = score;
        best = anime;
      }
    }

    return bestScore <= 0 ? null : best;
  }

  int _scoreAnime(
    Map<String, dynamic> json,
    AnimeThemesAnime anime,
    MediaItem item,
  ) {
    int score = 0;

    final Map<String, String> ids = item.externalIds;
    final String anilistId = (ids['anilist'] ?? '').trim();
    final String malId = (ids['mal'] ?? '').trim();
    final String kitsuId = (ids['kitsu'] ?? '').trim();
    for (final Object? rawResource in _list(json['resources'])) {
      if (rawResource is! Map) continue;
      final Map<String, dynamic> resource = rawResource.cast<String, dynamic>();
      final String site = _string(resource['site']).toLowerCase();
      final String externalId = _string(resource['external_id']);
      if (anilistId.isNotEmpty &&
          site == 'anilist' &&
          externalId == anilistId) {
        score += 1000;
      }
      if (malId.isNotEmpty && site == 'myanimelist' && externalId == malId) {
        score += 1000;
      }
      if (kitsuId.isNotEmpty && site == 'kitsu' && externalId == kitsuId) {
        score += 1000;
      }
    }

    final Set<String> targetTitles = _titleQueries(item).map(_norm).toSet();
    if (targetTitles.contains(_norm(anime.name))) score += 120;
    if (anime.themes.isNotEmpty) score += 30;
    if (anime.year != null && anime.year! > 0) score += 1;
    return score;
  }

  List<String> _titleQueries(MediaItem item) {
    final List<String> titles = <String>[
      item.externalIds['anilist_title_romaji'] ?? '',
      item.externalIds['anilist_title_english'] ?? '',
      item.externalIds['anilist_title_native'] ?? '',
      item.originalTitle,
      item.title,
      ...item.aliases,
    ];
    final Set<String> seen = <String>{};
    return <String>[
      for (final String title in titles)
        if (title.trim().isNotEmpty && seen.add(_norm(title))) title.trim(),
    ];
  }
}

class AnimeThemesAnime {
  const AnimeThemesAnime({
    required this.name,
    required this.slug,
    required this.imageUrl,
    required this.themes,
    this.year,
  });

  final String name;
  final String slug;
  final String imageUrl;
  final List<AnimeThemeInfo> themes;
  final int? year;

  String get pageUrl =>
      slug.isEmpty ? 'https://animethemes.moe' : _animeThemesAnimeUrl(slug);

  factory AnimeThemesAnime.fromJson(
    Map<String, dynamic> json, {
    String fallbackImageUrl = '',
  }) {
    final String imageUrl =
        _imageForFacet(json['images'], 'Large Cover') ??
        _imageForFacet(json['images'], 'Small Cover') ??
        fallbackImageUrl;

    final String slug = _string(json['slug']);
    final String pageUrl = slug.isEmpty
        ? 'https://animethemes.moe'
        : _animeThemesAnimeUrl(slug);

    final List<AnimeThemeInfo> themes = <AnimeThemeInfo>[
      for (final Object? raw in _list(json['animethemes']))
        if (raw is Map)
          AnimeThemeInfo.fromJson(
            raw.cast<String, dynamic>(),
            animeSlug: slug,
            fallbackOpenUrl: pageUrl,
            imageUrl: imageUrl,
          ),
    ]..sort(_compareThemes);

    return AnimeThemesAnime(
      name: _string(json['name']),
      slug: slug,
      imageUrl: imageUrl,
      themes: themes,
      year: _intOrNull(json['year']),
    );
  }
}

class AnimeThemeInfo {
  const AnimeThemeInfo({
    required this.label,
    required this.songTitle,
    required this.imageUrl,
    required this.openUrl,
    required this.videoUrl,
    required this.episodes,
    required this.versionCount,
    required this.nsfw,
    required this.spoiler,
    required this.type,
    required this.sequence,
  });

  final String label;
  final String songTitle;
  final String imageUrl;
  final String openUrl;
  final String videoUrl;
  final String episodes;
  final int versionCount;
  final bool nsfw;
  final bool spoiler;
  final String type;
  final int? sequence;

  factory AnimeThemeInfo.fromJson(
    Map<String, dynamic> json, {
    required String animeSlug,
    required String fallbackOpenUrl,
    required String imageUrl,
  }) {
    final String type = _string(json['type']).toUpperCase();
    final int? sequence = _intOrNull(json['sequence']);
    final String slug = _string(json['slug']);
    final String label = slug.isNotEmpty
        ? slug
        : sequence == null || sequence <= 0
        ? type
        : '$type$sequence';

    final List<Object?> entries = _list(json['animethemeentries']);
    final List<String> episodes = <String>[];
    bool nsfw = false;
    bool spoiler = false;
    String videoUrl = '';
    String themePageUrl = '';
    for (final Object? rawEntry in entries) {
      if (rawEntry is! Map) continue;
      final Map<String, dynamic> entry = rawEntry.cast<String, dynamic>();
      final String entryEpisodes = _string(entry['episodes']);
      if (entryEpisodes.isNotEmpty) episodes.add(entryEpisodes);
      nsfw = nsfw || entry['nsfw'] == true;
      spoiler = spoiler || entry['spoiler'] == true;
      for (final Object? rawVideo in _list(entry['videos'])) {
        if (rawVideo is! Map) continue;
        final Map<String, dynamic> video = rawVideo.cast<String, dynamic>();
        if (videoUrl.isEmpty) {
          videoUrl = _string(video['link']);
        }
        if (themePageUrl.isEmpty) {
          final String videoPageSlug = _videoPageSlug(
            themeSlug: label,
            entryVersion: _intOrNull(entry['version']),
            video: video,
          );
          if (animeSlug.isNotEmpty && videoPageSlug.isNotEmpty) {
            themePageUrl = _animeThemesThemeUrl(animeSlug, videoPageSlug);
          }
        }
      }
    }

    final Object? song = json['song'];
    final String songTitle = song is Map
        ? _string(song.cast<String, dynamic>()['title'])
        : '';

    return AnimeThemeInfo(
      label: label,
      songTitle: songTitle.isNotEmpty ? songTitle : label,
      imageUrl: imageUrl,
      openUrl: themePageUrl.isNotEmpty ? themePageUrl : fallbackOpenUrl,
      videoUrl: videoUrl,
      episodes: episodes.join(', '),
      versionCount: entries.length,
      nsfw: nsfw,
      spoiler: spoiler,
      type: type,
      sequence: sequence,
    );
  }
}

int _compareThemes(AnimeThemeInfo a, AnimeThemeInfo b) {
  final int typeCompare = _themeTypeRank(
    a.type,
  ).compareTo(_themeTypeRank(b.type));
  if (typeCompare != 0) return typeCompare;
  final int sequenceCompare = (a.sequence ?? 9999).compareTo(
    b.sequence ?? 9999,
  );
  if (sequenceCompare != 0) return sequenceCompare;
  return a.label.compareTo(b.label);
}

int _themeTypeRank(String type) => switch (type.toUpperCase()) {
  'OP' => 0,
  'ED' => 1,
  _ => 2,
};

String _videoPageSlug({
  required String themeSlug,
  required int? entryVersion,
  required Map<String, dynamic> video,
}) {
  final String tags = _string(video['tags']);
  if (themeSlug.isEmpty || tags.isEmpty) return '';
  final String versionSuffix = entryVersion != null && entryVersion > 1
      ? 'v$entryVersion'
      : '';
  return '$themeSlug$versionSuffix-$tags';
}

String _animeThemesAnimeUrl(String animeSlug) {
  return Uri.https('animethemes.moe', '/anime/$animeSlug').toString();
}

String _animeThemesThemeUrl(String animeSlug, String videoPageSlug) {
  return Uri.https(
    'animethemes.moe',
    '/anime/$animeSlug/$videoPageSlug',
  ).toString();
}

String? _imageForFacet(Object? rawImages, String facet) {
  for (final Object? rawImage in _list(rawImages)) {
    if (rawImage is! Map) continue;
    final Map<String, dynamic> image = rawImage.cast<String, dynamic>();
    if (_string(image['facet']).toLowerCase() == facet.toLowerCase()) {
      final String link = _string(image['link']);
      if (link.isNotEmpty) return link;
    }
  }
  return null;
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const <Object?>[];
}

String _string(Object? value) => value?.toString().trim() ?? '';

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value));
}

String _norm(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
