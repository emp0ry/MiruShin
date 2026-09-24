import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

abstract final class AppConstants {
  static const String appName = 'MiruShin';
  static String appVersion = '';
  static const String githubLatestReleaseUrl =
      'https://github.com/emp0ry/MiruShin/releases/latest';
  static const String appWebsiteUrl = 'https://mirushin.emp0ry.com/';
  static const String supportUrl = 'https://buymeacoffee.com/emp0ry';
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
  static const String trackerMobileRedirectUri = 'app://mirushin/auth';

  // Google Drive appDataFolder sync. OAuth client ids are public application
  // identifiers. Desktop/TV token exchange is proxied through mirushin-auth so
  // no Google client secret is ever included in a Flutter or Web build.
  static const String _googleOAuthClientIdOverride = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
  );
  static const String googleOAuthAndroidClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID_ANDROID',
    defaultValue:
        '77095881269-0e650r5a4va10mg58in43jp44vare97a.apps.googleusercontent.com',
  );
  static const String googleOAuthIosClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID_IOS',
    defaultValue:
        '77095881269-gaji31e827i85ro8loeu2srbegektntu.apps.googleusercontent.com',
  );
  static const String googleOAuthDesktopClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID_DESKTOP',
    defaultValue:
        '77095881269-macrb5098to4uirb3v4c5rolqi96fl8o.apps.googleusercontent.com',
  );
  static const String googleOAuthTvClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID_TV',
    defaultValue:
        '77095881269-6kojpc9iivfodvqimj2lp2346mvodo6v.apps.googleusercontent.com',
  );
  static const String googleOAuthWebClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID_WEB',
    defaultValue:
        '77095881269-gpka49ipagksvge36o4qdqbudaduc6eg.apps.googleusercontent.com',
  );

  // The existing PKCE + loopback implementation is used on desktop. Android
  // and iOS use the native Google authorization SDK; Android's SDK requires
  // the Web client id as its serverClientId while the Android client registered
  // in Google Cloud validates this package name and signing certificate.
  static String get googleOAuthClientId {
    if (_googleOAuthClientIdOverride.trim().isNotEmpty) {
      return _googleOAuthClientIdOverride.trim();
    }
    if (kIsWeb) return googleOAuthWebClientId.trim();
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => googleOAuthDesktopClientId,
      TargetPlatform.android => googleOAuthWebClientId,
      TargetPlatform.iOS => googleOAuthIosClientId,
      TargetPlatform.fuchsia => '',
    };
  }

  static bool get googleOAuthConfigured {
    if (kIsWeb) return googleOAuthClientId.trim().isNotEmpty;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        googleOAuthAndroidClientId.trim().isNotEmpty &&
            googleOAuthClientId.trim().isNotEmpty,
      TargetPlatform.iOS => googleOAuthClientId.trim().isNotEmpty,
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => googleOAuthClientId.trim().isNotEmpty,
      TargetPlatform.fuchsia => false,
    };
  }

  // Android TV uses the Web OAuth client through an ephemeral Worker/PKCE QR
  // handoff because Google's live device endpoint rejects Drive appdata even
  // though it is still documented as an allowed Limited Input scope.
  static bool get googleOAuthTvConfigured =>
      googleOAuthWebClientId.trim().isNotEmpty;

  static const int googleOAuthDesktopCallbackPort = 28375;
  static const String googleOAuthDesktopRedirectUri = 'http://127.0.0.1:28375/';
  static const String googleOAuthAuthorizeUrl =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String googleOAuthProxyUrl = 'https://auth.emp0ry.com/token';
  static const String googleDriveApiBaseUrl =
      'https://www.googleapis.com/drive/v3';
  static const String googleDriveUploadBaseUrl =
      'https://www.googleapis.com/upload/drive/v3';

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
  // Desktop: the Worker callback page forwards the code to this localhost
  // listener so the app captures it automatically (like MAL/AniList) instead of
  // making the user copy it by hand.
  static const int shikimoriDesktopCallbackPort = 28374;
  // Canonical API host. shikimori.one redirects here, but the cross-host
  // redirect strips the Authorization header. Authenticated calls such as
  // whoami and user_rates must target shikimori.io directly.
  static const String shikimoriApiBaseUrl = 'https://shikimori.io';
  static const String shikimoriUserAgent = 'MiruShin';
  // Legacy OOB code page parsing fallback.
  static const String shikimoriOobRedirectUri = 'urn:ietf:wg:oauth:2.0:oob';
  static const String shikimoriOobHost = 'shikimori.one';
  static const String shikimoriOobCodePathPrefix = '/oauth/authorize/';

  // Watch-party WebRTC signaling lives in the same Worker (mirushin-auth). It is
  // used only for temporary pairing; once the P2P DataChannel opens the room is
  // deleted and all playback sync flows directly between peers.
  static const String watchPartyBaseUrl = 'https://auth.emp0ry.com/watch-party';
  // Lightweight anti-abuse proof shared with mirushin-auth. This is a speed bump
  // against generic scripts, not a true secret once the app is distributed.
  static const String authWorkerProofSecret =
      'mirushin-auth-proof-v1-2e2f2fe7f1194af4a2c0d517d316fd3a';

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
