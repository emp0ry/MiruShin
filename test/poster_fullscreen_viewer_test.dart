import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/media_details/presentation/poster_fullscreen_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  group('maximumQualityArtworkUrl', () {
    test('requests the original TMDB poster', () {
      expect(
        maximumQualityArtworkUrl('https://image.tmdb.org/t/p/w500/poster.jpg'),
        'https://image.tmdb.org/t/p/original/poster.jpg',
      );
    });

    test('requests the original TMDB backdrop and preserves its query', () {
      expect(
        maximumQualityArtworkUrl(
          'https://image.tmdb.org/t/p/w1280/backdrop.jpg?language=en',
        ),
        'https://image.tmdb.org/t/p/original/backdrop.jpg?language=en',
      );
    });

    test('keeps an original TMDB URL unchanged', () {
      const String url =
          'https://image.tmdb.org/t/p/original/already-original.jpg';
      expect(maximumQualityArtworkUrl(url), url);
    });

    test('requests the largest AniList cover', () {
      expect(
        maximumQualityArtworkUrl(
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/'
          'medium/example.jpg',
        ),
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/'
        'large/example.jpg',
      );
    });

    test('keeps the largest AniList cover unchanged', () {
      const String url =
          'https://s4.anilist.co/file/anilistcdn/media/anime/cover/'
          'large/example.jpg';
      expect(maximumQualityArtworkUrl(url), url);
    });

    test('keeps the direct AniList banner URL unchanged', () {
      const String url =
          'https://s4.anilist.co/file/anilistcdn/media/anime/banner/example.jpg';
      expect(maximumQualityArtworkUrl(url), url);
    });
  });

  testWidgets('poster viewer fills the window and can be closed', (
    WidgetTester tester,
  ) async {
    await _openViewer(tester);

    expect(find.byKey(posterFullscreenViewerKey), findsOneWidget);
    expect(
      tester.getSize(find.byKey(posterFullscreenViewerKey)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byKey(posterInteractiveViewerKey),
    );
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 6);
    expect(viewer.trackpadScrollCausesScale, isTrue);
    expect(find.byIcon(Icons.center_focus_strong_rounded), findsNothing);
    expect(find.textContaining('zoom ·'), findsNothing);

    await tester.tap(find.byKey(posterViewerCloseKey));
    await tester.pumpAndSettle();
    expect(find.byKey(posterFullscreenViewerKey), findsNothing);
  });

  testWidgets('download action is anchored at the bottom right', (
    WidgetTester tester,
  ) async {
    int downloads = 0;
    await _openViewer(
      tester,
      onDownload: (BuildContext context) async {
        downloads += 1;
      },
    );

    final Finder download = find.byKey(posterViewerDownloadKey);
    expect(download, findsOneWidget);
    final Rect viewerRect = tester.getRect(
      find.byKey(posterFullscreenViewerKey),
    );
    final Rect downloadRect = tester.getRect(download);
    expect(downloadRect.center.dx, greaterThan(viewerRect.center.dx));
    expect(downloadRect.center.dy, greaterThan(viewerRect.center.dy));

    await tester.tap(download);
    await tester.pump();
    expect(downloads, 1);
    expect(find.byKey(posterFullscreenViewerKey), findsOneWidget);
  });

  testWidgets('single tap closes the poster viewer', (
    WidgetTester tester,
  ) async {
    await _openViewer(tester);

    await tester.tap(find.byKey(posterInteractiveViewerKey));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(posterFullscreenViewerKey), findsNothing);
  });

  testWidgets('double tap resets zoom without closing the viewer', (
    WidgetTester tester,
  ) async {
    await _openViewer(tester);
    final Finder viewerFinder = find.byKey(posterInteractiveViewerKey);
    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      viewerFinder,
    );
    final TransformationController controller =
        viewer.transformationController!;
    final Offset center = tester.getCenter(viewerFinder);
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -80)));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

    await tester.tap(viewerFinder);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(viewerFinder);
    await tester.pumpAndSettle();

    expect(controller.value.storage, orderedEquals(Matrix4.identity().storage));
    expect(find.byKey(posterFullscreenViewerKey), findsOneWidget);
  });

  testWidgets('mouse wheel zooms the poster in and out', (
    WidgetTester tester,
  ) async {
    await _openViewer(tester);
    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byKey(posterInteractiveViewerKey),
    );
    final TransformationController controller =
        viewer.transformationController!;
    final Offset center = tester.getCenter(
      find.byKey(posterInteractiveViewerKey),
    );
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -80)));
    await tester.pump();

    final double zoomedInScale = controller.value.getMaxScaleOnAxis();
    expect(zoomedInScale, greaterThan(1));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), lessThan(zoomedInScale));
  });

  testWidgets('touch pinch zooms the poster', (WidgetTester tester) async {
    await _openViewer(tester);
    final InteractiveViewer viewer = tester.widget<InteractiveViewer>(
      find.byKey(posterInteractiveViewerKey),
    );
    final TransformationController controller =
        viewer.transformationController!;
    final Offset center = tester.getCenter(
      find.byKey(posterInteractiveViewerKey),
    );
    final TestGesture first = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    final TestGesture second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await first.moveTo(center - const Offset(80, 0));
    await second.moveTo(center + const Offset(80, 0));
    await tester.pump();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));

    await first.up();
    await second.up();
    await tester.pump(kDoubleTapMinTime + const Duration(milliseconds: 1));
  });

  test('poster viewer labels are translated in every supported locale', () {
    const List<String> keys = <String>[
      'View poster fullscreen',
      'Poster unavailable',
      'View background image fullscreen',
      'Background image unavailable',
      'Image download cancelled',
      'Image download failed: {error}',
      'Image saved to {path}',
      'Image shared',
    ];
    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in keys) {
        expect(
          values[key],
          isA<String>().having((String value) => value.trim(), key, isNotEmpty),
        );
        if (locale != 'en') expect(values[key], isNot(key));
      }
    }
  });
}

Future<void> _openViewer(
  WidgetTester tester, {
  PosterDownloadCallback? onDownload,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showPosterFullscreenViewer(
                context,
                title: 'Test poster',
                poster: const ColoredBox(color: Colors.deepPurple),
                onDownload: onDownload,
              ),
              child: const Text('Open poster'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open poster'));
  await tester.pumpAndSettle();
}
