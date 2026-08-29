import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/router.dart';
import '../../../shared/models/media_item.dart';
import '../../addons/application/sora_source_providers.dart';
import '../../addons/domain/sora_models.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/player_models.dart';
import '../../watch/domain/normalized_models.dart';
import '../domain/watch_party_models.dart';

/// Re-resolves a watch-party episode/source **locally** through this device's
/// own Sora addon (no stream URL is shared), then loads and aligns the player.
/// Guests use [ignoreProgress] while the host keeps normal progress persistence
/// when accepting a permitted guest stream request.
class WatchPartyGuestResolver {
  WatchPartyGuestResolver(this._ref, {this.ignoreProgress = true});

  final Ref _ref;
  final bool ignoreProgress;

  /// Applies [descriptor]: re-resolves the stream locally and, if it is a new
  /// episode/source, swaps it into the player (or navigates into the player when
  /// the guest is not watching yet). Then seeks to [position], applies [speed],
  /// and resumes only when the host is [playing].
  Future<void> apply(
    SourceDescriptor descriptor, {
    required Duration position,
    required double speed,
    required bool temporarySpeedActive,
    required bool playing,
    bool syncQuality = true,
    bool forceReload = false,
  }) async {
    final PlaybackController playback = _ref.read(
      playbackControllerProvider.notifier,
    );

    // Realign without reloading when the exact episode and source are active.
    final PlaybackState currentState = _ref.read(playbackControllerProvider);
    final MediaPlaybackItem? current = currentState.item;
    if (!forceReload &&
        _isSameSource(currentState, descriptor, syncQuality: syncQuality)) {
      await _align(
        playback,
        position: position,
        speed: speed,
        temporarySpeedActive: temporarySpeedActive,
        playing: playing,
      );
      return;
    }

    final MediaPlaybackItem item = await _buildPlaybackItem(
      descriptor,
      startPosition: position,
      initialQualityId: syncQuality ? descriptor.qualityId : null,
    );

    if (current == null) {
      // Navigate to the player when the guest has not entered it yet.
      final BuildContext? context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await context.push(AppRoutes.watchPlay, extra: item);
    } else {
      // Swap the episode and source in place when the player is already open.
      await playback.load(item);
    }
    await _align(
      playback,
      position: position,
      speed: speed,
      temporarySpeedActive: temporarySpeedActive,
      playing: playing,
    );
  }

  bool _isSameEpisode(MediaPlaybackItem item, SourceDescriptor d) {
    return (item.externalIds['sora_addon_id'] ?? '') == d.soraAddonId &&
        (item.externalIds['sora_episode_href'] ?? '') == d.soraEpisodeHref &&
        item.seasonNumber == d.seasonNumber &&
        item.episodeNumber == d.episodeNumber;
  }

  bool _isSameSource(
    PlaybackState state,
    SourceDescriptor descriptor, {
    required bool syncQuality,
  }) {
    final MediaPlaybackItem? item = state.item;
    if (item == null || !_isSameEpisode(item, descriptor)) return false;
    final bool sameStream =
        _sameOptionalId(descriptor.serverId, state.server?.id) &&
        _sameOptionalId(descriptor.voiceoverId, state.voiceover?.id);
    if (!sameStream || !syncQuality) return sameStream;
    return _sameOptionalId(descriptor.qualityId, state.quality?.id) ||
        _sameOptionalId(descriptor.qualityId, state.quality?.label);
  }

  bool _sameOptionalId(String? left, String? right) {
    return _cleanId(left) == _cleanId(right);
  }

  Future<MediaPlaybackItem> _buildPlaybackItem(
    SourceDescriptor descriptor, {
    required Duration startPosition,
    required String? initialQualityId,
  }) async {
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
    final NormalizedServer? selectedServer = _serverById(
      bundle.availableServers,
      descriptor.serverId,
    );
    if (selectedServer != null) {
      bundle = bundle.withServer(selectedServer);
    }

    return MediaPlaybackItem.fromBundle(
      bundle,
      media,
      descriptor.seasonNumber,
      startPosition: startPosition,
      startPolicy: PlaybackStartPolicy.explicitPosition,
      // The guest mirrors the host; it shouldn't drive auto-next or persist its
      // own progress for the shared session.
      ignoreProgress: ignoreProgress,
      initialQualityId: initialQualityId,
      initialVoiceoverId: descriptor.voiceoverId,
      useBundleSelectedVoiceover: false,
    );
  }

  NormalizedServer? _serverById(
    List<NormalizedServer> servers,
    String? serverId,
  ) {
    final String? cleanServerId = _cleanId(serverId);
    if (cleanServerId == null) return null;
    for (final NormalizedServer server in servers) {
      if (_cleanId(server.id) == cleanServerId) return server;
    }
    return null;
  }

  String? _cleanId(String? value) {
    final String clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  /// Waits briefly for the engine to initialize, then seeks/speed/play to match
  /// the host. The periodic positionSync heartbeat keeps it aligned afterwards.
  Future<void> _align(
    PlaybackController playback, {
    required Duration position,
    required double speed,
    required bool temporarySpeedActive,
    required bool playing,
  }) async {
    for (int attempt = 0; attempt < 40; attempt++) {
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
    await playback.applyRemoteSeek(position);
    await playback.applyRemoteSpeed(speed, temporary: temporarySpeedActive);
    if (playing) {
      await playback.applyRemotePlay();
    } else {
      await playback.applyRemotePause();
    }
  }
}
