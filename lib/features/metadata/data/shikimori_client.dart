import 'package:dio/dio.dart';

typedef ShikimoriRussianDetails = ({
  String title,
  String description,
  String youtubeTrailerUrl,
});

class ShikimoriSearchHit {
  const ShikimoriSearchHit({
    this.id = 0,
    required this.malId,
    required this.russian,
    required this.name,
  });
  final int id;
  final int malId;
  final String russian;
  final String name;
}

class ShikiMoriClient {
  ShikiMoriClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 14),
            ),
          );

  final Dio _dio;
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  static const String _restUrl = 'https://shikimori.io/api/animes';
  static const String _mangasUrl = 'https://shikimori.io/api/mangas';
  static const String _graphqlUrl = 'https://shikimori.io/api/graphql';
  static const Duration _cacheTtl = Duration(hours: 12);
  static const int _maxCacheSize = 300;

  // Direct lookup by MAL ID via GraphQL — reliable, no 301.
  Future<String?> findRussianTitleByMalId(int malId) async {
    final String key = 'mal:$malId';
    final _CacheEntry? cached = _cache[key];
    if (cached != null && cached.expiry.isAfter(DateTime.now())) {
      return cached.value;
    }

    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        _graphqlUrl,
        data: <String, dynamic>{
          'query': '{ animes(ids: "$malId") { russian } }',
        },
        options: Options(
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );

      final Object? body = response.data;
      if (body is! Map) return null;
      final Object? animes = (body['data'] as Map?)?['animes'];
      if (animes is! List<dynamic> || animes.isEmpty) return null;
      final Object? first = animes.first;
      if (first is! Map) return null;
      final Object? russian = first['russian'];
      final String? result = russian is String && russian.trim().isNotEmpty
          ? russian.trim()
          : null;
      _putCache(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<String?> findRussianTitle(String query) async {
    final String key = query.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) {
      final _CacheEntry entry = _cache[key]!;
      if (entry.expiry.isAfter(DateTime.now())) {
        return entry.value;
      }
      _cache.remove(key);
    }

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        _restUrl,
        queryParameters: <String, String>{
          'search': query.trim(),
          'limit': '3',
          'censored': 'false',
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );

      final Object? data = response.data;
      if (data is! List<dynamic> || data.isEmpty) {
        return null;
      }

      final Object? first = data.first;
      if (first is! Map) return null;

      final Object? russian = first['russian'];
      final String? result = russian is String && russian.trim().isNotEmpty
          ? russian.trim()
          : null;
      _putCache(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  // Search anime/manga by Russian (or any) query; returns up to [limit] hits.
  Future<List<ShikimoriSearchHit>> searchByQuery(
    String query, {
    int limit = 20,
    bool isManga = false,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <ShikimoriSearchHit>[];
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        isManga ? _mangasUrl : _restUrl,
        queryParameters: <String, String>{
          'search': trimmed,
          'limit': limit.toString(),
          'censored': 'false',
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) return const <ShikimoriSearchHit>[];
      final List<ShikimoriSearchHit> hits = <ShikimoriSearchHit>[];
      for (final Object? item in data) {
        if (item is! Map) continue;
        final int? shikimoriId = _parseInt(item['id']);
        final int? malId = _malIdFromJson(item);
        if ((shikimoriId == null || shikimoriId <= 0) &&
            (malId == null || malId <= 0)) {
          continue;
        }
        final String russian = item['russian']?.toString().trim() ?? '';
        final String name = item['name']?.toString().trim() ?? '';
        hits.add(
          ShikimoriSearchHit(
            id: shikimoriId ?? malId ?? 0,
            malId: malId ?? shikimoriId ?? 0,
            russian: russian,
            name: name,
          ),
        );
      }
      return hits;
    } catch (_) {
      return const <ShikimoriSearchHit>[];
    }
  }

  // Batch-fetch Russian titles for a list of MAL IDs via REST.
  Future<Map<int, String>> batchRussianTitles(List<int> ids) async {
    if (ids.isEmpty) return const <int, String>{};

    final List<int> uniqueIds = ids
        .where((int id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (uniqueIds.isEmpty) return const <int, String>{};

    final DateTime now = DateTime.now();
    final Map<int, String> result = <int, String>{};
    final List<int> pendingIds = <int>[];
    for (final int id in uniqueIds) {
      final String cacheKey = 'mal:$id';
      final _CacheEntry? cached = _cache[cacheKey];
      if (cached != null && cached.expiry.isAfter(now)) {
        final String? value = cached.value;
        if (value != null && value.isNotEmpty) {
          result[id] = value;
        }
        continue;
      }
      if (cached != null) _cache.remove(cacheKey);
      pendingIds.add(id);
    }

    for (int i = 0; i < pendingIds.length; i += 50) {
      final int end = i + 50 < pendingIds.length ? i + 50 : pendingIds.length;
      result.addAll(await _fetchRussianTitleBatch(pendingIds.sublist(i, end)));
    }

    return result;
  }

  Future<Map<int, String>> _fetchRussianTitleBatch(List<int> ids) async {
    if (ids.isEmpty) return const <int, String>{};
    final String joined = ids.join(',');
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        _restUrl,
        queryParameters: <String, String>{
          'ids': joined,
          'limit': ids.length.clamp(1, 50).toString(),
          'censored': 'false',
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) return const <int, String>{};
      final Map<int, String> result = <int, String>{};
      for (final Object? item in data) {
        if (item is! Map) continue;
        // id_mal is the MAL ID; Shikimori's own `id` may differ.
        final int? malId = _malIdFromJson(item) ?? _parseInt(item['id']);
        if (malId == null || malId <= 0) continue;
        final String? russian = item['russian']?.toString().trim();
        if (russian != null && russian.isNotEmpty) {
          result[malId] = russian;
          _putCache('mal:$malId', russian);
        }
      }
      for (final int id in ids) {
        if (!result.containsKey(id)) {
          _putCache('mal:$id', null);
        }
      }
      return result;
    } catch (_) {
      return const <int, String>{};
    }
  }

  // Fetch full details from Shikimori REST for Russian text and trailer data.
  Future<ShikimoriRussianDetails?> getRussianDetails(
    int id, {
    int? expectedMalId,
    bool isManga = false,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '${isManga ? _mangasUrl : _restUrl}/$id',
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! Map) return null;
      if (expectedMalId != null && expectedMalId > 0) {
        final int? actualMalId = _malIdFromJson(data);
        // Shikimori's REST detail endpoint omits `id_mal`, so only reject when
        // it is actually present AND disagrees. Rejecting on a missing id_mal
        // (the common case) discarded every valid response, which is why the
        // Russian description never came through while titles did.
        if (actualMalId != null && actualMalId != expectedMalId) return null;
      }
      final String russian = data['russian']?.toString().trim() ?? '';
      final String description = _stripMarkup(
        data['description']?.toString().trim() ?? '',
      );
      final String youtubeTrailerUrl = isManga
          ? ''
          : _russianYoutubeTrailerUrl(data['videos']);
      if (russian.isEmpty && description.isEmpty && youtubeTrailerUrl.isEmpty) {
        return null;
      }
      return (
        title: russian,
        description: description,
        youtubeTrailerUrl: youtubeTrailerUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ShikimoriRussianDetails?> getRussianDetailsForMedia({
    int? malId,
    Iterable<String> queries = const <String>[],
    bool isManga = false,
  }) async {
    if (malId != null && malId > 0) {
      final ShikimoriRussianDetails? direct = await getRussianDetails(
        malId,
        expectedMalId: malId,
        isManga: isManga,
      );
      if (_hasDetails(direct)) return direct;
    }

    final Set<String> seenQueries = <String>{};
    for (final String rawQuery in queries) {
      final String query = rawQuery.trim();
      if (query.isEmpty || !seenQueries.add(query.toLowerCase())) continue;
      final List<ShikimoriSearchHit> hits = await searchByQuery(
        query,
        limit: 5,
        isManga: isManga,
      );
      if (hits.isEmpty) continue;
      final ShikimoriSearchHit hit = _bestHit(hits, malId);
      final bool exactMalMatch =
          malId == null || malId <= 0 || hit.malId == malId;
      final int detailId = hit.id > 0 ? hit.id : hit.malId;
      final ShikimoriRussianDetails? details = await getRussianDetails(
        detailId,
        expectedMalId: malId != null && malId > 0 ? malId : null,
        isManga: isManga,
      );
      if (_hasDetails(details)) return details;
      if (exactMalMatch && hit.russian.isNotEmpty) {
        return (title: hit.russian, description: '', youtubeTrailerUrl: '');
      }
    }

    return null;
  }

  static ShikimoriSearchHit _bestHit(
    List<ShikimoriSearchHit> hits,
    int? malId,
  ) {
    if (malId == null || malId <= 0) return hits.first;
    for (final ShikimoriSearchHit hit in hits) {
      if (hit.malId == malId) return hit;
    }
    return hits.first;
  }

  static bool _hasDetails(ShikimoriRussianDetails? details) {
    return details != null &&
        (details.title.trim().isNotEmpty ||
            details.description.trim().isNotEmpty ||
            details.youtubeTrailerUrl.trim().isNotEmpty);
  }

  static String _russianYoutubeTrailerUrl(Object? videos) {
    if (videos is! List<dynamic>) return '';
    final List<({String url, int localizationRank, int score, int order})>
    candidates = <({String url, int localizationRank, int score, int order})>[];
    var order = 0;
    for (final Object? entry in videos) {
      if (entry is! Map) continue;
      final int currentOrder = order++;
      final String url = _bestVideoUrl(entry);
      if (url.isEmpty) continue;
      final String hosting = entry['hosting']?.toString().trim() ?? '';
      if (!_isYoutubeHosting(hosting) || !_isYoutubeUrl(url)) continue;
      final String kind = entry['kind']?.toString().trim().toLowerCase() ?? '';
      final String videoText = _videoText(entry);
      if (!_hasRussianLocalizationMarker(videoText)) continue;
      if (!_isTrailerVideo(kind, videoText)) continue;
      candidates.add((
        url: url,
        localizationRank: _russianTrailerLocalizationRank(videoText),
        score: _trailerVideoScore(kind, videoText),
        order: currentOrder,
      ));
    }
    if (candidates.isEmpty) return '';
    candidates.sort((a, b) {
      final int localization = a.localizationRank.compareTo(b.localizationRank);
      if (localization != 0) return localization;
      final int score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.order.compareTo(b.order);
    });
    return candidates.first.url;
  }

  static bool _isYoutubeHosting(String hosting) {
    final String normalized = hosting.toLowerCase();
    return normalized == 'youtube' ||
        normalized == 'youtu.be' ||
        normalized == 'youtube.com' ||
        normalized == 'www.youtube.com';
  }

  static bool _isYoutubeUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String host = uri.host.toLowerCase();
    return host == 'youtu.be' || host.endsWith('youtube.com');
  }

  static String _bestVideoUrl(Map<dynamic, dynamic> entry) {
    for (final String key in const <String>['url', 'player_url']) {
      final String url = _normalizeYoutubeUrl(
        entry[key]?.toString().trim() ?? '',
      );
      if (url.isNotEmpty && _isYoutubeUrl(url)) return url;
    }
    return '';
  }

  static String _videoText(Map<dynamic, dynamic> entry) {
    return <String>[
      entry['name']?.toString().trim() ?? '',
      entry['description']?.toString().trim() ?? '',
    ].where((String value) => value.isNotEmpty).join(' ');
  }

  static bool _isTrailerVideo(String kind, String name) {
    final String normalizedName = name.toLowerCase();
    return kind == 'pv' ||
        kind == 'trailer' ||
        kind == 'promo' ||
        normalizedName.contains('trailer') ||
        normalizedName.contains('трейлер') ||
        normalizedName.contains('тизер') ||
        normalizedName.contains('анонс') ||
        RegExp(r'\bpv\b').hasMatch(normalizedName);
  }

  static bool _hasRussianLocalizationMarker(String name) {
    return _russianTrailerLocalizationRank(name) < 2;
  }

  static int _russianTrailerLocalizationRank(String name) {
    final String normalizedName = name.toLowerCase();
    if (normalizedName.contains('озвучк')) return 0;
    if (normalizedName.contains('субтитр') ||
        normalizedName.contains('субтритр')) {
      return 1;
    }
    return 2;
  }

  static int _trailerVideoScore(String kind, String name) {
    final String normalizedName = name.toLowerCase();
    int score = 0;
    if (_hasCyrillic(name) ||
        normalizedName.contains('рус') ||
        normalizedName.contains('russian')) {
      score += 100;
    }
    if (normalizedName.contains('трейлер') ||
        normalizedName.contains('trailer')) {
      score += 40;
    }
    if (kind == 'pv' || RegExp(r'\bpv\b').hasMatch(normalizedName)) {
      score += 20;
    }
    if (normalizedName.contains('тизер') || normalizedName.contains('анонс')) {
      score += 10;
    }
    return score;
  }

  static bool _hasCyrillic(String value) {
    return RegExp(r'[а-яёА-ЯЁ]').hasMatch(value);
  }

  static int? _malIdFromJson(Map<dynamic, dynamic> data) {
    return _parseInt(data['id_mal'] ?? data['myanimelist_id']);
  }

  static String _normalizeYoutubeUrl(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final String lower = trimmed.toLowerCase();
    if (lower.startsWith('www.youtube.com') ||
        lower.startsWith('youtube.com') ||
        lower.startsWith('youtu.be')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  static String _stripMarkup(String text) {
    // [tag=id text content] -> "text content"
    String result = text.replaceAllMapped(
      RegExp(r'\[\w+=\d+\s+([^\]]+)\]'),
      (Match m) => m.group(1) ?? '',
    );
    // [tag=id]content[/tag] -> "content"
    result = result.replaceAllMapped(
      RegExp(r'\[\w+=\d+\]([^\[]*)\[/\w+\]'),
      (Match m) => m.group(1) ?? '',
    );
    // strip any remaining [tag] or [/tag]
    result = result.replaceAll(RegExp(r'\[/?[^\]]*\]'), '');
    return result.trim();
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _putCache(String key, String? value) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiry});
  final String? value;
  final DateTime expiry;
}
