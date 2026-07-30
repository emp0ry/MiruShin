import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';

/// Initialize the MPV-like MediaKit backend on native platforms.
///
/// Skipped on Linux: the player always uses FVP there (see
/// `resolvePlayerEngineBackend` in player_engine_factory_io), and merely
/// loading libmpv + its large native
/// dependency tree into the process destabilizes the flutter_js QuickJS addon
/// runtime, causing a hard SIGSEGV when opening a stream. Version 1.2.2 never
/// initialized MediaKit and was stable on Linux for this reason.
void configureMiruShinMediaKit() {
  if (Platform.isLinux) return;
  MediaKit.ensureInitialized();
}
