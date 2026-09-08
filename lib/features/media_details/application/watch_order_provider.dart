import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../metadata/application/metadata_cache_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../settings/application/settings_state.dart';
import '../../tracking/application/tracker_sync_coordinator.dart';
import '../../tracking/data/mal_api_client.dart';
import '../../tracking/domain/tracker_models.dart';
import '../data/watch_order_repository.dart';
import '../domain/watch_order.dart';

final watchOrderRepositoryProvider = Provider<WatchOrderRepository>((ref) {
  final SettingsState settings = ref.watch(settingsProvider);
  final String malToken = settings.malAccessToken.trim();
  return WatchOrderRepository(
    shikimori: ref.watch(shikimoriClientProvider),
    anilist: ref.watch(anilistApiClientProvider),
    malFallback: settings.hasMalSession && malToken.isNotEmpty
        ? MalApiClient(
            accessToken: malToken,
            onRefreshToken: ref.read(settingsProvider.notifier).refreshMalToken,
          )
        : null,
    onPrimaryFailure: (Object error) {
      unawaited(
        ref
            .read(trackerSyncCoordinatorProvider)
            .recordProviderFailure(TrackerSource.anilist, error),
      );
    },
    onPrimarySuccess: () {
      unawaited(
        ref
            .read(trackerSyncCoordinatorProvider)
            .recordProviderSuccess(TrackerSource.anilist),
      );
    },
    cache: ref.watch(metadataCacheStoreProvider),
  );
});

final watchOrderProvider = FutureProvider.autoDispose.family<WatchOrder, int>(
  (ref, malId) => ref.watch(watchOrderRepositoryProvider).get(malId),
);
