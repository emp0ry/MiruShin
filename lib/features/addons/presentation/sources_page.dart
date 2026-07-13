import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation_helpers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/include_exclude_filter_chip.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/page_back_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../core/widgets/tv_focusable.dart';
import '../../../core/widgets/tv_text_field_focus.dart';
import '../application/addon_sources_provider.dart';
import '../application/sora_addons_provider.dart';
import '../domain/addon_source_models.dart';
import '../domain/sora_models.dart';

class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AddonSourcesState state = ref.watch(addonSourcesProvider);
    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PageBackButton(
                  onPressed: () => goBackOrGo(context, AppRoutes.addons),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SectionHeader(
                    title: context.t('Sources'),
                    subtitle: context.t(
                      'Add module catalogs, then browse and install addons.',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _SourcesHero(state: state),
            const SizedBox(height: AppSpacing.xxl),
            _SourcesList(state: state),
          ],
        ),
      ),
    );
  }
}

class _SourcesHero extends ConsumerWidget {
  const _SourcesHero({required this.state});

  final AddonSourcesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      radius: AppRadius.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.t('Addon sources'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.t(
              'A source is a catalog URL that lists modules you can browse '
              'and install. There are no built-in sources, so add your own '
              'to get started.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => _showAddSourceDialog(context),
                icon: const Icon(Icons.add_link_rounded),
                label: Text(context.t('Add Source')),
              ),
              OutlinedButton.icon(
                onPressed: state.isEmpty
                    ? null
                    : () => ref.read(addonSourcesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.t('Refresh All')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourcesList extends ConsumerWidget {
  const _SourcesList({required this.state});

  final AddonSourcesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return const SkeletonBox(height: 220, radius: AppRadius.xxl);
    }
    if (state.isEmpty) {
      return NeutralPlaceholder(
        title: context.t('No sources added'),
        message: context.t(
          'Add a module catalog URL to browse its addons and install them.',
        ),
        height: 280,
        icon: Icons.travel_explore_rounded,
        action: FilledButton.icon(
          onPressed: () => _showAddSourceDialog(context),
          icon: const Icon(Icons.add_link_rounded),
          label: Text(context.t('Add Source')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: context.t('Your sources')),
        for (int index = 0; index < state.sources.length; index++)
          Padding(
            key: ValueKey<String>(state.sources[index].id),
            padding: EdgeInsets.only(
              bottom: index == state.sources.length - 1 ? 0 : AppSpacing.md,
            ),
            child: _SourceCard(source: state.sources[index]),
          ),
      ],
    );
  }
}

class _SourceCard extends ConsumerWidget {
  const _SourceCard({required this.source});

  final AddonSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AddonCatalogEntry>> catalog = ref.watch(
      addonCatalogProvider(source.url),
    );
    return TvFocusable(
      onTap: () => context.openSourceModules(source),
      interactPointer: false,
      borderRadius: AppRadius.all(AppRadius.lg),
      child: GlassCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => context.openSourceModules(source),
        canRequestFocus: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: AppRadius.all(AppRadius.md),
              ),
              child: const Icon(Icons.travel_explore_rounded),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    source.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  catalog.when(
                    data: (List<AddonCatalogEntry> entries) => Text(
                      context.tf('{count} modules', <String, Object?>{
                        'count': entries.length,
                      }),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    loading: () => Text(
                      context.t('Loading...'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    error: (Object error, _) => Text(
                      context.t('Could not load catalog'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Builder(
              builder: (BuildContext menuContext) => IconButton(
                tooltip: context.t('Source actions'),
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _showSourceMenu(menuContext, ref, source),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SourceAction { browse, copyUrl, rename, remove }

Future<void> _showSourceMenu(
  BuildContext context,
  WidgetRef ref,
  AddonSource source,
) async {
  final RenderBox button = context.findRenderObject()! as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final Offset bottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final _SourceAction? action = await showMenu<_SourceAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    ),
    items: <PopupMenuEntry<_SourceAction>>[
      PopupMenuItem<_SourceAction>(
        value: _SourceAction.browse,
        child: Text(context.t('Browse modules')),
      ),
      PopupMenuItem<_SourceAction>(
        value: _SourceAction.copyUrl,
        child: Text(context.t('Copy URL')),
      ),
      PopupMenuItem<_SourceAction>(
        value: _SourceAction.rename,
        child: Text(context.t('Rename')),
      ),
      PopupMenuItem<_SourceAction>(
        value: _SourceAction.remove,
        child: Text(context.t('Remove')),
      ),
    ],
  );
  if (action == null || !context.mounted) {
    return;
  }
  switch (action) {
    case _SourceAction.browse:
      context.openSourceModules(source);
    case _SourceAction.copyUrl:
      await Clipboard.setData(ClipboardData(text: source.url));
      if (context.mounted) _showSnack(context, context.t('Source URL copied'));
    case _SourceAction.rename:
      await _showRenameSourceDialog(context, ref, source);
    case _SourceAction.remove:
      final bool confirmed = await _confirmRemoveSource(context, source);
      if (confirmed) {
        await ref.read(addonSourcesProvider.notifier).removeSource(source.id);
        if (context.mounted) _showSnack(context, context.t('Source removed'));
      }
  }
}

Future<bool> _confirmRemoveSource(
  BuildContext context,
  AddonSource source,
) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(context.t('Remove Source')),
      content: Text(
        context.tf(
          'Remove {name}? Installed addons stay in your library.',
          <String, Object?>{'name': source.displayName},
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t('Remove')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<void> _showRenameSourceDialog(
  BuildContext context,
  WidgetRef ref,
  AddonSource source,
) async {
  final TextEditingController controller = TextEditingController(
    text: source.name,
  );
  final String? name = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(context.t('Rename Source')),
      content: TvTextFieldFocus(
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.t('Source name')),
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(context.t('Save')),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name != null && context.mounted) {
    await ref.read(addonSourcesProvider.notifier).renameSource(source.id, name);
  }
}

Future<void> _showAddSourceDialog(BuildContext context) async {
  final AddonSource? added = await showDialog<AddonSource>(
    context: context,
    builder: (BuildContext context) => const _AddSourceDialog(),
  );
  if (added != null && context.mounted) {
    _showSnack(
      context,
      context.tf('{name} added', <String, Object?>{'name': added.displayName}),
    );
  }
}

class _AddSourceDialog extends ConsumerStatefulWidget {
  const _AddSourceDialog();

  @override
  ConsumerState<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends ConsumerState<_AddSourceDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _add() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AddonSource source = await ref
          .read(addonSourcesProvider.notifier)
          .addSource(_controller.text);
      if (mounted) Navigator.of(context).pop(source);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is SoraAddonException ? error.message : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return AlertDialog(
      backgroundColor: palette.surfaceColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.xl),
        side: BorderSide(color: palette.borderColor),
      ),
      title: Text(context.t('Add Source')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TvTextFieldFocus(
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                enabled: !_loading,
                decoration: InputDecoration(
                  labelText: context.t('Catalog URL'),
                  hintText: 'example.com/modules.json',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: IconButton(
                    tooltip: context.t('Paste'),
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _loading ? null : _pasteFromClipboard,
                  ),
                ),
                onSubmitted: (_) => _loading ? null : _add(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        FilledButton.icon(
          onPressed: _loading ? null : _add,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
          label: Text(context.t('Add')),
        ),
      ],
    );
  }
}

// ===========================================================================
// Source modules browser
// ===========================================================================

class SourceModulesPage extends ConsumerStatefulWidget {
  const SourceModulesPage({required this.source, super.key});

  final AddonSource source;

  @override
  ConsumerState<SourceModulesPage> createState() => _SourceModulesPageState();
}

class _SourceModulesPageState extends ConsumerState<SourceModulesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  // Multi-select: empty set means "all". An entry matches a category when the
  // set is empty or contains the entry's value.
  final Set<String> _languageFilters = <String>{};
  final Set<String> _languageExcludes = <String>{};
  final Set<String> _typeFilters = <String>{};
  final Set<String> _typeExcludes = <String>{};
  bool? _downloadSupportFilter;
  final Set<String> _installing = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _activeFilterCount =>
      _languageFilters.length +
      _languageExcludes.length +
      _typeFilters.length +
      _typeExcludes.length +
      (_downloadSupportFilter == null ? 0 : 1);

  List<AddonCatalogEntry> _filter(List<AddonCatalogEntry> entries) {
    final String query = _query.trim().toLowerCase();
    return entries
        .where((AddonCatalogEntry entry) {
          if (query.isNotEmpty &&
              !entry.sourceName.toLowerCase().contains(query) &&
              !entry.language.toLowerCase().contains(query) &&
              !entry.type.toLowerCase().contains(query) &&
              !entry.author.name.toLowerCase().contains(query)) {
            return false;
          }
          if (_languageFilters.isNotEmpty &&
              !_languageFilters.contains(entry.language)) {
            return false;
          }
          if (_languageExcludes.contains(entry.language)) {
            return false;
          }
          if (_typeFilters.isNotEmpty && !_typeFilters.contains(entry.type)) {
            return false;
          }
          if (_typeExcludes.contains(entry.type)) {
            return false;
          }
          if (_downloadSupportFilter == true && !entry.downloadSupport) {
            return false;
          }
          if (_downloadSupportFilter == false && entry.downloadSupport) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<void> _install(AddonCatalogEntry entry) async {
    setState(() => _installing.add(entry.manifestUrl));
    final SoraInstalledAddon? installed = await ref
        .read(soraAddonsProvider.notifier)
        .installFromUrl(entry.installUrl);
    if (!mounted) return;
    setState(() => _installing.remove(entry.manifestUrl));
    if (installed != null) {
      _showSnack(
        context,
        context.tf('{name} installed', <String, Object?>{
          'name': installed.manifest.sourceName,
        }),
      );
    } else {
      _showSnack(
        context,
        ref.read(soraAddonsProvider).error ??
            context.t('Could not install addon.'),
      );
    }
  }

  Future<void> _showFilterSheet(List<AddonCatalogEntry> entries) async {
    final List<String> languages = _distinct(
      entries.map((AddonCatalogEntry e) => e.language),
    );
    final List<String> types = _distinct(
      entries.map((AddonCatalogEntry e) => e.type),
    );
    final Set<String> tmpLanguageFilters = Set<String>.from(_languageFilters);
    final Set<String> tmpLanguageExcludes = Set<String>.from(_languageExcludes);
    final Set<String> tmpTypeFilters = Set<String>.from(_typeFilters);
    final Set<String> tmpTypeExcludes = Set<String>.from(_typeExcludes);
    bool? tmpDownloadSupportFilter = _downloadSupportFilter;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            void updateSheet(VoidCallback change) {
              change();
              setSheetState(() {});
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            context.t('Filters'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        TextButton(
                          onPressed: () => updateSheet(() {
                            tmpLanguageFilters.clear();
                            tmpLanguageExcludes.clear();
                            tmpTypeFilters.clear();
                            tmpTypeExcludes.clear();
                            tmpDownloadSupportFilter = null;
                          }),
                          child: Text(context.t('Clear all')),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _languageFilters
                                ..clear()
                                ..addAll(tmpLanguageFilters);
                              _languageExcludes
                                ..clear()
                                ..addAll(tmpLanguageExcludes);
                              _typeFilters
                                ..clear()
                                ..addAll(tmpTypeFilters);
                              _typeExcludes
                                ..clear()
                                ..addAll(tmpTypeExcludes);
                              _downloadSupportFilter = tmpDownloadSupportFilter;
                            });
                            Navigator.pop(sheetContext);
                          },
                          child: Text(context.t('Apply')),
                        ),
                      ],
                    ),
                    if (languages.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.t('Language'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: <Widget>[
                          FilterChip(
                            label: Text(context.t('All languages')),
                            selected:
                                tmpLanguageFilters.isEmpty &&
                                tmpLanguageExcludes.isEmpty,
                            onSelected: (_) => updateSheet(() {
                              tmpLanguageFilters.clear();
                              tmpLanguageExcludes.clear();
                            }),
                          ),
                          for (final String language in languages)
                            IncludeExcludeFilterChip(
                              label: language,
                              state: includeExcludeStateOf<String>(
                                language,
                                tmpLanguageFilters,
                                tmpLanguageExcludes,
                              ),
                              onInclude: () => updateSheet(() {
                                setIncludeExcludeSelection<String>(
                                  included: tmpLanguageFilters,
                                  excluded: tmpLanguageExcludes,
                                  value: language,
                                  state: IncludeExcludeState.included,
                                );
                              }),
                              onExclude: () => updateSheet(() {
                                setIncludeExcludeSelection<String>(
                                  included: tmpLanguageFilters,
                                  excluded: tmpLanguageExcludes,
                                  value: language,
                                  state: IncludeExcludeState.excluded,
                                );
                              }),
                              onClear: () => updateSheet(() {
                                setIncludeExcludeSelection<String>(
                                  included: tmpLanguageFilters,
                                  excluded: tmpLanguageExcludes,
                                  value: language,
                                  state: IncludeExcludeState.neutral,
                                );
                              }),
                            ),
                        ],
                      ),
                    ],
                    if (types.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        context.t('Type'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: <Widget>[
                          FilterChip(
                            label: Text(context.t('All types')),
                            selected:
                                tmpTypeFilters.isEmpty &&
                                tmpTypeExcludes.isEmpty,
                            onSelected: (_) => updateSheet(() {
                              tmpTypeFilters.clear();
                              tmpTypeExcludes.clear();
                            }),
                          ),
                          for (final String type in types)
                            IncludeExcludeFilterChip(
                              label: type,
                              state: includeExcludeStateOf<String>(
                                type,
                                tmpTypeFilters,
                                tmpTypeExcludes,
                              ),
                              onInclude: () => updateSheet(() {
                                setIncludeExcludeSelection<String>(
                                  included: tmpTypeFilters,
                                  excluded: tmpTypeExcludes,
                                  value: type,
                                  state: IncludeExcludeState.included,
                                );
                              }),
                              onExclude: () => updateSheet(() {
                                setIncludeExcludeSelection<String>(
                                  included: tmpTypeFilters,
                                  excluded: tmpTypeExcludes,
                                  value: type,
                                  state: IncludeExcludeState.excluded,
                                );
                              }),
                              onClear: () => updateSheet(() {
                                setIncludeExcludeSelection<String>(
                                  included: tmpTypeFilters,
                                  excluded: tmpTypeExcludes,
                                  value: type,
                                  state: IncludeExcludeState.neutral,
                                );
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        IncludeExcludeFilterChip(
                          label: context.t('Download support'),
                          state: switch (tmpDownloadSupportFilter) {
                            true => IncludeExcludeState.included,
                            false => IncludeExcludeState.excluded,
                            null => IncludeExcludeState.neutral,
                          },
                          onInclude: () => updateSheet(
                            () => tmpDownloadSupportFilter = true,
                          ),
                          onExclude: () => updateSheet(
                            () => tmpDownloadSupportFilter = false,
                          ),
                          onClear: () => updateSheet(
                            () => tmpDownloadSupportFilter = null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<String> _distinct(Iterable<String> values) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String value in values) {
      final String trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      result.add(trimmed);
    }
    result.sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AddonCatalogEntry>> catalog = ref.watch(
      addonCatalogProvider(widget.source.url),
    );
    final Set<String> installedUrls = ref
        .watch(soraAddonsProvider)
        .installed
        .map(
          (SoraInstalledAddon addon) => addon.manifestUrl.trim().toLowerCase(),
        )
        .toSet();
    final List<AddonCatalogEntry> allEntries =
        catalog.asData?.value ?? const <AddonCatalogEntry>[];

    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PageBackButton(
                  onPressed: () => goBackOrGo(context, AppRoutes.addonsSources),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SectionHeader(
                    title: widget.source.displayName,
                    subtitle: widget.source.url,
                  ),
                ),
                IconButton(
                  tooltip: context.t('Refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () =>
                      ref.invalidate(addonCatalogProvider(widget.source.url)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: TvTextFieldFocus(
                    releaseHorizontal: true,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: context.t('Search addons'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onChanged: (String value) =>
                          setState(() => _query = value),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterButton(
                  activeCount: _activeFilterCount,
                  onPressed: allEntries.isEmpty
                      ? null
                      : () => _showFilterSheet(allEntries),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            catalog.when(
              loading: () =>
                  const SkeletonBox(height: 320, radius: AppRadius.xxl),
              error: (Object error, _) => NeutralPlaceholder(
                title: context.t('Could not load catalog'),
                message: error is SoraAddonException
                    ? error.message
                    : error.toString(),
                height: 320,
                icon: Icons.cloud_off_rounded,
                action: FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(addonCatalogProvider(widget.source.url)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.t('Retry')),
                ),
              ),
              data: (List<AddonCatalogEntry> entries) {
                final List<AddonCatalogEntry> filtered = _filter(entries);
                if (filtered.isEmpty) {
                  return NeutralPlaceholder(
                    title: context.t('No modules found'),
                    message: entries.isEmpty
                        ? context.t('This source has no modules.')
                        : context.t('No modules match your search.'),
                    height: 280,
                    icon: Icons.extension_off_rounded,
                  );
                }
                return Column(
                  children: <Widget>[
                    for (int index = 0; index < filtered.length; index++)
                      Padding(
                        key: ValueKey<String>(
                          '${filtered[index].id}:${filtered[index].manifestUrl}',
                        ),
                        padding: EdgeInsets.only(
                          bottom: index == filtered.length - 1
                              ? 0
                              : AppSpacing.md,
                        ),
                        child: _ModuleCard(
                          entry: filtered[index],
                          installed: installedUrls.contains(
                            filtered[index].manifestUrl.trim().toLowerCase(),
                          ),
                          installing: _installing.contains(
                            filtered[index].manifestUrl,
                          ),
                          onInstall: () => _install(filtered[index]),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Widget icon = activeCount > 0
        ? Badge(
            label: Text('$activeCount'),
            child: const Icon(Icons.tune_rounded),
          )
        : const Icon(Icons.tune_rounded);
    return IconButton.filledTonal(
      tooltip: context.t('Filters'),
      onPressed: onPressed,
      icon: icon,
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.entry,
    required this.installed,
    required this.installing,
    required this.onInstall,
  });

  final AddonCatalogEntry entry;
  final bool installed;
  final bool installing;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SourceNetworkIcon(url: entry.iconUrl, size: 44),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            entry.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (entry.author.name.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: <Widget>[
                                _SourceNetworkIcon(
                                  url: entry.author.iconUrl,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    entry.author.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (entry.note.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    entry.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    if (entry.type.isNotEmpty) MetadataChip(label: entry.type),
                    if (entry.language.isNotEmpty)
                      MetadataChip(label: entry.language.toUpperCase()),
                    if (entry.quality.isNotEmpty)
                      MetadataChip(label: entry.quality),
                    if (entry.version.isNotEmpty)
                      MetadataChip(label: 'v${entry.version}'),
                    if (entry.softsub)
                      MetadataChip(label: context.t('Softsub')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _ModuleInstallButton(
            installed: installed,
            installing: installing,
            installable: entry.isInstallable,
            onInstall: onInstall,
          ),
        ],
      ),
    );
  }
}

class _ModuleInstallButton extends StatelessWidget {
  const _ModuleInstallButton({
    required this.installed,
    required this.installing,
    required this.installable,
    required this.onInstall,
  });

  final bool installed;
  final bool installing;
  final bool installable;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    if (installing) {
      return const SizedBox.square(
        dimension: 36,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (installed) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: Text(context.t('Installed')),
      );
    }
    return FilledButton.icon(
      onPressed: installable ? onInstall : null,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(context.t('Add')),
    );
  }
}

class _SourceNetworkIcon extends StatelessWidget {
  const _SourceNetworkIcon({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        borderRadius: AppRadius.all(AppRadius.md),
      ),
      child: Icon(Icons.extension_rounded, size: size * 0.48),
    );
    if (url.trim().isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.md),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (BuildContext context, String url) => fallback,
        errorWidget: (BuildContext context, String url, Object error) =>
            fallback,
      ),
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

extension _OpenSourceModules on BuildContext {
  void openSourceModules(AddonSource source) {
    Navigator.of(this).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SourceModulesPage(source: source),
      ),
    );
  }
}
