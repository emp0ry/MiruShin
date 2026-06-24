import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import 'oauth_token_bundle.dart';

/// Shikimori OAuth2 (authorization code).
///
/// The bundled app exchanges and refreshes tokens through a small Worker so the
/// Shikimori client secret is not shipped in release binaries. User-supplied
/// custom credentials still use Shikimori directly.
class ShikimoriOAuthService {
  ShikimoriOAuthService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Scope needed to read and write the signed-in user's anime rates.
  static const String scope = 'user_rates';

  Uri buildAuthorizeUri({
    required String clientId,
    required String redirectUri,
    required String state,
  }) {
    if (clientId.trim().isEmpty) {
      return Uri.parse(AppConstants.shikimoriAuthorizeProxyUrl).replace(
        queryParameters: <String, String>{
          'state': state,
        },
      );
    }

    return Uri.parse(AppConstants.shikimoriAuthorizeUrl).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId.trim(),
        'redirect_uri': redirectUri,
        'scope': scope,
        'state': state,
      },
    );
  }

  Future<OAuthTokenBundle> exchangeCode({
    required String clientId,
    required String clientSecret,
    required String code,
    required String redirectUri,
  }) {
    final String secret = clientSecret.trim();
    if (secret.isEmpty) {
      return _tokenViaProxy(<String, String>{
        'grant_type': 'authorization_code',
        'code': code,
      });
    }

    return _tokenDirect(<String, String>{
      'grant_type': 'authorization_code',
      'client_id': clientId.trim(),
      'client_secret': secret,
      'code': code,
      'redirect_uri': redirectUri,
    });
  }

  Future<OAuthTokenBundle> refresh({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) {
    final String secret = clientSecret.trim();
    if (secret.isEmpty) {
      return _tokenViaProxy(<String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });
    }

    return _tokenDirect(<String, String>{
      'grant_type': 'refresh_token',
      'client_id': clientId.trim(),
      'client_secret': secret,
      'refresh_token': refreshToken,
    });
  }

  Future<OAuthTokenBundle> _tokenViaProxy(Map<String, String> payload) {
    return _postToken(
      AppConstants.shikimoriTokenProxyUrl,
      data: payload,
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<OAuthTokenBundle> _tokenDirect(Map<String, String> form) {
    return _postToken(
      AppConstants.shikimoriTokenUrl,
      data: form,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: <String, String>{
          'User-Agent': AppConstants.shikimoriUserAgent,
        },
      ),
    );
  }

  Future<OAuthTokenBundle> _postToken(
    String url, {
    required Object data,
    required Options options,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      url,
      data: data,
      options: options,
    );
    final Object? responseData = response.data;
    if (responseData is! Map<String, dynamic>) {
      throw StateError('Unexpected Shikimori token response.');
    }
    final OAuthTokenBundle bundle = OAuthTokenBundle.fromTokenResponse(
      responseData,
    );
    if (bundle.accessToken.isEmpty) {
      throw StateError(
        'Shikimori token response did not include an access token.',
      );
    }
    return bundle;
  }
}
