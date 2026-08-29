import 'watch_party_models.dart';

/// QR payload helpers for watch-party pairing. Default rooms keep the original
/// code URI; relay rooms also carry their relay origin and guest join token.

const String _qrPrefix = 'mirushin://watch-party/join?code=';

final RegExp _codePattern = RegExp(r'^[A-Z0-9]{6}$');

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
    final String query = Uri(
      queryParameters: <String, String>{
        'room': roomId,
        'transport': 'relay',
        'relay': relayUrl.toString(),
        'token': joinToken!,
      },
    ).query;
    return 'mirushin:///watch-party/join?$query';
  }

  static WatchPartyInvite? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final String value = raw.trim();
    final Uri? uri = Uri.tryParse(value);
    if (uri?.queryParameters['transport'] == 'relay') {
      final bool validRoute =
          (uri!.scheme == 'mirushin' || uri.scheme.isEmpty) &&
          uri.path == '/watch-party/join';
      final String room = uri.queryParameters['room']?.trim() ?? '';
      final Uri? relay = Uri.tryParse(uri.queryParameters['relay'] ?? '');
      final String token = uri.queryParameters['token']?.trim() ?? '';
      if (!validRoute ||
          !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(room) ||
          relay == null ||
          relay.host.isEmpty ||
          !RegExp(r'^[A-Za-z0-9_-]{16,256}$').hasMatch(token)) {
        return null;
      }
      return WatchPartyInvite(
        roomId: room,
        mode: WatchPartyConnectionMode.selfHostedRelay,
        relayUrl: relay,
        joinToken: token,
      );
    }
    final String? code = decodeWatchPartyQr(value);
    return code == null ? null : WatchPartyInvite(roomId: code);
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

  final Uri? uri = Uri.tryParse(trimmed);
  final String? fromQuery = uri?.queryParameters['code'];
  if (fromQuery != null) {
    final String code = fromQuery.trim().toUpperCase();
    if (_codePattern.hasMatch(code)) return code;
  }

  final String bare = trimmed.toUpperCase();
  return _codePattern.hasMatch(bare) ? bare : null;
}
