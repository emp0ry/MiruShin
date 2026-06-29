import 'package:flutter_test/flutter_test.dart';
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
      ),
    );

    final WatchPartyEvent decoded = WatchPartyEvent.fromJson(event.toJson());

    expect(decoded.type, WatchPartyEventType.permissionsChanged);
    expect(decoded.permissions?.canControlPlayback, isTrue);
    expect(decoded.permissions?.canSeek, isTrue);
    expect(decoded.permissions?.canChangeSpeed, isTrue);
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
