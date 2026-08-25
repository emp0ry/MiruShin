import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/application/cloudflare_challenge_service.dart';
import 'package:mirushin/features/addons/data/sora_addon_store.dart';
import 'package:mirushin/features/addons/data/sora_js_runtime.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime executes a fake async Sora module', () async {
    final Directory temp = await Directory.systemTemp.createTemp('sora_js_');
    addTearDown(() => temp.delete(recursive: true));
    final File script = File('${temp.path}/module.js');
    await script.writeAsString('''
async function searchResults(keyword) {
  return JSON.stringify([{ title: keyword + " Result", image: "poster.jpg", href: "/title" }]);
}
async function extractDetails(url) {
  return JSON.stringify({ title: "Demo", description: "Details", aliases: ["Alias"] });
}
async function extractEpisodes(url) {
  return JSON.stringify([{ number: 1, href: "/ep-1", title: "Episode 1", description: "Pilot" }]);
}
async function extractStreamUrl(url) {
  return JSON.stringify({
    streams: [{
      title: "Server A",
      streamUrl: "https://cdn.example.com/video.m3u8",
      headers: { Referer: "https://example.com" },
      subtitles: [{ url: "https://cdn.example.com/en.vtt", language: "en", label: "English" }]
    }]
  });
}
''');

    final SoraInstalledAddon addon = SoraInstalledAddon(
      id: 'demo',
      manifestUrl: 'https://example.com/addon.json',
      manifest: SoraAddonManifest.fromJson(<String, dynamic>{
        'sourceName': 'Demo Sora',
        'iconUrl': 'https://example.com/icon.png',
        'author': <String, dynamic>{'name': 'Tester'},
        'version': '1.0.0',
        'language': 'en',
        'streamType': 'HLS',
        'quality': '1080p',
        'baseUrl': 'https://example.com',
        'searchBaseUrl': 'https://example.com/search',
        'scriptUrl': 'https://example.com/module.js',
        'type': 'anime',
        'downloadSupport': false,
      }),
      manifestPath: '${temp.path}/manifest.json',
      scriptPath: script.path,
      enabled: true,
      installedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      lastCheckedAt: DateTime.now(),
      lastError: null,
      order: 0,
    );
    final SoraAddonStore store = SoraAddonStore(
      supportDirectoryProvider: () async => temp,
    );
    final SoraJsRuntime runtime = SoraJsRuntime(store: store);
    addTearDown(runtime.invalidateAll);

    final List<SoraSearchResult> results = await runtime.searchResults(
      addon: addon,
      keyword: 'Demo',
      languageCode: 'en',
      titleVariants: const <SoraTitleVariant>[
        SoraTitleVariant(languageCode: 'en', title: 'Demo'),
      ],
    );
    expect(results.single.title, 'Demo Result');

    final SoraSourceDetails details = await runtime.extractDetails(
      addon: addon,
      result: results.single,
    );
    expect(details.description, 'Details');

    final List<SoraEpisode> episodes = await runtime.extractEpisodes(
      addon: addon,
      result: results.single,
    );
    expect(episodes.single.description, 'Pilot');

    final SoraResolvedStreams streams = await runtime.extractStreams(
      addon: addon,
      episode: episodes.single,
    );
    expect(streams.candidates.single.url, contains('.m3u8'));
    expect(streams.candidates.single.subtitles.single.language, 'en');
  });

  test('runtime preserves large fetch JSON for episode extraction', () async {
    final Directory temp = await Directory.systemTemp.createTemp('sora_js_');
    addTearDown(() => temp.delete(recursive: true));

    final String largeDescription = List<String>.filled(600 * 1024, 'x').join();
    final String videosUrl = 'https://example.com/videos';
    final String videosJson = jsonEncode(<String, dynamic>{
      'episodes': <Map<String, dynamic>>[
        <String, dynamic>{
          'number': 1,
          'href': '/ep-1',
          'title': 'Episode 1',
          'description': largeDescription,
        },
      ],
    });
    final Dio dio = Dio()
      ..httpClientAdapter = _FakeAdapter(<String, String>{
        videosUrl: videosJson,
      });

    final File script = File('${temp.path}/module.js');
    await script.writeAsString('''
async function searchResults(keyword) {
  return JSON.stringify([{ title: keyword + " Result", image: "poster.jpg", href: "/title" }]);
}
async function extractEpisodes(url) {
  const res = await fetchv2(${jsonEncode(videosUrl)}, {});
  const json = await res.json();
  return JSON.stringify(json.episodes);
}
async function extractStreamUrl(url) {
  return JSON.stringify({
    streams: [{ title: "Server A", streamUrl: "https://cdn.example.com/video.m3u8" }]
  });
}
''');

    final SoraInstalledAddon addon = SoraInstalledAddon(
      id: 'large-fetch',
      manifestUrl: 'https://example.com/addon.json',
      manifest: SoraAddonManifest.fromJson(<String, dynamic>{
        'sourceName': 'Large Fetch Sora',
        'iconUrl': 'https://example.com/icon.png',
        'author': <String, dynamic>{'name': 'Tester'},
        'version': '1.0.0',
        'language': 'en',
        'streamType': 'HLS',
        'quality': '1080p',
        'baseUrl': 'https://example.com',
        'searchBaseUrl': 'https://example.com/search',
        'scriptUrl': 'https://example.com/module.js',
        'type': 'anime',
        'downloadSupport': false,
      }),
      manifestPath: '${temp.path}/manifest.json',
      scriptPath: script.path,
      enabled: true,
      installedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      lastCheckedAt: DateTime.now(),
      lastError: null,
      order: 0,
    );
    final SoraAddonStore store = SoraAddonStore(
      supportDirectoryProvider: () async => temp,
    );
    final SoraJsRuntime runtime = SoraJsRuntime(store: store, dio: dio);
    addTearDown(runtime.invalidateAll);

    final List<SoraSearchResult> results = await runtime.searchResults(
      addon: addon,
      keyword: 'Large',
      languageCode: 'en',
      titleVariants: const <SoraTitleVariant>[
        SoraTitleVariant(languageCode: 'en', title: 'Large'),
      ],
    );
    final List<SoraEpisode> episodes = await runtime.extractEpisodes(
      addon: addon,
      result: results.single,
    );

    expect(episodes.single.description, largeDescription);
  });

  test(
    'runtime drains fire-and-forget detail fetches before returning',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp('sora_js_');
      addTearDown(() => temp.delete(recursive: true));

      const String logUrl = 'https://telemetry.example.com/rest/v1/app_logs';
      final List<String> completedRequests = <String>[];
      final Dio dio = Dio()
        ..httpClientAdapter = _FakeAdapter(
          <String, String>{logUrl: '{}'},
          delay: const Duration(milliseconds: 40),
          onComplete: completedRequests.add,
        );

      final File script = File('${temp.path}/module.js');
      await script.writeAsString('''
async function searchResults(keyword) {
  return JSON.stringify([{ title: keyword + " Result", image: "poster.jpg", href: "/title" }]);
}
async function extractDetails(url) {
  fetchv2(${jsonEncode(logUrl)}, {}, "POST", JSON.stringify({ url }));
  return JSON.stringify({ title: "Background", description: "Details" });
}
''');

      final SoraInstalledAddon addon = SoraInstalledAddon(
        id: 'background-fetch',
        manifestUrl: 'https://example.com/addon.json',
        manifest: SoraAddonManifest.fromJson(<String, dynamic>{
          'sourceName': 'Background Fetch Sora',
          'iconUrl': 'https://example.com/icon.png',
          'author': <String, dynamic>{'name': 'Tester'},
          'version': '1.0.0',
          'language': 'en',
          'streamType': 'HLS',
          'quality': '1080p',
          'baseUrl': 'https://example.com',
          'searchBaseUrl': 'https://example.com/search',
          'scriptUrl': 'https://example.com/module.js',
          'type': 'anime',
          'downloadSupport': false,
        }),
        manifestPath: '${temp.path}/manifest.json',
        scriptPath: script.path,
        enabled: true,
        installedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastCheckedAt: DateTime.now(),
        lastError: null,
        order: 0,
      );
      final SoraAddonStore store = SoraAddonStore(
        supportDirectoryProvider: () async => temp,
      );
      final SoraJsRuntime runtime = SoraJsRuntime(store: store, dio: dio);
      addTearDown(runtime.invalidateAll);

      final List<SoraSearchResult> results = await runtime.searchResults(
        addon: addon,
        keyword: 'Background',
        languageCode: 'en',
        titleVariants: const <SoraTitleVariant>[
          SoraTitleVariant(languageCode: 'en', title: 'Background'),
        ],
      );

      expect(results.single.title, 'Background Result');
      await runtime.extractDetails(addon: addon, result: results.single);
      expect(completedRequests, contains(logUrl));
    },
  );

  test(
    'iOS browser flow replays Cloudflare on the effective redirected host',
    () async {
      final TargetPlatform? previousPlatform =
          debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
      });

      final Directory temp = await Directory.systemTemp.createTemp('sora_js_');
      addTearDown(() => temp.delete(recursive: true));

      final Uri originalUri = Uri.parse(
        'https://stable-origin.example.test/search?q=demo',
      );
      final Uri effectiveUri = Uri.parse(
        'https://stable-effective.example.test/search?q=demo',
      );
      final _CloudflareRedirectAdapter adapter = _CloudflareRedirectAdapter(
        originalUri: originalUri,
        effectiveUri: effectiveUri,
      );
      final Dio dio = Dio()..httpClientAdapter = adapter;
      int solverCalls = 0;
      Uri? solvedUri;
      CloudflareChallengeService.instance.registerSolver(({
        required Uri url,
        required String userAgent,
      }) async {
        solverCalls++;
        solvedUri = url;
        return (
          cookies: 'cf_clearance=ios-browser-token',
          effectiveUri: Uri(
            scheme: url.scheme,
            host: url.host,
            port: url.hasPort ? url.port : null,
            path: '/',
          ),
          userAgent: 'iOS WebView Test UA',
        );
      });
      addTearDown(() async {
        CloudflareChallengeService.instance.registerSolver(null);
        await CloudflareChallengeService.instance.cookies.clear(originalUri);
        await CloudflareChallengeService.instance.cookies.clear(effectiveUri);
      });

      final File script = File('${temp.path}/module.js');
      await script.writeAsString('''
async function searchResults(keyword) {
  const response = await fetchv2(${jsonEncode(originalUri.toString())}, {});
  return JSON.stringify(await response.json());
}
''');
      final SoraInstalledAddon addon = SoraInstalledAddon(
        id: 'ios-browser-cloudflare',
        manifestUrl: 'https://manifest.example.test/addon.json',
        manifest: SoraAddonManifest.fromJson(<String, dynamic>{
          'sourceName': 'iOS Browser Cloudflare Test',
          'iconUrl': 'https://manifest.example.test/icon.png',
          'author': <String, dynamic>{'name': 'Tester'},
          'version': '1.0.0',
          'language': 'en',
          'streamType': 'HLS',
          'quality': '1080p',
          'baseUrl': 'https://stable-origin.example.test',
          'searchBaseUrl': originalUri.toString(),
          'scriptUrl': 'https://manifest.example.test/module.js',
          'type': 'anime',
          'downloadSupport': false,
        }),
        manifestPath: '${temp.path}/manifest.json',
        scriptPath: script.path,
        enabled: true,
        installedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastCheckedAt: DateTime.now(),
        lastError: null,
        order: 0,
      );
      final SoraAddonStore store = SoraAddonStore(
        supportDirectoryProvider: () async => temp,
      );
      final SoraJsRuntime runtime = SoraJsRuntime(store: store, dio: dio);
      addTearDown(runtime.invalidateAll);

      final List<SoraSearchResult> results = await runtime.searchResults(
        addon: addon,
        keyword: 'Demo',
        languageCode: 'en',
        titleVariants: const <SoraTitleVariant>[
          SoraTitleVariant(languageCode: 'en', title: 'Demo'),
        ],
      );

      expect(results.single.title, 'Redirected Result');
      expect(solverCalls, 1);
      expect(solvedUri, effectiveUri);
      expect(adapter.originalRequests, hasLength(1));
      expect(adapter.effectiveRequests, hasLength(1));
      expect(
        adapter.effectiveRequests.last.headers['Cookie'],
        contains('cf_clearance=ios-browser-token'),
      );
      expect(
        adapter.effectiveRequests.last.headers['User-Agent'],
        'iOS WebView Test UA',
      );
    },
  );

  test(
    'Windows replays Cloudflare clearance on the effective redirected host',
    () async {
      final TargetPlatform? previousPlatform =
          debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
      });

      final Directory temp = await Directory.systemTemp.createTemp('sora_js_');
      addTearDown(() => temp.delete(recursive: true));

      final Uri originalUri = Uri.parse(
        'https://origin.example.test/search?q=demo',
      );
      final Uri effectiveUri = Uri.parse(
        'https://effective.example.test/search?q=demo',
      );
      final _CloudflareRedirectAdapter adapter = _CloudflareRedirectAdapter(
        originalUri: originalUri,
        effectiveUri: effectiveUri,
      );
      final Dio dio = Dio()..httpClientAdapter = adapter;
      int solverCalls = 0;
      Uri? solvedUri;
      CloudflareChallengeService.instance.registerSolver(({
        required Uri url,
        required String userAgent,
      }) async {
        solverCalls++;
        solvedUri = url;
        return (
          cookies: 'cf_clearance=windows-test-token',
          effectiveUri: Uri(
            scheme: url.scheme,
            host: url.host,
            port: url.hasPort ? url.port : null,
            path: '/',
          ),
          userAgent: 'Windows WebView Test UA',
        );
      });
      addTearDown(() async {
        CloudflareChallengeService.instance.registerSolver(null);
        await CloudflareChallengeService.instance.cookies.clear(effectiveUri);
      });

      final File script = File('${temp.path}/module.js');
      await script.writeAsString('''
async function searchResults(keyword) {
  const response = await fetchv2(${jsonEncode(originalUri.toString())}, {});
  return JSON.stringify(await response.json());
}
''');
      final SoraInstalledAddon addon = SoraInstalledAddon(
        id: 'windows-cloudflare-redirect',
        manifestUrl: 'https://manifest.example.test/addon.json',
        manifest: SoraAddonManifest.fromJson(<String, dynamic>{
          'sourceName': 'Redirect Test',
          'iconUrl': 'https://manifest.example.test/icon.png',
          'author': <String, dynamic>{'name': 'Tester'},
          'version': '1.0.0',
          'language': 'en',
          'streamType': 'HLS',
          'quality': '1080p',
          'baseUrl': 'https://origin.example.test',
          'searchBaseUrl': originalUri.toString(),
          'scriptUrl': 'https://manifest.example.test/module.js',
          'type': 'anime',
          'downloadSupport': false,
        }),
        manifestPath: '${temp.path}/manifest.json',
        scriptPath: script.path,
        enabled: true,
        installedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastCheckedAt: DateTime.now(),
        lastError: null,
        order: 0,
      );
      final SoraAddonStore store = SoraAddonStore(
        supportDirectoryProvider: () async => temp,
      );
      final SoraJsRuntime runtime = SoraJsRuntime(store: store, dio: dio);
      addTearDown(runtime.invalidateAll);

      final List<SoraSearchResult> first = await runtime.searchResults(
        addon: addon,
        keyword: 'Demo',
        languageCode: 'en',
        titleVariants: const <SoraTitleVariant>[
          SoraTitleVariant(languageCode: 'en', title: 'Demo'),
        ],
      );
      final List<SoraSearchResult> second = await runtime.searchResults(
        addon: addon,
        keyword: 'Demo',
        languageCode: 'en',
        titleVariants: const <SoraTitleVariant>[
          SoraTitleVariant(languageCode: 'en', title: 'Demo'),
        ],
      );

      expect(first.single.title, 'Redirected Result');
      expect(second.single.title, 'Redirected Result');
      expect(solverCalls, 1);
      expect(solvedUri, effectiveUri);
      expect(adapter.effectiveRequests, hasLength(2));
      for (final RequestOptions request in adapter.effectiveRequests) {
        expect(request.headers['Cookie'], contains('cf_clearance='));
        expect(request.headers['User-Agent'], 'Windows WebView Test UA');
      }
    },
    skip: !Platform.isWindows,
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses, {this.delay = Duration.zero, this.onComplete});

  final Map<String, String> responses;
  final Duration delay;
  final void Function(String url)? onComplete;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String url = options.uri.toString();
    final String? body = responses[url];
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    onComplete?.call(url);
    return ResponseBody.fromString(
      body ?? 'missing',
      body == null ? 404 : 200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CloudflareRedirectAdapter implements HttpClientAdapter {
  _CloudflareRedirectAdapter({
    required this.originalUri,
    required this.effectiveUri,
  });

  final Uri originalUri;
  final Uri effectiveUri;
  final List<RequestOptions> originalRequests = <RequestOptions>[];
  final List<RequestOptions> effectiveRequests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri == originalUri) {
      originalRequests.add(options);
      final String cookie = '${options.headers['Cookie'] ?? ''}';
      if (cookie.contains('cf_clearance=')) {
        return ResponseBody.fromString(
          jsonEncode(<Map<String, String>>[
            <String, String>{
              'title': 'Redirected Result',
              'image': 'poster.jpg',
              'href': '/title',
            },
          ]),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      }
    }
    if (options.uri == effectiveUri) {
      effectiveRequests.add(options);
      final String cookie = '${options.headers['Cookie'] ?? ''}';
      if (cookie.contains('cf_clearance=')) {
        return ResponseBody.fromString(
          jsonEncode(<Map<String, String>>[
            <String, String>{
              'title': 'Redirected Result',
              'image': 'poster.jpg',
              'href': '/title',
            },
          ]),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      }
    }

    final ResponseBody challenged = ResponseBody.fromString(
      '<script src="/cdn-cgi/challenge-platform/test.js"></script>',
      403,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html'],
        'server': <String>['cloudflare'],
      },
    );
    if (options.uri == originalUri) {
      challenged.redirects = <RedirectRecord>[
        RedirectRecord(301, 'GET', effectiveUri),
      ];
    }
    return challenged;
  }

  @override
  void close({bool force = false}) {}
}
