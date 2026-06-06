import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolved multi-language titles for an anime.
class AnimeTitles {
  const AnimeTitles({
    this.english = '',
    this.japanese = '',
    this.romaji = '',
    this.russian = '',
  });

  final String english;
  final String japanese;
  final String romaji;
  final String russian;

  bool get isEmpty =>
      english.isEmpty && japanese.isEmpty && romaji.isEmpty && russian.isEmpty;
}

/// Resolves anime titles from AniList, Jikan (MAL), and Shikimori with
/// graceful fallback at each step.
///
/// Priority:
///   English / Romaji / Japanese -> AniList first, then Jikan if AniList fails.
///   Russian                     -> Shikimori first; falls back to whatever
///                                  AniList/Jikan already gave when Shikimori
///                                  is unavailable.
class AnimeTitlesService {
  static const String _anilistEndpoint = 'https://graphql.anilist.co';
  static const String _jikanBase = 'https://api.jikan.moe/v4';
  static const String _shikimoriEndpoint = 'https://shikimori.one/api/graphql';

  // Persistent cache TTL: 7 days (Russian titles rarely change).
  static const Duration _cacheTtl = Duration(days: 7);
  static const String _cachePrefix = 'animeTitles.v1.';

  static Dio _makeDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static Future<AnimeTitles> resolve({
    String? anilistId,
    String? malId,
    Iterable<String> titleCandidates = const <String>[],
  }) async {
    // Check persistent cache first.
    final String? cacheKey = _cacheKeyFor(anilistId, malId);
    if (cacheKey != null) {
      final AnimeTitles? cached = await _readCache(cacheKey);
      if (cached != null) return cached;
    }

    final Dio dio = _makeDio();
    String english = '';
    String japanese = '';
    String romaji = '';
    String russian = '';

    // ── 1. AniList -> English, Romaji, Japanese ──────────────────────────────
    if (anilistId != null && anilistId.trim().isNotEmpty) {
      try {
        final AnimeTitles al = await _fromAniList(dio, anilistId.trim());
        english = al.english;
        japanese = al.japanese;
        romaji = al.romaji;
        debugPrint(
          '[AnimeTitles] AniList OK — EN:"$english" ROMAJI:"$romaji" JP:"$japanese"',
        );
      } catch (e) {
        debugPrint('[AnimeTitles] AniList failed: $e');
      }
    }

    // ── 2. Jikan (unofficial MAL) fallback ──────────────────────────────────
    if ((english.isEmpty || romaji.isEmpty) &&
        malId != null &&
        malId.trim().isNotEmpty) {
      try {
        final AnimeTitles jk = await _fromJikan(dio, malId.trim());
        if (english.isEmpty) english = jk.english;
        if (japanese.isEmpty) japanese = jk.japanese;
        if (romaji.isEmpty) romaji = jk.romaji;
        debugPrint(
          '[AnimeTitles] Jikan OK — EN:"$english" ROMAJI:"$romaji" JP:"$japanese"',
        );
      } catch (e) {
        debugPrint('[AnimeTitles] Jikan failed: $e');
      }
    }

    // ── 3. Shikimori -> Russian (primary); fallback titles if others failed ──
    if (malId != null && malId.trim().isNotEmpty) {
      try {
        final AnimeTitles sh = await _withRetry429(
          () => _fromShikimori(dio, malId.trim()),
        );
        russian = sh.russian;
        if (english.isEmpty) english = sh.english;
        if (japanese.isEmpty) japanese = sh.japanese;
        // Shikimori `name` is romanized (≈ romaji)
        if (romaji.isEmpty) romaji = sh.romaji;
        debugPrint('[AnimeTitles] Shikimori OK — RU:"$russian"');
      } catch (e) {
        debugPrint('[AnimeTitles] Shikimori failed: $e');
      }
    }

    if (russian.isEmpty) {
      try {
        final AnimeTitles sh = await _withRetry429(
          () => _fromShikimoriSearch(dio, titleCandidates),
        );
        russian = sh.russian;
        if (english.isEmpty) english = sh.english;
        if (japanese.isEmpty) japanese = sh.japanese;
        if (romaji.isEmpty) romaji = sh.romaji;
        if (russian.isNotEmpty) {
          debugPrint('[AnimeTitles] Shikimori search OK — RU:"$russian"');
        }
      } catch (e) {
        debugPrint('[AnimeTitles] Shikimori search failed: $e');
      }
    }

    final AnimeTitles result = AnimeTitles(
      english: english,
      japanese: japanese,
      romaji: romaji,
      russian: russian,
    );

    // Persist only when we got at least a Russian title (the slow path).
    if (cacheKey != null && russian.isNotEmpty) {
      await _writeCache(cacheKey, result);
    }

    return result;
  }

  // ── Persistent cache helpers ───────────────────────────────────────────────

  static String? _cacheKeyFor(String? anilistId, String? malId) {
    if (anilistId != null && anilistId.trim().isNotEmpty) {
      return '$_cachePrefix${anilistId.trim()}';
    }
    if (malId != null && malId.trim().isNotEmpty) {
      return '${_cachePrefix}mal.${malId.trim()}';
    }
    return null;
  }

  static Future<AnimeTitles?> _readCache(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(key);
      if (raw == null) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final int? cachedAt = decoded['cachedAt'] as int?;
      if (cachedAt == null) return null;
      final DateTime expiry = DateTime.fromMillisecondsSinceEpoch(cachedAt)
          .add(_cacheTtl);
      if (DateTime.now().isAfter(expiry)) {
        await prefs.remove(key);
        return null;
      }
      return AnimeTitles(
        english: (decoded['english'] as String?) ?? '',
        japanese: (decoded['japanese'] as String?) ?? '',
        romaji: (decoded['romaji'] as String?) ?? '',
        russian: (decoded['russian'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String key, AnimeTitles titles) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(<String, dynamic>{
          'english': titles.english,
          'japanese': titles.japanese,
          'romaji': titles.romaji,
          'russian': titles.russian,
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  // ── AniList ────────────────────────────────────────────────────────────────

  static Future<AnimeTitles> _fromAniList(Dio dio, String anilistId) async {
    const String query = r'''
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    title { english romaji native }
  }
}''';
    final Response<dynamic> response = await dio.post<dynamic>(
      _anilistEndpoint,
      data: <String, dynamic>{
        'query': query,
        'variables': <String, dynamic>{'id': int.parse(anilistId)},
      },
      options: Options(
        headers: <String, String>{'Content-Type': 'application/json'},
      ),
    );
    final Object? data = response.data;
    if (data is! Map) return const AnimeTitles();
    final Object? title = ((data['data'] as Map?)?['Media'] as Map?)?['title'];
    if (title is! Map) return const AnimeTitles();
    return AnimeTitles(
      english: _str(title['english']),
      romaji: _str(title['romaji']),
      japanese: _str(title['native']),
    );
  }

  // ── Jikan (unofficial MAL REST) ───────────────────────────────────────────

  static Future<AnimeTitles> _fromJikan(Dio dio, String malId) async {
    final Response<dynamic> response = await dio.get<dynamic>(
      '$_jikanBase/anime/$malId',
    );
    final Object? data = response.data;
    if (data is! Map) return const AnimeTitles();
    final Object? d = data['data'];
    if (d is! Map) return const AnimeTitles();

    String english = _str(d['title_english']);
    String japanese = _str(d['title_japanese']);
    // `title` field is usually the romanized/default title
    String romaji = _str(d['title']);

    final Object? titles = d['titles'];
    if (titles is List) {
      for (final Object? t in titles) {
        if (t is! Map) continue;
        final String type = _str(t['type']).toLowerCase();
        final String ttl = _str(t['title']);
        if (ttl.isEmpty) continue;
        if (type == 'english' && english.isEmpty) english = ttl;
        if ((type == 'japanese' || type == 'ja') && japanese.isEmpty) {
          japanese = ttl;
        }
        if ((type == 'default' || type == 'romaji') && romaji.isEmpty) {
          romaji = ttl;
        }
      }
    }
    return AnimeTitles(english: english, japanese: japanese, romaji: romaji);
  }

  // ── Shikimori GraphQL ──────────────────────────────────────────────────────

  static Future<AnimeTitles> _fromShikimori(Dio dio, String malId) async {
    // Shikimori uses MAL IDs. `name` is the romanized title.
    final String gqlQuery =
        '{ animes(ids: "$malId") { name english japanese russian } }';
    final Response<dynamic> response = await dio.post<dynamic>(
      _shikimoriEndpoint,
      data: <String, dynamic>{'query': gqlQuery},
      options: Options(
        headers: <String, String>{'Content-Type': 'application/json'},
      ),
    );
    final Object? data = response.data;
    if (data is! Map) return const AnimeTitles();
    final Object? animes = (data['data'] as Map?)?['animes'];
    if (animes is! List || animes.isEmpty) return const AnimeTitles();
    final Object? first = animes.first;
    if (first is! Map) return const AnimeTitles();
    return AnimeTitles(
      english: _str(first['english']),
      japanese: _str(first['japanese']),
      romaji: _str(first['name']),
      russian: _str(first['russian']),
    );
  }

  static Future<AnimeTitles> _fromShikimoriSearch(
    Dio dio,
    Iterable<String> titleCandidates,
  ) async {
    final List<String> queries = _uniqueQueries(titleCandidates);
    for (final String query in queries) {
      final Response<dynamic> response = await dio.get<dynamic>(
        'https://shikimori.one/api/animes',
        queryParameters: <String, String>{
          'search': query,
          'limit': '10',
          'censored': 'false',
        },
        options: Options(
          headers: <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0 anime title resolver',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! List || data.isEmpty) {
        continue;
      }
      final Map<String, dynamic>? match = _bestShikimoriMatch(data, query);
      if (match == null) {
        continue;
      }
      final AnimeTitles titles = AnimeTitles(
        english: _str(match['english']),
        japanese: _str(match['japanese']),
        romaji: _str(match['name']),
        russian: _str(match['russian']),
      );
      if (!titles.isEmpty) {
        return titles;
      }
    }
    return const AnimeTitles();
  }

  static List<String> _uniqueQueries(Iterable<String> values) {
    final List<String> queries = <String>[];
    final Set<String> seen = <String>{};
    for (final String value in values) {
      final String trimmed = value.trim();
      final String key = trimmed.toLowerCase();
      if (trimmed.isEmpty || !seen.add(key)) {
        continue;
      }
      queries.add(trimmed);
      if (queries.length >= 4) {
        break;
      }
    }
    return queries;
  }

  static Map<String, dynamic>? _bestShikimoriMatch(
    List<dynamic> items,
    String query,
  ) {
    final String queryKey = _matchKey(query);
    Map<String, dynamic>? first;
    for (final Object? item in items) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> map = item.map(
        (Object? key, Object? value) =>
            MapEntry<String, dynamic>(key.toString(), value),
      );
      first ??= map;
      for (final Object? value in <Object?>[
        map['name'],
        map['russian'],
        map['english'],
        map['japanese'],
      ]) {
        if (_matchKey(value) == queryKey) {
          return map;
        }
      }
    }
    return first;
  }

  static String _matchKey(Object? value) {
    return value
            ?.toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-zа-яё0-9]+', unicode: true), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';
  }

  static Future<T> _withRetry429<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return fn();
      }
      rethrow;
    }
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}
