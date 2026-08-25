import 'dart:io';

/// Returns an explicit edge IP carried by a signed media URL, when present.
/// This is intentionally based only on URL metadata and never on a host name.
String? explicitMediaEdgeAddress(Uri uri) {
  final String? rawAddresses = uri.queryParameters['urls'];
  if (rawAddresses == null || rawAddresses.trim().isEmpty) return null;

  for (final String candidate in rawAddresses.split(RegExp(r'[,;|]'))) {
    final String trimmed = candidate.trim();
    if (trimmed.isEmpty) continue;
    if (InternetAddress.tryParse(trimmed) != null) return trimmed;
  }

  final Match? match = RegExp(
    r'(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)',
  ).firstMatch(rawAddresses);
  final String? address = match?.group(0);
  return address != null && InternetAddress.tryParse(address) != null
      ? address
      : null;
}

bool mediaUrlRequiresPinnedProxy(String? url) {
  if (url == null || url.trim().isEmpty) return false;
  final Uri? uri = Uri.tryParse(url);
  return uri != null && explicitMediaEdgeAddress(uri) != null;
}
