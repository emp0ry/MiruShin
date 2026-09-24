import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/application/settings_state.dart';
import '../../settings/data/workspace_preferences_store.dart';
import '../domain/player_models.dart';

final playerSettingsProvider =
    AsyncNotifierProvider<PlayerSettingsController, PlayerSettings>(
      PlayerSettingsController.new,
    );

class PlayerSettingsController extends AsyncNotifier<PlayerSettings> {
  static const String _key = 'mirushin.player.settings';

  @override
  Future<PlayerSettings> build() async {
    ref.watch(drivePreferencesRevisionProvider);
    final int? viewerId = ref.watch(
      settingsProvider.select((SettingsState value) => value.anilistViewerId),
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    PlayerSettings result = const PlayerSettings();
    try {
      if (raw != null && raw.isNotEmpty) {
        result = PlayerSettings.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        );
      }
    } on Object {
      result = const PlayerSettings();
    }
    final String workspaceId = viewerId == null ? 'local' : 'anilist:$viewerId';
    final Object? scoped = WorkspacePreferencesStore(
      prefs,
    ).read(workspaceId, WorkspacePreferencesStore.playerAutoTrackKey);
    return scoped is bool ? result.copyWith(autoAnilistSync: scoped) : result;
  }

  Future<void> _update(PlayerSettings settings) async {
    state = AsyncData<PlayerSettings>(settings);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  Future<void> setSpeed(double speed) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(playbackSpeed: speed));
  }

  Future<void> setVolume(double volume) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    final double normalized = volume.clamp(0.0, 1.0).toDouble();
    await _update(
      current.copyWith(
        volume: normalized,
        lastAudibleVolume: normalized > 0
            ? normalized
            : current.lastAudibleVolume,
      ),
    );
  }

  Future<void> setPlayerBackend(PlayerBackend backend) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(playerBackend: backend));
  }

  Future<void> setSeekPreviewMode(SeekPreviewMode mode) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(seekPreviewMode: mode));
  }

  Future<void> setSeekPreviewsEnabled(bool enabled) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(seekPreviewsEnabled: enabled));
  }

  Future<void> setVerticalStretch(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(verticalStretch: value));
  }

  Future<void> setHorizontalSwipeSeekEnabled(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(horizontalSwipeSeekEnabled: value));
  }

  Future<void> setSeekInterval(Duration interval) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(seekInterval: interval));
  }

  Future<void> setSubtitlesEnabled(bool enabled) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(subtitlesEnabled: enabled));
  }

  Future<void> setSubtitleDelay(Duration delay) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(subtitleDelay: delay));
  }

  Future<void> setSubtitleFontSize(double size) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(subtitleFontSize: size.clamp(12.0, 48.0)));
  }

  Future<void> setSubtitleBottomOffset(double offset) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(
      current.copyWith(subtitleBottomOffset: offset.clamp(20.0, 300.0)),
    );
  }

  Future<void> setSubtitleTextColor(int color) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(subtitleTextColor: color));
  }

  Future<void> setSubtitleHasBackground(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(subtitleHasBackground: value));
  }

  Future<void> setSubtitleBackgroundOpacity(double value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(
      current.copyWith(subtitleBackgroundOpacity: value.clamp(0.0, 1.0)),
    );
  }

  Future<void> setShowSkipButtons(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(showSkipButtons: value));
  }

  Future<void> setShowSkipOpeningButton(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(showSkipOpeningButton: value));
  }

  Future<void> setShowSkipEndingButton(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(showSkipEndingButton: value));
  }

  Future<void> setShowNextEpisodeButton(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(showNextEpisodeButton: value));
  }

  Future<void> setUseAniSkip(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(useAniSkip: value));
  }

  Future<void> setSkipMarkersSource(SkipMarkersSource value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(skipMarkersSource: value));
  }

  Future<void> setAutoSkipOpening(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(autoSkipOpening: value));
  }

  Future<void> setAutoSkipEnding(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(autoSkipEnding: value));
  }

  Future<void> setAutoplayNext(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(autoplayNext: value));
  }

  Future<void> setDiscordRpcEnabled(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(discordRpcEnabled: value));
  }

  Future<void> setAutoAnilistSync(bool value) async {
    final PlayerSettings current = state.value ?? const PlayerSettings();
    await _update(current.copyWith(autoAnilistSync: value));
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? viewerId = ref.read(settingsProvider).anilistViewerId;
    await WorkspacePreferencesStore(prefs).write(
      viewerId == null ? 'local' : 'anilist:$viewerId',
      WorkspacePreferencesStore.playerAutoTrackKey,
      value,
    );
    ref.read(drivePreferencesRevisionProvider.notifier).changed();
  }
}
