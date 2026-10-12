import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../core/diagnostics/player_diagnostics.dart';
import '../../../profile/application/anilist_profile_export.dart';
import '../../application/player_settings.dart';

/// Observes a plain D press only; never issues a playback command.
KeyEventResult handlePlayerDiagnosticKeyEvent(
  KeyEvent event, {
  required bool enabled,
  PlayerDiagnostics? recorder,
}) {
  final diagnostics = recorder ?? PlayerDiagnostics.instance;
  final keyboard = HardwareKeyboard.instance;
  if (!enabled ||
      !diagnostics.enabled ||
      event.logicalKey != LogicalKeyboardKey.keyD ||
      keyboard.isControlPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed ||
      keyboard.isShiftPressed) {
    return KeyEventResult.ignored;
  }
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext?.widget is EditableText ||
      focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
    return KeyEventResult.ignored;
  }
  if (event is KeyDownEvent) {
    diagnostics.markMicroPause();
    return KeyEventResult.handled;
  }
  // Holding D creates just one mark, not a stream of repeated marks.
  return event is KeyRepeatEvent || event is KeyUpEvent
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

class PlayerDiagnosticsControls extends ConsumerWidget {
  const PlayerDiagnosticsControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(playerSettingsProvider).value?.diagnosticsEnabled ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(context.t('Playback diagnostics')),
          subtitle: Text(
            context.t(
              'Record the last ten minutes on this device. Does not change playback or upload reports.',
            ),
          ),
          value: enabled,
          onChanged: (value) => ref
              .read(playerSettingsProvider.notifier)
              .setDiagnosticsEnabled(value),
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('Press D in the player to mark a micro-pause.')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_alt),
                  label: Text(context.t('Save diagnostic report')),
                  onPressed: () async {
                    final report = PlayerDiagnostics.instance.report();
                    final payload = LibraryExportPayload(
                      filename:
                          'mirushin-player-diagnostics_${DateTime.now().millisecondsSinceEpoch}.json',
                      bytes: Uint8List.fromList(utf8.encode(report)),
                      mimeType: 'application/json',
                      fileExtension: 'json',
                      shareText: context.t('Playback diagnostics'),
                    );
                    await saveLibraryExportPayload(context, payload);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}
