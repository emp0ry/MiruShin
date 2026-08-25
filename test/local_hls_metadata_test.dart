import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/local_hls_metadata.dart';

void main() {
  test('reads duration through a local HLS master playlist', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'mirushin-hls-metadata-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final Directory video = Directory(
      '${root.path}${Platform.pathSeparator}video',
    );
    await video.create();
    await File('${root.path}${Platform.pathSeparator}index.m3u8').writeAsString(
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nvideo/index.m3u8\n',
    );
    await File(
      '${video.path}${Platform.pathSeparator}index.m3u8',
    ).writeAsString(
      '#EXTM3U\n#EXTINF:2.25,\nseg_1.m4s\n'
      '#EXTINF:3.5,\nseg_2.m4s\n#EXT-X-ENDLIST\n',
    );

    expect(
      await readLocalHlsDuration(
        File('${root.path}${Platform.pathSeparator}index.m3u8').uri,
      ),
      const Duration(milliseconds: 5750),
    );
  });
}
