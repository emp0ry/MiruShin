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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GestureOverlay(
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
    expect(detector.onVerticalDragUpdate, isNotNull);
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
}
