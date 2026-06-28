/// Detects Cloudflare anti-bot interstitials ("Just a moment…" / Turnstile) in
/// the responses the Sora JS runtime gets back from Dio.
///
/// Cloudflare serves these as a `403`/`503` with a `Server: cloudflare` header
/// (or the newer `cf-mitigated: challenge` header) and an HTML body that wires
/// up the `cdn-cgi/challenge-platform` script. Plain HTTP clients can't pass the
/// challenge, so when one is detected the runtime hands off to an interactive
/// WebView that runs the challenge and captures the `cf_clearance` cookie.
class CloudflareChallenge {
  const CloudflareChallenge._();

  /// Status codes Cloudflare uses for managed challenges.
  static const Set<int> _challengeStatuses = <int>{403, 503};

  /// Substrings that only appear on a challenge/interstitial page.
  static const List<String> _bodyMarkers = <String>[
    'cdn-cgi/challenge-platform',
    '__cf_chl',
    'cf_chl_opt',
    'cf-browser-verification',
    'turnstile',
    'just a moment',
    'enable javascript and cookies to continue',
  ];

  /// Whether [status] + [headers] + [body] look like a Cloudflare challenge
  /// (as opposed to a genuine 403/503 from the origin).
  ///
  /// [headers] keys are matched case-insensitively; values may be a `String` or
  /// a `List<String>` (Dio exposes both shapes).
  static bool isChallenge(
    int? status,
    Map<String, dynamic> headers,
    String body,
  ) {
    if (status == null || !_challengeStatuses.contains(status)) return false;

    final String mitigated = _header(headers, 'cf-mitigated').toLowerCase();
    if (mitigated.contains('challenge')) return true;

    final bool servedByCloudflare =
        _header(headers, 'server').toLowerCase().contains('cloudflare');
    if (!servedByCloudflare) return false;

    final String haystack = body.toLowerCase();
    for (final String marker in _bodyMarkers) {
      if (haystack.contains(marker)) return true;
    }
    return false;
  }

  static String _header(Map<String, dynamic> headers, String name) {
    final String target = name.toLowerCase();
    for (final MapEntry<String, dynamic> entry in headers.entries) {
      if (entry.key.toLowerCase() != target) continue;
      final dynamic value = entry.value;
      if (value is List) return value.join(', ');
      return value?.toString() ?? '';
    }
    return '';
  }
}
