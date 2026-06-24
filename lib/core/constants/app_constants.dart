import 'package:package_info_plus/package_info_plus.dart';

abstract final class AppConstants {
  static const String appName = 'MiruShin';
  static String appVersion = '';
  static const String githubProjectUrl = 'https://github.com/emp0ry/MiruShin';
  static const String githubLatestReleaseUrl =
      'https://github.com/emp0ry/MiruShin/releases/latest';
  static const String appWebsiteUrl = 'https://mirushin.emp0ry.com/';
  static const String discordRpcApplicationId = '1507695411635159110';
  static const String discordRpcLogoImageUrl =
      'https://github.com/emp0ry/MiruShin/blob/main/assets/icons/logo.png?raw=true';
  static const String tmdbAttribution =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';
  static const String aniListMobileClientId = '40342';
  static const String aniListDesktopClientId = '40343';
  static const int aniListDesktopCallbackPort = 28372;
  static const String aniListMobileRedirectUri = 'app://mirushin/auth';
  static const String aniListDesktopRedirectUri = 'http://localhost:28372/';
  static const String aniListRedirectScheme = 'app';
  static const String aniListRedirectHost = 'mirushin';
  static const String aniListRedirectPath = '/auth';

  // Redirect target shared by the authorization-code trackers (MAL, Shikimori).
  // On mobile the in-app WebView intercepts this URL before navigation; on
  // desktop the local callback server listens on the matching localhost port.
  static const String trackerRedirectScheme = 'app';
  static const String trackerRedirectHost = 'mirushin';
  static const String trackerRedirectPath = '/auth';
  static const String trackerMobileRedirectUri = 'app://mirushin/auth';

  // MyAnimeList OAuth2 (authorization code + PKCE, no client secret).
  static const String malAuthorizeUrl =
      'https://myanimelist.net/v1/oauth2/authorize';
  static const String malTokenUrl = 'https://myanimelist.net/v1/oauth2/token';
  static const String malAuthorizeProxyUrl =
      'https://auth.emp0ry.com/mal/authorize';
  static const String malTokenProxyUrl = 'https://auth.emp0ry.com/mal/token';
  static const String malApiBaseUrl = 'https://api.myanimelist.net/v2';
  static const int malDesktopCallbackPort = 28373;
  static const String malDesktopRedirectUri = 'http://localhost:28373/token';

  // Shikimori OAuth2. The default callback/token exchange goes through a
  // Cloudflare Worker so the app does not bundle the Shikimori client secret.
  static const String shikimoriAuthorizeUrl =
      'https://shikimori.io/oauth/authorize';
  static const String shikimoriTokenUrl = 'https://shikimori.io/oauth/token';
  static const String shikimoriAuthorizeProxyUrl =
      'https://auth.emp0ry.com/shikimori/authorize';
  static const String shikimoriTokenProxyUrl = 'https://auth.emp0ry.com/token';
  static const String shikimoriCallbackUrl = 'https://auth.emp0ry.com/callback';
  static const String shikimoriApiBaseUrl = 'https://shikimori.one';
  static const String shikimoriUserAgent = 'MiruShin';
  // Legacy OOB code page parsing fallback.
  static const String shikimoriOobRedirectUri = 'urn:ietf:wg:oauth:2.0:oob';
  static const String shikimoriOobHost = 'shikimori.one';
  static const String shikimoriOobCodePathPrefix = '/oauth/authorize/';

  static Future<void> init() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        appVersion = info.buildNumber.isNotEmpty
            ? '${info.version}+${info.buildNumber}'
            : info.version;
      }
    } catch (_) {}
  }
}
