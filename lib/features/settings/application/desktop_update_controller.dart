import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/desktop_update_installer.dart';
import '../domain/update_models.dart';

enum DesktopUpdatePhase { idle, downloading, preparing, restarting, failed }

class DesktopUpdateState {
  const DesktopUpdateState({
    this.phase = DesktopUpdatePhase.idle,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final DesktopUpdatePhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  bool get isBusy =>
      phase == DesktopUpdatePhase.downloading ||
      phase == DesktopUpdatePhase.preparing ||
      phase == DesktopUpdatePhase.restarting;

  double? get progress {
    if (phase != DesktopUpdatePhase.downloading || totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0, 1);
  }
}

final desktopUpdateInstallerProvider = Provider<DesktopUpdateInstaller>((ref) {
  return createDesktopUpdateInstaller();
});

final desktopUpdateControllerProvider =
    NotifierProvider<DesktopUpdateController, DesktopUpdateState>(
      DesktopUpdateController.new,
    );

class DesktopUpdateController extends Notifier<DesktopUpdateState> {
  @override
  DesktopUpdateState build() => const DesktopUpdateState();

  bool canInstall(UpdateInfo update) {
    final DesktopUpdateInstaller installer = ref.read(
      desktopUpdateInstallerProvider,
    );
    final DesktopUpdatePlatform? platform = installer.platform;
    if (!installer.isSupported || platform == null) return false;
    final UpdateAsset? asset = selectDesktopUpdateAsset(
      update.assets,
      platform,
    );
    return asset?.sha256Digest != null;
  }

  /// Returns false when this installation cannot be updated in place and the
  /// caller should offer the release page instead.
  Future<bool> installAndRestart(UpdateInfo update) async {
    if (state.isBusy) return true;

    final DesktopUpdateInstaller installer = ref.read(
      desktopUpdateInstallerProvider,
    );
    final DesktopUpdatePlatform? platform = installer.platform;
    if (!installer.isSupported || platform == null) return false;

    final UpdateAsset? asset = selectDesktopUpdateAsset(
      update.assets,
      platform,
    );
    if (asset?.sha256Digest == null) return false;

    state = const DesktopUpdateState(phase: DesktopUpdatePhase.downloading);
    try {
      await installer.prepareAndLaunch(
        update: update,
        asset: asset!,
        onProgress:
            (
              DesktopUpdatePreparationPhase phase,
              int receivedBytes,
              int totalBytes,
            ) {
              state = DesktopUpdateState(
                phase: phase == DesktopUpdatePreparationPhase.downloading
                    ? DesktopUpdatePhase.downloading
                    : DesktopUpdatePhase.preparing,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
              );
            },
      );
      state = const DesktopUpdateState(phase: DesktopUpdatePhase.restarting);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
      state = const DesktopUpdateState(
        phase: DesktopUpdatePhase.failed,
        error: 'The app could not close to finish the update.',
      );
    } catch (error) {
      state = DesktopUpdateState(
        phase: DesktopUpdatePhase.failed,
        error: error.toString(),
      );
    }
    return true;
  }

  void reset() {
    if (!state.isBusy) state = const DesktopUpdateState();
  }
}
