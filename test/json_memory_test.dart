import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/utils/json_memory.dart';
import 'package:mirushin/features/library/domain/cloud_replica_models.dart';

void main() {
  test(
    'streamed JSON hashes and sizes match legacy bytes including Unicode',
    () {
      for (final value in <Object?>[
        null,
        true,
        0,
        -0.0,
        '',
        'English / Русский / 日本語 / 😀',
        String.fromCharCode(0xd800),
        {
          'nested': [
            1,
            'a\nb\t"',
            {'array': []},
          ],
        },
        List.generate(1000, (i) => {'id': i, 'text': '😀я日' * 100}),
      ]) {
        final expected = utf8.encode(jsonEncode(value));
        expect(jsonSha256(value), sha256.convert(expected).toString());
        expect(jsonUtf8Size(value), expected.length);
      }
    },
  );

  test('chunked UTF-8 hash preserves split surrogate pairs', () {
    const value = 'abc😀日本語';
    final expected = sha256.convert(utf8.encode(value)).toString();
    for (int split = 0; split <= value.length; split++) {
      expect(
        utf8ChunksSha256([value.substring(0, split), value.substring(split)]),
        expected,
      );
    }
  });

  test('encoded snapshot preserves full operation history and v2 bytes', () {
    final snapshot = DriveLibrarySnapshot(
      snapshotId: 'checkpoint',
      deviceId: 'a',
      createdAt: DateTime.utc(2026),
      replicaNamespace: 'anilist:1',
      media: [
        {
          'localId': 'title',
          'media': {'title': '日本語 😀'},
        },
      ],
      libraryEntries: [
        {'localId': 'title', 'inLibrary': true},
      ],
      providerBindings: [],
      providerSnapshots: [],
      episodeStates: [],
      streamPreferences: [],
      operations: List.generate(
        2000,
        (i) => {
          'operationId': 'op$i',
          'before': {'progress': i},
          'after': {'progress': i + 1, 'notes': 'Русский 😀'},
        },
      ),
    );
    final encoded = encodeDriveLibrarySnapshot(snapshot);
    expect(encoded.bytes, utf8.encode(snapshot.encode()));
    expect(encoded.checksum, snapshot.checksum);
    expect(encoded.entryCount, 1);
    expect(encoded.bytes.length, snapshot.encodedSizeBytes);
    final restored = DriveLibrarySnapshot.fromJson(
      jsonDecode(utf8.decode(encoded.bytes)),
    );
    expect(restored.operations, hasLength(2000));
    expect(restored.checksum, snapshot.checksum);
  });
}
