import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/presentation/library_page.dart';

void main() {
  group('library next-airing label', () {
    final DateTime now = DateTime(2026, 9, 13, 19, 45);

    test('hides an expired AniList schedule retained by MAL fallback', () {
      expect(
        libraryNextAiringLabel(
          nextEpisode: 1178,
          airingAt: DateTime(2026, 9, 13, 18, 16),
          now: now,
        ),
        isNull,
      );
    });

    test('formats a genuinely imminent episode without "in soon"', () {
      expect(
        libraryNextAiringLabel(
          nextEpisode: 12,
          airingAt: now.add(const Duration(seconds: 30)),
          now: now,
        ),
        'Ep 12 airing soon',
      );
    });

    test('keeps the normal future countdown', () {
      expect(
        libraryNextAiringLabel(
          nextEpisode: 12,
          airingAt: now.add(const Duration(hours: 3)),
          now: now,
        ),
        'Ep 12 in 3h',
      );
    });
  });
}
