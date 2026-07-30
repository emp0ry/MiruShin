import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/metadata_cache_store.dart';
import '../../settings/application/settings_state.dart';

final metadataCacheStoreProvider = Provider<MetadataCacheStore>(
  (Ref ref) => MetadataCacheStore(
    enabled: ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.metadataCacheEnabled,
      ),
    ),
  ),
);
