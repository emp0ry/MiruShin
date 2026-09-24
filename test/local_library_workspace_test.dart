import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/application/local_library_provider.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/shared/models/library_item.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  test(
    'AniList workspaces isolate tracker anime while TMDB stays shared',
    () async {
      final LibraryItem tmdbAnime = _item(
        id: 'tmdb:anime:10',
        title: 'Shared TMDB Anime',
        externalIds: const <String, String>{
          'tmdb': '10',
          'tmdb_media_type': 'tv',
        },
      );
      final LibraryItem aliceAnime = _item(
        id: 'anilist:anime:100',
        title: 'Alice Anime',
        externalIds: const <String, String>{'anilist': '100'},
      );
      final LibraryItem bobAnime = _item(
        id: 'anilist:anime:200',
        title: 'Bob Anime',
        externalIds: const <String, String>{'anilist': '200'},
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'library.localItems': jsonEncode(<Map<String, dynamic>>[
          tmdbAnime.toJson(),
          aliceAnime.toJson(),
        ]),
        'library.localItems.anilist-2': jsonEncode(<Map<String, dynamic>>[
          bobAnime.toJson(),
        ]),
      });

      final CanonicalLibraryDatabase ownerDatabase = CanonicalLibraryDatabase(
        NativeDatabase.memory(),
      );
      final ProviderContainer owner = ProviderContainer(
        overrides: [
          libraryWorkspaceScopeProvider.overrideWithValue(
            const LibraryWorkspaceScope(
              workspaceId: 'anilist:1',
              databaseName: 'owner',
              replicaNamespace: 'anilist-1',
              importsLegacyData: true,
            ),
          ),
          canonicalLibraryRepositoryProvider.overrideWithValue(
            CanonicalLibraryRepository(
              ownerDatabase,
              workspaceId: 'anilist:1',
              replicaNamespace: 'anilist-1',
              importsLegacyData: true,
            ),
          ),
        ],
      );
      addTearDown(() async {
        owner.dispose();
        await ownerDatabase.close();
      });
      owner.read(localLibraryProvider);
      await _waitForLibrary(owner, 2);
      expect(
        owner
            .read(localLibraryProvider)
            .map((LibraryItem item) => item.mediaItem.id),
        containsAll(<String>['tmdb:anime:10', 'anilist:anime:100']),
      );

      final CanonicalLibraryDatabase bobDatabase = CanonicalLibraryDatabase(
        NativeDatabase.memory(),
      );
      final ProviderContainer bob = ProviderContainer(
        overrides: [
          libraryWorkspaceScopeProvider.overrideWithValue(
            const LibraryWorkspaceScope(
              workspaceId: 'anilist:2',
              databaseName: 'bob',
              replicaNamespace: 'anilist-2',
              importsLegacyData: false,
            ),
          ),
          canonicalLibraryRepositoryProvider.overrideWithValue(
            CanonicalLibraryRepository(
              bobDatabase,
              workspaceId: 'anilist:2',
              replicaNamespace: 'anilist-2',
              importsLegacyData: false,
            ),
          ),
        ],
      );
      addTearDown(() async {
        bob.dispose();
        await bobDatabase.close();
      });
      bob.read(localLibraryProvider);
      await _waitForLibrary(bob, 2);
      final List<String> bobIds = bob
          .read(localLibraryProvider)
          .map((LibraryItem item) => item.mediaItem.id)
          .toList(growable: false);
      expect(
        bobIds,
        containsAll(<String>['tmdb:anime:10', 'anilist:anime:200']),
      );
      expect(bobIds, isNot(contains('anilist:anime:100')));
    },
  );
}

Future<void> _waitForLibrary(ProviderContainer container, int count) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    if (container.read(localLibraryProvider).length == count) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Local library did not finish loading.');
}

LibraryItem _item({
  required String id,
  required String title,
  required Map<String, String> externalIds,
}) {
  final DateTime now = DateTime.utc(2026, 9, 24);
  return LibraryItem(
    id: 'local:$id',
    mediaItem: MediaItem(
      id: id,
      title: title,
      originalTitle: title,
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: id.startsWith('tmdb:') ? 'TMDB' : 'AniList',
      externalIds: externalIds,
      statusLabel: '',
    ),
    status: LibraryStatus.watching,
    progress: 0.5,
    addedAt: now,
    updatedAt: now,
    trackingSyncState: 'synced',
  );
}
