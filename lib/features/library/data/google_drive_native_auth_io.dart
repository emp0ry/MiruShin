import 'dart:async';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/platform/tv_platform.dart';

class GoogleDriveNativeAuthService {
  const GoogleDriveNativeAuthService();

  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;

  static bool get isSupported =>
      Platform.isIOS || (Platform.isAndroid && !TvPlatform.isAndroidTv);

  Future<String> signIn() async {
    _requireSupported();
    await _initialize();
    final GoogleSignInAccount account = await _signIn.authenticate(
      scopeHint: _scopes,
    );
    final GoogleSignInClientAuthorization authorization =
        await account.authorizationClient.authorizationForScopes(_scopes) ??
        await account.authorizationClient.authorizeScopes(_scopes);
    return authorization.accessToken;
  }

  Future<String?> restoreAccessToken() async {
    if (!isSupported) return null;
    await _initialize();
    final Future<GoogleSignInAccount?>? attempt = _signIn
        .attemptLightweightAuthentication();
    final GoogleSignInAccount? account = attempt == null ? null : await attempt;
    if (account == null) return null;
    final GoogleSignInClientAuthorization? authorization = await account
        .authorizationClient
        .authorizationForScopes(_scopes);
    return authorization?.accessToken;
  }

  Future<void> signOut() async {
    if (!isSupported) return;
    await _initialize();
    // Sign out only on this device. disconnect() revokes the whole Google
    // project's grant and would also invalidate other MiruShin devices.
    await _signIn.signOut();
  }

  static Future<void> _initialize() {
    _requireSupported();
    return _initialization ??= _signIn.initialize(
      clientId: Platform.isIOS ? AppConstants.googleOAuthIosClientId : null,
      serverClientId: Platform.isAndroid
          ? AppConstants.googleOAuthWebClientId
          : null,
    );
  }

  static void _requireSupported() {
    if (!isSupported) {
      throw UnsupportedError(
        'Native Google authorization is unavailable on this platform.',
      );
    }
  }
}
