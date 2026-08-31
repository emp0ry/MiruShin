import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/security/app_secure_storage.dart';
import 'package:mirushin/features/settings/application/mirushin_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test(
    'secure backup covers MiruShin secrets without unrelated values',
    () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        AppSecureStorage.anilistAccessTokenKey: 'anilist-token',
        AppSecureStorage.malRefreshTokenKey: 'mal-refresh',
        AppSecureStorage.shikimoriCustomClientSecretKey: 'shikimori-secret',
        'another.application.secret': 'leave-me-alone',
      });
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const AppSecureStorage secure = AppSecureStorage();

      expect(await secure.exportBackupValues(), <String, String>{
        AppSecureStorage.anilistAccessTokenKey: 'anilist-token',
        AppSecureStorage.malRefreshTokenKey: 'mal-refresh',
        AppSecureStorage.shikimoriCustomClientSecretKey: 'shikimori-secret',
      });

      await secure.replaceBackupValues(<String, String>{
        AppSecureStorage.malAccessTokenKey: 'restored-mal-token',
      });

      expect(await secure.readAniListAccessToken(), isNull);
      expect(await secure.readMalAccessToken(), 'restored-mal-token');
      expect(await secure.readMalRefreshToken(), isNull);
      expect(
        await const FlutterSecureStorage().read(
          key: 'another.application.secret',
        ),
        'leave-me-alone',
      );
    },
  );

  test(
    'full backup restores preferences, accounts, avatars, and addons',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.themeMode': 'oled',
        'settings.compactMode': true,
        'settings.anilistAvatarUrl': 'https://img.test/anilist.jpg',
        'settings.anilistUserSettingsCache': jsonEncode(<String, Object>{
          'titleLanguage': 'RUSSIAN',
          'staffNameLanguage': 'NATIVE',
          'activityMergeTime': 30,
          'displayAdultContent': true,
          'airingNotifications': false,
          'airingNotificationScope': 'watching',
          'scoreFormat': 'POINT_100',
          'rowOrder': 'score',
          'animeCustomLists': <String>['Favorites'],
        }),
        'settings.anilistSavedAccounts': <String>[
          jsonEncode(<String, Object>{
            'viewerId': 77,
            'viewerName': 'Saved AniList user',
            'avatarUrl': 'https://img.test/anilist-saved.jpg',
            'accessToken': 'saved-anilist-token',
            'expiresAt': '2035-02-01T00:00:00.000Z',
          }),
        ],
        'settings.malAvatarUrl': 'https://img.test/mal.jpg',
        'settings.shikimoriAvatarUrl': 'https://img.test/shikimori.jpg',
        // Desktop stores can decode persisted JSON arrays as List<Object?>.
        'library.anilist.ANIME.current.genres': <Object>['Action', 'Drama'],
        'library.local.statuses': <Object>['watching'],
        'library.local.providers.excluded': <Object>['Demo source'],
        'library.local.minRating': 7.5,
        'library.episodeProgress': '{"demo|S1E1.0":{"completed":true}}',
        'mirushin.player.settings': jsonEncode(<String, Object>{
          'playbackSpeed': 2.25,
          'seekInterval': 30,
          'preferredQuality': '1080p',
          'preferredVoiceover': 'Japanese',
          'preferredSubtitleLanguage': 'English',
          'subtitlesEnabled': false,
          'autoSkipOpening': true,
          'autoSkipEnding': true,
          'autoplayNext': false,
          'autoAnilistSync': false,
          'playerBackend': 'fvp',
          'seekPreviewsEnabled': true,
          'seekPreviewMode': 'progressive',
        }),
        'watch.streamSelection.v1.demo': jsonEncode(<String, Object>{
          'serverId': 'server-2',
          'qualityId': '1080p',
        }),
        'mirushin.watch_party.connection.v1': jsonEncode(<String, Object>{
          'mode': 'selfHostedRelay',
          'relayUrl': 'https://relay.example.com',
        }),
        'mirushin.watch_party.trusted_relays.v1': jsonEncode(<String>[
          'https://relay.example.com',
        ]),
        'example.int': 42,
        'example.double': 0.75,
        'metadata.cache.demo': '{"temporary":true}',
        'metadata.cacheTouched.demo': 123456,
        'secureStorageFallback.anilist.accessToken': 'duplicate-fallback',
      });
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final _FakeSecureStorage secure = _FakeSecureStorage(<String, String>{
        AppSecureStorage.anilistAccessTokenKey: 'anilist-token',
        AppSecureStorage.anilistExpiresAtKey: '2035-01-01T00:00:00.000Z',
        AppSecureStorage.malAccessTokenKey: 'mal-token',
        AppSecureStorage.malRefreshTokenKey: 'mal-refresh',
        AppSecureStorage.shikimoriAccessTokenKey: 'shikimori-token',
        AppSecureStorage.shikimoriRefreshTokenKey: 'shikimori-refresh',
        AppSecureStorage.shikimoriCustomClientSecretKey: 'shikimori-secret',
      });
      final Directory support = await Directory.systemTemp.createTemp(
        'mirushin_backup_test_',
      );
      addTearDown(() async {
        if (await support.exists()) await support.delete(recursive: true);
      });
      final Directory addon = Directory(
        '${support.path}${Platform.pathSeparator}sora_addons'
        '${Platform.pathSeparator}demo',
      );
      await addon.create(recursive: true);
      await File(
        '${addon.path}${Platform.pathSeparator}manifest.json',
      ).writeAsString('{"sourceName":"Demo"}');
      await File(
        '${addon.path}${Platform.pathSeparator}module.js',
      ).writeAsString('export const demo = true;');
      await File(
        '${support.path}${Platform.pathSeparator}sora_addons'
        '${Platform.pathSeparator}cloudflare_cookies.json',
      ).writeAsString('{"demo":{"cookies":"cf_clearance=test"}}');

      final MiruShinBackupService service = MiruShinBackupService(
        preferences: preferences,
        secureStorage: secure,
        supportDirectoryProvider: () async => support,
      );
      final String raw = await service.createBackupJson();
      final Map<String, dynamic> document = Map<String, dynamic>.from(
        jsonDecode(raw) as Map,
      );

      expect(document['format'], MiruShinBackupService.formatName);
      expect(document['version'], MiruShinBackupService.formatVersion);
      expect(document['containsSecrets'], isTrue);
      expect(document['includedData'], MiruShinBackupService.includedData);
      final Map<String, dynamic> exportedPreferences =
          Map<String, dynamic>.from(document['preferences'] as Map);
      expect(exportedPreferences['settings.anilistAvatarUrl'], isNotNull);
      expect(exportedPreferences['settings.malAvatarUrl'], isNotNull);
      expect(exportedPreferences['settings.shikimoriAvatarUrl'], isNotNull);
      expect(
        exportedPreferences['settings.anilistUserSettingsCache'],
        isNotNull,
      );
      expect(exportedPreferences['settings.anilistSavedAccounts'], isNotNull);
      expect(
        exportedPreferences['library.anilist.ANIME.current.genres'],
        <String, dynamic>{
          'type': 'stringList',
          'value': <String>['Action', 'Drama'],
        },
      );
      expect(exportedPreferences['library.local.statuses'], <String, dynamic>{
        'type': 'stringList',
        'value': <String>['watching'],
      });
      expect(
        exportedPreferences['library.local.providers.excluded'],
        <String, dynamic>{
          'type': 'stringList',
          'value': <String>['Demo source'],
        },
      );
      expect(exportedPreferences['library.local.minRating'], <String, dynamic>{
        'type': 'double',
        'value': 7.5,
      });
      expect(exportedPreferences['mirushin.player.settings'], isNotNull);
      expect(exportedPreferences['watch.streamSelection.v1.demo'], isNotNull);
      expect(
        exportedPreferences['mirushin.watch_party.connection.v1'],
        isNotNull,
      );
      expect(
        exportedPreferences['mirushin.watch_party.trusted_relays.v1'],
        isNotNull,
      );
      expect(
        exportedPreferences['secureStorageFallback.anilist.accessToken'],
        isNull,
      );
      expect(exportedPreferences['metadata.cache.demo'], isNull);
      expect(exportedPreferences['metadata.cacheTouched.demo'], isNull);
      final Map<String, dynamic> exportedFiles = Map<String, dynamic>.from(
        (document['files'] as Map)['soraAddons'] as Map,
      );
      expect(exportedFiles['demo/module.js'], 'export const demo = true;');
      expect(
        exportedFiles['cloudflare_cookies.json'],
        contains('cf_clearance'),
      );

      await preferences.clear();
      await preferences.setString('should.be.removed', 'old');
      secure.values = <String, String>{
        AppSecureStorage.anilistAccessTokenKey: 'different-token',
      };
      await Directory(
        '${support.path}${Platform.pathSeparator}sora_addons',
      ).delete(recursive: true);
      final Directory staleAddon = Directory(
        '${support.path}${Platform.pathSeparator}sora_addons'
        '${Platform.pathSeparator}stale',
      );
      await staleAddon.create(recursive: true);
      await File(
        '${staleAddon.path}${Platform.pathSeparator}module.js',
      ).writeAsString('stale');

      await service.importBackupJson(raw);

      expect(preferences.getString('settings.themeMode'), 'oled');
      expect(preferences.getBool('settings.compactMode'), isTrue);
      expect(preferences.getInt('example.int'), 42);
      expect(preferences.getDouble('example.double'), 0.75);
      expect(
        preferences.getStringList('library.anilist.ANIME.current.genres'),
        <String>['Action', 'Drama'],
      );
      expect(preferences.getStringList('library.local.statuses'), <String>[
        'watching',
      ]);
      expect(
        preferences.getStringList('library.local.providers.excluded'),
        <String>['Demo source'],
      );
      expect(preferences.getDouble('library.local.minRating'), 7.5);
      expect(
        preferences.getString('settings.anilistAvatarUrl'),
        'https://img.test/anilist.jpg',
      );
      expect(
        preferences.getString('settings.malAvatarUrl'),
        'https://img.test/mal.jpg',
      );
      expect(
        preferences.getString('settings.shikimoriAvatarUrl'),
        'https://img.test/shikimori.jpg',
      );
      final Map<String, dynamic> restoredAniListSettings =
          jsonDecode(
                preferences.getString('settings.anilistUserSettingsCache')!,
              )
              as Map<String, dynamic>;
      expect(restoredAniListSettings['titleLanguage'], 'RUSSIAN');
      expect(restoredAniListSettings['airingNotificationScope'], 'watching');
      expect(restoredAniListSettings['animeCustomLists'], <String>[
        'Favorites',
      ]);
      final Map<String, dynamic> restoredSavedAniListAccount =
          jsonDecode(
                preferences
                    .getStringList('settings.anilistSavedAccounts')!
                    .single,
              )
              as Map<String, dynamic>;
      expect(
        restoredSavedAniListAccount['avatarUrl'],
        'https://img.test/anilist-saved.jpg',
      );
      expect(restoredSavedAniListAccount['accessToken'], 'saved-anilist-token');
      final Map<String, dynamic> restoredPlayer =
          jsonDecode(preferences.getString('mirushin.player.settings')!)
              as Map<String, dynamic>;
      expect(restoredPlayer['playbackSpeed'], 2.25);
      expect(restoredPlayer['preferredVoiceover'], 'Japanese');
      expect(restoredPlayer['autoSkipOpening'], isTrue);
      expect(restoredPlayer['playerBackend'], 'fvp');
      expect(
        preferences.getString('watch.streamSelection.v1.demo'),
        contains('server-2'),
      );
      expect(
        preferences.getString('mirushin.watch_party.connection.v1'),
        contains('relay.example.com'),
      );
      expect(
        preferences.getString('mirushin.watch_party.trusted_relays.v1'),
        contains('relay.example.com'),
      );
      expect(preferences.containsKey('should.be.removed'), isFalse);
      expect(
        secure.values[AppSecureStorage.anilistAccessTokenKey],
        'anilist-token',
      );
      expect(secure.values[AppSecureStorage.malRefreshTokenKey], 'mal-refresh');
      expect(
        secure.values[AppSecureStorage.shikimoriCustomClientSecretKey],
        'shikimori-secret',
      );
      expect(
        await File(
          '${support.path}${Platform.pathSeparator}sora_addons'
          '${Platform.pathSeparator}demo${Platform.pathSeparator}module.js',
        ).readAsString(),
        'export const demo = true;',
      );
      expect(await staleAddon.exists(), isFalse);
    },
  );

  test('invalid backup is rejected before current state changes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.themeMode': 'dark',
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final _FakeSecureStorage secure = _FakeSecureStorage(<String, String>{
      AppSecureStorage.anilistAccessTokenKey: 'current-token',
    });
    final MiruShinBackupService service = MiruShinBackupService(
      preferences: preferences,
      secureStorage: secure,
    );

    await expectLater(
      service.importBackupJson('{"format":"something-else","version":1}'),
      throwsA(isA<MiruShinBackupException>()),
    );

    expect(preferences.getString('settings.themeMode'), 'dark');
    expect(
      secure.values[AppSecureStorage.anilistAccessTokenKey],
      'current-token',
    );
  });

  test('unsafe addon paths are rejected before import', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.themeMode': 'dark',
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final _FakeSecureStorage secure = _FakeSecureStorage(<String, String>{});
    final MiruShinBackupService service = MiruShinBackupService(
      preferences: preferences,
      secureStorage: secure,
    );
    final Map<String, dynamic> document = Map<String, dynamic>.from(
      jsonDecode(await service.createBackupJson()) as Map,
    );
    document['files'] = <String, dynamic>{
      'soraAddons': <String, String>{'../outside.txt': 'blocked'},
    };

    await expectLater(
      service.importBackupJson(jsonEncode(document)),
      throwsA(isA<MiruShinBackupException>()),
    );

    expect(preferences.getString('settings.themeMode'), 'dark');
  });

  test('failed secure restore rolls preferences back', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.themeMode': 'light',
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final _FakeSecureStorage secure = _FakeSecureStorage(<String, String>{
      AppSecureStorage.anilistAccessTokenKey: 'old-token',
    });
    final MiruShinBackupService service = MiruShinBackupService(
      preferences: preferences,
      secureStorage: secure,
    );
    final String backup = await service.createBackupJson();

    await preferences.setString('settings.themeMode', 'oled');
    secure.values = <String, String>{
      AppSecureStorage.anilistAccessTokenKey: 'current-token',
    };
    secure.failNextReplace = true;

    await expectLater(
      service.importBackupJson(backup),
      throwsA(isA<MiruShinBackupException>()),
    );

    expect(preferences.getString('settings.themeMode'), 'oled');
    expect(
      secure.values[AppSecureStorage.anilistAccessTokenKey],
      'current-token',
    );
  });

  test('backup controls are translated in every supported locale', () {
    const List<String> keys = <String>[
      'Data & backup',
      'Full MiruShin backup',
      'Includes every app setting and saved page state, player settings and stream choices, Watch with Friends relay and trust settings, AniList settings, AniList/MAL/Shikimori sessions and avatars, local library progress, addons, and source cookies. Downloaded videos and temporary caches are not included.',
      'Export config',
      'Import config',
      'Export full backup?',
      'Import full backup?',
      'Backup export cancelled',
      'Backup exported',
      'Backup import cancelled',
      'Backup restored. Restart MiruShin to apply every restored page state.',
      'Backup export failed: {error}',
      'Backup import failed: {error}',
    ];

    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in keys) {
        expect(values[key], isA<String>());
        expect((values[key] as String).trim(), isNotEmpty);
        if (locale != 'en') expect(values[key], isNot(key));
      }
    }
  });
}

class _FakeSecureStorage extends AppSecureStorage {
  _FakeSecureStorage(this.values);

  Map<String, String> values;
  bool failNextReplace = false;

  @override
  Future<Map<String, String>> exportBackupValues() async =>
      Map<String, String>.from(values);

  @override
  Future<void> replaceBackupValues(Map<String, String> replacement) async {
    if (failNextReplace) {
      failNextReplace = false;
      throw StateError('simulated secure-storage failure');
    }
    values = Map<String, String>.from(replacement);
  }
}
