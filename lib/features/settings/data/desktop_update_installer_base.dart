import '../domain/update_models.dart';

enum DesktopUpdatePreparationPhase { downloading, preparing }

typedef DesktopUpdateProgressCallback =
    void Function(
      DesktopUpdatePreparationPhase phase,
      int receivedBytes,
      int totalBytes,
    );

abstract class DesktopUpdateInstaller {
  bool get isSupported;

  DesktopUpdatePlatform? get platform;

  Future<void> prepareAndLaunch({
    required UpdateInfo update,
    required UpdateAsset asset,
    required DesktopUpdateProgressCallback onProgress,
  });
}

class DesktopUpdateException implements Exception {
  const DesktopUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
