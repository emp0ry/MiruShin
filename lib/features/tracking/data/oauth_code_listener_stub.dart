import 'oauth_token_bundle.dart';

/// Web stub: localhost listeners are unavailable in the browser, so callers
/// fall back to manual paste of the redirected URL.
class OAuthCodeListener {
  Future<OAuthCodeResult?> wait() async => null;

  Future<void> cancel() async {}
}

Future<OAuthCodeListener> startOAuthCodeListener({required int port}) {
  throw UnsupportedError('Localhost OAuth listener is not available here.');
}
