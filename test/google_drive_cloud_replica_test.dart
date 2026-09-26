import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/data/google_drive_cloud_replica.dart';

void main() {
  test('cancelling a Drive pass aborts its active HTTP work', () async {
    final CancelToken cancelToken = CancelToken()..cancel('app closing');
    final GoogleDriveCloudReplica replica = GoogleDriveCloudReplica(
      accessToken: 'access-token',
      cancelToken: cancelToken,
    );

    await expectLater(
      replica.readUsage(),
      throwsA(
        isA<DioException>().having(
          (DioException error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });

  test('cloud reset deletes only MiruShin appDataFolder records', () async {
    final Dio dio = Dio();
    final List<String> deleted = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.method == 'GET' && options.uri.path.endsWith('/files')) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: <String, dynamic>{
                  'files': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'manifest',
                      'name': 'mirushin.manifest.v1.json',
                      'size': '20',
                    },
                    <String, dynamic>{
                      'id': 'prefs',
                      'name': 'mirushin.preferences.segment.device.1.v1.json',
                      'size': '30',
                    },
                    <String, dynamic>{
                      'id': 'unrelated',
                      'name': 'another-app.json',
                      'size': '40',
                    },
                  ],
                },
              ),
            );
            return;
          }
          if (options.method == 'DELETE') {
            deleted.add(options.uri.pathSegments.last);
            handler.resolve(
              Response<void>(requestOptions: options, statusCode: 204),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request: ${options.method} ${options.uri}',
            ),
          );
        },
      ),
    );

    final List<(int, int)> progress = <(int, int)>[];
    final int count =
        await GoogleDriveCloudReplica(
          accessToken: 'access-token',
          dio: dio,
        ).deleteAllMiruShinData(
          onProgress: (int completed, int total) {
            progress.add((completed, total));
          },
        );

    expect(count, 2);
    expect(deleted, <String>['manifest', 'prefs']);
    expect(progress, <(int, int)>[(1, 2), (2, 2)]);
  });
}
