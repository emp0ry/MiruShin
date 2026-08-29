import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/media_item.dart';
import '../domain/normalized_models.dart';

final streamSelectionPreferenceStoreProvider =
    Provider<StreamSelectionPreferenceStore>(
      (Ref ref) => const StreamSelectionPreferenceStore(),
    );

class StreamSelectionPreference {
  const StreamSelectionPreference({
    this.serverId = '',
    this.serverTitle = '',
    this.qualityId = '',
    this.qualityLabel = '',
  });

  final String serverId;
  final String serverTitle;
  final String qualityId;
  final String qualityLabel;

  bool get hasServer =>
      serverId.trim().isNotEmpty || serverTitle.trim().isNotEmpty;

  bool get hasQuality =>
      qualityId.trim().isNotEmpty || qualityLabel.trim().isNotEmpty;

  Map<String, Object> toJson() => <String, Object>{
    'serverId': serverId,
    'serverTitle': serverTitle,
    'qualityId': qualityId,
    'qualityLabel': qualityLabel,
  };

  factory StreamSelectionPreference.fromJson(Map<String, dynamic> json) {
    return StreamSelectionPreference(
      serverId: json['serverId'] as String? ?? '',
      serverTitle: json['serverTitle'] as String? ?? '',
      qualityId: json['qualityId'] as String? ?? '',
      qualityLabel: json['qualityLabel'] as String? ?? '',
    );
  }
}

class AppliedStreamSelection {
  const AppliedStreamSelection({
    required this.bundle,
    this.initialQualityLabel,
  });

  final NormalizedStreamBundle bundle;

  /// An explicit quality is supplied only when a saved quality was matched or
  /// when a stale saved selection must fall back to the first available one.
  /// Null preserves the player's existing global quality preference.
  final String? initialQualityLabel;
}

AppliedStreamSelection applyStreamSelectionPreference(
  NormalizedStreamBundle bundle,
  StreamSelectionPreference? preference,
) {
  if (preference == null || !preference.hasServer) {
    return AppliedStreamSelection(bundle: bundle);
  }

  final NormalizedServer? server = _matchingServer(
    bundle.availableServers,
    preference,
  );
  if (server == null) {
    final NormalizedStreamBundle fallback = bundle.availableServers.isEmpty
        ? bundle
        : bundle.withServer(bundle.availableServers.first);
    return AppliedStreamSelection(
      bundle: fallback,
      initialQualityLabel: fallback.selectedQuality?.label,
    );
  }

  NormalizedStreamBundle selected = bundle.withServer(server);
  if (!preference.hasQuality) {
    return AppliedStreamSelection(bundle: selected);
  }

  final NormalizedQuality? quality = _matchingQuality(
    server.qualities,
    preference,
  );
  if (quality != null) {
    selected = selected.withQuality(quality);
  }
  return AppliedStreamSelection(
    bundle: selected,
    // withServer() selects the first quality, which is the required fallback
    // when the remembered quality no longer exists.
    initialQualityLabel: selected.selectedQuality?.label,
  );
}

NormalizedServer? _matchingServer(
  List<NormalizedServer> servers,
  StreamSelectionPreference preference,
) {
  final String serverId = preference.serverId.trim();
  if (serverId.isNotEmpty) {
    for (final NormalizedServer server in servers) {
      if (server.id.trim() == serverId) return server;
    }
  }

  final String serverTitle = _normalized(preference.serverTitle);
  if (serverTitle.isNotEmpty) {
    for (final NormalizedServer server in servers) {
      if (_normalized(server.title) == serverTitle) return server;
    }
  }
  return null;
}

NormalizedQuality? _matchingQuality(
  List<NormalizedQuality> qualities,
  StreamSelectionPreference preference,
) {
  final Set<String> preferred = <String>{
    _normalized(preference.qualityId),
    _normalized(preference.qualityLabel),
  }..remove('');
  for (final NormalizedQuality quality in qualities) {
    if (preferred.contains(_normalized(quality.label))) return quality;
  }
  return null;
}

String _normalized(String value) => value.trim().toLowerCase();

class StreamSelectionPreferenceStore {
  const StreamSelectionPreferenceStore({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String _keyPrefix = 'watch.streamSelection.v1.';

  final SharedPreferences? _preferences;

  Future<StreamSelectionPreference?> read({
    required MediaType mediaType,
    required String mediaId,
  }) async {
    final SharedPreferences preferences =
        _preferences ?? await SharedPreferences.getInstance();
    final String key = _key(mediaType, mediaId);
    final String? raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Expected an object.');
      final StreamSelectionPreference preference =
          StreamSelectionPreference.fromJson(decoded.cast<String, dynamic>());
      if (!preference.hasServer) return null;
      return preference;
    } on Object {
      await preferences.remove(key);
      return null;
    }
  }

  Future<void> save({
    required MediaType mediaType,
    required String mediaId,
    required StreamSelectionPreference preference,
  }) async {
    if (mediaId.trim().isEmpty || !preference.hasServer) return;
    final SharedPreferences preferences =
        _preferences ?? await SharedPreferences.getInstance();
    await preferences.setString(
      _key(mediaType, mediaId),
      jsonEncode(preference.toJson()),
    );
  }

  static String _key(MediaType mediaType, String mediaId) {
    final String scope = '${mediaType.name}:${mediaId.trim()}';
    final String encoded = base64UrlEncode(
      utf8.encode(scope),
    ).replaceAll('=', '');
    return '$_keyPrefix$encoded';
  }
}
