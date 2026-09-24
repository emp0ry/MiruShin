import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/data/google_drive_oauth_service.dart';

void main() {
  test(
    'desktop token exchange sends PKCE to Worker without a client secret',
    () async {
      final Dio dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                final Map<String, dynamic> fields = Map<String, dynamic>.from(
                  options.data as Map<dynamic, dynamic>,
                );
                expect(options.uri.path, '/token');
                expect(fields['provider'], 'google');
                expect(fields['action'], 'token');
                expect(fields['platform'], 'desktop');
                expect(fields.containsKey('client_id'), isFalse);
                expect(fields.containsKey('client_secret'), isFalse);
                expect(options.headers['x-mirushin-timestamp'], isNotEmpty);
                expect(options.headers['x-mirushin-signature'], isNotEmpty);
                expect(fields['redirect_uri'], 'http://127.0.0.1:28375/');
                expect(fields['code'], 'authorization-code');
                expect(fields['code_verifier'], 'pkce-verifier');
                expect(fields['grant_type'], 'authorization_code');
                handler.resolve(
                  Response<dynamic>(
                    requestOptions: options,
                    data: <String, dynamic>{
                      'access_token': 'access-token',
                      'refresh_token': 'refresh-token',
                      'expires_in': 3600,
                    },
                  ),
                );
              },
        ),
      );

      final GoogleDriveTokenBundle tokens =
          await GoogleDriveOAuthService(dio: dio).exchangeCode(
            redirectUri: 'http://127.0.0.1:28375/',
            code: 'authorization-code',
            codeVerifier: 'pkce-verifier',
          );

      expect(tokens.accessToken, 'access-token');
      expect(tokens.refreshToken, 'refresh-token');
    },
  );

  test('desktop refresh goes through Worker without a client secret', () async {
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final Map<String, dynamic> fields = Map<String, dynamic>.from(
            options.data as Map<dynamic, dynamic>,
          );
          expect(options.uri.path, '/token');
          expect(fields['provider'], 'google');
          expect(fields['action'], 'token');
          expect(fields['platform'], 'desktop');
          expect(fields.containsKey('client_id'), isFalse);
          expect(fields.containsKey('client_secret'), isFalse);
          expect(fields['refresh_token'], 'refresh-token');
          expect(fields['grant_type'], 'refresh_token');
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: <String, dynamic>{
                'access_token': 'new-access-token',
                'expires_in': 3600,
              },
            ),
          );
        },
      ),
    );

    final GoogleDriveTokenBundle tokens = await GoogleDriveOAuthService(
      dio: dio,
    ).refresh(refreshToken: 'refresh-token');

    expect(tokens.accessToken, 'new-access-token');
    expect(tokens.refreshToken, 'refresh-token');
  });

  test('TV device flow requests a code and respects Google polling', () async {
    final Dio dio = Dio();
    int pollCount = 0;
    String? deviceChallenge;
    final List<Duration> waits = <Duration>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final Map<String, dynamic> fields = Map<String, dynamic>.from(
            options.data as Map<dynamic, dynamic>,
          );
          if (fields['action'] == 'device_code') {
            expect(options.uri.path, '/token');
            expect(fields['provider'], 'google');
            expect(fields['platform'], 'tv');
            deviceChallenge = '${fields['code_challenge']}';
            expect(deviceChallenge, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
            expect(fields.containsKey('client_id'), isFalse);
            expect(fields.containsKey('client_secret'), isFalse);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: <String, dynamic>{
                  'device_code': 'device-code',
                  'user_code': 'ABCD-EFGH',
                  'verification_url': 'https://www.google.com/device',
                  'expires_in': 1800,
                  'interval': 5,
                },
              ),
            );
            return;
          }

          pollCount += 1;
          expect(options.uri.path, '/token');
          expect(fields['provider'], 'google');
          expect(fields['action'], 'token');
          expect(fields['platform'], 'tv');
          expect(fields.containsKey('client_id'), isFalse);
          expect(fields.containsKey('client_secret'), isFalse);
          expect(fields['device_code'], 'device-code');
          expect(
            GoogleDriveOAuthService.codeChallenge('${fields['code_verifier']}'),
            deviceChallenge,
          );
          expect(
            fields['grant_type'],
            'urn:ietf:params:oauth:grant-type:device_code',
          );
          if (pollCount <= 2) {
            final String code = pollCount == 1
                ? 'authorization_pending'
                : 'slow_down';
            handler.reject(
              DioException.badResponse(
                statusCode: pollCount == 1 ? 428 : 403,
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: pollCount == 1 ? 428 : 403,
                  data: <String, dynamic>{
                    'error': code,
                    'error_description': 'Keep polling.',
                  },
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: <String, dynamic>{
                'access_token': 'tv-access-token',
                'refresh_token': 'tv-refresh-token',
                'expires_in': 3600,
              },
            ),
          );
        },
      ),
    );
    final GoogleDriveOAuthService service = GoogleDriveOAuthService(dio: dio);

    final GoogleDriveDeviceAuthorization authorization = await service
        .requestDeviceAuthorization();
    final GoogleDriveTokenBundle tokens = await service.pollDeviceAuthorization(
      authorization: authorization,
      wait: (Duration duration) async => waits.add(duration),
    );

    expect(authorization.userCode, 'ABCD-EFGH');
    expect(
      authorization.verificationUri,
      Uri.parse('https://www.google.com/device'),
    );
    expect(waits, const <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ]);
    expect(tokens.accessToken, 'tv-access-token');
    expect(tokens.refreshToken, 'tv-refresh-token');
  });

  test(
    'Google token errors are concise and preserve provider details',
    () async {
      final Dio dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                handler.reject(
                  DioException.badResponse(
                    statusCode: 400,
                    requestOptions: options,
                    response: Response<dynamic>(
                      requestOptions: options,
                      statusCode: 400,
                      data: <String, dynamic>{
                        'error': 'invalid_grant',
                        'error_description': 'Bad code.\nTry signing in again.',
                      },
                    ),
                  ),
                );
              },
        ),
      );

      await expectLater(
        GoogleDriveOAuthService(dio: dio).exchangeCode(
          redirectUri: 'http://127.0.0.1:28375/',
          code: 'authorization-code',
          codeVerifier: 'pkce-verifier',
        ),
        throwsA(
          isA<GoogleDriveOAuthException>().having(
            (GoogleDriveOAuthException error) => error.toString(),
            'message',
            'Google OAuth token exchange failed [HTTP 400] (invalid_grant): '
                'Bad code. Try signing in again.',
          ),
        ),
      );
    },
  );

  test('TV refresh selects the TV Worker credential set', () async {
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final Map<String, dynamic> fields = Map<String, dynamic>.from(
            options.data as Map<dynamic, dynamic>,
          );
          expect(options.uri.path, '/token');
          expect(fields['provider'], 'google');
          expect(fields['action'], 'token');
          expect(fields['platform'], 'tv');
          expect(fields.containsKey('client_secret'), isFalse);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: <String, dynamic>{
                'access_token': 'tv-new-access-token',
                'expires_in': 3600,
              },
            ),
          );
        },
      ),
    );

    final GoogleDriveTokenBundle tokens = await GoogleDriveOAuthService(
      dio: dio,
    ).refresh(refreshToken: 'tv-refresh-token', television: true);

    expect(tokens.accessToken, 'tv-new-access-token');
    expect(tokens.refreshToken, 'tv-refresh-token');
  });
}
