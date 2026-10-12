import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../library/presentation/library_export_flow.dart';
import '../../../profile/application/anilist_profile_export.dart';
import 'settings_widgets.dart';

/// Available without an AniList session or a working tracker connection.
class LibraryExportSection extends ConsumerWidget {
  const LibraryExportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSection(
    title: context.t('Export'),
    icon: Icons.ios_share_rounded,
    children: <Widget>[
      SettingsRow(
        title: context.t('Export (MyAnimeList)'),
        subtitle: context.t(
          'Exports the Local Library in MyAnimeList XML format. Works offline.',
        ),
        trailing: FilledButton.icon(
          onPressed: () => showLibraryExportSheet(
            context,
            ref,
            target: LibraryExportTarget.myAnimeList,
          ),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('MyAnimeList'),
        ),
      ),
      SettingsRow(
        title: context.t('Export Shikimori'),
        subtitle: context.t(
          'Exports the Local Library in Shikimori JSON format. Works offline.',
        ),
        trailing: OutlinedButton.icon(
          onPressed: () => showLibraryExportSheet(
            context,
            ref,
            target: LibraryExportTarget.shikimori,
          ),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Shikimori'),
        ),
      ),
    ],
  );
}
