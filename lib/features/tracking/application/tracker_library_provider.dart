import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/anilist_models.dart';
import '../../settings/application/settings_state.dart';
import 'tracker_sync_coordinator.dart';

/// Local-first anime library for MAL/Shikimori selection. The selected source
/// is tried first, then connected providers are used as fallbacks. The common
/// cache is returned when every provider is unavailable.
final trackerAnimeListProvider = FutureProvider<List<AniListAnimeListFolder>>((
  Ref ref,
) async {
  final SettingsState settings = ref.watch(settingsProvider);
  final TrackerLibrarySnapshot result = await ref
      .read(trackerSyncCoordinatorProvider)
      .refreshAnimeLibrary(preferred: settings.effectivePrimaryTrackerSource);
  return result.folders;
});
