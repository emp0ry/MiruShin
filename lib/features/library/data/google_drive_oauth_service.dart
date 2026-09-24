import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/auth_worker_proof.dart';

class GoogleDriveTokenBundle {
  const GoogleDriveTokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory GoogleDriveTokenBundle.fromJson(
    Map<String, dynamic> json, {
    String fallbackRefreshToken = '',
  }) {
    final int expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return GoogleDriveTokenBundle(
      accessToken: '${json['access_token'] ?? ''}'.trim(),
      refreshToken: '${json['refresh_token'] ?? fallbackRefreshToken}'.trim(),
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: expiresIn > 120 ? expiresIn - 60 : expiresIn),
      ),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

class GoogleDriveDeviceAuthorization {
  const GoogleDriveDeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.intervalSeconds,
    required this.codeVerifier,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final int intervalSeconds;
  final String codeVerifier;
}

class GoogleDriveOAuthException implements Exception {
  const GoogleDriveOAuthException({
    required this.operation,
    required this.code,
    required this.description,
    this.statusCode,
  });

  final String operation;
  final String code;
  final String description;
  final int? statusCode;

  @override
  String toString() {
    final String status = statusCode == null ? '' : ' [HTTP $statusCode]';
    final String reason = code.isEmpty ? '' : ' ($code)';
    return 'Google OAuth $operation failed$status$reason: $description';
  }
}

class GoogleDriveOAuthService {
  GoogleDriveOAuthService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _verifierChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String generateCodeVerifier() {
    final Random random = Random.secure();
    return List<String>.generate(
      96,
      (_) => _verifierChars[random.nextInt(_verifierChars.length)],
    ).join();
  }

  static String codeChallenge(String verifier) => base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', '');

  Uri buildAuthorizeUri({
    required String clientId,
    required String redirectUri,
    required String codeVerifier,
    required String state,
  }) {
    if (clientId.trim().isEmpty) {
      throw StateError('Google OAuth client id is not configured.');
    }
    return Uri.parse(AppConstants.googleOAuthAuthorizeUrl).replace(
      queryParameters: <String, String>{
        'client_id': clientId.trim(),
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'https://www.googleapis.com/auth/drive.appdata',
        'code_challenge': codeChallenge(codeVerifier),
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      },
    );
  }

  Future<GoogleDriveTokenBundle> exchangeCode({
    required String redirectUri,
    required String code,
    required String codeVerifier,
  }) async {
    final Response<dynamic> response = await _postToken(
      operation: 'token exchange',
      data: <String, String>{
        'platform': 'desktop',
        'redirect_uri': redirectUri,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
      },
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected Google OAuth token response.');
    }
    final GoogleDriveTokenBundle bundle = GoogleDriveTokenBundle.fromJson(data);
    if (bundle.accessToken.isEmpty || bundle.refreshToken.isEmpty) {
      throw StateError('Google OAuth did not return offline access.');
    }
    return bundle;
  }

  Future<GoogleDriveDeviceAuthorization> requestDeviceAuthorization() async {
    final String codeVerifier = generateCodeVerifier();
    final Response<dynamic> response = await _postWorker(
      url: AppConstants.googleOAuthProxyUrl,
      operation: 'device authorization',
      data: <String, String>{
        'provider': 'google',
        'action': 'device_code',
        'platform': 'tv',
        'code_challenge': codeChallenge(codeVerifier),
      },
    );
    final Map<String, dynamic> data = _responseMap(
      response.data,
      operation: 'device authorization',
    );
    final String deviceCode = '${data['device_code'] ?? ''}'.trim();
    final String userCode = '${data['user_code'] ?? ''}'.trim();
    final String verificationUrl =
        '${data['verification_uri'] ?? data['verification_url'] ?? ''}'.trim();
    final int expiresIn = (data['expires_in'] as num?)?.toInt() ?? 0;
    final int interval = (data['interval'] as num?)?.toInt() ?? 5;
    final Uri? verificationUri = Uri.tryParse(verificationUrl);
    if (deviceCode.isEmpty ||
        verificationUri == null ||
        !verificationUri.hasScheme ||
        expiresIn <= 0) {
      throw StateError('Unexpected Google OAuth device-code response.');
    }
    return GoogleDriveDeviceAuthorization(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      intervalSeconds: interval < 1 ? 5 : interval,
      codeVerifier: codeVerifier,
    );
  }

  Future<GoogleDriveTokenBundle> pollDeviceAuthorization({
    required GoogleDriveDeviceAuthorization authorization,
    bool Function()? isCancelled,
    Future<void> Function(Duration duration)? wait,
  }) async {
    final Future<void> Function(Duration) delay = wait ?? Future<void>.delayed;
    int intervalSeconds = authorization.intervalSeconds;
    while (DateTime.now().toUtc().isBefore(authorization.expiresAt)) {
      if (isCancelled?.call() == true) {
        throw const GoogleDriveOAuthException(
          operation: 'device authorization',
          code: 'canceled',
          description: 'Authorization was canceled.',
        );
      }
      await delay(Duration(seconds: intervalSeconds));
      if (isCancelled?.call() == true) {
        throw const GoogleDriveOAuthException(
          operation: 'device authorization',
          code: 'canceled',
          description: 'Authorization was canceled.',
        );
      }
      try {
        final Response<dynamic> response = await _postToken(
          operation: 'device authorization',
          data: <String, String>{
            'platform': 'tv',
            'device_code': authorization.deviceCode,
            'code_verifier': authorization.codeVerifier,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        );
        final Map<String, dynamic> data = _responseMap(
          response.data,
          operation: 'device authorization',
        );
        final GoogleDriveTokenBundle bundle = GoogleDriveTokenBundle.fromJson(
          data,
        );
        if (bundle.accessToken.isEmpty || bundle.refreshToken.isEmpty) {
          throw StateError('Google OAuth did not return offline access.');
        }
        return bundle;
      } on GoogleDriveOAuthException catch (error) {
        if (error.code == 'authorization_pending') continue;
        if (error.code == 'slow_down') {
          intervalSeconds += 5;
          continue;
        }
        rethrow;
      }
    }
    throw const GoogleDriveOAuthException(
      operation: 'device authorization',
      code: 'expired_token',
      description: 'The device code expired. Start the connection again.',
    );
  }

  Future<GoogleDriveTokenBundle> refresh({
    required String refreshToken,
    bool television = false,
  }) async {
    final Response<dynamic> response = await _postToken(
      operation: 'token refresh',
      data: <String, String>{
        'platform': television ? 'tv' : 'desktop',
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected Google OAuth refresh response.');
    }
    return GoogleDriveTokenBundle.fromJson(
      data,
      fallbackRefreshToken: refreshToken,
    );
  }

  Future<Response<dynamic>> _postToken({
    required String operation,
    required Map<String, String> data,
  }) {
    return _postWorker(
      url: AppConstants.googleOAuthProxyUrl,
      operation: operation,
      data: <String, String>{'provider': 'google', 'action': 'token', ...data},
    );
  }

  Future<Response<dynamic>> _postWorker({
    required String url,
    required String operation,
    required Map<String, String> data,
  }) async {
    try {
      return await _dio.post<dynamic>(
        url,
        data: data,
        options: Options(
          contentType: Headers.jsonContentType,
          headers: AuthWorkerProof.headers(),
        ),
      );
    } on DioException catch (error) {
      final Response<dynamic>? response = error.response;
      final Object? body = response?.data;
      final Map<dynamic, dynamic>? fields = body is Map<dynamic, dynamic>
          ? body
          : null;
      final String code = '${fields?['error'] ?? ''}'.trim();
      final String rawDescription = '${fields?['error_description'] ?? ''}'
          .trim();
      final String description = rawDescription.isNotEmpty
          ? rawDescription.replaceAll(RegExp(r'\s+'), ' ')
          : response == null
          ? 'Could not reach the MiruShin authorization service.'
          : 'Google rejected the OAuth request.';
      throw GoogleDriveOAuthException(
        operation: operation,
        code: code,
        description: description,
        statusCode: response?.statusCode,
      );
    }
  }

  Map<String, dynamic> _responseMap(
    Object? value, {
    required String operation,
  }) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map<dynamic, dynamic>) {
      return value.map(
        (dynamic key, dynamic item) => MapEntry<String, dynamic>('$key', item),
      );
    }
    throw StateError('Unexpected Google OAuth $operation response.');
  }
}
