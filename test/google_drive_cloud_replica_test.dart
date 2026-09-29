import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/data/google_drive_cloud_replica.dart';
import 'package:mirushin/features/library/domain/cloud_replica_models.dart';
import 'package:mirushin/features/settings/domain/preference_sync_models.dart';

void main() {
  test('optimized Library checksum stays compatible with old v2 manifests', () {
    final DriveLibrarySnapshot snapshot = DriveLibrarySnapshot(
      snapshotId: 'new-envelope',
      deviceId: 'device-a',
      createdAt: DateTime.utc(2026, 9, 29),
      replicaNamespace: 'anilist:1',
      media: <Map<String, dynamic>>[
        <String, dynamic>{
          'localId': 'z',
          'media': <String, dynamic>{'title': 'Z'},
        },
        <String, dynamic>{
          'localId': 'a',
          'media': <String, dynamic>{'title': 'A'},
        },
      ],
      libraryEntries: <Map<String, dynamic>>[
        <String, dynamic>{'localId': 'z', 'inLibrary': true},
        <String, dynamic>{'localId': 'a', 'inLibrary': true},
      ],
      providerBindings: <Map<String, dynamic>>[
        <String, dynamic>{'localId': 'z', 'verifiedAtMs': 10},
      ],
      providerSnapshots: <Map<String, dynamic>>[
        <String, dynamic>{
          'localId': 'z',
          'fetchedAtMs': 20,
          'destructiveConfirmationCount': 1,
          'raw': <String, dynamic>{'notes': 'keep'},
        },
      ],
      episodeStates: const <Map<String, dynamic>>[],
      streamPreferences: const <Map<String, dynamic>>[],
      operations: const <Map<String, dynamic>>[],
    );
    List<Map<String, dynamic>> oldSort(List<Map<String, dynamic>> rows) =>
        <Map<String, dynamic>>[
          ...rows,
        ]..sort((left, right) => jsonEncode(left).compareTo(jsonEncode(right)));
    final String oldChecksum = sha256
        .convert(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'schemaVersion': 2,
              'replicaNamespace': snapshot.replicaNamespace,
              'entryCount': snapshot.entryCount,
              'media': oldSort(snapshot.media),
              'libraryEntries': oldSort(snapshot.libraryEntries),
              'providerBindings': oldSort(<Map<String, dynamic>>[
                <String, dynamic>{'localId': 'z'},
              ]),
              'providerSnapshots': oldSort(<Map<String, dynamic>>[
                <String, dynamic>{
                  'localId': 'z',
                  'raw': <String, dynamic>{'notes': 'keep'},
                },
              ]),
              'episodeStates': oldSort(snapshot.episodeStates),
              'streamPreferences': oldSort(snapshot.streamPreferences),
              'operations': oldSort(snapshot.operations),
            }),
          ),
        )
        .toString();
    expect(snapshot.checksum, oldChecksum);
  });

  test('unchanged backup is prepared off-isolate without re-upload', () async {
    final DriveLibrarySnapshot snapshot = DriveLibrarySnapshot(
      snapshotId: 'checkpoint',
      deviceId: 'device-a',
      createdAt: DateTime.utc(2026, 9, 29),
      replicaNamespace: 'anilist:1',
      media: const <Map<String, dynamic>>[],
      libraryEntries: const <Map<String, dynamic>>[],
      providerBindings: const <Map<String, dynamic>>[],
      providerSnapshots: const <Map<String, dynamic>>[],
      episodeStates: const <Map<String, dynamic>>[],
      streamPreferences: const <Map<String, dynamic>>[],
      operations: const <Map<String, dynamic>>[],
    );
    final Dio dio = Dio();
    var uploads = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.method == 'GET' && options.uri.path.endsWith('/files')) {
            final String query = '${options.queryParameters['q'] ?? ''}';
            final String name = query.contains(snapshot.fileName)
                ? snapshot.fileName
                : 'mirushin.anilist:1.manifest.v1.json';
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: <String, dynamic>{
                  'files': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': name == snapshot.fileName ? 'snapshot' : 'manifest',
                      'name': name,
                    },
                  ],
                },
              ),
            );
            return;
          }
          if (options.method == 'GET' &&
              options.uri.path.endsWith('/files/manifest')) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: jsonEncode(
                  DriveReplicaManifest(
                    snapshotChecksum: snapshot.checksum,
                  ).toJson(),
                ),
              ),
            );
            return;
          }
          uploads += 1;
          handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request: ${options.method} ${options.uri}',
            ),
          );
        },
      ),
    );
    final GoogleDriveCloudReplica replica = GoogleDriveCloudReplica(
      accessToken: 'access-token',
      replicaNamespace: 'anilist:1',
      dio: dio,
    );

    final CloudReplicaFile result = await replica.pushLibrarySnapshot(snapshot);
    expect(result.id, 'snapshot');
    expect(uploads, 0);
  });

  test('Library backup is decoded and verified off the UI isolate', () async {
    final DriveLibrarySnapshot snapshot = DriveLibrarySnapshot(
      snapshotId: 'checkpoint',
      deviceId: 'device-a',
      createdAt: DateTime.utc(2026, 9, 29),
      replicaNamespace: 'anilist:1',
      media: const <Map<String, dynamic>>[],
      libraryEntries: const <Map<String, dynamic>>[
        <String, dynamic>{'localId': 'a', 'inLibrary': true},
      ],
      providerBindings: const <Map<String, dynamic>>[],
      providerSnapshots: const <Map<String, dynamic>>[],
      episodeStates: const <Map<String, dynamic>>[],
      streamPreferences: const <Map<String, dynamic>>[],
      operations: const <Map<String, dynamic>>[],
    );
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.method == 'GET' &&
              options.uri.path.endsWith('/files/manifest')) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                data: jsonEncode(
                  DriveReplicaManifest(
                    snapshotFileName: snapshot.fileName,
                    snapshotChecksum: snapshot.checksum,
                    snapshotEntryCount: 1,
                  ).toJson(),
                ),
              ),
            );
            return;
          }
          if (options.method == 'GET' &&
              options.uri.path.endsWith('/files/snapshot')) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                data: snapshot.encode(),
              ),
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
    final GoogleDriveCloudReplica replica = GoogleDriveCloudReplica(
      accessToken: 'access-token',
      replicaNamespace: 'anilist:1',
      dio: dio,
    );

    final DriveLibrarySnapshot? restored = await replica.pullLibrarySnapshot(
      manifestFileId: 'manifest',
      snapshotFileId: 'snapshot',
    );
    expect(restored?.entryCount, 1);
    expect(restored?.checksum, snapshot.checksum);
  });

  test(
    'delivery ledger merges targets and skips unchanged manifest writes',
    () async {
      final Dio dio = Dio();
      var manifest = const DriveReplicaManifest(
        deliveryLedger: <String, Map<String, String>>{
          'operation-1': <String, String>{'anilist:1': 'confirmed'},
        },
      );
      var writes = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                if (options.method == 'GET' &&
                    options.uri.path.endsWith('/files')) {
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: <String, dynamic>{
                        'files': <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'manifest',
                            'name': 'mirushin.manifest.v1.json',
                          },
                        ],
                      },
                    ),
                  );
                  return;
                }
                if (options.method == 'GET' &&
                    options.uri.path.endsWith('/files/manifest')) {
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: jsonEncode(manifest.toJson()),
                    ),
                  );
                  return;
                }
                if (options.method == 'PATCH' &&
                    options.uri.path.endsWith('/files/manifest')) {
                  writes += 1;
                  manifest = DriveReplicaManifest.fromJson(
                    jsonDecode(utf8.decode(options.data as List<int>))
                        as Map<String, dynamic>,
                  );
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: <String, dynamic>{'id': 'manifest'},
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
      final GoogleDriveCloudReplica replica = GoogleDriveCloudReplica(
        accessToken: 'access-token',
        dio: dio,
      );
      const Map<String, Map<String, String>> delivery =
          <String, Map<String, String>>{
            'operation-1': <String, String>{'mal:2': 'confirmed'},
          };

      await replica.mergeDeliveryLedger(delivery);
      await replica.mergeDeliveryLedger(delivery);

      expect(writes, 1);
      expect(manifest.deliveryLedger['operation-1'], <String, String>{
        'anilist:1': 'confirmed',
        'mal:2': 'confirmed',
      });
    },
  );

  test('retry registers an already uploaded segment in the manifest', () async {
    final DriveReplicaSegment segment = DriveReplicaSegment(
      segmentId: 'segment-1',
      deviceId: 'device-a',
      createdAt: DateTime.utc(2026, 9, 28),
      replicaNamespace: 'anilist-1',
      operations: const <Map<String, dynamic>>[
        <String, dynamic>{'operationId': 'operation-1'},
      ],
      media: const <Map<String, dynamic>>[],
      libraryEntries: const <Map<String, dynamic>>[],
      episodeStates: const <Map<String, dynamic>>[],
      streamPreferences: const <Map<String, dynamic>>[],
    );
    final Dio dio = Dio();
    var uploads = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          if (options.method == 'GET' && options.uri.path.endsWith('/files')) {
            final String query = '${options.queryParameters['q'] ?? ''}';
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: <String, dynamic>{
                  'files': query.contains(segment.fileName)
                      ? <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'existing-segment',
                            'name': segment.fileName,
                          },
                        ]
                      : <Map<String, dynamic>>[],
                },
              ),
            );
            return;
          }
          if (options.method == 'POST' && options.uri.path.endsWith('/files')) {
            uploads += 1;
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                data: <String, dynamic>{'id': 'new-manifest'},
              ),
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

    final CloudReplicaFile result = await GoogleDriveCloudReplica(
      accessToken: 'access-token',
      replicaNamespace: 'anilist-1',
      dio: dio,
    ).pushSegment(segment);

    expect(result.id, 'existing-segment');
    expect(uploads, 1);
  });

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
