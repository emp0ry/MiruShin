import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/settings/domain/update_models.dart';

void main() {
  group('isNewerVersion', () {
    test('compares numeric version components', () {
      expect(isNewerVersion('v2.6.0', '2.5.9+48'), isTrue);
      expect(isNewerVersion('2.5.1', '2.5.0'), isTrue);
      expect(isNewerVersion('2.5.0', '2.5.0'), isFalse);
      expect(isNewerVersion('2.4.99', '2.5.0'), isFalse);
    });

    test('rejects malformed versions', () {
      expect(isNewerVersion('latest', '2.5.0'), isFalse);
      expect(isNewerVersion('2.6.0', 'unknown'), isFalse);
    });
  });

  group('selectDesktopUpdateAsset', () {
    const List<UpdateAsset> assets = <UpdateAsset>[
      UpdateAsset(
        name: 'MiruShin-windows-v2.6.0-portable.zip',
        downloadUrl: 'https://example.invalid/windows.zip',
        size: 1,
      ),
      UpdateAsset(
        name: 'MiruShin-windows-v2.6.0-setup.msi',
        downloadUrl: 'https://example.invalid/windows.msi',
        size: 2,
      ),
      UpdateAsset(
        name: 'MiruShin-windows-v2.6.0-setup.exe',
        downloadUrl: 'https://example.invalid/windows.exe',
        size: 3,
      ),
      UpdateAsset(
        name: 'MiruShin-macos-v2.6.0.dmg',
        downloadUrl: 'https://example.invalid/macos.dmg',
        size: 4,
      ),
      UpdateAsset(
        name: 'MiruShin-linux-v2.6.0.AppImage',
        downloadUrl: 'https://example.invalid/linux.AppImage',
        size: 5,
      ),
      UpdateAsset(
        name: 'MiruShin-linux-v2.6.0.tar.gz',
        downloadUrl: 'https://example.invalid/linux.tar.gz',
        size: 6,
      ),
    ];

    test('prefers the Windows setup executable', () {
      final UpdateAsset? selected = selectDesktopUpdateAsset(
        assets,
        DesktopUpdatePlatform.windows,
      );
      expect(selected?.name, endsWith('setup.exe'));
    });

    test('selects only replaceable macOS and Linux packages', () {
      expect(
        selectDesktopUpdateAsset(assets, DesktopUpdatePlatform.macos)?.name,
        endsWith('.dmg'),
      );
      expect(
        selectDesktopUpdateAsset(assets, DesktopUpdatePlatform.linux)?.name,
        endsWith('.AppImage'),
      );
    });
  });

  test('normalizes only valid SHA-256 release digests', () {
    final String hex = List<String>.filled(64, 'A').join();
    expect(normalizeSha256Digest('sha256:$hex'), hex.toLowerCase());
    expect(normalizeSha256Digest(hex), isNull);
    expect(normalizeSha256Digest('sha256:1234'), isNull);
  });
}
