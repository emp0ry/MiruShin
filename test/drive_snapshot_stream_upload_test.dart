import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/network/request_cancellation_scope.dart';
import 'package:mirushin/features/library/data/google_drive_cloud_replica.dart';
import 'package:mirushin/features/library/domain/cloud_replica_models.dart';

void main() {
  test(
    'streamed snapshot uses real HTTP framing and reports send progress',
    () async {
      final snapshot = DriveLibrarySnapshot(
        snapshotId: 's',
        deviceId: 'a',
        createdAt: DateTime.utc(2026),
        replicaNamespace: 'local',
        media: [],
        libraryEntries: [],
        providerBindings: [],
        providerSnapshots: [],
        episodeStates: [],
        streamPreferences: [],
        operations: [
          {'notes': 'あ' * 50000},
        ],
      );
      final encoded = encodeDriveLibrarySnapshot(snapshot);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      int uploadedBytes = 0;
      Map<String, dynamic>? published;
      server.listen((request) async {
        Object response;
        if (request.method == 'GET' && request.uri.path.endsWith('/files')) {
          final q = request.uri.queryParameters['q'] ?? '';
          final isSnapshot = q.contains(snapshot.fileName);
          response = {
            'files': [
              {
                'id': isSnapshot ? 'snapshot' : 'manifest',
                'name': isSnapshot
                    ? snapshot.fileName
                    : 'mirushin.manifest.v1.json',
              },
            ],
          };
        } else if (request.method == 'GET') {
          response = const DriveReplicaManifest().toJson();
        } else {
          final bytes = BytesBuilder();
          await for (final chunk in request) {
            bytes.add(chunk);
          }
          final data = bytes.takeBytes();
          if (request.uri.path.endsWith('/snapshot')) {
            uploadedBytes = data.length;
            expect(data, encoded.bytes);
            expect(request.contentLength, encoded.bytes.length);
          } else {
            published = jsonDecode(utf8.decode(data));
          }
          response = {'id': 'uploaded'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final dio = Dio();
      final parent = CancelToken();
      final requestTokens = <CancelToken>{};
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.cancelToken, isNot(same(parent)));
            expect(requestTokens.add(options.cancelToken!), isTrue);
            final path = options.uri.path;
            options.baseUrl = 'http://127.0.0.1:${server.port}';
            options.path = path;
            handler.next(options);
          },
        ),
      );
      final progress = <(int, int)>[];
      await GoogleDriveCloudReplica(
        accessToken: 'fixture',
        cancelToken: parent,
        replicaNamespace: 'local',
        dio: dio,
      ).pushEncodedLibrarySnapshot(
        encoded,
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(uploadedBytes, encoded.bytes.length);
      expect(progress, isNotEmpty);
      expect(progress.last, (encoded.bytes.length, encoded.bytes.length));
      expect(published?['snapshotChecksum'], snapshot.checksum);
      expect(requestTokens.length, greaterThan(1));
      expect(RequestCancellationScope.linkedTo(parent).activeRequestCount, 0);
      parent.cancel('closing');
      await Future<void>.delayed(Duration.zero);
      expect(requestTokens.every((token) => !token.isCancelled), isTrue);
    },
  );

  for (final create in [true, false]) {
    test(
      'snapshot ${create ? 'multipart create' : 'update'} streams bounded chunks',
      () async {
        final snapshot = DriveLibrarySnapshot(
          snapshotId: 's',
          deviceId: 'a',
          createdAt: DateTime.utc(2026),
          replicaNamespace: 'anilist:1',
          media: [],
          libraryEntries: [
            {'localId': 'one', 'inLibrary': true},
          ],
          providerBindings: [],
          providerSnapshots: [],
          episodeStates: [],
          streamPreferences: [],
          operations: [
            {'operationId': 'op', 'notes': '日本語😀' * 20000},
          ],
        );
        final encoded = encodeDriveLibrarySnapshot(snapshot);
        final dio = Dio();
        Map<String, dynamic>? manifest;
        int uploads = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              Object data;
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('/files')) {
                final q = '${options.queryParameters['q']}';
                data = {
                  'files': [
                    if (q.contains(snapshot.fileName) && !create)
                      {'id': 'snapshot', 'name': snapshot.fileName}
                    else if (!q.contains(snapshot.fileName))
                      {
                        'id': 'manifest',
                        'name': 'mirushin.anilist:1.manifest.v1.json',
                      },
                  ],
                };
              } else if (options.method == 'GET' &&
                  options.uri.path.endsWith('/manifest')) {
                data = jsonEncode(const DriveReplicaManifest().toJson());
              } else if (options.data is Stream<List<int>>) {
                uploads++;
                final chunks = await (options.data as Stream<List<int>>)
                    .toList();
                expect(
                  chunks.every((chunk) => chunk.length <= 64 * 1024),
                  isTrue,
                );
                final collected = BytesBuilder();
                for (final chunk in chunks) {
                  collected.add(chunk);
                }
                final bytes = collected.takeBytes();
                expect(
                  int.parse('${options.headers['Content-Length']}'),
                  bytes.length,
                );
                final body = utf8.decode(bytes);
                if (create) {
                  expect(options.method, 'POST');
                  expect(options.queryParameters['uploadType'], 'multipart');
                  expect(body, contains('"parents":["appDataFolder"]'));
                  expect(body, contains(snapshot.encode()));
                } else {
                  expect(options.method, 'PATCH');
                  expect(options.queryParameters['uploadType'], 'media');
                  expect(bytes, encoded.bytes);
                }
                data = {'id': 'snapshot', 'name': snapshot.fileName};
              } else if (options.method == 'PATCH' &&
                  options.uri.path.endsWith('/manifest')) {
                manifest = jsonDecode(utf8.decode(options.data as List<int>));
                data = {'id': 'manifest'};
              } else {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    message: 'Unexpected fixture request',
                  ),
                );
                return;
              }
              handler.resolve(Response(requestOptions: options, data: data));
            },
          ),
        );
        final replica = GoogleDriveCloudReplica(
          accessToken: 'fixture',
          replicaNamespace: 'anilist:1',
          dio: dio,
        );
        final file = await replica.pushEncodedLibrarySnapshot(encoded);
        expect(uploads, 1);
        expect(file.sizeBytes, encoded.bytes.length);
        expect(manifest?['snapshotChecksum'], snapshot.checksum);
        expect(manifest?['snapshotEntryCount'], 1);
      },
    );
  }
}
