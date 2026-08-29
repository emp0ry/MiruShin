import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/watch_party_models.dart';

final watchPartyConnectionSettingsProvider =
    AsyncNotifierProvider<
      WatchPartyConnectionSettingsController,
      WatchPartyConnectionSettings
    >(WatchPartyConnectionSettingsController.new);

class WatchPartyConnectionSettings {
  const WatchPartyConnectionSettings({
    this.mode = WatchPartyConnectionMode.defaultConnection,
    this.relayUrl,
  });

  final WatchPartyConnectionMode mode;
  final String? relayUrl;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    if (relayUrl != null) 'relayUrl': relayUrl,
  };

  factory WatchPartyConnectionSettings.fromJson(Map<String, Object?> json) {
    final String? rawUrl = json['relayUrl'] as String?;
    String? normalizedUrl;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      try {
        normalizedUrl = WatchPartyRelayUrl.parse(rawUrl).toString();
      } on FormatException {
        normalizedUrl = null;
      }
    }
    return WatchPartyConnectionSettings(
      mode:
          json['mode'] == WatchPartyConnectionMode.selfHostedRelay.name &&
              normalizedUrl != null
          ? WatchPartyConnectionMode.selfHostedRelay
          : WatchPartyConnectionMode.defaultConnection,
      relayUrl: normalizedUrl,
    );
  }
}

class WatchPartyConnectionSettingsController
    extends AsyncNotifier<WatchPartyConnectionSettings> {
  static const String _key = 'mirushin.watch_party.connection.v1';

  @override
  Future<WatchPartyConnectionSettings> build() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const WatchPartyConnectionSettings();
    }
    try {
      return WatchPartyConnectionSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return const WatchPartyConnectionSettings();
    }
  }

  Future<void> saveRelay(String rawUrl) async {
    final Uri relay = WatchPartyRelayUrl.parse(rawUrl);
    await _save(
      WatchPartyConnectionSettings(
        mode: WatchPartyConnectionMode.selfHostedRelay,
        relayUrl: relay.toString(),
      ),
    );
  }

  Future<void> resetToDefault() => _save(const WatchPartyConnectionSettings());

  Future<void> useDefault() async {
    final WatchPartyConnectionSettings current =
        state.value ?? const WatchPartyConnectionSettings();
    await _save(WatchPartyConnectionSettings(relayUrl: current.relayUrl));
  }

  Future<void> _save(WatchPartyConnectionSettings value) async {
    state = AsyncData<WatchPartyConnectionSettings>(value);
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(value.toJson()));
  }
}

abstract final class WatchPartyRelayUrl {
  static Uri parse(String raw) {
    final String trimmed = raw.trim();
    final Uri? parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid relay URL.');
    }
    if (parsed.hasQuery || parsed.hasFragment) {
      throw const FormatException(
        'Relay URLs cannot contain a query or fragment.',
      );
    }
    final String scheme = parsed.scheme.toLowerCase();
    if (scheme != 'https' &&
        scheme != 'wss' &&
        scheme != 'http' &&
        scheme != 'ws') {
      throw const FormatException('Use an HTTPS or WSS relay URL.');
    }
    if ((scheme == 'http' || scheme == 'ws') && !_isLocalHost(parsed.host)) {
      throw const FormatException(
        'Unencrypted relay URLs are allowed only for localhost or private networks.',
      );
    }
    final String httpScheme = scheme == 'wss'
        ? 'https'
        : scheme == 'ws'
        ? 'http'
        : scheme;
    String path = parsed.path;
    while (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return parsed.replace(scheme: httpScheme, path: path == '/' ? '' : path);
  }

  static bool _isLocalHost(String host) {
    final String value = host.toLowerCase();
    if (value == 'localhost' ||
        value.endsWith('.localhost') ||
        value.endsWith('.local')) {
      return true;
    }
    if (value == '::1' ||
        (value.contains(':') &&
            (value.startsWith('fc') ||
                value.startsWith('fd') ||
                value.startsWith('fe80:')))) {
      return true;
    }
    final List<int>? parts = value.split('.').length == 4
        ? value.split('.').map(int.tryParse).whereType<int>().toList()
        : null;
    if (parts == null ||
        parts.length != 4 ||
        parts.any((int part) => part < 0 || part > 255)) {
      return false;
    }
    return parts[0] == 10 ||
        parts[0] == 127 ||
        (parts[0] == 192 && parts[1] == 168) ||
        (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
        (parts[0] == 169 && parts[1] == 254);
  }

  static Uri endpoint(Uri base, String suffix) {
    final String basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$suffix', query: null, fragment: null);
  }

  static Uri webSocketEndpoint(Uri base, String suffix) {
    final Uri endpointUri = endpoint(base, suffix);
    return endpointUri.replace(
      scheme: endpointUri.scheme == 'https' ? 'wss' : 'ws',
    );
  }

  static String origin(Uri relay) =>
      relay.replace(path: '', query: null, fragment: null).toString();
}
