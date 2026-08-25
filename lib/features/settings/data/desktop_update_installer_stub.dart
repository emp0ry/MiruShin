import '../domain/update_models.dart';
import 'desktop_update_installer_base.dart';

DesktopUpdateInstaller createDesktopUpdateInstaller() =>
    const _UnsupportedDesktopUpdateInstaller();

class _UnsupportedDesktopUpdateInstaller implements DesktopUpdateInstaller {
  const _UnsupportedDesktopUpdateInstaller();

  @override
  bool get isSupported => false;

  @override
  DesktopUpdatePlatform? get platform => null;

  @override
  Future<void> prepareAndLaunch({
    required UpdateInfo update,
    required UpdateAsset asset,
    required DesktopUpdateProgressCallback onProgress,
  }) {
    throw const DesktopUpdateException(
      'Automatic updates are unavailable on this platform.',
    );
  }
}
