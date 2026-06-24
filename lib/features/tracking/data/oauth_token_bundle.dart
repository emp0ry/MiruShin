/// Tokens returned by an OAuth2 authorization-code exchange or refresh.
///
/// Shared by the MyAnimeList and Shikimori trackers, both of which use the
/// authorization-code flow with refresh tokens (unlike AniList's long-lived
/// implicit token).
class OAuthTokenBundle {
  const OAuthTokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  factory OAuthTokenBundle.fromTokenResponse(Map<String, dynamic> json) {
    final Object? expiresIn = json['expires_in'];
    final int seconds = expiresIn is num
        ? expiresIn.toInt()
        : int.tryParse('${expiresIn ?? ''}') ?? 3600;
    return OAuthTokenBundle(
      accessToken: '${json['access_token'] ?? ''}'.trim(),
      refreshToken: '${json['refresh_token'] ?? ''}'.trim(),
      // Refresh a little early to avoid racing the server-side expiry.
      expiresAt: DateTime.now().add(Duration(seconds: seconds - 60)),
    );
  }
}

/// The authorization `code` (and optional `state`) captured from an OAuth2
/// redirect, before it is exchanged for tokens.
class OAuthCodeResult {
  const OAuthCodeResult({required this.code, this.state});

  final String code;
  final String? state;
}
