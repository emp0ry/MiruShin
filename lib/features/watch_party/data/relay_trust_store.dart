import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../application/watch_party_connection_settings.dart';

class RelayTrustStore {
  static const String _key = 'mirushin.watch_party.trusted_relays.v1';

  Future<bool> isTrusted(Uri relay) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return _read(preferences).contains(WatchPartyRelayUrl.origin(relay));
  }

  Future<void> trust(Uri relay) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final Set<String> origins = _read(preferences)
      ..add(WatchPartyRelayUrl.origin(relay));
    await preferences.setString(_key, jsonEncode(origins.toList()..sort()));
  }

  Set<String> _read(SharedPreferences preferences) {
    final String? raw = preferences.getString(_key);
    if (raw == null) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((dynamic value) => '$value')
          .toSet();
    } on Object {
      return <String>{};
    }
  }
}
