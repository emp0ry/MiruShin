import '../../../shared/models/media_item.dart';

/// Who controls global playback. The room creator is always [host] for the
/// room's lifetime; everyone else is a [guest] that only receives and applies
/// the host's playback state.
enum WatchPartyRole { host, guest }

/// Lifecycle of the pairing + P2P connection. [signaling] covers the Worker
/// handshake; [connected] means the DataChannel is open and sync flows P2P.
enum WatchPartyConnectionStatus {
  idle,
  signaling,
  connecting,
  connected,
  reconnecting,
  closed,
  error,
}

/// The kinds of messages exchanged over the WebRTC DataChannel once paired.
enum WatchPartyEventType {
  play,
  pause,
  seek,
  speed,
  sourceChanged,
  episodeChanged,
  positionSync,
  helloRequest,
  stateSnapshot,
  permissionsChanged,
}

WatchPartyEventType _eventTypeFromName(String value) {
  for (final WatchPartyEventType type in WatchPartyEventType.values) {
    if (type.name == value) return type;
  }
  return WatchPartyEventType.positionSync;
}

/// Everything a guest needs to re-resolve the same episode/source *locally*
/// through its own Sora addon. No stream URL is shared — the guest runs the
/// resolver itself so tokenized/expiring URLs stay valid per client.
class SourceDescriptor {
  const SourceDescriptor({
    required this.mediaId,
    required this.title,
    required this.originalTitle,
    required this.posterUrl,
    required this.backdropUrl,
    required this.mediaType,
    required this.externalIds,
    required this.soraAddonId,
    required this.soraEpisodeHref,
    required this.seasonNumber,
    required this.episodeNumber,
    this.serverId,
    this.voiceoverId,
    this.qualityId,
    this.episodeCount,
  });

  final String mediaId;
  final String title;
  final String originalTitle;
  final String posterUrl;
  final String backdropUrl;
  final MediaType mediaType;
  final Map<String, String> externalIds;
  final String soraAddonId;
  final String soraEpisodeHref;
  final int seasonNumber;
  final double episodeNumber;
  final String? serverId;
  final String? voiceoverId;
  final String? qualityId;
  final int? episodeCount;

  bool sameEpisodeAs(SourceDescriptor? other) {
    if (other == null) return false;
    return soraAddonId == other.soraAddonId &&
        soraEpisodeHref == other.soraEpisodeHref &&
        seasonNumber == other.seasonNumber &&
        episodeNumber == other.episodeNumber;
  }

  bool sameSelectionAs(SourceDescriptor? other) {
    return sameEpisodeAs(other) &&
        serverId == other?.serverId &&
        voiceoverId == other?.voiceoverId &&
        qualityId == other?.qualityId;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mediaId': mediaId,
    'title': title,
    'originalTitle': originalTitle,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'mediaType': mediaType.name,
    'externalIds': externalIds,
    'soraAddonId': soraAddonId,
    'soraEpisodeHref': soraEpisodeHref,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    if (serverId != null) 'serverId': serverId,
    if (voiceoverId != null) 'voiceoverId': voiceoverId,
    if (qualityId != null) 'qualityId': qualityId,
    if (episodeCount != null) 'episodeCount': episodeCount,
  };

  factory SourceDescriptor.fromJson(Map<String, dynamic> json) {
    final Object? rawIds = json['externalIds'];
    final Map<String, String> ids = <String, String>{};
    if (rawIds is Map) {
      rawIds.forEach((Object? key, Object? value) {
        if (key != null && value != null) ids['$key'] = '$value';
      });
    }
    MediaType type = MediaType.anime;
    for (final MediaType t in MediaType.values) {
      if (t.name == json['mediaType']) {
        type = t;
        break;
      }
    }
    return SourceDescriptor(
      mediaId: '${json['mediaId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      originalTitle: '${json['originalTitle'] ?? ''}',
      posterUrl: '${json['posterUrl'] ?? ''}',
      backdropUrl: '${json['backdropUrl'] ?? ''}',
      mediaType: type,
      externalIds: ids,
      soraAddonId: '${json['soraAddonId'] ?? ''}',
      soraEpisodeHref: '${json['soraEpisodeHref'] ?? ''}',
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 1,
      episodeNumber: (json['episodeNumber'] as num?)?.toDouble() ?? 1.0,
      serverId: json['serverId'] as String?,
      voiceoverId: json['voiceoverId'] as String?,
      qualityId: json['qualityId'] as String?,
      episodeCount: (json['episodeCount'] as num?)?.toInt(),
    );
  }
}

class WatchPartyPermissions {
  const WatchPartyPermissions({
    this.canControlPlayback = false,
    this.canSeek = false,
    this.canChangeSpeed = false,
  });

  final bool canControlPlayback;
  final bool canSeek;
  final bool canChangeSpeed;

  WatchPartyPermissions copyWith({
    bool? canControlPlayback,
    bool? canSeek,
    bool? canChangeSpeed,
  }) {
    return WatchPartyPermissions(
      canControlPlayback: canControlPlayback ?? this.canControlPlayback,
      canSeek: canSeek ?? this.canSeek,
      canChangeSpeed: canChangeSpeed ?? this.canChangeSpeed,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'canControlPlayback': canControlPlayback,
    'canSeek': canSeek,
    'canChangeSpeed': canChangeSpeed,
  };

  factory WatchPartyPermissions.fromJson(Map<String, dynamic> json) {
    return WatchPartyPermissions(
      canControlPlayback: json['canControlPlayback'] == true,
      canSeek: json['canSeek'] == true,
      canChangeSpeed: json['canChangeSpeed'] == true,
    );
  }

  static const WatchPartyPermissions locked = WatchPartyPermissions();
}

/// A single sync message. Carries a server-agnostic [sentAt] timestamp so the
/// receiver can extrapolate the expected position:
/// `expected = position + ((now - sentAt) / 1000) * speed` while playing.
class WatchPartyEvent {
  WatchPartyEvent({
    required this.type,
    int? sentAt,
    this.position = Duration.zero,
    this.speed = 1.0,
    this.isPlaying = false,
    this.temporarySpeedActive = false,
    this.source,
    this.permissions,
  }) : sentAt = sentAt ?? DateTime.now().millisecondsSinceEpoch;

  final WatchPartyEventType type;
  final int sentAt;
  final Duration position;
  final double speed;
  final bool isPlaying;
  final bool temporarySpeedActive;
  final SourceDescriptor? source;
  final WatchPartyPermissions? permissions;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'sentAt': sentAt,
    'positionMs': position.inMilliseconds,
    'speed': speed,
    'isPlaying': isPlaying,
    'temporarySpeedActive': temporarySpeedActive,
    if (source != null) 'source': source!.toJson(),
    if (permissions != null) 'permissions': permissions!.toJson(),
  };

  factory WatchPartyEvent.fromJson(Map<String, dynamic> json) {
    final Object? rawSource = json['source'];
    final Object? rawPermissions = json['permissions'];
    return WatchPartyEvent(
      type: _eventTypeFromName('${json['type']}'),
      sentAt: (json['sentAt'] as num?)?.toInt(),
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      isPlaying: json['isPlaying'] == true,
      temporarySpeedActive: json['temporarySpeedActive'] == true,
      source: rawSource is Map<String, dynamic>
          ? SourceDescriptor.fromJson(rawSource)
          : null,
      permissions: rawPermissions is Map
          ? WatchPartyPermissions.fromJson(
              rawPermissions.map(
                (Object? key, Object? value) => MapEntry('$key', value),
              ),
            )
          : null,
    );
  }
}

/// Immutable UI-facing state of the current watch party.
class WatchPartyRoomState {
  const WatchPartyRoomState({
    this.roomCode,
    this.role,
    this.status = WatchPartyConnectionStatus.idle,
    this.peerConnected = false,
    this.lastError,
    this.permissions = WatchPartyPermissions.locked,
  });

  final String? roomCode;
  final WatchPartyRole? role;
  final WatchPartyConnectionStatus status;
  final bool peerConnected;
  final String? lastError;
  final WatchPartyPermissions permissions;

  bool get isActive =>
      role != null && status != WatchPartyConnectionStatus.idle;
  bool get isHost => role == WatchPartyRole.host;
  bool get isGuest => role == WatchPartyRole.guest;
  bool get isConnected => status == WatchPartyConnectionStatus.connected;

  WatchPartyRoomState copyWith({
    String? roomCode,
    WatchPartyRole? role,
    WatchPartyConnectionStatus? status,
    bool? peerConnected,
    String? lastError,
    WatchPartyPermissions? permissions,
    bool clearError = false,
    bool clearRoomCode = false,
  }) {
    return WatchPartyRoomState(
      roomCode: clearRoomCode ? null : roomCode ?? this.roomCode,
      role: role ?? this.role,
      status: status ?? this.status,
      peerConnected: peerConnected ?? this.peerConnected,
      lastError: clearError ? null : lastError ?? this.lastError,
      permissions: permissions ?? this.permissions,
    );
  }

  static const WatchPartyRoomState idle = WatchPartyRoomState();
}
