import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/media_details/domain/fanart_gallery.dart';
import 'package:mirushin/features/media_details/presentation/fanart_gallery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets('renders one row with 4K artwork before regular artwork', (
    WidgetTester tester,
  ) async {
    await _pumpGallery(tester, _gallery());

    expect(find.byKey(fanartGallerySectionKey), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('4K Backgrounds'), findsNothing);
    expect(find.text('Backgrounds'), findsNothing);
    final CachedNetworkImage regularThumbnail = tester
        .widget<CachedNetworkImage>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('fanart-gallery-image-regular'),
            ),
            matching: find.byType(CachedNetworkImage),
          ),
        );
    expect(regularThumbnail.imageUrl, 'https://example.invalid/regular.jpg');
    expect(regularThumbnail.maxWidthDiskCache, 480);
    final Offset fourK = tester.getTopLeft(
      find.byKey(const ValueKey<String>('fanart-gallery-image-four-k')),
    );
    final Offset regular = tester.getTopLeft(
      find.byKey(const ValueKey<String>('fanart-gallery-image-regular')),
    );
    expect(fourK.dy, regular.dy);
    expect(fourK.dx, lessThan(regular.dx));
  });

  testWidgets('hides an empty Gallery and empty group headers', (
    WidgetTester tester,
  ) async {
    await _pumpGallery(tester, FanartGallery.empty);
    expect(find.byKey(fanartGallerySectionKey), findsNothing);

    await _pumpGallery(
      tester,
      FanartGallery.fromBackgrounds(<FanartBackground>[
        _background('regular', 1920, 1080),
      ]),
    );
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('4K Backgrounds'), findsNothing);
    expect(find.text('Backgrounds'), findsNothing);
  });

  testWidgets('opens the exact image and navigates originals fullscreen', (
    WidgetTester tester,
  ) async {
    await _pumpGallery(tester, _gallery());

    await tester.tap(
      find.byKey(const ValueKey<String>('fanart-gallery-image-regular')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(fanartGalleryViewerKey), findsOneWidget);
    expect(find.byKey(fanartGalleryCounterKey), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
    final Text counter = tester.widget<Text>(
      find.byKey(fanartGalleryCounterKey),
    );
    expect(counter.style?.fontSize, 11);
    expect(counter.style?.decoration, TextDecoration.none);
    expect(
      find.ancestor(
        of: find.byKey(fanartGalleryCounterKey),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('fanart-gallery-original-regular')),
      findsOneWidget,
    );
    final Image original = tester.widget<Image>(
      find.byKey(const ValueKey<String>('fanart-gallery-original-regular')),
    );
    expect(original.image, isA<NetworkImage>());

    await tester.tap(
      find.byKey(const ValueKey<String>('fanart-gallery-previous')),
    );
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fanart-gallery-original-four-k')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(fanartGalleryViewerKey), findsNothing);
  });

  test('Gallery labels are translated in every supported locale', () {
    const List<String> keys = <String>[
      'Gallery',
      '4K Backgrounds',
      'Backgrounds',
      'Previous',
      'Fanart.tv API key',
      'Enter Fanart.tv API key',
      'Stored in secure platform storage. Used for Media Details Gallery backgrounds.',
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

Future<void> _pumpGallery(WidgetTester tester, FanartGallery gallery) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: FanartGalleryContent(gallery: gallery, mediaTitle: 'Test title'),
      ),
    ),
  );
  await tester.pump();
}

FanartGallery _gallery() {
  return FanartGallery.fromBackgrounds(<FanartBackground>[
    _background('four-k', 3840, 2160),
    _background('regular', 1920, 1080),
  ]);
}

FanartBackground _background(String id, int width, int height) {
  return FanartBackground(
    id: id,
    url: 'https://example.invalid/$id.jpg',
    width: width,
    height: height,
    likes: 0,
    language: '00',
  );
}
