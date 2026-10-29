import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../application/settings_state.dart';
import 'settings_widgets.dart';

class GoogleDriveLibrarySyncRow extends ConsumerWidget {
  const GoogleDriveLibrarySyncRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsProvider.select(
        (settings) => settings.googleDriveLibrarySyncEnabled,
      ),
    );
    return SettingsRow(
      title: context.t('Sync full library'),
      subtitle: context.t(
        'Only on this device. When off, your library comes from the selected catalog. Watch positions and other Drive data still sync. Turn on to restore an older full backup.',
      ),
      trailing: Switch(
        value: enabled,
        onChanged: ref
            .read(settingsProvider.notifier)
            .setGoogleDriveLibrarySyncEnabled,
      ),
    );
  }
}
