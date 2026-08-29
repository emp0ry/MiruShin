import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('source descriptor selection includes stream identifiers', () {
    final SourceDescriptor source = _descriptor(
      serverId: 'server-a',
      voiceoverId: 'sub',
      qualityId: '720p',
    );
    final SourceDescriptor sameEpisodeDifferentServer = _descriptor(
      serverId: 'server-b',
      voiceoverId: 'sub',
      qualityId: '720p',
    );

    expect(source.sameEpisodeAs(sameEpisodeDifferentServer), isTrue);
    expect(source.sameSelectionAs(sameEpisodeDifferentServer), isFalse);
    expect(source.sameStreamAs(sameEpisodeDifferentServer), isFalse);
  });

  test('stream selection ignores device-local quality', () {
    final SourceDescriptor quality720 = _descriptor(qualityId: '720p');
    final SourceDescriptor quality1080 = _descriptor(qualityId: '1080p');

    expect(quality720.sameSelectionAs(quality1080), isFalse);
    expect(quality720.sameStreamAs(quality1080), isTrue);
  });

  test('source descriptor round-trips selected quality', () {
    final SourceDescriptor source = _descriptor(qualityId: '1080p');
    final SourceDescriptor decoded = SourceDescriptor.fromJson(source.toJson());

    expect(decoded.qualityId, '1080p');
    expect(decoded.sameSelectionAs(source), isTrue);
  });

  test('watch party event round-trips guest permissions', () {
    final WatchPartyEvent event = WatchPartyEvent(
      type: WatchPartyEventType.permissionsChanged,
      permissions: const WatchPartyPermissions(
        canControlPlayback: true,
        canSeek: true,
        canChangeSpeed: true,
        canChangeStream: true,
      ),
    );

    final WatchPartyEvent decoded = WatchPartyEvent.fromJson(event.toJson());

    expect(decoded.type, WatchPartyEventType.permissionsChanged);
    expect(decoded.permissions?.canControlPlayback, isTrue);
    expect(decoded.permissions?.canSeek, isTrue);
    expect(decoded.permissions?.canChangeSpeed, isTrue);
    expect(decoded.permissions?.canChangeStream, isTrue);
  });

  test('stream change request round-trips the requested selection', () {
    final WatchPartyEvent event = WatchPartyEvent(
      type: WatchPartyEventType.streamChangeRequested,
      source: _descriptor(serverId: 'server-b', voiceoverId: 'dub'),
    );

    final WatchPartyEvent decoded = WatchPartyEvent.fromJson(event.toJson());

    expect(decoded.type, WatchPartyEventType.streamChangeRequested);
    expect(decoded.source?.serverId, 'server-b');
    expect(decoded.source?.voiceoverId, 'dub');
  });

  test('watch-party playback item carries the exact voiceover choice', () {
    const NormalizedServer server = NormalizedServer(
      id: 'server',
      title: 'Server',
      streamUrl: 'https://example.invalid/video.m3u8',
    );
    const NormalizedStreamBundle bundle = NormalizedStreamBundle(
      addonId: 'addon',
      episode: SoraEpisode(
        number: 1,
        href: '/episode-1',
        title: '',
        image: '',
        description: '',
        duration: '',
      ),
      selectedServer: server,
      availableServers: <NormalizedServer>[server],
      selectedVoiceOver: NormalizedVoiceOver(id: 'default', label: 'Default'),
      availableVoiceOvers: <NormalizedVoiceOver>[
        NormalizedVoiceOver(id: 'default', label: 'Default'),
        NormalizedVoiceOver(id: 'dub', label: 'Dub'),
      ],
    );
    const MediaItem media = MediaItem(
      id: 'media',
      title: 'Title',
      originalTitle: 'Original',
      overview: '',
      type: MediaType.anime,
      year: 0,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: <String>[],
      sourceProvider: 'addon',
      externalIds: <String, String>{},
      statusLabel: '',
    );

    final MediaPlaybackItem dub = MediaPlaybackItem.fromBundle(
      bundle,
      media,
      1,
      initialVoiceoverId: 'dub',
      useBundleSelectedVoiceover: false,
    );
    final MediaPlaybackItem base = MediaPlaybackItem.fromBundle(
      bundle,
      media,
      1,
      useBundleSelectedVoiceover: false,
    );

    expect(dub.initialVoiceoverId, 'dub');
    expect(base.initialVoiceoverId, isNull);
  });

  test('watch party event round-trips temporary speed state', () {
    final WatchPartyEvent event = WatchPartyEvent(
      type: WatchPartyEventType.speed,
      speed: 2.0,
      temporarySpeedActive: true,
    );

    final WatchPartyEvent decoded = WatchPartyEvent.fromJson(event.toJson());

    expect(decoded.type, WatchPartyEventType.speed);
    expect(decoded.speed, 2.0);
    expect(decoded.temporarySpeedActive, isTrue);
  });
}

SourceDescriptor _descriptor({
  String? serverId = 'server-a',
  String? voiceoverId,
  String? qualityId,
}) {
  return SourceDescriptor(
    mediaId: 'media-1',
    title: 'Title',
    originalTitle: 'Original Title',
    posterUrl: '',
    backdropUrl: '',
    mediaType: MediaType.anime,
    externalIds: const <String, String>{'mal': '1'},
    soraAddonId: 'addon',
    soraEpisodeHref: '/episode-1',
    seasonNumber: 1,
    episodeNumber: 1,
    serverId: serverId,
    voiceoverId: voiceoverId,
    qualityId: qualityId,
  );
}
