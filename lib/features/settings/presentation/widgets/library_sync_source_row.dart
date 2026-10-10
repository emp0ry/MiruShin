import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../tracking/domain/tracker_models.dart';
import '../../application/settings_state.dart';
import 'settings_widgets.dart';

class LibrarySyncSourceRow extends ConsumerWidget {
  const LibrarySyncSourceRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      settingsProvider.select((settings) => settings.primaryTrackerSource),
    );
    return SettingsRow(
      title: context.t('Library sync source'),
      subtitle: context.t(
        'Only this catalog can update your local anime and manga library. MiruShin sends local changes to every connected catalog. If this source is unavailable, your local library is kept.',
      ),
      trailing: DropdownButton<TrackerSource>(
        value: source,
        items: [
          for (final provider in TrackerSource.values)
            DropdownMenuItem(value: provider, child: Text(provider.label)),
        ],
        onChanged: (value) {
          if (value != null && value != source) {
            ref.read(settingsProvider.notifier).setPrimaryTrackerSource(value);
          }
        },
      ),
    );
  }
}
