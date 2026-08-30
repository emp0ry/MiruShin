import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link.dart';
import 'package:mirushin/app/deep_links/mirushin_deep_link_queue.dart';

void main() {
  test('queues cold links in order and dispatches warm links immediately', () {
    final List<String> dispatched = <String>[];
    final MiruShinDeepLinkQueue queue = MiruShinDeepLinkQueue(
      dispatch: (MiruShinDeepLink link) {
        dispatched.add(link.deduplicationKey);
      },
    );

    queue.accept('mirushin://anilist/anime/21');
    queue.accept('mirushin://tmdb/movie/550');
    expect(dispatched, isEmpty);

    queue.markReady();
    expect(dispatched, <String>[
      'mirushin://anilist/anime/21',
      'mirushin://tmdb/movie/550',
    ]);

    queue.accept('mirushin://tmdb/tv/1399');
    expect(dispatched.last, 'mirushin://tmdb/tv/1399');
  });

  test('ignores malformed links and suppresses immediate duplicates', () {
    DateTime now = DateTime.utc(2026, 8, 30);
    final List<MiruShinDeepLink> dispatched = <MiruShinDeepLink>[];
    final MiruShinDeepLinkQueue queue = MiruShinDeepLinkQueue(
      dispatch: dispatched.add,
      now: () => now,
    )..markReady();

    queue.accept('not a link');
    queue.accept('mirushin://anilist/anime/21');
    queue.accept('mirushin://anilist/anime/21');
    expect(dispatched, hasLength(1));

    now = now.add(const Duration(seconds: 3));
    queue.accept('mirushin://anilist/anime/21');
    expect(dispatched, hasLength(2));
  });

  test('bounds the pre-navigation queue', () {
    final List<MiruShinMediaDeepLink> dispatched = <MiruShinMediaDeepLink>[];
    final MiruShinDeepLinkQueue queue = MiruShinDeepLinkQueue(
      dispatch: (MiruShinDeepLink link) {
        dispatched.add(link as MiruShinMediaDeepLink);
      },
    );
    for (
      int id = 1;
      id <= MiruShinDeepLinkQueue.maximumPendingLinks + 1;
      id++
    ) {
      queue.accept('mirushin://tmdb/movie/$id');
    }

    queue.markReady();
    expect(dispatched, hasLength(MiruShinDeepLinkQueue.maximumPendingLinks));
    expect(dispatched.first.numericId, 2);
    expect(dispatched.last.numericId, 17);
  });
}
