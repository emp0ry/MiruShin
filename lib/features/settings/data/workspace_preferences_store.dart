import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/settings_preferences.dart';

const String workspacePreferencePrefix = 'mirushin.workspace.v1.';

String workspacePreferenceKey(String workspaceId, String key) =>
    '$workspacePreferencePrefix${Uri.encodeComponent(workspaceId)}.${Uri.encodeComponent(key)}';

class DrivePreferencesRevision extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

final drivePreferencesRevisionProvider =
    NotifierProvider<DrivePreferencesRevision, int>(
      DrivePreferencesRevision.new,
    );

class WorkspacePreferencesStore {
  WorkspacePreferencesStore(this.preferences);

  static const String migrationKey =
      'mirushin.workspace_preferences.migration.v1';
  static const String playerAutoTrackKey = 'player.autoAnilistSync';
  static const String airingScopeKey = 'anilist.airingNotificationScope';
  static const String userSettingsCacheKey = 'anilist.userSettingsCache';

  final SharedPreferences preferences;

  String key(String workspaceId, String rawKey) =>
      workspacePreferenceKey(workspaceId, rawKey);

  Object? read(String workspaceId, String rawKey) =>
      preferences.get(key(workspaceId, rawKey));

  Future<void> write(String workspaceId, String rawKey, Object? value) async {
    final String target = key(workspaceId, rawKey);
    if (value == null) {
      await preferences.remove(target);
    } else if (value is String) {
      await preferences.setString(target, value);
    } else if (value is bool) {
      await preferences.setBool(target, value);
    } else if (value is int) {
      await preferences.setInt(target, value);
    } else if (value is double) {
      await preferences.setDouble(target, value);
    } else if (value is List && value.every((Object? item) => item is String)) {
      await preferences.setStringList(
        target,
        value.cast<String>().toList(growable: false),
      );
    } else {
      throw ArgumentError.value(value, rawKey, 'Unsupported preference type');
    }
  }

  Future<void> migrateLegacy({required Iterable<int> viewerIds}) async {
    if (preferences.getBool(migrationKey) == true) return;
    final Set<String> workspaces = <String>{
      'local',
      ...viewerIds.where((int id) => id > 0).map((int id) => 'anilist:$id'),
    };
    final Set<String> legacyKeys = preferences
        .getKeys()
        .where(
          (String key) =>
              key.startsWith('library.anilist.') ||
              key.startsWith('library.local.'),
        )
        .toSet();
    legacyKeys.addAll(<String>{
      SettingsPreferences.appLanguageKey,
      SettingsPreferences.discordRpcEnabledKey,
      SettingsPreferences.anilistTitleLanguageKey,
      SettingsPreferences.anilistLibraryDefaultPageKey,
      SettingsPreferences.anilistUserSettingsCacheKey,
    });
    final String? rawPlayer = preferences.getString('mirushin.player.settings');
    Object? autoTrack;
    if (rawPlayer != null && rawPlayer.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawPlayer);
        if (decoded is Map) autoTrack = decoded['autoAnilistSync'];
      } on Object {
        // Preserve the old player blob and use the default for this field.
      }
    }
    for (final String workspace in workspaces) {
      for (final String legacyKey in legacyKeys) {
        final Object? value = preferences.get(legacyKey);
        if (value != null && read(workspace, legacyKey) == null) {
          await write(workspace, legacyKey, value);
        }
      }
      if (autoTrack != null && read(workspace, playerAutoTrackKey) == null) {
        await write(workspace, playerAutoTrackKey, autoTrack);
      }
      if (read(workspace, airingScopeKey) == null) {
        final String? raw = preferences.getString(
          SettingsPreferences.anilistUserSettingsCacheKey,
        );
        if (raw != null) {
          try {
            final Object? decoded = jsonDecode(raw);
            if (decoded is Map && decoded['airingNotificationScope'] != null) {
              await write(
                workspace,
                airingScopeKey,
                '${decoded['airingNotificationScope']}',
              );
            }
          } on Object {
            // The original cache remains available for a future retry.
          }
        }
      }
    }
    await preferences.setBool(migrationKey, true);
  }

  Future<void> captureActiveProfile({
    required String workspaceId,
    required String? appLanguage,
    required bool discordRpcEnabled,
    required String titleLanguage,
    required String defaultLibraryPage,
  }) async {
    await write(workspaceId, SettingsPreferences.appLanguageKey, appLanguage);
    await write(
      workspaceId,
      SettingsPreferences.discordRpcEnabledKey,
      discordRpcEnabled,
    );
    await write(
      workspaceId,
      SettingsPreferences.anilistTitleLanguageKey,
      titleLanguage,
    );
    await write(
      workspaceId,
      SettingsPreferences.anilistLibraryDefaultPageKey,
      defaultLibraryPage,
    );
  }
}
