import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/data/sora_addon_clipboard.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';

void main() {
  test('pairs exactly one json manifest and one js script in either order', () {
    final SoraAddonClipboardFile manifest = SoraAddonClipboardFile(
      name: 'yummyanime.JSON',
      bytes: Uint8List.fromList(<int>[1]),
    );
    final SoraAddonClipboardFile script = SoraAddonClipboardFile(
      name: 'yummyanime.js',
      bytes: Uint8List.fromList(<int>[2]),
    );

    final SoraLocalAddonFiles files = SoraLocalAddonFiles.fromFiles(
      <SoraAddonClipboardFile>[script, manifest],
    );

    expect(files.manifest, same(manifest));
    expect(files.script, same(script));
  });

  test('rejects extra, missing, duplicate, or unrelated clipboard files', () {
    SoraAddonClipboardFile file(String name) =>
        SoraAddonClipboardFile(name: name, bytes: Uint8List(0));

    for (final List<SoraAddonClipboardFile> files
        in <List<SoraAddonClipboardFile>>[
          <SoraAddonClipboardFile>[file('addon.json')],
          <SoraAddonClipboardFile>[file('addon.json'), file('other.json')],
          <SoraAddonClipboardFile>[file('addon.js'), file('other.js')],
          <SoraAddonClipboardFile>[file('addon.json'), file('notes.txt')],
          <SoraAddonClipboardFile>[
            file('addon.json'),
            file('addon.js'),
            file('notes.txt'),
          ],
        ]) {
      expect(
        () => SoraLocalAddonFiles.fromFiles(files),
        throwsA(isA<SoraAddonException>()),
      );
    }
  });
}
