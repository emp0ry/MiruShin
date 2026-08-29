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
  });

  test('poster viewer labels are translated in every supported locale', () {
    const List<String> keys = <String>[
      'View poster fullscreen',
      'Poster unavailable',
      'View background image fullscreen',
      'Background image unavailable',
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

Future<void> _openViewer(WidgetTester tester) async {
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
