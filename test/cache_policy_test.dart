import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/core/utils/settings_preferences.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cache retention defaults to one month and persists user choice',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences raw = await SharedPreferences.getInstance();
      final SettingsPreferences preferences = SettingsPreferences(raw);

      expect(
        CacheRetention.fromName(preferences.readCacheRetention()),
        CacheRetention.oneMonth,
      );

      await preferences.saveCacheRetention(CacheRetention.threeMonths.name);

      expect(
        CacheRetention.fromName(preferences.readCacheRetention()),
        CacheRetention.threeMonths,
      );
      expect(CacheRetention.never.duration, isNull);
    },
  );

  test(
    'legacy disabled preference no longer disables metadata cache',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.metadataCacheEnabled': false,
      });
      const MetadataCacheStore store = MetadataCacheStore();

      await store.write('tmdb.details.always-on', <String, dynamic>{
        'title': 'cached',
      });

      expect(await store.read('tmdb.details.always-on'), <String, dynamic>{
        'title': 'cached',
      });
    },
  );

  test(
    'expired metadata is removed while a valid snapshot is touched',
    () async {
      final DateTime writtenAt = DateTime.utc(2026, 1, 1);
      final DateTime sixDaysLater = writtenAt.add(const Duration(days: 6));
      SharedPreferences.setMockInitialValues(<String, Object>{
        'metadata.cache.tmdb.details.valid': jsonEncode(<String, dynamic>{
          'title': 'cached',
        }),
        'metadata.cacheTouched.tmdb.details.valid':
            writtenAt.millisecondsSinceEpoch,
        'metadata.cache.tmdb.details.expired': jsonEncode(<String, dynamic>{
          'title': 'stale',
        }),
        'metadata.cacheTouched.tmdb.details.expired':
            writtenAt.millisecondsSinceEpoch,
        'metadata.cache.tmdb.details.unused': jsonEncode(<String, dynamic>{
          'title': 'unused',
        }),
        'metadata.cacheTouched.tmdb.details.unused':
            writtenAt.millisecondsSinceEpoch,
      });

      final MetadataCacheStore validStore = MetadataCacheStore(
        maxAge: const Duration(days: 7),
        nowForTesting: sixDaysLater,
      );
      expect(await validStore.read('tmdb.details.valid'), <String, dynamic>{
        'title': 'cached',
      });

      final SharedPreferences raw = await SharedPreferences.getInstance();
      expect(
        raw.getInt('metadata.cacheTouched.tmdb.details.valid'),
        sixDaysLater.millisecondsSinceEpoch,
      );

      final MetadataCacheStore expiredStore = MetadataCacheStore(
        maxAge: const Duration(days: 7),
        nowForTesting: writtenAt.add(const Duration(days: 8)),
      );
      expect(await expiredStore.read('tmdb.details.expired'), isNull);
      expect(raw.containsKey('metadata.cache.tmdb.details.expired'), isFalse);
      expect(
        raw.containsKey('metadata.cacheTouched.tmdb.details.expired'),
        isFalse,
      );

      await expiredStore.pruneExpired();
      expect(raw.containsKey('metadata.cache.tmdb.details.unused'), isFalse);
      expect(
        raw.containsKey('metadata.cacheTouched.tmdb.details.unused'),
        isFalse,
      );
    },
  );

  test('cache policy controls are translated in every supported locale', () {
    const List<String> keys = <String>[
      'Applies to memory, artwork, and metadata cache.',
      'Cache retention',
      'Cached details and artwork unused for longer than this are removed.',
      '1 Week',
      '1 Month',
      '3 Months',
      'Never expire',
    ];
    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in keys) {
        expect(
          values[key],
          isA<String>().having(
            (String value) => value.trim(),
            '$locale translation for "$key"',
            isNotEmpty,
          ),
        );
      }
    }
  });
}
