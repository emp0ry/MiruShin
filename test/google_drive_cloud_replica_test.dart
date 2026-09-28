import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/data/google_drive_cloud_replica.dart';
import 'package:mirushin/features/library/domain/cloud_replica_models.dart';
import 'package:mirushin/features/settings/domain/preference_sync_models.dart';

void main() {
  test(
    'unchanged Drive change cursor does not enumerate appData files',
    () async {
      final Dio dio = Dio();
      final List<String> requests = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                requests.add(options.uri.path);
                if (options.uri.path.endsWith('/changes')) {
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: <String, dynamic>{
                        'changes': <Object>[],
                        'newStartPageToken': 'next-token',
                      },
                    ),
                  );
                  return;
                }
                handler.reject(
                  DioException(
                    requestOptions: options,
                    message: 'Unexpected Drive request',
                  ),
                );
              },
        ),
      );
      final DriveLibraryChanges changes = await GoogleDriveCloudReplica(
        accessToken: 'access-token',
        replicaNamespace: 'anilist-1',
        dio: dio,
      ).pullLibraryChanges(excluding: const <String>{}, pageToken: 'old-token');

      expect(changes.segments, isEmpty);
      expect(changes.nextPageToken, 'next-token');
      expect(changes.manifestChanged, isFalse);
      expect(requests, hasLength(1));
      expect(requests.single, endsWith('/changes'));
    },
  );

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

  test(
    'one malformed preference segment does not block valid replicas',
    () async {
      final PreferenceReplicaSegment valid = PreferenceReplicaSegment(
        deviceId: 'valid-device',
        revision: 3,
        createdAt: DateTime.utc(2026, 9, 27),
        values: const <String, PreferenceSyncValue>{},
        tombstones: const <String, PreferenceSyncVersion>{},
      );
      final Dio dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                if (options.method == 'GET' &&
                    options.uri.path.endsWith('/files') &&
                    options.queryParameters['alt'] != 'media') {
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: <String, dynamic>{
                        'files': <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'broken',
                            'name':
                                'mirushin.preferences.segment.broken.1.v1.json',
                          },
                          <String, dynamic>{
                            'id': 'valid',
                            'name': valid.fileName,
                          },
                        ],
                      },
                    ),
                  );
                  return;
                }
                if (options.method == 'GET' &&
                    options.uri.path.endsWith('/files/broken')) {
                  handler.resolve(
                    Response<dynamic>(requestOptions: options, data: '{broken'),
                  );
                  return;
                }
                if (options.method == 'GET' &&
                    options.uri.path.endsWith('/files/valid')) {
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: valid.encode(),
                    ),
                  );
                  return;
                }
                handler.reject(
                  DioException(
                    requestOptions: options,
                    message:
                        'Unexpected request: ${options.method} ${options.uri}',
                  ),
                );
              },
        ),
      );

      final List<PreferenceReplicaSegment> pulled =
          await GoogleDriveCloudReplica(
            accessToken: 'access-token',
            dio: dio,
          ).pullPreferenceSegments(excluding: const <String>{});

      expect(pulled, hasLength(1));
      expect(pulled.single.fileName, valid.fileName);
    },
  );
}
