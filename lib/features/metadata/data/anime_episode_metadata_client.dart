import 'package:dio/dio.dart';

import '../domain/anime_episode_metadata.dart';

class AnimeEpisodeMetadataClient {
  AnimeEpisodeMetadataClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;
  final Map<String, _CacheEntry<AnimeEpisodeMetadataBundle>> _cache =
      <String, _CacheEntry<AnimeEpisodeMetadataBundle>>{};

  static const Duration _cacheTtl = Duration(hours: 6);
  static const int _maxCacheSize = 120;

  Future<AnimeEpisodeMetadataBundle> fetch({
    required int anilistId,
    required String languageCode,
  }) async {
    if (anilistId <= 0) return AnimeEpisodeMetadataBundle.empty;

    final String normalizedLanguage = languageCode.trim().toLowerCase();
    final String key = '$anilistId:$normalizedLanguage';
    final AnimeEpisodeMetadataBundle? cached = _cache[key]?.valueIfFresh;
    if (cached != null) return cached;

    final List<Map<int, AnimeEpisodeMetadata>> results =
        await Future.wait(<Future<Map<int, AnimeEpisodeMetadata>>>[
          _fetchAniZip(
            anilistId,
            normalizedLanguage,
          ).catchError((_) async => <int, AnimeEpisodeMetadata>{}),
          _fetchAniList(
            anilistId,
          ).catchError((_) async => <int, AnimeEpisodeMetadata>{}),
        ]);

    final Map<int, AnimeEpisodeMetadata> episodes =
        <int, AnimeEpisodeMetadata>{};
    for (final Map<int, AnimeEpisodeMetadata> result in results) {
      for (final MapEntry<int, AnimeEpisodeMetadata> entry in result.entries) {
        final AnimeEpisodeMetadata current =
            episodes[entry.key] ?? const AnimeEpisodeMetadata();
        final AnimeEpisodeMetadata incoming = entry.value;
        episodes[entry.key] = current.copyWith(
          aniZipImage: incoming.aniZipImage.isNotEmpty
              ? incoming.aniZipImage
              : current.aniZipImage,
          aniZipTitle: incoming.aniZipTitle.isNotEmpty
              ? incoming.aniZipTitle
              : current.aniZipTitle,
          aniListThumbnail: incoming.aniListThumbnail.isNotEmpty
              ? incoming.aniListThumbnail
              : current.aniListThumbnail,
          aniListTitle: incoming.aniListTitle.isNotEmpty
              ? incoming.aniListTitle
              : current.aniListTitle,
          tvdbTitle: incoming.tvdbTitle.isNotEmpty
              ? incoming.tvdbTitle
              : current.tvdbTitle,
        );
      }
    }

    final AnimeEpisodeMetadataBundle bundle = AnimeEpisodeMetadataBundle(
      anilistId: anilistId,
      languageCode: normalizedLanguage,
      episodes: Map<int, AnimeEpisodeMetadata>.unmodifiable(episodes),
    );
    _putCache(key, bundle);
    return bundle;
  }

  Future<Map<int, AnimeEpisodeMetadata>> _fetchAniList(int anilistId) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      'https://graphql.anilist.co',
      data: <String, dynamic>{
        'query': '''
          query EpisodeArtwork(\$id: Int) {
            Media(id: \$id, type: ANIME) {
              streamingEpisodes { title thumbnail url site }
            }
          }
        ''',
        'variables': <String, dynamic>{'id': anilistId},
      },
      options: Options(
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final Object? media = _nested(response.data, const <String>[
      'data',
      'Media',
    ]);
    if (media is! Map) return const <int, AnimeEpisodeMetadata>{};
    final Object? rawEpisodes = media['streamingEpisodes'];
    if (rawEpisodes is! List) return const <int, AnimeEpisodeMetadata>{};

    final Map<int, AnimeEpisodeMetadata> episodes =
        <int, AnimeEpisodeMetadata>{};
    for (final Object? raw in rawEpisodes) {
      if (raw is! Map) continue;
      final String title = _string(raw['title']);
      final int? number = _episodeNumberFromAniListTitle(title);
      if (number == null || number <= 0) continue;
      final AnimeEpisodeMetadata current =
          episodes[number] ?? const AnimeEpisodeMetadata();
      final String thumbnail = _string(raw['thumbnail']);
      episodes[number] = current.copyWith(
        aniListTitle: current.aniListTitle.isEmpty ? title : null,
        aniListThumbnail: current.aniListThumbnail.isEmpty ? thumbnail : null,
      );
    }
    return episodes;
  }

  Future<Map<int, AnimeEpisodeMetadata>> _fetchAniZip(
    int anilistId,
    String languageCode,
  ) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      'https://api.ani.zip/mappings',
      queryParameters: <String, dynamic>{'anilist_id': anilistId},
      options: Options(
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );
    final Object? body = response.data;
    if (body is! Map) return const <int, AnimeEpisodeMetadata>{};
    final Object? rawEpisodes = body['episodes'];

    final Iterable<MapEntry<Object?, Object?>> entries = switch (rawEpisodes) {
      Map<dynamic, dynamic> map => map.entries.map(
        (MapEntry<dynamic, dynamic> e) =>
            MapEntry<Object?, Object?>(e.key, e.value),
      ),
      List<dynamic> list => list.indexed.map(
        ((int, dynamic) e) => MapEntry<Object?, Object?>(e.$1 + 1, e.$2),
      ),
      _ => const <MapEntry<Object?, Object?>>[],
    };

    final Map<int, AnimeEpisodeMetadata> episodes =
        <int, AnimeEpisodeMetadata>{};
    for (final MapEntry<Object?, Object?> entry in entries) {
      final Object? raw = entry.value;
      if (raw is! Map) continue;
      final int? number = _episodeNumberFromAniZip(raw, entry.key);
      if (number == null || number <= 0) continue;
      final String title = _localizedAniZipTitle(
        raw['title'] ?? raw['titles'] ?? raw['name'],
        languageCode,
      );
      final String image = _string(
        raw['image'],
        fallback: _string(
          raw['thumbnail'],
          fallback: _string(raw['img'], fallback: _string(raw['poster'])),
        ),
      );
      final String tvdbTitle = _localizedAniZipTitle(
        raw['tvdbTitle'] ?? raw['tvdb_title'] ?? raw['tvdbName'],
        languageCode,
      );
      episodes[number] = (episodes[number] ?? const AnimeEpisodeMetadata())
          .copyWith(
            aniZipTitle: title,
            aniZipImage: image,
            tvdbTitle: tvdbTitle,
          );
    }
    return episodes;
  }

  void _putCache(String key, AnimeEpisodeMetadataBundle value) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry<AnimeEpisodeMetadataBundle>(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }

  static int? _episodeNumberFromAniListTitle(String title) {
    if (title.trim().isEmpty) return null;
    final RegExpMatch? seasonEpisode = RegExp(
      r'\bs\d+\s*e(\d+(?:\.\d+)?)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (seasonEpisode != null) return _positiveInt(seasonEpisode.group(1));

    final RegExpMatch? explicit = RegExp(
      r'\b(?:episode|ep\.?|e|#)\s*(\d+(?:\.\d+)?)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (explicit != null) return _positiveInt(explicit.group(1));

    final RegExpMatch? leading = RegExp(
      r'^\s*(\d+(?:\.\d+)?)\b',
    ).firstMatch(title);
    final int? leadingNumber = _positiveInt(leading?.group(1));
    if (leadingNumber != null) return leadingNumber;

    final RegExpMatch? any = RegExp(r'(\d{1,4})').firstMatch(title);
    return _positiveInt(any?.group(1));
  }

  static int? _episodeNumberFromAniZip(
    Map<dynamic, dynamic> json,
    Object? key,
  ) {
    for (final Object? value in <Object?>[
      json['episodeNumber'],
      json['number'],
      json['episode'],
      key,
      json['absoluteEpisodeNumber'],
    ]) {
      final int? parsed = _positiveInt(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _localizedAniZipTitle(Object? value, String languageCode) {
    if (value is String) return value.trim();
    if (value is! Map) return '';

    final Map<String, String> titles = <String, String>{};
    value.forEach((Object? key, Object? mapValue) {
      final String title = _string(mapValue);
      if (title.isNotEmpty) titles[key.toString().toLowerCase()] = title;
    });
    if (titles.isEmpty) return '';

    final List<String> preferred = switch (languageCode) {
      'ja' => const <String>['ja'],
      'jpn' => const <String>['ja'],
      'x-jat' => const <String>['x-jat'],
      'romaji' => const <String>['x-jat'],
      _ => const <String>['en'],
    };
    for (final String key in <String>[
      ...preferred,
      'en',
      'x-jat',
      'ja',
      'x-unk',
    ]) {
      final String? title = titles[key];
      if (title != null && title.isNotEmpty) return title;
    }
    return titles.values.first;
  }

  static int? _positiveInt(Object? value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) {
      if (value != value.roundToDouble()) return null;
      return value.round();
    }
    if (value is String) {
      final String trimmed = value.trim();
      final RegExpMatch? match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(trimmed);
      if (match == null) return null;
      final double? parsed = double.tryParse(match.group(1) ?? '');
      if (parsed == null || parsed <= 0) return null;
      if (parsed != parsed.roundToDouble()) return null;
      return parsed.round();
    }
    return null;
  }

  static Object? _nested(Object? value, List<String> keys) {
    Object? current = value;
    for (final String key in keys) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num || value is bool) return value.toString();
    return fallback;
  }
}

class _CacheEntry<T> {
  const _CacheEntry({required this.value, required this.expiry});

  final T value;
  final DateTime expiry;

  T? get valueIfFresh => expiry.isAfter(DateTime.now()) ? value : null;
}
