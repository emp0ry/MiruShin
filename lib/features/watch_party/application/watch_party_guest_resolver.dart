import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/router.dart';
import '../../../shared/models/media_item.dart';
import '../../addons/application/sora_addons_provider.dart';
import '../../addons/application/sora_source_providers.dart';
import '../../addons/domain/sora_models.dart';
import '../../downloads/application/downloads_provider.dart';
import '../../downloads/application/offline_playback.dart';
import '../../downloads/data/download_store.dart';
import '../../downloads/domain/download_identity.dart';
import '../../downloads/domain/download_models.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/player_models.dart';
import '../../watch/domain/normalized_models.dart';
import '../domain/watch_party_models.dart';
import 'watch_party_download_matcher.dart';

const String watchPartyMissingAddonError =
    'Install the same module as the host, then retry.';
const String watchPartySourceUnavailableError =
    "The host's selected stream is not available on this device.";
const String watchPartyPlaybackFailedError =
    "Could not play the host's source on this device.";

class WatchPartySourceUnavailable implements Exception {
  const WatchPartySourceUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

enum WatchPartyResolutionTarget { local, online, missingAddon }

WatchPartyResolutionTarget watchPartyResolutionTarget({
  required bool hasPlayableDownload,
  required bool addonInstalled,
}) {
  if (hasPlayableDownload) return WatchPartyResolutionTarget.local;
  return addonInstalled
      ? WatchPartyResolutionTarget.online
      : WatchPartyResolutionTarget.missingAddon;
}

class WatchPartyResolutionGuard {
  int _generation = 0;

  int begin() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;
}

/// Resolves the host's canonical source on this device. A compatible completed
/// download wins regardless of whether the host itself is online or offline;
/// otherwise the same Sora addon re-resolves an online URL locally.
class WatchPartyGuestResolver {
  WatchPartyGuestResolver(this._ref);

  final Ref _ref;
  final WatchPartyResolutionGuard _guard = WatchPartyResolutionGuard();

  Future<bool> apply(
    SourceDescriptor descriptor, {
    required Duration position,
    required double speed,
    required bool temporarySpeedActive,
    required bool playing,
    bool syncQuality = true,
    bool forceReload = false,
  }) async {
    final int generation = _guard.begin();
    final PlaybackController playback = _ref.read(
      playbackControllerProvider.notifier,
    );

    PlaybackState currentState = _ref.read(playbackControllerProvider);
    final MediaPlaybackItem? current = currentState.item;
    if (current != null && _isSameEpisode(current, descriptor)) {
      playback.setCurrentItemProgressIgnored(false);
      currentState = _ref.read(playbackControllerProvider);
    }
    if (!forceReload && _isSameSource(currentState, descriptor)) {
      return _align(
        playback,
        generation: generation,
        position: position,
        speed: speed,
        temporarySpeedActive: temporarySpeedActive,
        playing: playing,
      );
    }

    final DownloadController downloads = _ref.read(downloadsProvider.notifier);
    await downloads.ensureLoaded();
    if (!_isCurrent(generation)) return false;
    final String? rootPath = downloads.rootPath;
    final List<DownloadedEpisode> snapshot = _ref.read(downloadsProvider);
    final DownloadStore store = _ref.read(downloadStoreProvider);
    final WatchPartyDownloadMatch? localMatch = rootPath == null
        ? null
        : selectWatchPartyDownload(
            descriptor: descriptor,
            downloads: snapshot,
            isPlayable: (DownloadedEpisode episode) =>
                store.hasPlayableFile(rootPath, episode),
          );

    final bool addonInstalled =
        _ref.read(soraAddonsProvider).byId(descriptor.soraAddonId) != null;
    final WatchPartyResolutionTarget initialTarget = watchPartyResolutionTarget(
      hasPlayableDownload: localMatch != null && rootPath != null,
      addonInstalled: addonInstalled,
    );
    if (initialTarget == WatchPartyResolutionTarget.local &&
        localMatch != null &&
        rootPath != null) {
      final DownloadedEpisode episode = localMatch.episode;
      final MediaPlaybackItem localItem = buildOfflinePlaybackItem(
        episode: episode,
        rootPath: rootPath,
        moduleEpisodes: offlineModuleEpisodesFor(episode, snapshot),
        startPosition: position,
        startPolicy: PlaybackStartPolicy.explicitPosition,
      );
      bool localReady = false;
      try {
        localReady = await _loadAndWait(
          playback,
          localItem,
          generation: generation,
        );
      } on Object {
        if (!_isCurrent(generation)) return false;
        // A local file can disappear or become unreadable after the registry
        // check. Continue once through the normal online resolver.
      }
      if (!_isCurrent(generation)) return false;
      if (localReady) {
        return _align(
          playback,
          generation: generation,
          position: position,
          speed: speed,
          temporarySpeedActive: temporarySpeedActive,
          playing: playing,
        );
      }
    }

    final WatchPartyResolutionTarget fallbackTarget =
        watchPartyResolutionTarget(
          hasPlayableDownload: false,
          addonInstalled: addonInstalled,
        );
    if (fallbackTarget == WatchPartyResolutionTarget.missingAddon) {
      throw const WatchPartySourceUnavailable(watchPartyMissingAddonError);
    }

    late final MediaPlaybackItem onlineItem;
    try {
      onlineItem = await _buildOnlinePlaybackItem(
        descriptor,
        startPosition: position,
        initialQualityId: syncQuality ? descriptor.qualityId : null,
      );
    } on Object {
      if (!_isCurrent(generation)) return false;
      rethrow;
    }
    if (!_isCurrent(generation)) return false;
    late final bool onlineReady;
    try {
      onlineReady = await _loadAndWait(
        playback,
        onlineItem,
        generation: generation,
      );
    } on Object {
      if (!_isCurrent(generation)) return false;
      rethrow;
    }
    if (!_isCurrent(generation)) return false;
    if (!onlineReady) {
      throw const WatchPartySourceUnavailable(watchPartyPlaybackFailedError);
    }
    return _align(
      playback,
      generation: generation,
      position: position,
      speed: speed,
      temporarySpeedActive: temporarySpeedActive,
      playing: playing,
    );
  }

  bool _isSameEpisode(MediaPlaybackItem item, SourceDescriptor descriptor) {
    if (item.id != descriptor.mediaId &&
        !_sharesExternalMediaId(item.externalIds, descriptor.externalIds)) {
      return false;
    }
    return (item.externalIds['sora_addon_id'] ?? '') ==
            descriptor.soraAddonId &&
        normalizeDownloadedEpisodeHref(
              item.externalIds['sora_episode_href'] ?? '',
            ) ==
            normalizeDownloadedEpisodeHref(descriptor.soraEpisodeHref) &&
        item.seasonNumber == descriptor.seasonNumber &&
        item.episodeNumber == descriptor.episodeNumber;
  }

  bool _isSameSource(PlaybackState state, SourceDescriptor descriptor) {
    final MediaPlaybackItem? item = state.item;
    if (item == null ||
        state.engine?.state.value.isInitialized != true ||
        !_isSameEpisode(item, descriptor)) {
      return false;
    }
    final bool offline = state.server?.id == 'offline';
    final String? serverId =
        _cleanId(item.externalIds[offlineOriginServerIdKey]) ??
        (offline ? null : _cleanId(state.server?.id));
    final String? voiceoverId =
        _cleanId(item.externalIds[offlineOriginVoiceoverIdKey]) ??
        (offline ? null : _cleanId(state.voiceover?.id));
    return _sameOptionalId(descriptor.serverId, serverId) &&
        _sameOptionalId(descriptor.voiceoverId, voiceoverId);
  }

  bool _sharesExternalMediaId(
    Map<String, String> left,
    Map<String, String> right,
  ) {
    for (final String key in const <String>[
      'anilist',
      'mal',
      'shikimori',
      'tmdb',
    ]) {
      final String leftId = left[key]?.trim() ?? '';
      final String rightId = right[key]?.trim() ?? '';
      if (leftId.isNotEmpty && leftId == rightId) return true;
    }
    return false;
  }

  bool _sameOptionalId(String? left, String? right) {
    return _cleanId(left) == _cleanId(right);
  }

  Future<MediaPlaybackItem> _buildOnlinePlaybackItem(
    SourceDescriptor descriptor, {
    required Duration startPosition,
    required String? initialQualityId,
  }) async {
    if (_ref.read(soraAddonsProvider).byId(descriptor.soraAddonId) == null) {
      throw const WatchPartySourceUnavailable(watchPartyMissingAddonError);
    }
    final MediaItem media = MediaItem(
      id: descriptor.mediaId,
      title: descriptor.title,
      originalTitle: descriptor.originalTitle,
      overview: '',
      type: descriptor.mediaType,
      year: 0,
      posterUrl: descriptor.posterUrl,
      backdropUrl: descriptor.backdropUrl,
      rating: 0,
      genres: const <String>[],
      sourceProvider: descriptor.soraAddonId,
      externalIds: descriptor.externalIds,
      episodeCount: descriptor.episodeCount,
      statusLabel: '',
    );
    final SoraEpisode episode = SoraEpisode(
      number: descriptor.episodeNumber,
      href: descriptor.soraEpisodeHref,
      title: '',
      image: '',
      description: '',
      duration: '',
      raw: <String, dynamic>{'season': descriptor.seasonNumber},
    );

    NormalizedStreamBundle bundle = await _ref.read(
      soraStreamBundleProvider(
        SoraStreamRequest(
          addonId: descriptor.soraAddonId,
          episode: episode,
          voiceover: descriptor.voiceoverId,
        ),
      ).future,
    );
    final String? requestedServerId = _cleanId(descriptor.serverId);
    if (requestedServerId != null) {
      final NormalizedServer? selectedServer = _serverById(
        bundle.availableServers,
        requestedServerId,
      );
      if (selectedServer == null) {
        throw const WatchPartySourceUnavailable(
          watchPartySourceUnavailableError,
        );
      }
      bundle = bundle.withServer(selectedServer);
    }

    return MediaPlaybackItem.fromBundle(
      bundle,
      media,
      descriptor.seasonNumber,
      startPosition: startPosition,
      startPolicy: PlaybackStartPolicy.explicitPosition,
      ignoreProgress: false,
      initialQualityId: initialQualityId,
      initialVoiceoverId: descriptor.voiceoverId,
      useBundleSelectedVoiceover: false,
    );
  }

  NormalizedServer? _serverById(
    List<NormalizedServer> servers,
    String serverId,
  ) {
    for (final NormalizedServer server in servers) {
      if (_cleanId(server.id) == serverId) return server;
    }
    return null;
  }

  String? _cleanId(String? value) {
    final String clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  Future<bool> _loadAndWait(
    PlaybackController playback,
    MediaPlaybackItem item, {
    required int generation,
  }) async {
    if (!_isCurrent(generation)) return false;
    if (_ref.read(playbackControllerProvider).item == null) {
      final BuildContext? context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) {
        throw const WatchPartySourceUnavailable(watchPartyPlaybackFailedError);
      }
      unawaited(context.push(AppRoutes.watchPlay, extra: item));
    } else {
      await playback.load(item);
    }

    for (int attempt = 0; attempt < 120; attempt++) {
      if (!_isCurrent(generation)) return false;
      final PlaybackState state = _ref.read(playbackControllerProvider);
      if (isSamePlaybackRouteItem(state.item, item)) {
        if (state.engine?.state.value.isInitialized == true) return true;
        if (!state.loading && state.error != null) return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<bool> _align(
    PlaybackController playback, {
    required int generation,
    required Duration position,
    required double speed,
    required bool temporarySpeedActive,
    required bool playing,
  }) async {
    for (int attempt = 0; attempt < 40; attempt++) {
      if (!_isCurrent(generation)) return false;
      if (_ref
              .read(playbackControllerProvider)
              .engine
              ?.state
              .value
              .isInitialized ==
          true) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!_isCurrent(generation)) return false;
    await playback.applyRemoteSeek(position);
    if (!_isCurrent(generation)) return false;
    await playback.applyRemoteSpeed(speed, temporary: temporarySpeedActive);
    if (!_isCurrent(generation)) return false;
    if (playing) {
      await playback.applyRemotePlay();
    } else {
      await playback.applyRemotePause();
    }
    return _isCurrent(generation);
  }

  bool _isCurrent(int generation) => _guard.isCurrent(generation);
}
