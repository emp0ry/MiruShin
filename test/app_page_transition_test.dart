import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/navigation/app_page_transition.dart';

void main() {
  testWidgets('shared-axis page motion combines slide and fade', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPageTransition(
            key: const ValueKey<String>('transition'),
            animation: const AlwaysStoppedAnimation<double>(0.5),
            secondaryAnimation: const AlwaysStoppedAnimation<double>(0),
            motion: AppPageMotion.sharedAxis,
            child: const Text('Page'),
          ),
        ),
      ),
    );

    final Finder transition = find.byKey(const ValueKey<String>('transition'));
    expect(
      find.descendant(of: transition, matching: find.byType(SlideTransition)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: transition, matching: find.byType(FadeTransition)),
      findsNWidgets(2),
    );
  });

  testWidgets('reduced motion renders page without transition wrappers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: AppPageTransition(
              key: const ValueKey<String>('transition'),
              animation: const AlwaysStoppedAnimation<double>(0.5),
              secondaryAnimation: const AlwaysStoppedAnimation<double>(0),
              motion: AppPageMotion.sharedAxis,
              child: const Text('Page'),
            ),
          ),
        ),
      ),
    );

    final Finder transition = find.byKey(const ValueKey<String>('transition'));
    expect(
      find.descendant(of: transition, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    expect(find.text('Page'), findsOneWidget);
  });
}
