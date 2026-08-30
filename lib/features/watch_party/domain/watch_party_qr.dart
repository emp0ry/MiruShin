import '../application/watch_party_connection_settings.dart';
import 'watch_party_models.dart';

/// QR payload helpers for watch-party pairing. Default rooms keep the original
/// code URI; relay rooms also carry their relay origin and guest join token.

const String _qrPrefix = 'mirushin://watch-party/join?code=';
const int _maximumInviteLength = 4096;

final RegExp _codePattern = RegExp(r'^[A-Z0-9]{6}$');
final RegExp _relayRoomPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
final RegExp _relayTokenPattern = RegExp(r'^[A-Za-z0-9_-]{16,256}$');

String encodeWatchPartyQr(String code) => '$_qrPrefix$code';

class WatchPartyInvite {
  const WatchPartyInvite({
    required this.roomId,
    this.mode = WatchPartyConnectionMode.defaultConnection,
    this.relayUrl,
    this.joinToken,
  });

  final String roomId;
  final WatchPartyConnectionMode mode;
  final Uri? relayUrl;
  final String? joinToken;

  bool get isRelay => mode == WatchPartyConnectionMode.selfHostedRelay;

  String encode() {
    if (!isRelay) return encodeWatchPartyQr(roomId);
    final Uri relay = WatchPartyRelayUrl.parse(relayUrl.toString());
    return WatchPartyRelayUrl.endpoint(relay, '/join')
        .replace(
          queryParameters: <String, String>{
            'room': roomId,
            'token': joinToken!,
          },
        )
        .toString();
  }

  static WatchPartyInvite? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final String value = raw.trim();
    if (value.length > _maximumInviteLength) return null;
    try {
      return _tryParse(value, allowBridge: true);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static WatchPartyInvite? _tryParse(
    String value, {
    required bool allowBridge,
  }) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) return null;

    if (_isMiruShinJoinRoute(uri)) {
      final Map<String, List<String>> parameters = uri.queryParametersAll;
      if (allowBridge && _hasExactParameters(parameters, <String>{'invite'})) {
        final String nested = parameters['invite']!.single.trim();
        if (nested.isEmpty || nested.length > _maximumInviteLength) return null;
        final Uri? nestedUri = Uri.tryParse(nested);
        if (nestedUri == null ||
            (nestedUri.scheme != 'https' && nestedUri.scheme != 'http')) {
          return null;
        }
        return _tryParse(nested, allowBridge: false);
      }

      if (_hasExactParameters(parameters, <String>{'code'})) {
        final String code = parameters['code']!.single.trim().toUpperCase();
        return _codePattern.hasMatch(code)
            ? WatchPartyInvite(roomId: code)
            : null;
      }

      // Backward compatibility for relay invites emitted before the HTTPS
      // landing-page contract. New invites are never generated in this form.
      if (_hasExactParameters(parameters, <String>{
            'room',
            'transport',
            'relay',
            'token',
          }) &&
          parameters['transport']!.single == 'relay') {
        final String room = parameters['room']!.single.trim();
        final String token = parameters['token']!.single.trim();
        if (!_relayRoomPattern.hasMatch(room) ||
            !_relayTokenPattern.hasMatch(token)) {
          return null;
        }
        final Uri relay = WatchPartyRelayUrl.parse(parameters['relay']!.single);
        return WatchPartyInvite(
          roomId: room,
          mode: WatchPartyConnectionMode.selfHostedRelay,
          relayUrl: relay,
          joinToken: token,
        );
      }
      return null;
    }

    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return _tryParseRelayLandingUri(uri);
    }

    final String bare = value.toUpperCase();
    return _codePattern.hasMatch(bare) ? WatchPartyInvite(roomId: bare) : null;
  }

  static WatchPartyInvite? _tryParseRelayLandingUri(Uri uri) {
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
      return null;
    }
    final Map<String, List<String>> parameters = uri.queryParametersAll;
    if (!_hasExactParameters(parameters, <String>{'room', 'token'})) {
      return null;
    }
    final List<String> segments = uri.pathSegments;
    if (segments.isEmpty || segments.last != 'join') return null;

    final String room = parameters['room']!.single.trim();
    final String token = parameters['token']!.single.trim();
    if (!_relayRoomPattern.hasMatch(room) ||
        !_relayTokenPattern.hasMatch(token)) {
      return null;
    }

    final List<String> baseSegments = segments.sublist(0, segments.length - 1);
    final Uri relay = WatchPartyRelayUrl.parse(
      Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        pathSegments: baseSegments,
      ).toString(),
    );
    return WatchPartyInvite(
      roomId: room,
      mode: WatchPartyConnectionMode.selfHostedRelay,
      relayUrl: relay,
      joinToken: token,
    );
  }
}

/// Extracts a 6-character room code from a scanned QR value (either the custom
/// URI or a bare code), or null when none is present.
///
/// The URI's `code` query parameter is checked first; only if that is absent do
/// we treat the whole value as a bare code. (A naive "first 6 alphanumerics"
/// scan would wrongly match "MIRUSH" inside the `mirushin://` scheme.)
String? decodeWatchPartyQr(String? raw) {
  if (raw == null) return null;
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  try {
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri != null && _isMiruShinJoinRoute(uri)) {
      final Map<String, List<String>> parameters = uri.queryParametersAll;
      if (_hasExactParameters(parameters, <String>{'code'})) {
        final String code = parameters['code']!.single.trim().toUpperCase();
        if (_codePattern.hasMatch(code)) return code;
      }
    }
  } on FormatException {
    return null;
  }

  final String bare = trimmed.toUpperCase();
  return _codePattern.hasMatch(bare) ? bare : null;
}

bool _isMiruShinJoinRoute(Uri uri) {
  if (uri.scheme.isEmpty) return uri.path == '/watch-party/join';
  if (uri.scheme.toLowerCase() != 'mirushin') return false;
  return (uri.host.toLowerCase() == 'watch-party' && uri.path == '/join') ||
      (uri.host.isEmpty && uri.path == '/watch-party/join');
}

bool _hasExactParameters(
  Map<String, List<String>> parameters,
  Set<String> expected,
) {
  return parameters.length == expected.length &&
      expected.every(
        (String key) => parameters[key] != null && parameters[key]!.length == 1,
      );
}
