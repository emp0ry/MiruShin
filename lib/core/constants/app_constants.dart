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
