import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/artwork_cache_manager.dart';
import '../../../core/cache/metadata_cache_store.dart';
import '../../settings/application/settings_state.dart';

final metadataCacheStoreProvider = Provider<MetadataCacheStore>((Ref ref) {
  final ({int limitMb, CacheRetention retention}) policy = ref.watch(
    settingsProvider.select(
      (SettingsState settings) =>
          (limitMb: settings.cacheLimitMb, retention: settings.cacheRetention),
    ),
  );
  final MetadataCacheStore store = MetadataCacheStore(
    maxAge: policy.retention.duration,
    maxCacheBytes: policy.limitMb * 1024 * 1024,
    onSizeChanged: miruShinArtworkCacheManager.enforceCachePolicy,
  );
  unawaited(store.enforceCachePolicy().catchError((Object _) {}));
  return store;
});
