import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation_helpers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/page_back_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../settings/application/settings_state.dart';
import '../../tracking/domain/tracker_models.dart';
import '../application/canonical_library_repository.dart';
import '../domain/canonical_library_models.dart';

class LibrarySyncPage extends ConsumerStatefulWidget {
  const LibrarySyncPage({super.key});

  @override
  ConsumerState<LibrarySyncPage> createState() => _LibrarySyncPageState();
}

class _LibrarySyncPageState extends ConsumerState<LibrarySyncPage> {
  LibraryOriginKind? _origin;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ProviderAccountPreview>> previews = ref.watch(
      pendingProviderAccountPreviewsProvider,
    );
    final AsyncValue<List<LibraryActivityEvent>> activity = ref.watch(
      libraryActivityProvider,
    );
    final AsyncValue<List<CanonicalLibraryConflict>> conflicts = ref.watch(
      libraryConflictsProvider,
    );
    return AdaptivePage(
      child: ListView(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageBackButton(
                onPressed: () => goBackOrGo(context, AppRoutes.settings),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: SectionHeader(title: context.t('Library Log'))),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.t(
              'Review your library changes, fix sync issues, and undo changes.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...previews.when(
            data: (List<ProviderAccountPreview> values) =>
                values.map(_accountPreviewCard).toList(growable: false),
            loading: () => const <Widget>[
              LinearProgressIndicator(),
              SizedBox(height: AppSpacing.md),
            ],
            error: (Object error, StackTrace stack) => <Widget>[
              _errorCard(),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
          ...conflicts.when(
            data: (List<CanonicalLibraryConflict> values) {
              if (values.isEmpty) return const <Widget>[];
              return <Widget>[
                Text(
                  context.t('Needs your attention'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                ...values.map(_conflictCard),
                const SizedBox(height: AppSpacing.lg),
              ];
            },
            loading: () => const <Widget>[],
            error: (Object error, StackTrace stack) => <Widget>[
              _errorCard(),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DropdownButton<LibraryOriginKind?>(
              value: _origin,
              hint: Text(context.t('All sources')),
              items: <DropdownMenuItem<LibraryOriginKind?>>[
                DropdownMenuItem<LibraryOriginKind?>(
                  value: null,
                  child: Text(context.t('All sources')),
                ),
                ...LibraryOriginKind.values.map(
                  (LibraryOriginKind value) =>
                      DropdownMenuItem<LibraryOriginKind?>(
                        value: value,
                        child: Text(context.t(_originLabel(value))),
                      ),
                ),
              ],
              onChanged: (LibraryOriginKind? value) {
                setState(() => _origin = value);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.route_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    context.t(
                      'Each entry shows where a change came from, what changed locally, and whether it reached your connected services.',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...activity.when(
            data: (List<LibraryActivityEvent> values) {
              final List<LibraryActivityEvent> filtered = values
                  .where(
                    (LibraryActivityEvent event) =>
                        _origin == null || event.originKind == _origin,
                  )
                  .toList(growable: false);
              if (filtered.isEmpty) {
                return <Widget>[
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(context.t('No library changes yet.')),
                    ),
                  ),
                ];
              }
              return filtered.map(_activityCard).toList(growable: false);
            },
            loading: () => const <Widget>[CircularProgressIndicator()],
            error: (Object error, StackTrace stack) => <Widget>[_errorCard()],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _accountPreviewCard(ProviderAccountPreview preview) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.shield_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.t('New tracker account needs review'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${preview.provider.toUpperCase()} · ${preview.entryCount} '
                '${context.t('remote entries')} · ${preview.localEntryCount} '
                '${context.t('local entries')}',
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () => _showAccountPreview(preview),
                icon: const Icon(Icons.manage_search_rounded),
                label: Text(
                  '${context.t('Review all entries')} (${preview.entries.length})',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _approve(preview),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(context.t('Accept and merge')),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _reject(preview),
                    child: Text(context.t('Keep local only')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityCard(LibraryActivityEvent event) {
    final bool canUndo =
        event.undoOf == null &&
        <LibraryMutationIntent>{
          LibraryMutationIntent.add,
          LibraryMutationIntent.edit,
          LibraryMutationIntent.remove,
          LibraryMutationIntent.progress,
          LibraryMutationIntent.remoteImport,
        }.contains(event.intent);
    final List<_LibraryChangeLine> changes = _changeLines(event);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                    child: Icon(_intentIcon(event.intent), size: 19),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          event.title?.trim().isNotEmpty == true
                              ? event.title!
                              : context.t('Library entry'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${context.t(_intentLabel(event.intent))} · '
                          '${_formatTime(event.occurredAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canUndo)
                    IconButton(
                      tooltip: context.t('Undo'),
                      onPressed: _busy ? null : () => _undo(event),
                      icon: const Icon(Icons.undo_rounded),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.sm),
              _activityRoute(event),
              if (changes.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.t('Changes'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < changes.length;
                        index++
                      ) ...<Widget>[
                        _changeRow(event, changes[index]),
                        if (index != changes.length - 1)
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityRoute(LibraryActivityEvent event) {
    final String? sourceTarget = libraryEventSourceTarget(event);
    final Set<String> targets = <String>{
      ...event.targets,
      ...event.deliveryStates.keys,
    }..remove(sourceTarget);
    final List<String> orderedTargets = targets.toList()
      ..sort(
        (String first, String second) =>
            _targetOrder(first).compareTo(_targetOrder(second)),
      );

    return Column(
      children: <Widget>[
        _routeRow(context.t('From'), <Widget>[
          _routePill(
            icon: _sourceIcon(event),
            label: context.t(libraryEventSourceLabel(event)),
            color: Theme.of(context).colorScheme.secondary,
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _routeRow(context.t('Saved in'), <Widget>[
          _routePill(
            icon: Icons.library_books_outlined,
            label: context.t('Local Library'),
            status: context.t('Saved'),
            color: AppColors.success,
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _routeRow(
          context.t('Sync to'),
          orderedTargets.isEmpty
              ? <Widget>[
                  _routePill(
                    icon: Icons.devices_outlined,
                    label: context.t('Local only'),
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ]
              : orderedTargets
                    .map(
                      (String target) => _deliveryPill(
                        target,
                        event.deliveryStates[target] ?? 'pending',
                      ),
                    )
                    .toList(growable: false),
        ),
      ],
    );
  }

  Widget _routeRow(String label, List<Widget> children) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 84,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: children,
        ),
      ),
    ],
  );

  Widget _routePill({
    required IconData icon,
    required String label,
    required Color color,
    String? status,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.42)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
        if (status != null) ...<Widget>[
          const SizedBox(width: 6),
          Text('·', style: TextStyle(color: color)),
          const SizedBox(width: 6),
          Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ],
    ),
  );

  Widget _deliveryPill(String target, String state) {
    final String normalized = state.toLowerCase();
    final bool complete =
        normalized == 'confirmed' || normalized == 'delivered';
    final bool error = normalized == 'failed' || normalized == 'blocked';
    final bool retry = normalized == 'retry' || normalized == 'retrying';
    final Color color = complete
        ? AppColors.success
        : error
        ? Theme.of(context).colorScheme.error
        : retry
        ? AppColors.warning
        : Theme.of(context).colorScheme.tertiary;
    final IconData icon = complete
        ? Icons.check_circle_outline_rounded
        : error
        ? Icons.error_outline_rounded
        : retry
        ? Icons.sync_problem_outlined
        : Icons.schedule_rounded;
    return _routePill(
      icon: icon,
      label: _targetLabel(target),
      status: context.t(_deliveryStateLabel(normalized)),
      color: color,
    );
  }

  Widget _changeRow(LibraryActivityEvent event, _LibraryChangeLine change) {
    final String before = _displayOperationValue(
      context,
      event,
      change.field,
      change.before,
    );
    final String after = _displayOperationValue(
      context,
      event,
      change.field,
      change.after,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              context.t(_fieldLabel(change.field)),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                _changeValue(
                  event: event,
                  field: change.field,
                  value: change.before,
                  fallback: before,
                  previous: true,
                  unchanged: before == after,
                ),
                const Icon(Icons.arrow_forward_rounded, size: 15),
                _changeValue(
                  event: event,
                  field: change.field,
                  value: change.after,
                  fallback: after,
                  previous: false,
                  unchanged: before == after,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeValue({
    required LibraryActivityEvent event,
    required String field,
    required Object? value,
    required String fallback,
    required bool previous,
    required bool unchanged,
  }) {
    final Color color = previous
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurface;
    if (field == 'score' && value is num && _usesSmileyScore(event, previous)) {
      return Icon(_smileyScoreIcon(value.toDouble()), size: 20, color: color);
    }
    if (field == 'scoreFormat' && _isSmileyFormat(value)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.sentiment_very_dissatisfied, size: 18, color: color),
          const SizedBox(width: 3),
          Icon(Icons.sentiment_neutral, size: 18, color: color),
          const SizedBox(width: 3),
          Icon(Icons.sentiment_very_satisfied, size: 18, color: color),
        ],
      );
    }
    return Text(
      fallback,
      style: previous
          ? Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              decoration: unchanged ? null : TextDecoration.lineThrough,
            )
          : Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  bool _usesSmileyScore(LibraryActivityEvent event, bool previous) {
    final Map<String, dynamic> primary = previous ? event.before : event.after;
    final Map<String, dynamic> fallback = previous ? event.after : event.before;
    return _isSmileyFormat(
      _operationValue(primary, 'scoreFormat') ??
          _operationValue(fallback, 'scoreFormat'),
    );
  }

  Widget _conflictCard(CanonicalLibraryConflict conflict) {
    final bool choose = conflict.canChooseValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${context.t('Library conflict')}: '
                      '${context.t(_fieldLabel(conflict.fieldName))}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                choose
                    ? context.t(
                        'This field changed differently on two devices. Choose which value becomes canonical.',
                      )
                    : context.t(
                        'MiruShin paused this change because it may be unsafe. Your trackers were not changed.',
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _formatTime(conflict.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _resolveConflict(conflict, takeIncoming: false),
                    child: Text(
                      choose
                          ? context.t('Keep local value')
                          : context.t('Acknowledge quarantine'),
                    ),
                  ),
                  if (choose)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () =>
                                _resolveConflict(conflict, takeIncoming: true),
                      child: Text(context.t('Use incoming value')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard() => GlassCard(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(context.t('Could not load sync data. Please try again.')),
    ),
  );

  Future<void> _showAccountPreview(ProviderAccountPreview preview) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext modalContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: <Widget>[
              ListTile(
                title: Text(
                  '${preview.provider.toUpperCase()} · ${preview.accountId}',
                  style: Theme.of(modalContext).textTheme.titleLarge,
                ),
                subtitle: Text(
                  context.t(
                    'Nothing is written to this account until you approve the merge.',
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: preview.entries.isEmpty
                    ? Center(child: Text(context.t('No entries to review.')))
                    : ListView.separated(
                        itemCount: preview.entries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final ProviderAccountPreviewEntry entry =
                              preview.entries[index];
                          final String local = entry.localStatus == null
                              ? context.t('Not in Local Library')
                              : '${entry.localStatus} · ${entry.localProgress}'
                                    '${entry.localScore == null ? '' : ' · ${entry.localScore}'}';
                          final String remote =
                              '${entry.remoteStatus} · ${entry.remoteProgress}'
                              '${entry.remoteScore == null ? '' : ' · ${entry.remoteScore}'}';
                          return ListTile(
                            leading: Icon(
                              entry.changeKind == 'new'
                                  ? Icons.add_circle_outline_rounded
                                  : entry.changeKind == 'unchanged'
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.compare_arrows_rounded,
                            ),
                            title: Text(entry.title),
                            subtitle: Text(
                              '${entry.mediaKind.toUpperCase()} · '
                              '${context.t('Local')}: $local\n'
                              '${preview.provider.toUpperCase()}: $remote',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approve(ProviderAccountPreview preview) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(canonicalLibraryRepositoryProvider)
          .approveProviderAccount(
            provider: preview.provider,
            accountId: preview.accountId,
          );
      ref.invalidate(pendingProviderAccountPreviewsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t('Approved. Refresh Library to perform the merge.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(ProviderAccountPreview preview) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(canonicalLibraryRepositoryProvider)
          .rejectProviderAccount(
            provider: preview.provider,
            accountId: preview.accountId,
          );
      ref.invalidate(pendingProviderAccountPreviewsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(LibraryActivityEvent event) async {
    setState(() => _busy = true);
    try {
      final CanonicalLibraryRepository repository = ref.read(
        canonicalLibraryRepositoryProvider,
      );
      final LibraryUndoPreview preview = await repository.previewUndo(
        event.operationId,
      );
      if (!mounted) return;
      if (!preview.canUndo) {
        throw StateError(
          context.t(
            'Every field from this event has a newer change and is protected.',
          ),
        );
      }
      Set<String>? selected = preview.safeFields;
      if (preview.safeFields.length > 1 || preview.blockedFields.isNotEmpty) {
        selected = await _chooseUndoFields(preview);
      }
      if (selected == null || selected.isEmpty) return;
      await repository.undo(event.operationId, fields: selected);
    } on Object catch (error) {
      debugPrint('Library undo failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t('Could not undo this change. Please try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Set<String>?> _chooseUndoFields(LibraryUndoPreview preview) {
    final Set<String> selected = <String>{...preview.safeFields};
    final List<String> safe = preview.safeFields.toList()..sort();
    final List<String> blocked = preview.blockedFields.toList()..sort();
    return showDialog<Set<String>>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: Text(context.t('Select fields to undo')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final String field in safe)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(field),
                      title: Text(context.t(_fieldLabel(field))),
                      subtitle: Text(
                        '${_undoValue(preview.after, field, context.t)} → '
                        '${_undoValue(preview.before, field, context.t)}',
                      ),
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(field);
                          } else {
                            selected.remove(field);
                          }
                        });
                      },
                    ),
                  if (blocked.isNotEmpty) ...<Widget>[
                    const Divider(),
                    Text(
                      context.t('Newer changes protected'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    for (final String field in blocked)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline_rounded),
                        title: Text(context.t(_fieldLabel(field))),
                        subtitle: Text(
                          context.t(
                            'This field changed later and will not be overwritten.',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () =>
                        Navigator.of(dialogContext).pop(<String>{...selected}),
              child: Text(context.t('Restore selected')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveConflict(
    CanonicalLibraryConflict conflict, {
    required bool takeIncoming,
  }) async {
    setState(() => _busy = true);
    try {
      final SettingsState settings = ref.read(settingsProvider);
      await ref
          .read(canonicalLibraryRepositoryProvider)
          .resolveConflict(
            conflictId: conflict.conflictId,
            takeIncoming: takeIncoming,
            trackerTargets: <TrackerSource>{
              if (settings.hasAniListSession) TrackerSource.anilist,
              if (settings.hasMalSession) TrackerSource.mal,
              if (settings.hasShikimoriSession) TrackerSource.shikimori,
            },
          );
    } on Object catch (error) {
      debugPrint('Library conflict resolution failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t('Could not save your choice. Please try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _originLabel(LibraryOriginKind value) => switch (value) {
  LibraryOriginKind.user => 'MiruShin',
  LibraryOriginKind.player => 'Player',
  LibraryOriginKind.provider => 'Tracker',
  LibraryOriginKind.drive => 'Google Drive',
  LibraryOriginKind.migration => 'Migration',
  LibraryOriginKind.undo => 'Undo',
  LibraryOriginKind.system => 'System',
};

String _intentLabel(LibraryMutationIntent value) => switch (value) {
  LibraryMutationIntent.add => 'Added',
  LibraryMutationIntent.edit => 'Edited',
  LibraryMutationIntent.remove => 'Removed',
  LibraryMutationIntent.progress => 'Progress',
  LibraryMutationIntent.episodeCompleted => 'Episode completed',
  LibraryMutationIntent.streamPreference => 'Stream preference',
  LibraryMutationIntent.remoteImport => 'Imported from tracker',
  LibraryMutationIntent.undo => 'Undo',
};

@visibleForTesting
String libraryChangeSummary(
  LibraryActivityEvent event, {
  String Function(String field)? fieldLabel,
}) {
  final List<String> changes = event.fields.take(4).map((String field) {
    final String before = _shortValue(_operationValue(event.before, field));
    final String after = _shortValue(_operationValue(event.after, field));
    return '${fieldLabel?.call(field) ?? field}: $before → $after';
  }).toList();
  if (event.fields.length > changes.length) {
    changes.add('+${event.fields.length - changes.length}');
  }
  return changes.join(' · ');
}

@visibleForTesting
String? libraryEventSourceTarget(LibraryActivityEvent event) {
  if (event.originKind == LibraryOriginKind.drive) return 'drive';
  if (event.originKind != LibraryOriginKind.provider) return null;
  final String provider = (event.originId ?? '')
      .split(':')
      .first
      .trim()
      .toLowerCase();
  return switch (provider) {
    'anilist' => 'anilist',
    'mal' || 'myanimelist' => 'mal',
    'shiki' || 'shikimori' => 'shikimori',
    _ => null,
  };
}

@visibleForTesting
String libraryEventSourceLabel(LibraryActivityEvent event) {
  final String? provider = libraryEventSourceTarget(event);
  if (provider != null) return _targetLabel(provider);
  return _originLabel(event.originKind);
}

class _LibraryChangeLine {
  const _LibraryChangeLine({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final Object? before;
  final Object? after;
}

List<_LibraryChangeLine> _changeLines(LibraryActivityEvent event) => event
    .fields
    .map(
      (String field) => _LibraryChangeLine(
        field: field,
        before: _operationValue(event.before, field),
        after: _operationValue(event.after, field),
      ),
    )
    .toList(growable: false);

Object? _operationValue(Map<String, dynamic> snapshot, String field) {
  if (field == 'membership') return snapshot['state'] is Map;
  if (field == 'episodeProgress') return snapshot['episode'];
  if (field == 'streamPreference') {
    return snapshot['preference'] ?? snapshot['streamPreference'];
  }
  if (snapshot.containsKey(field)) return snapshot[field];

  final Object? rawState = snapshot['state'];
  if (rawState is! Map) return null;
  final Map<String, dynamic> state = Map<String, dynamic>.from(rawState);
  if (state.containsKey(field)) return state[field];

  final Object? rawProviderStates = state['providerStates'];
  if (rawProviderStates is! Map) return null;
  final String? requiredProvider = switch (field) {
    'priority' ||
    'private' ||
    'hiddenFromStatusLists' ||
    'customLists' ||
    'advancedScores' ||
    'scoreFormat' => 'anilist',
    'malPriority' || 'malRewatchValue' || 'malTags' => 'mal',
    _ => null,
  };
  for (final MapEntry<Object?, Object?> providerEntry
      in rawProviderStates.entries) {
    if (requiredProvider != null &&
        '${providerEntry.key}'.toLowerCase() != requiredProvider) {
      continue;
    }
    final Object? rawProviderState = providerEntry.value;
    if (rawProviderState is! Map) continue;
    final Map<String, dynamic> providerState = Map<String, dynamic>.from(
      rawProviderState,
    );
    if (providerState.containsKey(field)) return providerState[field];
    final Object? rawData = providerState['data'];
    if (rawData is! Map) continue;
    final Map<String, dynamic> data = Map<String, dynamic>.from(rawData);
    if (data.containsKey(field)) return data[field];
    if (field == 'malPriority' && data.containsKey('priority')) {
      return data['priority'];
    }
    if (field == 'malRewatchValue') {
      return data['rewatchValue'] ?? data['rereadValue'];
    }
    if (field == 'malTags' && data.containsKey('tags')) return data['tags'];
  }
  return null;
}

String _fieldLabel(String field) => switch (field) {
  'membership' => 'Library membership',
  'status' => 'Status',
  'progress' => 'Progress',
  'progressVolumes' => 'Volumes read',
  'repeat' => 'Repeat count',
  'score' => 'Score',
  'scoreFormat' => 'Score format',
  'startedAt' => 'Start date',
  'completedAt' => 'Finish date',
  'notes' => 'Notes',
  'favorite' => 'Favorite',
  'priority' => 'Priority',
  'private' => 'Private entry',
  'hiddenFromStatusLists' => 'Hide from status lists',
  'customLists' => 'Custom lists',
  'advancedScores' => 'Advanced scores',
  'malPriority' => 'MAL priority',
  'malRewatchValue' => 'Rewatch value',
  'malTags' => 'MAL tags',
  'episodeProgress' => 'Episode progress',
  'streamPreference' => 'Stream preference',
  'identity' => 'Tracker ID matching',
  'massProviderChange' => 'Multiple tracker changes',
  _ => field,
};

String _shortValue(Object? value) {
  if (value == null || value == '') return '—';
  final String text = value is Map || value is Iterable ? '$value' : '$value';
  return text.length <= 36 ? text : '${text.substring(0, 33)}…';
}

String _displayOperationValue(
  BuildContext context,
  LibraryActivityEvent event,
  String field,
  Object? value,
) {
  if (value == null || value == '') return context.t('Not set');
  if (field == 'membership' && value is bool) {
    return context.t(value ? 'In library' : 'Not in library');
  }
  if (field == 'status') {
    final bool manga = _eventMediaKind(event) == 'manga';
    return context.t(switch ('$value'.toLowerCase()) {
      'planning' => 'Planning',
      'current' => manga ? 'Reading' : 'Watching',
      'paused' => 'Paused',
      'completed' => 'Completed',
      'dropped' => 'Dropped',
      'repeating' => manga ? 'Rereading' : 'Rewatching',
      _ => '$value',
    });
  }
  if (value is bool) return context.t(value ? 'Yes' : 'No');
  if (field == 'score' && value is num) {
    final Object? rawFormat =
        _operationValue(event.after, 'scoreFormat') ??
        _operationValue(event.before, 'scoreFormat');
    final CanonicalScoreFormat format = CanonicalScoreFormat.fromAniList(
      rawFormat?.toString(),
    );
    return format.displayLabel((value.toDouble() * 10).round());
  }
  if (field == 'malPriority' && value is num) {
    return context.t(switch (value.toInt()) {
      1 => 'Medium',
      2 => 'High',
      _ => 'Low',
    });
  }
  if (field == 'scoreFormat') {
    return switch ('$value'.toUpperCase()) {
      'POINT_100' || 'POINT100' => '100',
      'POINT_10_DECIMAL' || 'POINT10DECIMAL' => '10.0',
      'POINT_10' || 'POINT10' => '10',
      'POINT_5' || 'POINT5' => '5 ★',
      'POINT_3' || 'POINT3' || 'SMILEY' => ':(  :|  :)',
      _ => '$value',
    };
  }
  if (field == 'episodeProgress' && value is Map) {
    return _episodeValue(context, Map<String, dynamic>.from(value));
  }
  if (field == 'streamPreference' && value is Map) {
    return _streamValue(context, Map<String, dynamic>.from(value));
  }
  if ((field == 'startedAt' || field == 'completedAt') && value is String) {
    final DateTime? date = DateTime.tryParse(value);
    if (date != null) return _formatDate(date);
  }
  if (field == 'customLists' && value is Map) {
    final List<String> active = value.entries
        .where((MapEntry<Object?, Object?> entry) => entry.value == true)
        .map((MapEntry<Object?, Object?> entry) => '${entry.key}')
        .toList(growable: false);
    return active.isEmpty ? context.t('Not set') : active.join(', ');
  }
  if (field == 'advancedScores' && value is Map) {
    if (value.isEmpty) return context.t('Not set');
    return value.entries
        .map(
          (MapEntry<Object?, Object?> entry) => '${entry.key}: ${entry.value}',
        )
        .join(', ');
  }
  if (field == 'identity' || field == 'massProviderChange') {
    return context.t('Updated');
  }
  if (value is num) {
    return value is double && value == value.roundToDouble()
        ? '${value.toInt()}'
        : '$value';
  }
  if (value is Iterable) {
    final String text = value.join(', ');
    return text.isEmpty ? context.t('Not set') : _truncateValue(text);
  }
  if (value is Map) {
    if (value.isEmpty) return context.t('Not set');
    return _truncateValue(
      value.entries
          .map(
            (MapEntry<Object?, Object?> entry) =>
                '${entry.key}: ${entry.value}',
          )
          .join(', '),
    );
  }
  return _truncateValue('$value');
}

String _eventMediaKind(LibraryActivityEvent event) {
  for (final Map<String, dynamic> snapshot in <Map<String, dynamic>>[
    event.after,
    event.before,
  ]) {
    final Object? rawState = snapshot['state'];
    if (rawState is! Map) continue;
    final Object? rawIdentity = rawState['identity'];
    if (rawIdentity is! Map) continue;
    final String kind =
        '${rawIdentity['mediaKind'] ?? rawIdentity['kind'] ?? ''}'
            .toLowerCase();
    if (kind == 'anime' || kind == 'manga') return kind;
  }
  return 'anime';
}

String _episodeValue(BuildContext context, Map<String, dynamic> value) {
  final List<String> parts = <String>[];
  final int season = (value['season'] as num?)?.toInt() ?? 0;
  final int episode = (value['episode'] as num?)?.toInt() ?? 0;
  if (season > 0) parts.add('${context.t('Season')} $season');
  if (episode > 0) parts.add('${context.t('Episode')} $episode');
  final int seconds = (value['positionSeconds'] as num?)?.toInt() ?? 0;
  if (seconds > 0) parts.add(_formatDuration(seconds));
  if (value['completed'] == true) parts.add(context.t('Completed'));
  return parts.isEmpty ? context.t('Not set') : parts.join(' · ');
}

String _streamValue(BuildContext context, Map<String, dynamic> value) {
  final List<String> parts = <String>[
    '${value['sourceTitle'] ?? value['sourceId'] ?? ''}'.trim(),
    '${value['serverTitle'] ?? value['serverId'] ?? ''}'.trim(),
    '${value['voiceoverTitle'] ?? value['voiceoverId'] ?? ''}'.trim(),
    '${value['qualityLabel'] ?? value['qualityId'] ?? ''}'.trim(),
  ].where((String part) => part.isNotEmpty).toList(growable: false);
  return parts.isEmpty ? context.t('Not set') : parts.join(' · ');
}

String _truncateValue(String value) {
  final String normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.length <= 72
      ? normalized
      : '${normalized.substring(0, 69)}…';
}

String _formatDuration(int seconds) {
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  final int remainder = seconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(remainder)}'
      : '$minutes:${two(remainder)}';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _targetLabel(String target) => switch (target.toLowerCase()) {
  'drive' => 'Google Drive',
  'anilist' => 'AniList',
  'mal' || 'myanimelist' => 'MyAnimeList',
  'shiki' || 'shikimori' => 'Shikimori',
  _ => target,
};

int _targetOrder(String target) => switch (target.toLowerCase()) {
  'drive' => 0,
  'anilist' => 1,
  'mal' || 'myanimelist' => 2,
  'shiki' || 'shikimori' => 3,
  _ => 10,
};

String _deliveryStateLabel(String state) => switch (state) {
  'confirmed' || 'delivered' => 'Synced',
  'retry' || 'retrying' => 'Retrying',
  'failed' => 'Failed',
  'blocked' => 'Needs attention',
  _ => 'Waiting',
};

bool _isSmileyFormat(Object? value) {
  final String format = '$value'.trim().toUpperCase();
  return format == 'POINT_3' || format == 'POINT3' || format == 'SMILEY';
}

IconData _smileyScoreIcon(double score) {
  if (score <= 3) {
    if (score < 1.5) return Icons.sentiment_very_dissatisfied;
    if (score < 2.5) return Icons.sentiment_neutral;
    return Icons.sentiment_very_satisfied;
  }
  if (score < 5) return Icons.sentiment_very_dissatisfied;
  if (score < 7.5) return Icons.sentiment_neutral;
  return Icons.sentiment_very_satisfied;
}

IconData _sourceIcon(LibraryActivityEvent event) {
  final String? provider = libraryEventSourceTarget(event);
  if (provider == 'drive') return Icons.cloud_download_outlined;
  if (provider != null) return Icons.sync_alt_rounded;
  return switch (event.originKind) {
    LibraryOriginKind.user => Icons.touch_app_outlined,
    LibraryOriginKind.player => Icons.play_circle_outline_rounded,
    LibraryOriginKind.provider => Icons.cloud_download_outlined,
    LibraryOriginKind.drive => Icons.cloud_download_outlined,
    LibraryOriginKind.migration => Icons.move_to_inbox_outlined,
    LibraryOriginKind.undo => Icons.undo_rounded,
    LibraryOriginKind.system => Icons.settings_outlined,
  };
}

String _undoValue(
  Map<String, dynamic> snapshot,
  String field,
  String Function(String value) translate,
) {
  if (field == 'membership') {
    return snapshot['state'] is Map
        ? translate('In library')
        : translate('Not in library');
  }
  return _shortValue(_operationValue(snapshot, field));
}

IconData _intentIcon(LibraryMutationIntent value) => switch (value) {
  LibraryMutationIntent.add => Icons.add_rounded,
  LibraryMutationIntent.remove => Icons.delete_outline_rounded,
  LibraryMutationIntent.progress => Icons.play_arrow_rounded,
  LibraryMutationIntent.episodeCompleted => Icons.check_rounded,
  LibraryMutationIntent.streamPreference => Icons.tune_rounded,
  LibraryMutationIntent.remoteImport => Icons.cloud_download_outlined,
  LibraryMutationIntent.undo => Icons.undo_rounded,
  LibraryMutationIntent.edit => Icons.edit_outlined,
};

String _formatTime(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
