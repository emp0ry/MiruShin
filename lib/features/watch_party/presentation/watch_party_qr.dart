/// QR payload helpers for watch-party pairing. The payload is a small custom
/// URI carrying just the room code, with a plain 6-char-code fallback so a code
/// typed by hand and a scanned QR both work.
const String _qrPrefix = 'mirushin://watch-party/join?code=';

final RegExp _codePattern = RegExp(r'^[A-Z0-9]{6}$');

String encodeWatchPartyQr(String code) => '$_qrPrefix$code';

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
