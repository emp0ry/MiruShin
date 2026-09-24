import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/app_constants.dart';

/// Browser authorization uses Google Identity Services' token model. It does
/// not use a client secret or persist a refresh token in browser storage.
class GoogleDriveNativeAuthService {
  const GoogleDriveNativeAuthService();

  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;

  static bool get isSupported => true;

  Future<String> signIn() async {
    await _initialize();
    final GoogleSignInClientAuthorization authorization = await _signIn
        .authorizationClient
        .authorizeScopes(_scopes);
    return authorization.accessToken;
  }

  Future<String?> restoreAccessToken() async {
    await _initialize();
    final GoogleSignInClientAuthorization? authorization = await _signIn
        .authorizationClient
        .authorizationForScopes(_scopes);
    return authorization?.accessToken;
  }

  Future<void> signOut() async {
    await _initialize();
    await _signIn.signOut();
  }

  static Future<void> _initialize() {
    return _initialization ??= _signIn.initialize(
      clientId: AppConstants.googleOAuthWebClientId,
    );
  }
}
