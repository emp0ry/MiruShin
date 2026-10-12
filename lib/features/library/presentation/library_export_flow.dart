import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/models/media_item.dart';
import '../../profile/application/anilist_profile_export.dart';
import '../../settings/application/settings_state.dart';
import '../application/canonical_library_repository.dart';

Future<void> showLibraryExportSheet(
  BuildContext context,
  WidgetRef ref, {
  required LibraryExportTarget target,
}) async {
  final SettingsState settings = ref.read(settingsProvider);
  final repository = ref.read(canonicalLibraryRepositoryProvider);
  final String username = settings.anilistViewerName ?? 'MiruShin';

  final bool? anime = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.live_tv_rounded),
                title: Text(context.t('Anime')),
                onTap: () => Navigator.of(context).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: Text(context.t('Manga')),
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (anime == null || !context.mounted) return;

  final VoidCallback closeProgressDialog = await _showBlockingProgressDialog(
    context,
    context.t('Exporting...'),
  );

  try {
    final snapshot = await repository.buildExportSnapshot();
    final LibraryExportPayload? payload = buildLibraryExportPayload(
      snapshot: snapshot,
      username: username,
      anime: anime,
      target: target,
    );
    closeProgressDialog();
    if (!context.mounted) return;
    if (payload == null) {
      final skipped = snapshot.entries
          .where(
            (entry) =>
                entry.mediaItem.type ==
                (anime ? MediaType.anime : MediaType.manga),
          )
          .map((entry) => entry.mediaItem.title)
          .toList();
      if (skipped.isNotEmpty) {
        await _showSkippedEntries(context, skipped);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Nothing to export'))));
      return;
    }
    final String? savedPath = await saveLibraryExportPayload(context, payload);
    if (!context.mounted) return;
    if (savedPath == null) {
      return;
    }
    if (payload.skippedCount > 0) {
      await _showSkippedEntries(context, payload.skippedTitles);
      if (!context.mounted) return;
    }
    if (savedPath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Export file shared'))));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tf('Exported to: {path}', <String, Object?>{
            'path': savedPath,
          }),
        ),
      ),
    );
  } catch (error) {
    closeProgressDialog();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tf('Export failed: {error}', <String, Object?>{
            'error': error,
          }),
        ),
      ),
    );
  }
}

Future<void> _showSkippedEntries(
  BuildContext context,
  List<String> titles,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(dialogContext.t('Some entries were skipped')),
    content: SingleChildScrollView(
      child: Text(
        '${dialogContext.tf('Skipped {count} entries with missing or ambiguous provider IDs.', {'count': titles.length})}\n\n${titles.join('\n')}',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(dialogContext.t('OK')),
      ),
    ],
  ),
);

Future<VoidCallback> _showBlockingProgressDialog(
  BuildContext context,
  String message,
) async {
  final Completer<BuildContext> dialogContext = Completer<BuildContext>();
  var closed = false;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        if (!dialogContext.isCompleted) {
          scheduleMicrotask(() => dialogContext.complete(context));
        }
        return AlertDialog(
          content: Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(message),
            ],
          ),
        );
      },
    ).catchError((Object error) {
      if (!dialogContext.isCompleted) {
        dialogContext.completeError(error);
      }
    }),
  );

  final BuildContext mountedDialogContext = await dialogContext.future;
  return () {
    if (closed) return;
    closed = true;
    if (!mountedDialogContext.mounted) return;
    final NavigatorState navigator = Navigator.of(
      mountedDialogContext,
      rootNavigator: true,
    );
    if (navigator.canPop()) navigator.pop();
  };
}
