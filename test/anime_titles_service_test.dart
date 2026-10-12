import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/application/sora_source_providers.dart';
import 'package:mirushin/features/addons/data/anime_titles_service.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.response);
  final Future<Object?> Function(RequestOptions) response;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final value = await response(options);
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio client(FixtureAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://shikimori.one'))
      ..httpClientAdapter = adapter;
Object shiki({int id = 300, int mal = 2, String ru = 'Госпожа Кагуя'}) => {
  'data': {
    'animes': [
      {
        'id': '$id',
        'malId': '$mal',
        'name': 'Kaguya-sama',
        'russian': ru,
        'english': '',
        'japanese': '',
      },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  MediaItem media({
    List<String> aliases = const [],
    Map<String, String> extraIds = const {},
  }) => MediaItem(
    id: 'anilist:1',
    title: 'Kaguya-sama',
    originalTitle: '',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 8,
    genres: const [],
    sourceProvider: 'AniList',
    statusLabel: 'FINISHED',
    aliases: aliases,
    externalIds: {'anilist': '1', 'mal': '2', 'shikimori': '300', ...extraIds},
  );

  test(
    'source session prioritizes Shikimori RU while AniList is hanging',
    () async {
      final hanging = Completer<Object?>();
      final adapter = FixtureAdapter(
        (request) async =>
            request.uri.host == 'shikimori.one' ? shiki() : hanging.future,
      );
      final dio = client(adapter);
      final session = createSourceTitleSession(
        media: media(),
        languageCodes: ['ru', 'en'],
        settings: const SettingsState(),
        titleClient: dio,
      );
      final variants = await session
          .forLanguage('ru')
          .timeout(const Duration(seconds: 2));
      expect(
        variants.where((v) => v.languageCode == 'ru').single.title,
        'Госпожа Кагуя',
      );
      expect(hanging.isCompleted, isFalse);
      session.cancel();
      hanging.complete({});
      dio.close(force: true);
    },
  );

  test(
    'local RU starts immediately even if every title provider hangs',
    () async {
      final hanging = Completer<Object?>();
      final dio = client(FixtureAdapter((_) => hanging.future));
      final session = createSourceTitleSession(
        media: media(aliases: ['Локальное название']),
        languageCodes: ['ru', 'en'],
        settings: const SettingsState(),
        titleClient: dio,
      );
      final variants = await session
          .forLanguage('ru')
          .timeout(const Duration(seconds: 2));
      expect(variants.any((v) => v.title == 'Локальное название'), isTrue);
      session.cancel();
      hanging.complete({});
      dio.close(force: true);
    },
  );

  test('RU failure releases priority while AniList is still hanging', () async {
    final hanging = Completer<Object?>();
    final dio = client(
      FixtureAdapter(
        (request) async =>
            request.uri.host == 'shikimori.one' ? {} : hanging.future,
      ),
    );
    final session = createSourceTitleSession(
      media: media(),
      languageCodes: ['ru', 'en'],
      settings: const SettingsState(),
      titleClient: dio,
    );
    final variants = await session
        .forLanguage('ru')
        .timeout(const Duration(seconds: 2));
    expect(variants.any((v) => v.languageCode == 'ru'), isFalse);
    expect(variants.any((v) => v.languageCode == 'en'), isTrue);
    session.cancel();
    hanging.complete({});
    dio.close(force: true);
  });

  test(
    'distinctive selected season never uses parent IDs or parent Russian title',
    () async {
      final adapter = FixtureAdapter(
        (_) async => [
          {
            'id': 300,
            'name': 'Kaguya-sama',
            'russian': 'Wrong parent Russian title',
          },
        ],
      );
      final dio = client(adapter);
      final session = createSourceTitleSession(
        media: media(extraIds: {'sora_season_name': 'Distinct season two'}),
        languageCodes: ['ru', 'en'],
        settings: const SettingsState(),
        titleClient: dio,
      );
      final variants = await session
          .forLanguage('ru')
          .timeout(const Duration(seconds: 2));
      expect(
        variants.any((v) => v.title == 'Wrong parent Russian title'),
        isFalse,
      );
      expect(
        adapter.requests.every((r) => r.uri.path == '/api/animes'),
        isTrue,
      );
      expect(
        adapter.requests.first.queryParameters['search'],
        'Distinct season two',
      );
      session.cancel();
      dio.close(force: true);
    },
  );

  test(
    'working Shikimori publishes RU before hanging AniList/Jikan and cancellation stops HTTP',
    () async {
      final hanging = Completer<Object?>();
      final adapter = FixtureAdapter((request) async {
        if (request.uri.host == 'shikimori.one') return shiki();
        return hanging.future;
      });
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      final token = CancelToken();
      final ru = Completer<AnimeTitles>();
      final done = Completer<void>();
      final subscription =
          AnimeTitlesService.watch(
            anilistId: '1',
            malId: '2',
            shikimoriId: '300',
            dio: dio,
            cancelToken: token,
          ).listen((titles) {
            if (!ru.isCompleted && titles.russian.isNotEmpty) {
              ru.complete(titles);
            }
          }, onDone: done.complete);
      expect(
        (await ru.future.timeout(const Duration(seconds: 2))).russian,
        'Госпожа Кагуя',
      );
      expect(hanging.isCompleted, isFalse);
      token.cancel('test cancellation');
      await done.future.timeout(const Duration(seconds: 2));
      await subscription.cancel();
      hanging.complete({});
    },
  );

  test(
    'RU-only search does not make unnecessary AniList/Jikan requests',
    () async {
      final adapter = FixtureAdapter((_) async => shiki());
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      final titles = await AnimeTitlesService.resolve(
        anilistId: '1',
        malId: '2',
        shikimoriId: '300',
        languageCodes: ['ru'],
        dio: dio,
      );
      expect(titles.russian, 'Госпожа Кагуя');
      expect(adapter.requests.length, 1);
    },
  );

  test(
    'known Shikimori and MAL ID mismatch cannot supply a wrong title',
    () async {
      final adapter = FixtureAdapter(
        (_) async => shiki(mal: 999, ru: 'Wrong season'),
      );
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      final titles = await AnimeTitlesService.resolve(
        malId: '2',
        shikimoriId: '300',
        languageCodes: ['ru'],
        titleCandidates: ['Kaguya-sama'],
        dio: dio,
      );
      expect(titles.isEmpty, isTrue);
      expect(
        adapter.requests.where((r) => r.uri.path == '/api/animes'),
        isEmpty,
      );
    },
  );

  test(
    'MAL-only resolver verifies correspondence before reading Russian title',
    () async {
      final adapter = FixtureAdapter((request) async {
        final data = request.data as Map;
        if ('${data['query']}'.contains('ResolveShikimoriMedia')) {
          final variables = data['variables'] as Map;
          return variables.containsKey('ids')
              ? shiki(id: 2, mal: 999)
              : shiki();
        }
        return shiki();
      });
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      final titles = await AnimeTitlesService.resolve(
        malId: '2',
        languageCodes: ['ru'],
        titleCandidates: ['Kaguya-sama'],
        dio: dio,
      );
      expect(titles.russian, 'Госпожа Кагуя');
      expect(adapter.requests.last.data['query'], contains('ids: "300"'));
    },
  );

  test(
    'no arbitrary first title match; unidentified titles have separate cache identities',
    () async {
      final adapter = FixtureAdapter(
        (request) async => [
          {'id': 99, 'name': 'Other season', 'russian': 'Wrong'},
          {
            'id': 7,
            'name': request.queryParameters['search'],
            'russian': 'RU ${request.queryParameters['search']}',
          },
        ],
      );
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      final first = await AnimeTitlesService.resolve(
        titleCandidates: ['Season A'],
        languageCodes: ['ru'],
        dio: dio,
      );
      final second = await AnimeTitlesService.resolve(
        titleCandidates: ['Season B'],
        languageCodes: ['ru'],
        dio: dio,
      );
      expect(first.russian, 'RU Season A');
      expect(second.russian, 'RU Season B');
      expect(adapter.requests.length, 2);
      expect(
        (await AnimeTitlesService.resolve(
          titleCandidates: ['Season A'],
          languageCodes: ['ru'],
          dio: dio,
        )).russian,
        first.russian,
      );
      expect(adapter.requests.length, 2);
    },
  );

  test(
    'ambiguous exact title results and unmatched results are not accepted',
    () async {
      final adapter = FixtureAdapter(
        (request) async => [
          {'id': 1, 'name': 'Ambiguous', 'russian': 'Wrong one'},
          {'id': 2, 'name': 'Ambiguous', 'russian': 'Wrong two'},
        ],
      );
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      expect(
        (await AnimeTitlesService.resolve(
          titleCandidates: ['Ambiguous'],
          languageCodes: ['ru'],
          dio: dio,
        )).isEmpty,
        isTrue,
      );
      expect(
        (await AnimeTitlesService.resolve(
          titleCandidates: ['Unknown'],
          languageCodes: ['ru'],
          dio: dio,
        )).isEmpty,
        isTrue,
      );
    },
  );

  test(
    'empty provider result cannot erase a cached title; IDs and language order distinguish caches',
    () async {
      bool empty = false;
      final adapter = FixtureAdapter((_) async => empty ? {} : shiki());
      final dio = client(adapter);
      addTearDown(() => dio.close(force: true));
      await AnimeTitlesService.resolve(
        shikimoriId: '300',
        languageCodes: ['ru', 'en'],
        dio: dio,
      );
      empty = true;
      expect(
        (await AnimeTitlesService.resolve(
          shikimoriId: '300',
          languageCodes: ['ru', 'en'],
          dio: dio,
        )).russian,
        'Госпожа Кагуя',
      );
      expect(
        (await AnimeTitlesService.resolve(
          shikimoriId: '301',
          languageCodes: ['ru', 'en'],
          dio: dio,
        )).isEmpty,
        isTrue,
      );
      expect(
        (await AnimeTitlesService.resolve(
          shikimoriId: '300',
          languageCodes: ['en', 'ru'],
          dio: dio,
        )).isEmpty,
        isTrue,
      );
    },
  );
}
