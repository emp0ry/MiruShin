import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/presentation/widgets/gesture_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<GestureDetector> pumpOverlay(
    WidgetTester tester, {
    required bool horizontalSwipeSeekEnabled,
    GestureOverlayController? controller,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GestureOverlay(
              controller: controller,
              seekInterval: const Duration(seconds: 10),
              isMobile: true,
              isZoomed: false,
              horizontalSwipeSeekEnabled: horizontalSwipeSeekEnabled,
              onTap: () {},
              onActivity: () {},
              onToggleFullscreen: () {},
              onTogglePlay: () {},
              onZoomChanged: (_) {},
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(GestureOverlay),
        matching: find.byType(GestureDetector),
      ),
    );
  }

  testWidgets('removes horizontal drag recognizers when swipe seek is off', (
    WidgetTester tester,
  ) async {
    final GestureDetector detector = await pumpOverlay(
      tester,
      horizontalSwipeSeekEnabled: false,
    );

    expect(detector.onHorizontalDragStart, isNull);
    expect(detector.onHorizontalDragUpdate, isNull);
    expect(detector.onHorizontalDragEnd, isNull);
    expect(detector.onVerticalDragStart, isNull);
    expect(detector.onVerticalDragUpdate, isNull);
    expect(detector.onVerticalDragEnd, isNull);
    expect(detector.onTapUp, isNotNull);
  });

  testWidgets('keeps horizontal drag recognizers when swipe seek is on', (
    WidgetTester tester,
  ) async {
    final GestureDetector detector = await pumpOverlay(
      tester,
      horizontalSwipeSeekEnabled: true,
    );

    expect(detector.onHorizontalDragStart, isNotNull);
    expect(detector.onHorizontalDragUpdate, isNotNull);
    expect(detector.onHorizontalDragEnd, isNotNull);
  });

  testWidgets('never installs vertical volume drag recognizers', (
    WidgetTester tester,
  ) async {
    final GestureDetector detector = await pumpOverlay(
      tester,
      horizontalSwipeSeekEnabled: true,
    );

    expect(detector.onVerticalDragStart, isNull);
    expect(detector.onVerticalDragUpdate, isNull);
    expect(detector.onVerticalDragEnd, isNull);
    expect(detector.onHorizontalDragUpdate, isNotNull);
    expect(detector.onTapUp, isNotNull);
  });

  testWidgets('external arrow feedback accumulates and resets', (
    WidgetTester tester,
  ) async {
    final GestureOverlayController controller = GestureOverlayController();
    await pumpOverlay(
      tester,
      horizontalSwipeSeekEnabled: false,
      controller: controller,
    );

    controller.showSeekFeedback(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('+5s'), findsOneWidget);
    expect(tester.getCenter(find.text('+5s')).dx, greaterThan(700));

    controller.showSeekFeedback(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('+10s'), findsOneWidget);
    expect(find.text('+5s'), findsNothing);

    await tester.pump(const Duration(milliseconds: 901));
    expect(find.text('+10s'), findsNothing);

    controller.showSeekFeedback(const Duration(seconds: -5));
    await tester.pump();
    expect(find.text('-5s'), findsOneWidget);
    expect(tester.getCenter(find.text('-5s')).dx, lessThan(100));
  });
}
