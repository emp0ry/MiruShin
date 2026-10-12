import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/tracking_state_decoder.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';

void main() {
  test('only changed JSON rows are decoded again; output is ordered', () async {
    final decoder = TrackingStateDecoder();
    final rows = [_row('a', 1), _row('b', 2)];
    final first = await decoder.decode(rows);
    final second = await decoder.decode(rows.reversed.toList());
    expect(second.first, same(first.first));
    expect(second.last, same(first.last));
    final changed = await decoder.decode([_row('a', 3), _row('b', 2)]);
    expect(changed.first.progress, 3);
    expect(changed.first, isNot(same(first.last)));
    expect(changed.last, same(first.first));
  });

  test('cached nested state cannot be modified by a caller', () async {
    final state = (await TrackingStateDecoder().decode([_row('a', 1)])).single;
    expect(
      () => state.mediaItem.externalIds['mal'] = 'wrong',
      throwsUnsupportedError,
    );
    expect(() => state.mediaItem.aliases.add('wrong'), throwsUnsupportedError);
    expect(() => state.providerStates.clear(), throwsUnsupportedError);
    final data = state.providerStates[TrackerSource.anilist]!.data;
    expect(() => data['private'] = false, throwsUnsupportedError);
    expect(() => (data['customLists'] as List).clear(), throwsUnsupportedError);
    expect(
      () => (data['advancedScores'] as Map)['Story'] = 0,
      throwsUnsupportedError,
    );
  });

  test('LRU entry and JSON budgets are bounded', () async {
    final decoder = TrackingStateDecoder(maximumEntries: 2);
    final a = (await decoder.decode([_row('a', 1)])).single;
    final b = (await decoder.decode([_row('b', 2)])).single;
    expect((await decoder.decode([_row('a', 1)])).single, same(a));
    await decoder.decode([_row('c', 3)]);
    expect((await decoder.decode([_row('a', 1)])).single, same(a));
    expect((await decoder.decode([_row('b', 2)])).single, isNot(same(b)));
    final tiny = TrackingStateDecoder(maximumJsonBytes: 1);
    final uncached = (await tiny.decode([_row('a', 1)])).single;
    expect((await tiny.decode([_row('a', 1)])).single, isNot(same(uncached)));
  });

  test(
    'cold batch preserves rich provider data; malformed rows are isolated',
    () async {
      final decoder = TrackingStateDecoder();
      final rows = [for (int i = 0; i < 20; i++) _row('$i', i)];
      final states = await decoder.decode([...rows, ('corrupt', '{not json')]);
      expect(states, hasLength(20));
      expect(states.first.progress, 19);
      expect(states.first.mediaItem.externalIds['mal'], '1');
      expect(
        states
            .first
            .providerStates[TrackerSource.anilist]!
            .data['advancedScores'],
        {'Story': 80},
      );
      final repeated = await decoder.decode(rows);
      expect(repeated.first, same(states.first));
    },
  );

  test('decoders for different workspaces never share state', () async {
    final a = TrackingStateDecoder(), b = TrackingStateDecoder();
    expect((await a.decode([_row('same', 4)])).single.progress, 4);
    expect((await b.decode([_row('same', 8)])).single.progress, 8);
    expect((await a.decode([_row('same', 4)])).single.progress, 4);
  });

  test('rich 400-title Library reuses every unchanged decoded entry', () async {
    final rows = [
      for (int i = 0; i < 400; i++)
        () {
          final json = jsonDecode(_row('$i', i).$2) as Map<String, dynamic>;
          final media = json['mediaItem'] as Map<String, dynamic>;
          media['overview'] = List.filled(150, 'Saved description.').join(' ');
          (media['externalIds']
              as Map<String, dynamic>)['anilist_tags'] = jsonEncode([
            for (int tag = 0; tag < 80; tag++)
              {'id': tag, 'name': 'Tag $tag', 'rank': 75},
          ]);
          return ('$i', jsonEncode(json));
        }(),
    ];
    final decoder = TrackingStateDecoder();
    final first = await decoder.decode(rows);
    expect(first, hasLength(400));
    final warm = Stopwatch()..start();
    for (int pass = 0; pass < 5; pass++) {
      final repeated = await decoder.decode(rows);
      for (int i = 0; i < first.length; i++) {
        expect(repeated[i], same(first[i]));
      }
    }
    warm.stop();
    final baseline = Stopwatch()..start();
    for (int pass = 0; pass < 5; pass++) {
      for (final row in rows) {
        final value = UserMediaState.fromJson(
          jsonDecode(row.$2) as Map<String, dynamic>,
        );
        expect(value.mediaItem.title, isNotEmpty);
      }
    }
    baseline.stop();
    expect(
      first.first.toJson(),
      UserMediaState.fromJson(
        jsonDecode(rows.last.$2) as Map<String, dynamic>,
      ).toJson(),
    );
    // Timing is informational; correctness never depends on machine speed.
    // The reuse loop includes all of its identity assertions as well.
    debugPrint(
      'Synthetic 400-title read, five passes: '
      'cached=${warm.elapsedMicroseconds}us, '
      'previous full decode=${baseline.elapsedMicroseconds}us',
    );
  });
}

(String, String) _row(String id, int progress) => (
  id,
  jsonEncode({
    'identity': {'localId': id, 'kind': 'anime', 'anilistId': 1, 'malId': 1},
    'mediaItem': {
      'id': id,
      'type': 'anime',
      'title': 'Title $id',
      'aliases': ['Title'],
      'externalIds': {'mal': '1'},
    },
    'progress': progress,
    'status': 'current',
    'source': 'anilist',
    'createdAt': DateTime.utc(2026).toIso8601String(),
    'updatedAt': DateTime.utc(2026, 1, 1, 0, 0, progress).toIso8601String(),
    'providerStates': {
      'anilist': {
        'provider': 'anilist',
        'data': {
          'private': true,
          'customLists': ['Favorites'],
          'advancedScores': {'Story': 80},
        },
      },
    },
  }),
);
