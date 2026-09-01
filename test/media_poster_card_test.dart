import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/widgets/media_poster_card.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('poster card clips edges with an opaque bottom gradient', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 280,
              child: MediaPosterCard(
                item: _item(),
                compact: true,
                statusBadgeLabel: 'Completed',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Completed'), findsOneWidget);

    final Finder hairlineFinder = find.byKey(
      const ValueKey<String>('media-poster-bottom-hairline'),
    );
    final Positioned hairline = tester.widget<Positioned>(hairlineFinder);
    final ColoredBox hairlineBox = tester.widget<ColoredBox>(
      find.descendant(of: hairlineFinder, matching: find.byType(ColoredBox)),
    );
    final ClipRRect posterClip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey<String>('media-poster-clip')),
    );
    final Stack posterStack = tester.widget<Stack>(
      find.byKey(const ValueKey<String>('media-poster-stack')),
    );
    final Finder gradientFinder = find.byKey(
      const ValueKey<String>('media-poster-gradient'),
    );
    final DecoratedBox gradientBox = tester.widget<DecoratedBox>(
      gradientFinder,
    );
    final Positioned gradientPosition = tester.widget<Positioned>(
      find.ancestor(of: gradientFinder, matching: find.byType(Positioned)),
    );
    final LinearGradient gradient =
        (gradientBox.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(posterClip.clipBehavior, Clip.hardEdge);
    expect(posterStack.clipBehavior, Clip.hardEdge);
    expect(gradientPosition.left, 0);
    expect(gradientPosition.top, 0);
    expect(gradientPosition.right, -1);
    expect(gradientPosition.bottom, 0);
    expect(gradient.colors.last, Colors.black);
    expect(
      find.byKey(const ValueKey<String>('media-poster-left-hairline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('media-poster-right-hairline')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('media-poster-bottom-corner-hairline')),
      findsNothing,
    );
    expect(hairline.left, 0);
    expect(hairline.right, 0);
    expect(hairline.bottom, 0);
    expect(hairline.height, 1);
    expect(hairlineBox.color, const Color(0x8C000000));
  });
}

MediaItem _item() {
  return const MediaItem(
    id: 'anilist:1',
    title: 'Test Anime',
    originalTitle: 'Test Anime',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: <String>[],
    sourceProvider: 'AniList',
    externalIds: <String, String>{'anilist': '1'},
    statusLabel: 'FINISHED',
  );
}
