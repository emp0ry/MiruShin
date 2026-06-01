import 'dart:io' show Platform;

import 'package:media_kit/media_kit.dart';

/// Initialize the MPV-like MediaKit backend on native platforms.
///
/// Skipped on Linux: the player always uses FVP there (see `_resolveBackend` in
/// playback_controller), and merely loading libmpv + its large native
/// dependency tree into the process destabilizes the flutter_js QuickJS addon
/// runtime, causing a hard SIGSEGV when opening a stream. v1.2.2 — which never
/// initialized MediaKit — was stable on Linux for exactly this reason.
void configureMiruShinMediaKit() {
  if (Platform.isLinux) return;
  MediaKit.ensureInitialized();
}
