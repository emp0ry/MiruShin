import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/local_first_sync_engine.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:mirushin/features/tracking/data/canonical_tracking_sync_store.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingAdapter implements TrackerProviderAdapter {
  @override
  TrackerSource get source => TrackerSource.anilist;
  @override
  String get accountId => '7';
  final reads = <String>[];
  @override
  Future<List<UserMediaState>> fetchAnimeList() async {
    reads.add('anime');
    return [];
  }

  @override
  Future<List<UserMediaState>> fetchMangaList() async {
    reads.add('manga');
    return [];
  }

  @override
  Future<void> applyMutation(SyncJournalEntry entry) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('startup reconciliation fetches each media kind once', () async {
    SharedPreferences.setMockInitialValues({});
    final db = CanonicalLibraryDatabase(NativeDatabase.memory());
    final repo = CanonicalLibraryRepository(db);
    await repo.approveProviderAccount(provider: 'anilist', accountId: '7');
    final adapter = CountingAdapter();
    final container = ProviderContainer();
    final settings = SettingsState(
      anilistViewerId: 7,
      anilistAccessToken: 'audit',
      anilistExpiresAt: DateTime.utc(2100),
    );
    final provider = Provider(
      (ref) => TrackerSyncCoordinator(
        ref,
        repository: repo,
        store: CanonicalTrackingSyncStore(
          repository: repo,
          authoritativeSource: TrackerSource.anilist,
        ),
        settings: settings,
        beforeTrackerNetwork: () async => true,
        adapterFactory: (_) async => adapter,
      ),
    );
    final sync = container.read(provider);
    try {
      await Future.wait([
        sync.refreshAllConnectedLibraries(force: true),
        sync.refreshAllConnectedLibraries(mediaKind: 'manga', force: true),
      ]);
      expect(adapter.reads, ['anime', 'manga']);
      adapter.reads.clear();
      adapter.reads.clear();
      await Future.wait([
        sync.refreshAllConnectedLibraries(),
        sync.refreshAllConnectedLibraries(mediaKind: 'manga'),
      ]);
      expect(adapter.reads, ['anime', 'manga']);
      adapter.reads.clear();
      final before = DateTime.now().toUtc();
      final options = RequestOptions(path: 'https://graphql.anilist.co');
      await sync.recordProviderFailure(
        TrackerSource.anilist,
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 429,
            headers: Headers.fromMap({
              'retry-after': ['120'],
            }),
          ),
        ),
      );
      final health = (await repo.loadHealth())[TrackerSource.anilist]!;
      expect(
        health.nextRetryAt!.isBefore(before.add(const Duration(seconds: 120))),
        isFalse,
      );
      await sync.refreshAllConnectedLibraries(force: true);
      expect(adapter.reads, isEmpty);
    } finally {
      await sync.prepareForExit();
      container.dispose();
      await db.close();
    }
  });
}
