import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/presentation/library_page.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/anime_airing.dart';
import 'package:mirushin/shared/models/media_item.dart';

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

  group('canonical Library airing presentation', () {
    final now = DateTime.utc(2026, 10, 12, 12);
    test('fresh metadata repairs old next episode in both behind and strip', () {
      final entry = _entry(
        progress: 12,
        nextEpisode: 13,
        airingAt: now.subtract(const Duration(days: 7)),
        ids: {
          anilistNextAiringEpisodeKey: '15',
          anilistNextAiringAtKey:
              '${now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000}',
        },
      );
      expect(libraryEpisodesBehind(entry, now: now), 2);
      final upcoming = libraryUpcomingEntries([entry], now: now);
      expect(upcoming.single.nextEpisode, 15);
      expect(upcoming.single.airingAt, now.add(const Duration(days: 2)));
      expect(libraryEpisodesBehind(entry, progress: 14, now: now), isNull);
    });
    test(
      'counts an elapsed episode exactly once without guessing later airings',
      () {
        final entry = _entry(
          progress: 12,
          nextEpisode: 13,
          airingAt: now.subtract(const Duration(days: 21)),
        );
        expect(libraryEpisodesBehind(entry, now: now), 1);
        expect(
          libraryEpisodesBehind(entry, now: now.add(const Duration(days: 7))),
          1,
        );
        expect(libraryUpcomingEntries([entry], now: now), isEmpty);
      },
    );
    test(
      'episodes not yet aired and fully watched titles have no behind badge',
      () {
        expect(
          libraryEpisodesBehind(
            _entry(
              progress: 0,
              nextEpisode: 1,
              airingAt: now.add(const Duration(hours: 1)),
            ),
            now: now,
          ),
          isNull,
        );
        expect(
          libraryEpisodesBehind(
            _entry(
              progress: 12,
              nextEpisode: 13,
              airingAt: now.add(const Duration(days: 1)),
            ),
            now: now,
          ),
          isNull,
        );
        expect(libraryEpisodesBehind(_entry(progress: 8), now: now), isNull);
      },
    );
    test(
      'explicit empty schedule clears obsolete fields, unlike missing metadata',
      () {
        final entry = _entry(
          progress: 0,
          nextEpisode: 2,
          airingAt: now.add(const Duration(days: 1)),
          ids: {anilistAiringKnownKey: 'true'},
        );
        expect(libraryUpcomingEntries([entry], now: now), isEmpty);
        expect(libraryEpisodesBehind(entry, now: now), isNull);
      },
    );
    test('Shikimori schedule and aired count work with no AniList data', () {
      final entry = _entry(
        progress: 4,
        ids: {
          shikimoriEpisodesAiredKey: '6',
          shikimoriNextEpisodeAtKey: now
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
      );
      expect(libraryEpisodesBehind(entry, now: now), 2);
      expect(libraryUpcomingEntries([entry], now: now).single.nextEpisode, 7);
      final countOnly = _entry(
        progress: 4,
        ids: {shikimoriEpisodesAiredKey: '6'},
      );
      expect(libraryEpisodesBehind(countOnly, now: now), 2);
      expect(libraryUpcomingEntries([countOnly], now: now), isEmpty);
    });
    test('all known future titles are sorted instead of only the legacy row', () {
      final first = _entry(
        progress: 0,
        ids: {
          anilistNextAiringEpisodeKey: '3',
          anilistNextAiringAtKey:
              '${now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}',
        },
      );
      final later = _entry(
        progress: 65,
        nextEpisode: 1181,
        airingAt: now.add(const Duration(days: 80)),
      );
      expect(
        libraryUpcomingEntries([
          later,
          first,
        ], now: now).map((e) => e.nextEpisode),
        [3, 1181],
      );
      // A genuine long-running title's absolute episode numbers must not be
      // truncated or converted into an arbitrary one-episode warning.
      expect(libraryEpisodesBehind(later, now: now), 1115);
    });
  });
}

AniListAnimeListEntry _entry({
  required int progress,
  int? nextEpisode,
  DateTime? airingAt,
  Map<String, String> ids = const {},
}) => AniListAnimeListEntry(
  id: 10,
  status: AniListListStatus.current,
  progress: progress,
  nextEpisode: nextEpisode,
  airingAt: airingAt,
  mediaItem: MediaItem(
    id: 'anilist:10',
    title: 'Airing title',
    originalTitle: '',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const [],
    sourceProvider: 'AniList',
    externalIds: {'anilist': '10', ...ids},
    statusLabel: 'RELEASING',
  ),
);
