import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../addons/domain/addon_sync_models.dart';
import '../../settings/domain/account_sync_models.dart';
import '../../settings/domain/preference_sync_models.dart';
import '../domain/cloud_replica_models.dart';

class GoogleDriveCloudReplica
    implements
        CloudReplica,
        AddonCloudReplica,
        AccountCloudReplica,
        PreferenceCloudReplica {
  GoogleDriveCloudReplica({
    required String accessToken,
    this.replicaNamespace = 'legacy',
    this.includeLegacyLibrary = false,
    Dio? dio,
  }) : _dio = dio ?? Dio(),
       _accessToken = accessToken;

  static const String manifestName = 'mirushin.manifest.v1.json';

  final Dio _dio;
  final String _accessToken;
  final String replicaNamespace;
  final bool includeLegacyLibrary;

  String get _libraryManifestName => replicaNamespace == 'legacy'
      ? manifestName
      : 'mirushin.$replicaNamespace.manifest.v1.json';

  String get _librarySegmentPrefix => replicaNamespace == 'legacy'
      ? 'mirushin.segment.'
      : 'mirushin.$replicaNamespace.segment.';

  bool _isLibrarySegment(String name) {
    final bool current =
        name.startsWith(_librarySegmentPrefix) && name.endsWith('.json');
    if (current) return true;
    return includeLegacyLibrary &&
        replicaNamespace != 'legacy' &&
        name.startsWith('mirushin.segment.') &&
        name.endsWith('.json');
  }

  Future<DriveLibrarySnapshot?> pullLibrarySnapshot({
    void Function(int received, int total)? onProgress,
  }) async {
    final _ManifestRead manifest = await _readManifest();
    final String fileName =
        manifest.value.snapshotFileName ??
        (replicaNamespace == 'legacy'
            ? 'mirushin.library.snapshot.v2.json'
            : 'mirushin.$replicaNamespace.library.snapshot.v2.json');
    final CloudReplicaFile? file = await _findByName(fileName);
    if (file == null) return null;
    final String body = await _download(file.id, onProgress: onProgress);
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Google Drive library snapshot.');
    }
    final DriveLibrarySnapshot snapshot = DriveLibrarySnapshot.fromJson(
      decoded,
    );
    if (snapshot.replicaNamespace != replicaNamespace &&
        !(includeLegacyLibrary && snapshot.replicaNamespace == 'legacy')) {
      throw StateError('Google Drive library snapshot workspace mismatch.');
    }
    final String? expectedChecksum = manifest.value.snapshotChecksum;
    if (expectedChecksum != null &&
        expectedChecksum.isNotEmpty &&
        expectedChecksum != snapshot.checksum &&
        expectedChecksum != snapshot.legacyEnvelopeChecksum) {
      throw StateError('Google Drive library snapshot checksum mismatch.');
    }
    final int? expectedCount = manifest.value.snapshotEntryCount;
    if (expectedCount != null && expectedCount != snapshot.entryCount) {
      throw StateError('Google Drive library snapshot entry count mismatch.');
    }
    return snapshot;
  }

  Future<CloudReplicaFile> pushLibrarySnapshot(
    DriveLibrarySnapshot snapshot, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (snapshot.replicaNamespace != replicaNamespace) {
      throw StateError('Google Drive library snapshot workspace mismatch.');
    }
    final String body = snapshot.encode();
    final _ManifestRead current = await _readManifest();
    if (current.value.snapshotChecksum == snapshot.checksum) {
      final CloudReplicaFile? existing = await _findByName(snapshot.fileName);
      if (existing != null) return existing;
    }
    final CloudReplicaFile? existing = await _findByName(snapshot.fileName);
    final CloudReplicaFile uploaded = existing == null
        ? await _createJsonFile(snapshot.fileName, body, onProgress: onProgress)
        : await _updateJsonFile(existing, body, onProgress: onProgress);
    await _updateManifest((DriveReplicaManifest manifest) {
      return _copyManifest(
        manifest,
        revision: manifest.revision + 1,
        snapshotFileName: snapshot.fileName,
        snapshotChecksum: snapshot.checksum,
        snapshotEntryCount: snapshot.entryCount,
        snapshotSizeBytes: snapshot.encodedSizeBytes,
        snapshotCreatedAt: snapshot.createdAt,
      );
    });
    return CloudReplicaFile(
      id: uploaded.id,
      name: uploaded.name,
      checksum: uploaded.checksum,
      etag: uploaded.etag,
      sizeBytes: snapshot.encodedSizeBytes,
    );
  }

  Future<DriveReplicaUsage> readUsage() async {
    final List<CloudReplicaFile> files = await _listFiles();
    final int total = files.fold<int>(
      0,
      (int sum, CloudReplicaFile file) => sum + (file.sizeBytes ?? 0),
    );
    final int snapshots = files
        .where((CloudReplicaFile file) => file.name.contains('.snapshot.'))
        .fold<int>(
          0,
          (int sum, CloudReplicaFile file) => sum + (file.sizeBytes ?? 0),
        );
    return DriveReplicaUsage(
      totalBytes: total,
      fileCount: files.length,
      snapshotBytes: snapshots,
    );
  }

  @override
  Future<void> pushAccountSegment(AccountReplicaSegment segment) async {
    if (await _findByName(segment.fileName) != null) return;
    await _createJsonFile(segment.fileName, segment.encode());
  }

  @override
  Future<List<AccountReplicaSegment>> pullAccountSegments({
    required Set<String> excluding,
  }) async {
    final List<CloudReplicaFile> files = (await _listFiles())
        .where(
          (CloudReplicaFile file) =>
              file.name.startsWith('mirushin.accounts.segment.') &&
              file.name.endsWith('.v1.json'),
        )
        .toList(growable: false);
    final List<AccountReplicaSegment> result = <AccountReplicaSegment>[];
    for (final CloudReplicaFile file in files) {
      if (excluding.contains(file.name)) continue;
      final AccountReplicaSegment segment = AccountReplicaSegment.decode(
        await _download(file.id),
      );
      if (file.name != segment.fileName) {
        throw StateError('Google Drive account segment identity mismatch.');
      }
      result.add(segment);
    }
    result.sort((AccountReplicaSegment a, AccountReplicaSegment b) {
      final int created = a.createdAt.compareTo(b.createdAt);
      if (created != 0) return created;
      final int device = a.deviceId.compareTo(b.deviceId);
      return device != 0 ? device : a.revision.compareTo(b.revision);
    });
    return result;
  }

  @override
  Future<void> pushPreferenceSegment(PreferenceReplicaSegment segment) async {
    if (await _findByName(segment.fileName) != null) return;
    await _createJsonFile(segment.fileName, segment.encode());
  }

  @override
  Future<List<PreferenceReplicaSegment>> pullPreferenceSegments({
    required Set<String> excluding,
  }) async {
    final List<CloudReplicaFile> files = (await _listFiles())
        .where(
          (CloudReplicaFile file) =>
              file.name.startsWith('mirushin.preferences.segment.') &&
              file.name.endsWith('.v1.json'),
        )
        .toList(growable: false);
    final List<PreferenceReplicaSegment> result = <PreferenceReplicaSegment>[];
    for (final CloudReplicaFile file in files) {
      if (excluding.contains(file.name)) continue;
      final PreferenceReplicaSegment segment = PreferenceReplicaSegment.decode(
        await _download(file.id),
      );
      if (file.name != segment.fileName) {
        throw StateError('Google Drive preference segment identity mismatch.');
      }
      result.add(segment);
    }
    result.sort((PreferenceReplicaSegment a, PreferenceReplicaSegment b) {
      final int created = a.createdAt.compareTo(b.createdAt);
      if (created != 0) return created;
      final int device = a.deviceId.compareTo(b.deviceId);
      return device != 0 ? device : a.revision.compareTo(b.revision);
    });
    return result;
  }

  @override
  Future<void> pushAddonSegment(AddonReplicaSegment segment) async {
    if (await _findByName(segment.fileName) != null) return;
    await _createJsonFile(segment.fileName, segment.encode());
  }

  @override
  Future<List<AddonReplicaSegment>> pullAddonSegments({
    required Set<String> excluding,
  }) async {
    final List<CloudReplicaFile> files = (await _listFiles())
        .where(
          (CloudReplicaFile file) =>
              file.name.startsWith('mirushin.addons.segment.') &&
              file.name.endsWith('.v1.json'),
        )
        .toList(growable: false);
    final List<AddonReplicaSegment> result = <AddonReplicaSegment>[];
    for (final CloudReplicaFile file in files) {
      if (excluding.contains(file.name)) continue;
      final AddonReplicaSegment segment = AddonReplicaSegment.decode(
        await _download(file.id),
      );
      if (file.name != segment.fileName) {
        throw StateError('Google Drive addon segment identity mismatch.');
      }
      result.add(segment);
    }
    result.sort((AddonReplicaSegment a, AddonReplicaSegment b) {
      final int created = a.createdAt.compareTo(b.createdAt);
      if (created != 0) return created;
      final int device = a.deviceId.compareTo(b.deviceId);
      return device != 0 ? device : a.revision.compareTo(b.revision);
    });
    return result;
  }

  Options _options({Map<String, String>? headers}) => Options(
    headers: <String, String>{
      'Authorization': 'Bearer $_accessToken',
      ...?headers,
    },
  );

  @override
  Future<CloudReplicaFile> pushSegment(DriveReplicaSegment segment) async {
    final CloudReplicaFile? existing = await _findByName(segment.fileName);
    if (existing != null) return existing;
    final CloudReplicaFile uploaded = await _createJsonFile(
      segment.fileName,
      segment.encode(),
    );
    await _updateManifest((DriveReplicaManifest manifest) {
      return DriveReplicaManifest(
        revision: manifest.revision + 1,
        segments: <String, String>{
          ...manifest.segments,
          segment.fileName: segment.checksum,
        },
        processedByDevice: manifest.processedByDevice,
        deliveryLedger: manifest.deliveryLedger,
        leaseOwner: manifest.leaseOwner,
        leaseExpiresAt: manifest.leaseExpiresAt,
        snapshotFileName: manifest.snapshotFileName,
        snapshotChecksum: manifest.snapshotChecksum,
        snapshotEntryCount: manifest.snapshotEntryCount,
        snapshotSizeBytes: manifest.snapshotSizeBytes,
        snapshotCreatedAt: manifest.snapshotCreatedAt,
      );
    });
    return uploaded;
  }

  @override
  Future<List<DriveReplicaSegment>> pullSegments({
    required Set<String> excluding,
  }) async {
    final _ManifestRead manifest = await _readManifest();
    final List<CloudReplicaFile> files = (await _listFiles())
        .where((CloudReplicaFile file) => _isLibrarySegment(file.name))
        .toList(growable: false);
    final List<DriveReplicaSegment> result = <DriveReplicaSegment>[];
    for (final CloudReplicaFile file in files) {
      if (excluding.contains(file.name)) continue;
      final String body = await _download(file.id);
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) continue;
      final DriveReplicaSegment segment = DriveReplicaSegment.fromJson(decoded);
      final String? expected = manifest.value.segments[file.name];
      if (expected != null && expected != segment.checksum) {
        throw StateError(
          'Google Drive segment checksum mismatch: ${file.name}',
        );
      }
      result.add(segment);
    }
    result.sort(
      (DriveReplicaSegment a, DriveReplicaSegment b) =>
          a.createdAt.compareTo(b.createdAt),
    );
    return result;
  }

  @override
  Future<Map<String, Map<String, String>>> readDeliveryLedger() async {
    final _ManifestRead manifest = await _readManifest();
    return <String, Map<String, String>>{
      for (final MapEntry<String, Map<String, String>> entry
          in manifest.value.deliveryLedger.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
  }

  @override
  Future<void> mergeDeliveryLedger(
    Map<String, Map<String, String>> deliveries,
  ) {
    if (deliveries.isEmpty) return Future<void>.value();
    return _updateManifest((DriveReplicaManifest manifest) {
      final Map<String, Map<String, String>> merged =
          <String, Map<String, String>>{
            ...manifest.deliveryLedger,
            for (final MapEntry<String, Map<String, String>> entry
                in deliveries.entries)
              entry.key: Map<String, String>.from(entry.value),
          };
      return DriveReplicaManifest(
        revision: manifest.revision + 1,
        segments: manifest.segments,
        processedByDevice: manifest.processedByDevice,
        deliveryLedger: merged,
        leaseOwner: manifest.leaseOwner,
        leaseExpiresAt: manifest.leaseExpiresAt,
        snapshotFileName: manifest.snapshotFileName,
        snapshotChecksum: manifest.snapshotChecksum,
        snapshotEntryCount: manifest.snapshotEntryCount,
        snapshotSizeBytes: manifest.snapshotSizeBytes,
        snapshotCreatedAt: manifest.snapshotCreatedAt,
      );
    });
  }

  @override
  Future<bool> acquireDeliveryLease({
    required String deviceId,
    Duration duration = const Duration(minutes: 2),
  }) async {
    bool acquired = false;
    await _updateManifest((DriveReplicaManifest manifest) {
      final DateTime now = DateTime.now().toUtc();
      final bool available =
          manifest.leaseOwner == null ||
          manifest.leaseOwner == deviceId ||
          manifest.leaseExpiresAt == null ||
          !manifest.leaseExpiresAt!.isAfter(now);
      if (!available) return manifest;
      acquired = true;
      return DriveReplicaManifest(
        revision: manifest.revision + 1,
        segments: manifest.segments,
        processedByDevice: manifest.processedByDevice,
        deliveryLedger: manifest.deliveryLedger,
        leaseOwner: deviceId,
        leaseExpiresAt: now.add(duration),
        snapshotFileName: manifest.snapshotFileName,
        snapshotChecksum: manifest.snapshotChecksum,
        snapshotEntryCount: manifest.snapshotEntryCount,
        snapshotSizeBytes: manifest.snapshotSizeBytes,
        snapshotCreatedAt: manifest.snapshotCreatedAt,
      );
    });
    return acquired;
  }

  @override
  Future<void> releaseDeliveryLease({required String deviceId}) {
    return _updateManifest((DriveReplicaManifest manifest) {
      if (manifest.leaseOwner != deviceId) return manifest;
      return DriveReplicaManifest(
        revision: manifest.revision + 1,
        segments: manifest.segments,
        processedByDevice: manifest.processedByDevice,
        deliveryLedger: manifest.deliveryLedger,
        snapshotFileName: manifest.snapshotFileName,
        snapshotChecksum: manifest.snapshotChecksum,
        snapshotEntryCount: manifest.snapshotEntryCount,
        snapshotSizeBytes: manifest.snapshotSizeBytes,
        snapshotCreatedAt: manifest.snapshotCreatedAt,
      );
    });
  }

  Future<List<CloudReplicaFile>> _listFiles() async {
    final List<CloudReplicaFile> result = <CloudReplicaFile>[];
    String? pageToken;
    do {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '${AppConstants.googleDriveApiBaseUrl}/files',
        queryParameters: <String, dynamic>{
          'spaces': 'appDataFolder',
          'q': 'trashed = false',
          'fields': 'nextPageToken,files(id,name,md5Checksum,size)',
          'pageSize': 1000,
          'pageToken': ?pageToken,
        },
        options: _options(),
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) break;
      final Object? files = data['files'];
      if (files is List) {
        result.addAll(
          files.whereType<Map<String, dynamic>>().map(
            (Map<String, dynamic> file) => CloudReplicaFile(
              id: '${file['id'] ?? ''}',
              name: '${file['name'] ?? ''}',
              checksum: file['md5Checksum']?.toString(),
              sizeBytes: int.tryParse('${file['size'] ?? ''}'),
            ),
          ),
        );
      }
      pageToken = data['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);
    return result;
  }

  Future<CloudReplicaFile?> _findByName(String name) async {
    final String escaped = name.replaceAll("'", "\\'");
    final Response<dynamic> response = await _dio.get<dynamic>(
      '${AppConstants.googleDriveApiBaseUrl}/files',
      queryParameters: <String, dynamic>{
        'spaces': 'appDataFolder',
        'q': "name = '$escaped' and trashed = false",
        'fields': 'files(id,name,md5Checksum,size)',
        'pageSize': 2,
      },
      options: _options(),
    );
    final Object? data = response.data;
    final Object? files = data is Map<String, dynamic> ? data['files'] : null;
    if (files is! List || files.isEmpty) return null;
    final List<Map<String, dynamic>> entries =
        files.whereType<Map<String, dynamic>>().toList()..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              '${a['id'] ?? ''}'.compareTo('${b['id'] ?? ''}'),
        );
    if (entries.isEmpty) return null;
    final Map<String, dynamic> first = entries.first;
    return CloudReplicaFile(
      id: '${first['id'] ?? ''}',
      name: '${first['name'] ?? name}',
      checksum: first['md5Checksum']?.toString(),
      sizeBytes: int.tryParse('${first['size'] ?? ''}'),
    );
  }

  Future<String> _download(
    String fileId, {
    void Function(int received, int total)? onProgress,
  }) async {
    final Response<String> response = await _dio.get<String>(
      '${AppConstants.googleDriveApiBaseUrl}/files/$fileId',
      queryParameters: const <String, String>{'alt': 'media'},
      options: _options(),
      onReceiveProgress: onProgress,
    );
    return response.data ?? '';
  }

  Future<CloudReplicaFile> _createJsonFile(
    String name,
    String content, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final String boundary =
        'mirushin-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    final String body =
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(<String, dynamic>{
          'name': name,
          'parents': <String>['appDataFolder'],
        })}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$content\r\n'
        '--$boundary--';
    final Response<dynamic> response = await _dio.post<dynamic>(
      '${AppConstants.googleDriveUploadBaseUrl}/files',
      queryParameters: const <String, String>{
        'uploadType': 'multipart',
        'fields': 'id,name,md5Checksum',
      },
      data: utf8.encode(body),
      options: _options(
        headers: <String, String>{
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
      ),
      onSendProgress: onProgress,
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected Google Drive upload response.');
    }
    return CloudReplicaFile(
      id: '${data['id'] ?? ''}',
      name: '${data['name'] ?? name}',
      checksum: data['md5Checksum']?.toString(),
      sizeBytes: utf8.encode(content).length,
    );
  }

  Future<CloudReplicaFile> _updateJsonFile(
    CloudReplicaFile file,
    String content, {
    String? etag,
    void Function(int sent, int total)? onProgress,
  }) async {
    final Response<dynamic> response = await _dio.patch<dynamic>(
      '${AppConstants.googleDriveUploadBaseUrl}/files/${file.id}',
      queryParameters: const <String, String>{
        'uploadType': 'media',
        'fields': 'id,name,md5Checksum',
      },
      data: utf8.encode(content),
      options: _options(
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          if (etag != null && etag.isNotEmpty) 'If-Match': etag,
        },
      ),
      onSendProgress: onProgress,
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected Google Drive update response.');
    }
    return CloudReplicaFile(
      id: '${data['id'] ?? file.id}',
      name: '${data['name'] ?? file.name}',
      checksum: data['md5Checksum']?.toString(),
      sizeBytes: utf8.encode(content).length,
    );
  }

  Future<_ManifestRead> _readManifest() async {
    final CloudReplicaFile? file = await _findByName(_libraryManifestName);
    if (file == null) {
      return const _ManifestRead(value: DriveReplicaManifest(), exists: false);
    }
    final Response<String> response = await _dio.get<String>(
      '${AppConstants.googleDriveApiBaseUrl}/files/${file.id}',
      queryParameters: const <String, String>{'alt': 'media'},
      options: _options(),
    );
    final Object? decoded = jsonDecode(response.data ?? '{}');
    return _ManifestRead(
      value: decoded is Map<String, dynamic>
          ? DriveReplicaManifest.fromJson(decoded)
          : const DriveReplicaManifest(),
      file: CloudReplicaFile(
        id: file.id,
        name: file.name,
        checksum: file.checksum,
        etag: response.headers.value('etag'),
      ),
      exists: true,
    );
  }

  Future<void> _updateManifest(
    DriveReplicaManifest Function(DriveReplicaManifest current) update,
  ) async {
    for (int attempt = 0; attempt < 4; attempt += 1) {
      final _ManifestRead read = await _readManifest();
      final DriveReplicaManifest next = update(read.value);
      if (identical(next, read.value)) return;
      try {
        if (read.file == null) {
          await _createJsonFile(
            _libraryManifestName,
            jsonEncode(next.toJson()),
          );
        } else {
          await _updateJsonFile(
            read.file!,
            jsonEncode(next.toJson()),
            etag: read.file!.etag,
          );
        }
        return;
      } on DioException catch (error) {
        if (error.response?.statusCode != 412 || attempt == 3) rethrow;
      }
    }
  }
}

DriveReplicaManifest _copyManifest(
  DriveReplicaManifest manifest, {
  required int revision,
  String? snapshotFileName,
  String? snapshotChecksum,
  int? snapshotEntryCount,
  int? snapshotSizeBytes,
  DateTime? snapshotCreatedAt,
}) => DriveReplicaManifest(
  revision: revision,
  segments: manifest.segments,
  processedByDevice: manifest.processedByDevice,
  deliveryLedger: manifest.deliveryLedger,
  leaseOwner: manifest.leaseOwner,
  leaseExpiresAt: manifest.leaseExpiresAt,
  snapshotFileName: snapshotFileName ?? manifest.snapshotFileName,
  snapshotChecksum: snapshotChecksum ?? manifest.snapshotChecksum,
  snapshotEntryCount: snapshotEntryCount ?? manifest.snapshotEntryCount,
  snapshotSizeBytes: snapshotSizeBytes ?? manifest.snapshotSizeBytes,
  snapshotCreatedAt: snapshotCreatedAt ?? manifest.snapshotCreatedAt,
);

class _ManifestRead {
  const _ManifestRead({required this.value, required this.exists, this.file});

  final DriveReplicaManifest value;
  final CloudReplicaFile? file;
  final bool exists;
}
