import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Current playback values only. No library membership, catalog metadata,
/// provider snapshots, operation history, or tracker delivery state.
class PlaybackReplicaSnapshot {
  const PlaybackReplicaSnapshot({
    required this.replicaNamespace,
    required this.deviceId,
    required this.media,
    required this.episodes,
    required this.streamPreferences,
  });

  final String replicaNamespace;
  final String deviceId;
  final List<Map<String, dynamic>> media;
  final List<Map<String, dynamic>> episodes;
  final List<Map<String, dynamic>> streamPreferences;

  bool get isEmpty => episodes.isEmpty && streamPreferences.isEmpty;

  String get fileName =>
      'mirushin.$replicaNamespace.playback.$deviceId.v1.json';

  Map<String, dynamic> get content => {
    'replicaNamespace': replicaNamespace,
    'media': media,
    'episodes': episodes,
    'streamPreferences': streamPreferences,
  };

  String get contentChecksum =>
      sha256.convert(utf8.encode(jsonEncode(content))).toString();

  String get checksum => md5.convert(utf8.encode(encode())).toString();

  String encode() =>
      jsonEncode({'schemaVersion': 1, 'deviceId': deviceId, ...content});

  factory PlaybackReplicaSnapshot.decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> || json['schemaVersion'] != 1) {
      throw const FormatException('Invalid playback snapshot version.');
    }
    String identifier(String key) {
      final value = json[key];
      if (value is! String || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
        throw FormatException('Invalid playback $key.');
      }
      return value;
    }

    List<Map<String, dynamic>> records(String key) {
      final value = json[key];
      if (value is! List ||
          value.any((item) => item is! Map<String, dynamic>)) {
        throw FormatException('Invalid playback $key.');
      }
      return value.cast<Map<String, dynamic>>();
    }

    return PlaybackReplicaSnapshot(
      replicaNamespace: identifier('replicaNamespace'),
      deviceId: identifier('deviceId'),
      media: records('media'),
      episodes: records('episodes'),
      streamPreferences: records('streamPreferences'),
    );
  }
}

abstract interface class PlaybackCloudReplica {
  Future<PlaybackCloudRead> pullPlaybackSnapshots({
    required Map<String, String> excluding,
  });

  /// Replaces this device's compact file, without touching library manifests.
  Future<void> pushPlaybackSnapshot(PlaybackReplicaSnapshot snapshot);
}

class PlaybackCloudRead {
  const PlaybackCloudRead({required this.snapshots, required this.fileNames});

  final List<PlaybackReplicaSnapshot> snapshots;
  final Set<String> fileNames;
}
