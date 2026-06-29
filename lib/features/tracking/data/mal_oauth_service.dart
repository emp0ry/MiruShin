import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/auth_worker_proof.dart';
import 'oauth_token_bundle.dart';

/// MyAnimeList OAuth2 (authorization code + PKCE).
///
/// MAL is a public client: it supports PKCE with `code_challenge_method=plain`
/// only (the challenge equals the verifier) and requires no client secret on
/// the token exchange.
class MalOAuthService {
  MalOAuthService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _pkceChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a PKCE code verifier. With `plain`, this value is also the
  /// `code_challenge` sent on the authorize request.
  static String generateCodeVerifier() {
    final Random random = Random.secure();
    return List<String>.generate(
      96,
      (_) => _pkceChars[random.nextInt(_pkceChars.length)],
    ).join();
  }

  Uri buildAuthorizeUri({
    required String clientId,
    required String codeChallenge,
    required String redirectUri,
    required String state,
  }) {
    if (clientId.trim().isEmpty) {
      return Uri.parse(AppConstants.malAuthorizeProxyUrl).replace(
        queryParameters: <String, String>{
          'platform': _platformForRedirectUri(redirectUri),
          'code_challenge': codeChallenge,
          'redirect_uri': redirectUri,
          'state': state,
          ...AuthWorkerProof.queryParameters(),
        },
      );
    }

    return Uri.parse(AppConstants.malAuthorizeUrl).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId.trim(),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'plain',
        'redirect_uri': redirectUri,
        'state': state,
      },
    );
  }

  Future<OAuthTokenBundle> exchangeCode({
    required String clientId,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) {
    if (clientId.trim().isEmpty) {
      return _tokenViaProxy(<String, String>{
        'platform': _platformForRedirectUri(redirectUri),
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': codeVerifier,
        'redirect_uri': redirectUri,
      });
    }

    return _token(<String, String>{
      'client_id': clientId.trim(),
      'grant_type': 'authorization_code',
      'code': code,
      'code_verifier': codeVerifier,
      'redirect_uri': redirectUri,
    });
  }

  Future<OAuthTokenBundle> refresh({
    required String clientId,
    required String refreshToken,
    required bool isMobile,
  }) {
    if (clientId.trim().isEmpty) {
      return _tokenViaProxy(<String, String>{
        'platform': isMobile ? 'mobile' : 'desktop',
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });
    }

    return _token(<String, String>{
      'client_id': clientId.trim(),
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
  }

  Future<OAuthTokenBundle> _tokenViaProxy(Map<String, String> payload) {
    return _postToken(
      AppConstants.malTokenProxyUrl,
      data: payload,
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: AuthWorkerProof.headers(),
      ),
    );
  }

  Future<OAuthTokenBundle> _token(Map<String, String> form) async {
    return _postToken(
      AppConstants.malTokenUrl,
      data: form,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
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
      throw StateError('Unexpected MAL token response.');
    }
    final OAuthTokenBundle bundle = OAuthTokenBundle.fromTokenResponse(
      responseData,
    );
    if (bundle.accessToken.isEmpty) {
      throw StateError('MAL token response did not include an access token.');
    }
    return bundle;
  }

  String _platformForRedirectUri(String redirectUri) {
    return redirectUri == AppConstants.trackerMobileRedirectUri
        ? 'mobile'
        : 'desktop';
  }
}
