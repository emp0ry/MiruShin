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

  testWidgets('poster card renders a top-left status badge', (
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
