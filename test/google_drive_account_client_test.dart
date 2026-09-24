import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/data/google_drive_account_client.dart';

void main() {
  test('loads the connected account through Drive about.get', () async {
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          expect(options.uri.path, '/drive/v3/about');
          expect(
            options.queryParameters['fields'],
            'user(displayName,emailAddress,photoLink,permissionId)',
          );
          expect(options.headers['Authorization'], 'Bearer access-token');
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              data: <String, dynamic>{
                'user': <String, dynamic>{
                  'permissionId': 'drive-user-id',
                  'displayName': 'MiruShin User',
                  'emailAddress': 'user@example.com',
                  'photoLink': 'https://example.com/avatar.png',
                },
              },
            ),
          );
        },
      ),
    );

    final GoogleDriveAccountProfile profile = await GoogleDriveAccountClient(
      dio: dio,
    ).fetchProfile('access-token');

    expect(profile.id, 'drive-user-id');
    expect(profile.displayName, 'MiruShin User');
    expect(profile.email, 'user@example.com');
    expect(profile.avatarUrl, 'https://example.com/avatar.png');
    expect(
      GoogleDriveAccountProfile.fromStoredJson(profile.toJson()).email,
      'user@example.com',
    );
  });
}
