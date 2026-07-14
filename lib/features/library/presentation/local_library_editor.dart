import 'package:flutter/material.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';

class LocalLibraryEditResult {
  const LocalLibraryEditResult({required this.status, this.remove = false});

  final LibraryStatus status;
  final bool remove;
}

Future<LocalLibraryEditResult?> showLocalLibraryEditor(
  BuildContext context, {
  required MediaItem item,
  LibraryStatus? current,
}) {
  return showModalBottomSheet<LocalLibraryEditResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LocalEditorSheet(item: item, current: current),
  );
}

class _LocalEditorSheet extends StatefulWidget {
  const _LocalEditorSheet({required this.item, this.current});

  final MediaItem item;
  final LibraryStatus? current;

  @override
  State<_LocalEditorSheet> createState() => _LocalEditorSheetState();
}

class _LocalEditorSheetState extends State<_LocalEditorSheet> {
  late LibraryStatus _status;

  static const List<({LibraryStatus status, IconData icon})>
  _options = <({LibraryStatus status, IconData icon})>[
    (status: LibraryStatus.planned, icon: Icons.bookmark_outline_rounded),
    (status: LibraryStatus.watching, icon: Icons.play_circle_outline_rounded),
    (status: LibraryStatus.completed, icon: Icons.check_circle_outline_rounded),
    (status: LibraryStatus.dropped, icon: Icons.cancel_outlined),
    (status: LibraryStatus.favorite, icon: Icons.favorite_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.current ?? LibraryStatus.planned;
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.current != null;
    final ColorScheme cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.item.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.t('Status'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _options
                  .map(
                    (({LibraryStatus status, IconData icon}) entry) =>
                        ChoiceChip(
                          avatar: Icon(entry.icon, size: 16),
                          label: Text(context.t(entry.status.label)),
                          selected: _status == entry.status,
                          onSelected: (_) =>
                              setState(() => _status = entry.status),
                        ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: <Widget>[
                if (isEditing) ...<Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(
                        const LocalLibraryEditResult(
                          status: LibraryStatus.planned,
                          remove: true,
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(context.t('Remove')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ] else
                  const Spacer(flex: 1),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(LocalLibraryEditResult(status: _status)),
                    child: Text(context.t('Save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
