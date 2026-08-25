import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final downloadSettingsProvider =
    AsyncNotifierProvider<DownloadSettingsController, bool>(
      DownloadSettingsController.new,
    );

/// Persists download-library behavior independently from player preferences.
class DownloadSettingsController extends AsyncNotifier<bool> {
  static const String autoDeleteWatchedEpisodesKey =
      'downloads.autoDeleteWatchedEpisodes';

  @override
  Future<bool> build() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getBool(autoDeleteWatchedEpisodesKey) ?? false;
  }

  Future<void> setAutoDeleteWatchedEpisodes(bool enabled) async {
    state = AsyncData<bool>(enabled);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setBool(autoDeleteWatchedEpisodesKey, enabled);
  }
}

bool shouldAutoDeleteWatchedEpisode({
  required bool enabled,
  required bool isWatched,
}) => enabled && isWatched;
