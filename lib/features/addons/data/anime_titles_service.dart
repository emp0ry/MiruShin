import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tracking/data/shikimori_api_client.dart';

/// Resolved multi-language titles for an anime.
class AnimeTitles {
  const AnimeTitles({
    this.english = '',
    this.japanese = '',
    this.romaji = '',
    this.russian = '',
    this.settledProviders = const {},
  });

  final String english;
  final String japanese;
  final String romaji;
  final String russian;

  /// Session-only completion signals, never persisted as metadata.
  final Set<String> settledProviders;

  bool get isEmpty =>
      english.isEmpty && japanese.isEmpty && romaji.isEmpty && russian.isEmpty;
}

/// Independent enrichment: every successful provider can publish immediately.
/// Provider IDs are verified; title-only enrichment never creates a binding.
class AnimeTitlesService {
  static const String _anilistEndpoint = 'https://graphql.anilist.co';
  static const String _jikanBase = 'https://api.jikan.moe/v4';
  static const String _shikimoriEndpoint = 'https://shikimori.one/api/graphql';

  // Persistent cache TTL: 7 days (Russian titles rarely change).
  static const Duration _cacheTtl = Duration(days: 7);
  static const String _cachePrefix = 'animeTitles.v2.';

  static Dio _makeDio() => Dio(
    BaseOptions(
      baseUrl: 'https://shikimori.one',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static Future<AnimeTitles> resolve({
    String? anilistId,
    String? malId,
    String? shikimoriId,
    Iterable<String> titleCandidates = const [],
    List<String> languageCodes = const ['ru', 'ja', 'en'],
    CancelToken? cancelToken,
    Dio? dio,
  }) async {
    AnimeTitles latest = const AnimeTitles();
    await for (final value in watch(
      anilistId: anilistId,
      malId: malId,
      shikimoriId: shikimoriId,
      titleCandidates: titleCandidates,
      languageCodes: languageCodes,
      cancelToken: cancelToken,
      dio: dio,
    )) {
      latest = value;
    }
    return latest;
  }

  /// Each provider publishes independently. Russian enrichment never awaits
  /// AniList/Jikan, and cancelling a consumer cancels all of its HTTP requests.
  static Stream<AnimeTitles> watch({
    String? anilistId,
    String? malId,
    String? shikimoriId,
    Iterable<String> titleCandidates = const [],
    List<String> languageCodes = const ['ru', 'ja', 'en'],
    CancelToken? cancelToken,
    Dio? dio,
  }) async* {
    final token = cancelToken ?? CancelToken();
    final candidates = _uniqueQueries(titleCandidates);
    final identity =
        '${anilistId ?? ''}${malId ?? ''}${shikimoriId ?? ''}'.isEmpty
        ? sha256.convert(utf8.encode(jsonEncode(candidates))).toString()
        : '';
    final key =
        '${_cachePrefix}al:${anilistId ?? ''}|mal:${malId ?? ''}|shiki:${shikimoriId ?? ''}|${languageCodes.join(',')}|$identity';
    final cached = await _readCache(key) ?? const AnimeTitles();
    if (token.isCancelled) return;
    if (!cached.isEmpty) yield cached;
    bool hasLanguage(String code) => switch (code) {
      'ru' => cached.russian.isNotEmpty,
      'ja' => cached.japanese.isNotEmpty || cached.romaji.isNotEmpty,
      _ => cached.english.isNotEmpty,
    };
    if (languageCodes.isNotEmpty && languageCodes.every(hasLanguage)) return;
    final client = dio ?? _makeDio();
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        options.cancelToken = token;
        handler.next(options);
      },
    );
    client.interceptors.add(interceptor);
    final updates = StreamController<AnimeTitles>();
    Future<void> cacheWrites = Future.value();
    final values = <String, AnimeTitles>{'cache': cached};
    final settled = <String>{};
    int pending = 0;
    AnimeTitles merged() {
      String field(String Function(AnimeTitles) read, List<String> order) {
        for (final source in order) {
          final text = read(values[source] ?? const AnimeTitles());
          if (text.isNotEmpty) return text;
        }
        return '';
      }

      return AnimeTitles(
        english: field((t) => t.english, [
          'anilist',
          'jikan',
          'shiki',
          'cache',
        ]),
        japanese: field((t) => t.japanese, [
          'anilist',
          'jikan',
          'shiki',
          'cache',
        ]),
        romaji: field((t) => t.romaji, ['anilist', 'jikan', 'shiki', 'cache']),
        russian: field((t) => t.russian, ['shiki', 'cache']),
        settledProviders: Set.unmodifiable(settled),
      );
    }

    final jobs = <String, Future<AnimeTitles> Function()>{
      if ((anilistId ?? '').isNotEmpty && languageCodes.any((c) => c != 'ru'))
        'anilist': () => _fromAniList(client, anilistId!),
      if ((malId ?? '').isNotEmpty && languageCodes.any((c) => c != 'ru'))
        'jikan': () => _fromJikan(client, malId!),
      'shiki': () async {
        final exact = await _withRetry429(
          () => _fromShikimori(client, malId, shikimoriId, candidates),
        );
        if (exact.russian.isNotEmpty ||
            (malId ?? '').isNotEmpty ||
            (shikimoriId ?? '').isNotEmpty) {
          return exact;
        }
        return _withRetry429(() => _fromShikimoriSearch(client, candidates));
      },
    };
    pending = jobs.length;
    for (final job in jobs.entries) {
      unawaited(() async {
        try {
          final result = await job.value();
          if (!token.isCancelled && !updates.isClosed && !result.isEmpty) {
            values[job.key] = result;
            cacheWrites = cacheWrites.then((_) => _writeCache(key, merged()));
            updates.add(merged());
          }
        } on Object {
          // A failed provider is independent and never erases cached fields.
        } finally {
          settled.add(job.key);
          if (!token.isCancelled && !updates.isClosed) updates.add(merged());
          pending--;
          if (pending == 0 && !updates.isClosed) await updates.close();
        }
      }());
    }
    try {
      await for (final update in updates.stream) {
        if (token.isCancelled) break;
        yield update;
      }
      await cacheWrites;
      if (!token.isCancelled && !merged().isEmpty) {
        await _writeCache(key, merged());
      }
    } finally {
      if (!token.isCancelled) token.cancel('title consumer finished');
      client.interceptors.remove(interceptor);
      if (dio == null) client.close(force: true);
      if (!updates.isClosed) unawaited(updates.close());
    }
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
      final DateTime expiry = DateTime.fromMillisecondsSinceEpoch(
        cachedAt,
      ).add(_cacheTtl);
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

  // AniList

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

  // Jikan (unofficial MAL REST)

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

  // Shikimori GraphQL

  static Future<AnimeTitles> _fromShikimori(
    Dio dio,
    String? malId,
    String? shikimoriId,
    Iterable<String> candidates,
  ) async {
    int? id = int.tryParse(shikimoriId ?? '');
    final int? mal = int.tryParse(malId ?? '');
    if (id == null && mal != null && mal > 0) {
      for (final title in ['', ..._uniqueQueries(candidates)]) {
        id = await ShikimoriApiClient(
          accessToken: '',
          userId: 0,
          dio: dio,
        ).resolveMediaIdByMalId(malId: mal, title: title);
        if (id != null) break;
      }
    }
    if (id == null || id <= 0) return const AnimeTitles();
    final response = await dio.post<dynamic>(
      _shikimoriEndpoint,
      data: {
        'query':
            '{ animes(ids: "$id") { id malId name english japanese russian } }',
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'MiruShin title resolver',
        },
      ),
    );
    final data = response.data;
    if (data is! Map) return const AnimeTitles();
    final items = (data['data'] as Map?)?['animes'];
    if (items is! List) return const AnimeTitles();
    for (final item in items.whereType<Map>()) {
      if (int.tryParse('${item['id']}') != id) continue;
      if (mal != null && int.tryParse('${item['malId']}') != mal) continue;
      return AnimeTitles(
        english: _str(item['english']),
        japanese: _str(item['japanese']),
        romaji: _str(item['name']),
        russian: _str(item['russian']),
      );
    }
    return const AnimeTitles();
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
      if (titles.russian.isNotEmpty) {
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
    if (queryKey.isEmpty) return null;
    final matches = <String, Map<String, dynamic>>{};
    for (final Object? item in items) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> map = item.map(
        (Object? key, Object? value) =>
            MapEntry<String, dynamic>(key.toString(), value),
      );
      for (final Object? value in <Object?>[
        map['name'],
        map['russian'],
        map['english'],
        map['japanese'],
      ]) {
        if (_matchKey(value) == queryKey) {
          matches['${map['id']}'] = map;
          break;
        }
      }
    }
    return matches.length == 1 ? matches.values.single : null;
  }

  static String _matchKey(Object? value) {
    return value
            ?.toString()
            .toLowerCase()
            .replaceAll(
              RegExp(
                r'[^a-zа-яё0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+',
                unicode: true,
              ),
              ' ',
            )
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
