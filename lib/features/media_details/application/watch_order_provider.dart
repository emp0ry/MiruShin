import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../metadata/application/metadata_cache_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../data/watch_order_repository.dart';
import '../domain/watch_order.dart';

final watchOrderRepositoryProvider = Provider<WatchOrderRepository>(
  (ref) => WatchOrderRepository(
    shikimori: ref.watch(shikimoriClientProvider),
    anilist: ref.watch(anilistApiClientProvider),
    cache: ref.watch(metadataCacheStoreProvider),
  ),
);

final watchOrderProvider = FutureProvider.autoDispose.family<WatchOrder, int>(
  (ref, malId) => ref.watch(watchOrderRepositoryProvider).get(malId),
);
