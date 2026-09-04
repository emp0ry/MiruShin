import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/media_details/domain/watch_order.dart';
import 'package:mirushin/features/media_details/domain/watch_order_resolver.dart';

import 'support/watch_order_fixtures.dart';

void main() {
  const resolver = WatchOrderResolver();
  List<int> ids(WatchOrder order) =>
      order.entries.map((entry) => entry.media.id).toList();

  test('prequel/sequel constraints override contradictory release dates', () {
    final order = resolver.resolve([
      watchMedia(3, year: 2000, relations: [relation(2, 'PREQUEL')]),
      watchMedia(1, year: 2030, relations: [relation(2, 'SEQUEL')]),
      watchMedia(2, year: 2020),
    ]);
    expect(ids(order), [1, 2, 3]);
  });

  test('ambiguous entries use full dates, then format and stable IDs', () {
    final order = resolver.resolve([
      watchMedia(6, year: null),
      watchMedia(5, year: 2020),
      watchMedia(4, year: 2020, month: 3),
      watchMedia(3, year: 2020, month: 3, day: 10, format: 'ONA'),
      watchMedia(2, year: 2020, month: 3, day: 10),
      watchMedia(1, year: 2020, month: 3, day: 9),
    ]);
    expect(ids(order), [1, 2, 3, 4, 5, 6]);
  });

  test(
    'invalid fuzzy dates stay unknown rather than rolling into next month',
    () {
      expect(
        WatchOrderDate.fromJson({'year': 2023, 'month': 2, 'day': 29}).day,
        isNull,
      );
      expect(
        WatchOrderDate.fromJson({'year': 2024, 'month': 2, 'day': 29}).day,
        29,
      );
      final invalid = WatchOrderDate.fromJson({
        'year': null,
        'month': 12,
        'day': 12,
      });
      expect(invalid.year, isNull);
      expect(invalid.month, isNull);
      expect(
        WatchOrderDate.fromJson({'year': 2020, 'month': 14}).month,
        isNull,
      );
    },
  );

  test('side story and parent linked extras stay near their main entry', () {
    final order = resolver.resolve([
      watchMedia(
        1,
        year: 2000,
        relations: [relation(2, 'SEQUEL'), relation(3, 'SIDE_STORY')],
      ),
      watchMedia(2, year: 2010),
      watchMedia(3, year: 2020, format: 'OVA'),
      watchMedia(
        4,
        year: 2021,
        format: 'SPECIAL',
        relations: [relation(1, 'PARENT')],
      ),
    ]);
    expect(ids(order), [1, 3, 4, 2]);
    expect(
      order.entries
          .where((entry) => !entry.isMainline)
          .map((entry) => entry.parentId),
      [1, 1],
    );
  });

  test('nested extra attachments are ordered after their direct parent', () {
    final order = resolver.resolve([
      watchMedia(1, year: 2000),
      watchMedia(2, year: 2010),
      watchMedia(
        3,
        year: 2020,
        format: 'OVA',
        relations: [relation(1, 'PARENT')],
      ),
      watchMedia(
        4,
        year: 1990,
        format: 'SPECIAL',
        relations: [relation(3, 'PARENT')],
      ),
    ]);
    expect(ids(order), [1, 3, 4, 2]);
  });

  test('unanchored extras go between nearby main releases', () {
    final order = resolver.resolve([
      watchMedia(1, year: 2000),
      watchMedia(2, year: 2010),
      watchMedia(3, year: 2005, format: 'MOVIE'),
      watchMedia(4, year: 1990, format: 'SPECIAL'),
      watchMedia(5, year: null, format: 'OVA'),
    ]);
    expect(ids(order), [4, 1, 3, 2, 5]);
    expect(
      order.entries
          .where((entry) => entry.isMainline)
          .map((entry) => entry.media.id),
      [1, 2],
    );
  });

  test('sequel movies and OVAs join mainline; summary/music remain extras', () {
    final order = resolver.resolve([
      watchMedia(
        1,
        relations: [
          relation(2, 'SEQUEL'),
          relation(4, 'SUMMARY'),
          relation(5, 'SIDE_STORY'),
        ],
      ),
      watchMedia(2, format: 'MOVIE', relations: [relation(3, 'SEQUEL')]),
      watchMedia(3, format: 'OVA'),
      watchMedia(4, format: 'MOVIE'),
      watchMedia(5, format: 'MUSIC'),
    ]);
    expect(
      order.entries
          .where((entry) => entry.isMainline)
          .map((entry) => entry.media.id),
      [1, 2, 3],
    );
  });

  test('movie-only franchise has an automatic mainline', () {
    final order = resolver.resolve([
      watchMedia(1, format: 'MOVIE', relations: [relation(2, 'SEQUEL')]),
      watchMedia(2, format: 'MOVIE'),
    ]);
    expect(order.entries.every((entry) => entry.isMainline), isTrue);
  });

  test('TV side story does not become mainline just because of its format', () {
    final order = resolver.resolve([
      watchMedia(1, relations: [relation(2, 'SIDE_STORY')]),
      watchMedia(2),
    ]);
    expect(order.entries.last.isMainline, isFalse);
  });

  test(
    'cycles are deterministic and retain constraints entering and leaving SCC',
    () {
      final input = [
        watchMedia(1, year: 2000, relations: [relation(2, 'SEQUEL')]),
        watchMedia(
          2,
          year: 2001,
          relations: [relation(1, 'SEQUEL'), relation(4, 'SEQUEL')],
        ),
        watchMedia(3, year: 2030, relations: [relation(2, 'SEQUEL')]),
        watchMedia(4, year: 1990),
      ];
      for (var seed = 0; seed < 10; seed++) {
        final order = resolver.resolve([...input]..shuffle(Random(seed)));
        expect(ids(order), [3, 1, 2, 4]);
        expect(order.hasCycles, isTrue);
      }
    },
  );

  test(
    'invalid, repeated, self and non-ordering relations do not expand graph',
    () {
      final first = watchMedia(
        1,
        relations: [
          relation(1, 'SEQUEL'),
          relation(999, 'SEQUEL'),
          relation(2, 'CHARACTER'),
          relation(2, 'ADAPTATION'),
          relation(2, 'OTHER'),
          relation(2, 'ALTERNATIVE'),
        ],
      );
      final order = resolver.resolve([first, first, watchMedia(2, year: 1990)]);
      expect(ids(order), [2, 1]);
      expect(order.hasCycles, isFalse);
    },
  );

  test('parent placement cannot overturn a strong sequence', () {
    final order = resolver.resolve([
      watchMedia(1, relations: [relation(2, 'SIDE_STORY')]),
      watchMedia(2, format: 'MUSIC', relations: [relation(1, 'SEQUEL')]),
    ]);
    expect(ids(order), [2, 1]);
    expect(order.entries.first.parentId, isNull);
  });

  test('cyclic parent links terminate without dropping extras', () {
    final order = resolver.resolve([
      watchMedia(1),
      watchMedia(2, format: 'OVA', relations: [relation(3, 'PARENT')]),
      watchMedia(3, format: 'SPECIAL', relations: [relation(2, 'PARENT')]),
    ]);
    expect(ids(order).toSet(), {1, 2, 3});
    expect(order.entries, hasLength(3));
  });

  test('dense cyclic parent data visits each candidate once per search', () {
    final input = [
      watchMedia(1),
      for (var id = 2; id <= 35; id++)
        watchMedia(
          id,
          format: 'SPECIAL',
          relations: [
            for (var target = 2; target <= 35; target++)
              if (target != id) relation(target, 'PARENT'),
          ],
        ),
    ];
    expect(resolver.resolve(input).entries, hasLength(35));
  });

  test('all-extra and empty franchises remain valid', () {
    expect(
      ids(
        resolver.resolve([
          watchMedia(2, format: 'SPECIAL'),
          watchMedia(1, format: 'MUSIC'),
        ]),
      ),
      [2, 1],
    );
    expect(resolver.resolve([]).entries, isEmpty);
  });

  test('many DAGs preserve every strong edge and every member', () {
    for (var seed = 0; seed < 25; seed++) {
      final random = Random(seed);
      final input = List.generate(
        24,
        (id) => watchMedia(
          id + 1,
          year: 1990 + random.nextInt(40),
          format: id.isEven ? 'TV' : 'OVA',
          relations: [
            for (var target = id + 2; target <= 24; target++)
              if (random.nextInt(12) == 0) relation(target, 'SEQUEL'),
          ],
        ),
      );
      final order = ids(resolver.resolve([...input]..shuffle(random)));
      expect(order.toSet(), input.map((node) => node.id).toSet());
      for (final node in input) {
        for (final edge in node.relations) {
          expect(
            order.indexOf(node.id),
            lessThan(order.indexOf(edge.targetId)),
          );
        }
      }
    }
  });
}
