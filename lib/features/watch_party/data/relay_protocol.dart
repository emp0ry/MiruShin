abstract final class WatchPartyRelayProtocol {
  static const String service = 'mirushin-watch-party-relay';
  static const String protocol = 'mirushin-watch-party';
  static const int version = 1;
  static const int maximumClientMessageBytes = 64 * 1024;
}

class WatchPartyRelayException implements Exception {
  const WatchPartyRelayException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class RelayHealthResult {
  const RelayHealthResult({required this.protocolVersion});

  final int protocolVersion;
}
