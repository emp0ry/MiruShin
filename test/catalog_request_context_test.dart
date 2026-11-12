import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/core/network/catalog_request_context.dart';
import 'package:mirushin/features/catalog/application/catalog_repository.dart';
import 'package:mirushin/features/metadata/data/shikimori_client.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('deadline includes time spent waiting before transport starts', (
    tester,
  ) async {
    final request = CatalogRequestContext();
    final gate = Completer<void>();
    final result = expectLater(
      request.run(() => gate.future),
      throwsA(isA<CatalogRequestTimeout>()),
    );
    await tester.pump(const Duration(seconds: 15));
    await result;
    expect(request.cancellation.activeRequestCount, 0);
  });

  test(
    'Unicode search keys are distinct and fresh pages do not refresh again',
    () async {
      final client = _SearchClient();
      final repository = AniListCatalogRepository(
        client: client,
        cache: const MetadataCacheStore(),
        cacheScope: 'test.unicode',
      );
      Future<List<MediaItem>> search(String query) => repository.discover(
        search: query,
        type: null,
        filter: 'Trending',
        page: 1,
      );
      expect((await search('Наруто')).single.title, 'Наруто');
      expect((await search('Блич')).single.title, 'Блич');
      expect((await search('Наруто')).single.title, 'Наруто');
      expect(client.calls, 2);
    },
  );

  test('Russian enrichment cannot hold initial catalog results', () async {
    final shikimori = _TranslationClient();
    final dio = Dio()..httpClientAdapter = _CatalogAdapter();
    addTearDown(() => dio.close(force: true));
    final client = AniListApiClient(
      dio: dio,
      titleLanguage: 'RUSSIAN',
      shikimori: shikimori,
    );
    final updates = <List<MediaItem>>[];
    final context = CatalogRequestContext(onItemsUpdated: updates.add);
    addTearDown(context.cancel);
    final items = await context.run(
      () => client.searchCatalog(kind: 'anime', query: 'Base'),
    );
    expect(items.single.title, 'Base');
    expect(updates, isEmpty);
    shikimori.gate.complete({101: 'Перевод'});
    await Future<void>.delayed(Duration.zero);
    expect(updates.single.single.title, 'Перевод');
    expect(context.cancellation.activeRequestCount, 0);
  });

  test(
    'cancellation aborts the active HTTP request without retry/fallback',
    () async {
      final adapter = _CatalogAdapter(stall: true);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final client = AniListApiClient(dio: dio);
      final context = CatalogRequestContext();
      final result = expectLater(
        context.run(() => client.searchCatalog(kind: 'anime', query: 'old')),
        throwsA(isA<CatalogRequestCancelled>()),
      );
      await adapter.entered.future;
      context.cancel();
      await result;
      await adapter.aborted.future;
      expect(adapter.calls, 1);
    },
  );
}

class _SearchClient extends AniListApiClient {
  int calls = 0;
  @override
  Future<List<MediaItem>> searchCatalog({
    required String kind,
    required String query,
    int page = 1,
    int perPage = 20,
  }) async {
    calls++;
    return [
      MediaItem(
        id: 'anilist:$query',
        title: query,
        originalTitle: query,
        overview: '',
        type: MediaType.anime,
        year: 2026,
        posterUrl: '',
        backdropUrl: '',
        rating: 0,
        genres: [],
        sourceProvider: 'AniList',
        externalIds: {},
        statusLabel: '',
      ),
    ];
  }
}

class _TranslationClient extends ShikimoriClient {
  final gate = Completer<Map<int, String>>();
  @override
  Future<Map<int, String>> batchRussianTitles(List<int> ids) => gate.future;
}

class _CatalogAdapter implements HttpClientAdapter {
  _CatalogAdapter({this.stall = false});
  final bool stall;
  final entered = Completer<void>();
  final aborted = Completer<void>();
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    if (stall) {
      await cancelFuture;
      aborted.complete();
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'Page': {
            'media': [
              {
                'id': 1,
                'idMal': 101,
                'title': {'english': 'Base', 'romaji': 'Base'},
                'coverImage': {},
                'format': 'TV',
                'status': 'FINISHED',
              },
            ],
          },
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
