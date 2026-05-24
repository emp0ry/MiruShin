import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../application/sora_addons_provider.dart';
import '../domain/sora_models.dart';

class AddonsPage extends ConsumerStatefulWidget {
  const AddonsPage({super.key});

  @override
  ConsumerState<AddonsPage> createState() => _AddonsPageState();
}

class _AddonsPageState extends ConsumerState<AddonsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(soraAddonsProvider.notifier).autoUpdateStale();
    });
  }

  @override
  Widget build(BuildContext context) {
    final SoraAddonsState state = ref.watch(soraAddonsProvider);
    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _AddonHero(state: state),
            const SizedBox(height: AppSpacing.xxl),
            _InstalledAddons(state: state),
          ],
        ),
      ),
    );
  }
}

class _AddonHero extends ConsumerWidget {
  const _AddonHero({required this.state});

  final SoraAddonsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      radius: AppRadius.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              MetadataChip(label: context.t('Sora module runtime')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            context.t('Sora Addons'),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.t(
              'Install Sora-compatible JSON modules by URL. MiruShin keeps a local working copy, updates safely, and lets media pages search enabled addons as sources.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              FilledButton.icon(
                onPressed: state.previewing || state.updating
                    ? null
                    : () => _showAddAddonDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.t('Add Addon')),
              ),
              OutlinedButton.icon(
                onPressed: state.installed.isEmpty || state.updating
                    ? null
                    : () => ref.read(soraAddonsProvider.notifier).updateAll(),
                icon: const Icon(Icons.update_rounded),
                label: Text(
                  state.updating
                      ? context.t('Updating...')
                      : context.t('Update All'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: state.installed.isEmpty || state.updating
                    ? null
                    : () => _exportAddons(context, ref),
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(context.t('Export')),
              ),
              OutlinedButton.icon(
                onPressed: state.updating || state.previewing
                    ? null
                    : () => _importAddons(context, ref),
                icon: const Icon(Icons.file_download_outlined),
                label: Text(context.t('Import')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _TrustWarning(error: state.error),
        ],
      ),
    );
  }
}

class _TrustWarning extends StatelessWidget {
  const _TrustWarning({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: (error == null ? AppColors.warning : AppColors.danger)
            .withValues(alpha: 0.12),
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(
          color: (error == null ? AppColors.warning : AppColors.danger)
              .withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            error == null
                ? Icons.warning_amber_rounded
                : Icons.error_outline_rounded,
            color: error == null ? AppColors.warning : AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              error ??
                  context.t(
                    'Addons are third-party code that can make network requests. Only install modules from creators you trust.',
                  ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstalledAddons extends ConsumerWidget {
  const _InstalledAddons({required this.state});

  final SoraAddonsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading) {
      return const SkeletonBox(height: 340, radius: AppRadius.xxl);
    }
    if (state.installed.isEmpty) {
      return NeutralPlaceholder(
        title: context.t('No Sora addons installed'),
        message: context.t(
          'Paste a Sora manifest JSON URL to preview the module before adding it.',
        ),
        height: 340,
        icon: Icons.extension_off_rounded,
        action: FilledButton.icon(
          onPressed: () => _showAddAddonDialog(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.t('Add Addon')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: context.t('Installed Addons'),
          subtitle:
              '${state.installed.where((SoraInstalledAddon addon) => addon.enabled).length}/${state.installed.length} ${context.t('enabled')}',
        ),
        _AddonOrderedList(addons: state.installed),
      ],
    );
  }
}

class _AddonOrderedList extends StatelessWidget {
  const _AddonOrderedList({required this.addons});

  final List<SoraInstalledAddon> addons;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int index = 0; index < addons.length; index++)
          Padding(
            key: ValueKey<String>(addons[index].id),
            padding: EdgeInsets.only(
              bottom: index == addons.length - 1 ? 0 : AppSpacing.md,
            ),
            child: _AddonCard(
              addon: addons[index],
              index: index,
              itemCount: addons.length,
            ),
          ),
      ],
    );
  }
}

class _AddonCard extends ConsumerWidget {
  const _AddonCard({
    required this.addon,
    required this.index,
    required this.itemCount,
  });

  final SoraInstalledAddon addon;
  final int index;
  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SoraAddonManifest manifest = addon.manifest;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderColor: addon.enabled
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.36)
          : null,
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
                    _NetworkIcon(url: manifest.iconUrl, size: 44),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            manifest.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          if (manifest.author.name.isNotEmpty)
                            Row(
                              children: <Widget>[
                                _NetworkIcon(
                                  url: manifest.author.iconUrl,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    manifest.author.name,
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
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (manifest.description.isNotEmpty) ...<Widget>[
                  Text(
                    manifest.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    if (manifest.type.isNotEmpty)
                      MetadataChip(label: manifest.type),
                    if (manifest.language.isNotEmpty)
                      MetadataChip(label: manifest.language.toUpperCase()),
                    if (manifest.quality.isNotEmpty)
                      MetadataChip(label: manifest.quality),
                    if (manifest.version.isNotEmpty)
                      MetadataChip(label: 'v${manifest.version}'),
                    if (manifest.softsub)
                      MetadataChip(label: context.t('Softsub')),
                    if (addon.lastError != null)
                      MetadataChip(
                        label: context.t('Update issue'),
                        icon: Icons.error_outline_rounded,
                        color: AppColors.danger,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  addon.lastCheckedAt == null
                      ? context.t('Not checked yet')
                      : '${context.t('Checked')} ${_relativeTime(addon.lastCheckedAt!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (addon.lastError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    addon.lastError!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _AddonCardControls(addon: addon, index: index, itemCount: itemCount),
        ],
      ),
    );
  }
}

class _AddonCardControls extends ConsumerWidget {
  const _AddonCardControls({
    required this.addon,
    required this.index,
    required this.itemCount,
  });

  final SoraInstalledAddon addon;
  final int index;
  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Builder(
            builder: (BuildContext menuContext) {
              return IconButton(
                tooltip: context.t('Addon actions'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _showAddonActionMenu(menuContext, ref, addon),
              );
            },
          ),
          if (itemCount > 1)
            _AddonOrderControls(index: index, itemCount: itemCount),
          Switch.adaptive(
            value: addon.enabled,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (bool value) => ref
                .read(soraAddonsProvider.notifier)
                .setEnabled(addon.id, value),
          ),
        ],
      ),
    );
  }
}

class _AddonOrderControls extends ConsumerWidget {
  const _AddonOrderControls({required this.index, required this.itemCount});

  final int index;
  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        IconButton(
          tooltip: context.t('Move addon up'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: index == 0
              ? null
              : () => ref
                    .read(soraAddonsProvider.notifier)
                    .reorder(index, index - 1),
        ),
        IconButton(
          tooltip: context.t('Move addon down'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: index == itemCount - 1
              ? null
              : () => ref
                    .read(soraAddonsProvider.notifier)
                    .reorder(index, index + 1),
        ),
      ],
    );
  }
}

class _NetworkIcon extends StatelessWidget {
  const _NetworkIcon({required this.url, required this.size});

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

enum _AddonAction { copyUrl, update, remove }

Future<void> _showAddonActionMenu(
  BuildContext context,
  WidgetRef ref,
  SoraInstalledAddon addon,
) async {
  final RenderBox button = context.findRenderObject()! as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final Offset bottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final _AddonAction? action = await showMenu<_AddonAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    ),
    items: <PopupMenuEntry<_AddonAction>>[
      PopupMenuItem<_AddonAction>(
        value: _AddonAction.copyUrl,
        child: Text(context.t('Copy URL')),
      ),
      PopupMenuItem<_AddonAction>(
        value: _AddonAction.update,
        child: Text(context.t('Update')),
      ),
      PopupMenuItem<_AddonAction>(
        value: _AddonAction.remove,
        child: Text(context.t('Remove')),
      ),
    ],
  );
  if (action != null && context.mounted) {
    await _handleAction(context, ref, action, addon);
  }
}

Future<void> _handleAction(
  BuildContext context,
  WidgetRef ref,
  _AddonAction action,
  SoraInstalledAddon addon,
) async {
  switch (action) {
    case _AddonAction.copyUrl:
      await Clipboard.setData(ClipboardData(text: addon.manifestUrl));
      if (context.mounted) {
        _showSnack(context, context.t('Addon URL copied'));
      }
    case _AddonAction.update:
      await ref.read(soraAddonsProvider.notifier).updateAddon(addon.id);
      if (context.mounted) {
        _showSnack(context, context.t('Addon update finished'));
      }
    case _AddonAction.remove:
      final bool remove = await _confirmRemove(context, addon);
      if (remove) {
        await ref.read(soraAddonsProvider.notifier).remove(addon.id);
        if (context.mounted) {
          _showSnack(context, context.t('Addon removed'));
        }
      }
  }
}

Future<bool> _confirmRemove(
  BuildContext context,
  SoraInstalledAddon addon,
) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(context.t('Remove Addon')),
        content: Text(
          context.t(
            'Remove ${addon.manifest.sourceName} from installed addons?',
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
      );
    },
  );
  return confirmed ?? false;
}

const XTypeGroup _addonsJsonTypeGroup = XTypeGroup(
  label: 'JSON',
  extensions: <String>['json'],
  mimeTypes: <String>['application/json'],
  uniformTypeIdentifiers: <String>['public.json'],
);

Future<void> _exportAddons(BuildContext context, WidgetRef ref) async {
  final Rect shareOrigin = _computeShareOrigin(context);
  try {
    final String raw = await ref
        .read(soraAddonsProvider.notifier)
        .exportInstalledJson();
    if (!context.mounted) return;
    final String filename = 'mirushin_addons_${_fileStamp()}.json';
    final String? savedPath = await _saveAddonJson(
      Uint8List.fromList(utf8.encode(raw)),
      filename,
      shareOrigin,
    );
    if (!context.mounted) return;
    if (savedPath == null) {
      _showSnack(context, context.t('Export cancelled'));
    } else if (savedPath.isEmpty) {
      _showSnack(context, context.t('Addon export shared'));
    } else {
      _showSnack(context, context.t('Addons exported to: $savedPath'));
    }
  } on Object catch (error) {
    if (context.mounted) {
      _showSnack(context, context.t('Addon export failed: $error'));
    }
  }
}

Future<void> _importAddons(BuildContext context, WidgetRef ref) async {
  try {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_addonsJsonTypeGroup],
    );
    if (file == null) {
      if (context.mounted) _showSnack(context, context.t('Import cancelled'));
      return;
    }
    final String raw = await file.readAsString();
    if (context.mounted) {
      _showSnack(context, context.t('Importing addons...'));
    }
    final result = await ref
        .read(soraAddonsProvider.notifier)
        .importInstalledJson(raw);
    if (!context.mounted) return;
    final String message = result.hasFailures
        ? context.t(
            'Imported ${result.installed} addons, ${result.failed} failed',
          )
        : context.t('Imported ${result.installed} addons');
    _showSnack(context, message);
  } on Object catch (error) {
    if (context.mounted) {
      _showSnack(context, context.t('Addon import failed: $error'));
    }
  }
}

Future<String?> _saveAddonJson(
  Uint8List bytes,
  String filename,
  Rect shareOrigin,
) async {
  if (!kIsWeb && Platform.isIOS) {
    final Directory tempDir = await getTemporaryDirectory();
    final String tempPath = p.join(tempDir.path, filename);
    await File(tempPath).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(tempPath, mimeType: 'application/json')],
        sharePositionOrigin: shareOrigin,
      ),
    );
    return '';
  }

  if (!kIsWeb && Platform.isAndroid) {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: bytes,
        fileName: filename,
        mimeTypesFilter: const <String>['application/json'],
      ),
    );
  }

  final FileSaveLocation? location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: const <XTypeGroup>[_addonsJsonTypeGroup],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes, flush: true);
  return location.path;
}

Rect _computeShareOrigin(BuildContext context) {
  try {
    final RenderBox? overlay =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final RenderBox? box = overlay ?? context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
  } on Object {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}

String _fileStamp() {
  final DateTime now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

Future<void> _showAddAddonDialog(BuildContext context) async {
  final SoraInstalledAddon? installed = await showDialog<SoraInstalledAddon>(
    context: context,
    builder: (BuildContext context) => const _AddAddonDialog(),
  );
  if (installed != null && context.mounted) {
    _showSnack(
      context,
      context.t('${installed.manifest.sourceName} installed'),
    );
  }
}

class _AddAddonDialog extends ConsumerStatefulWidget {
  const _AddAddonDialog();

  @override
  ConsumerState<_AddAddonDialog> createState() => _AddAddonDialogState();
}

class _AddAddonDialogState extends ConsumerState<_AddAddonDialog> {
  final TextEditingController _controller = TextEditingController();
  SoraAddonPreview? _preview;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      title: Text(context.t('Add Sora Addon')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: context.t('Manifest JSON URL'),
                  hintText: 'https://example.com/addon.json',
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
                onChanged: (_) {
                  if (_preview != null) {
                    setState(() => _preview = null);
                  }
                },
                onSubmitted: (_) => _loading ? null : _previewUrl(),
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
              if (_preview != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _PreviewCard(preview: _preview!),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _loading
              ? null
              : () {
                  ref.read(soraAddonsProvider.notifier).clearPreview();
                  Navigator.of(context).pop();
                },
          child: Text(context.t('Cancel')),
        ),
        if (_preview == null)
          FilledButton.icon(
            onPressed: _loading ? null : _previewUrl,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.manage_search_rounded),
            label: Text(context.t('Preview')),
          )
        else
          FilledButton.icon(
            onPressed: _loading ? null : _install,
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

  Future<void> _previewUrl() async {
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    final SoraAddonPreview? result = await ref
        .read(soraAddonsProvider.notifier)
        .previewFromUrl(_controller.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _preview = result;
      _error = result == null
          ? ref.read(soraAddonsProvider).error ??
                context.t('Could not preview addon.')
          : null;
      _loading = false;
    });
  }

  Future<void> _install() async {
    final SoraAddonPreview? current = _preview;
    if (current == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final SoraInstalledAddon? installed = await ref
        .read(soraAddonsProvider.notifier)
        .installPreview(current);
    if (!mounted) {
      return;
    }
    if (installed == null) {
      setState(() {
        _loading = false;
        _error =
            ref.read(soraAddonsProvider).error ??
            context.t('Could not install addon.');
      });
      return;
    }
    Navigator.of(context).pop(installed);
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final SoraAddonPreview preview;

  @override
  Widget build(BuildContext context) {
    final SoraAddonManifest manifest = preview.manifest;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceSoftColor.withValues(alpha: 0.72),
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: palette.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _NetworkIcon(url: manifest.iconUrl, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      manifest.sourceName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (manifest.author.name.isNotEmpty)
                      Row(
                        children: <Widget>[
                          _NetworkIcon(url: manifest.author.iconUrl, size: 22),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              '${context.t('by')} ${manifest.author.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (manifest.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(manifest.description),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              if (manifest.type.isNotEmpty) MetadataChip(label: manifest.type),
              if (manifest.streamType.isNotEmpty)
                MetadataChip(label: manifest.streamType),
              if (manifest.quality.isNotEmpty)
                MetadataChip(label: manifest.quality),
              if (manifest.language.isNotEmpty)
                MetadataChip(label: manifest.language.toUpperCase()),
              if (manifest.version.isNotEmpty)
                MetadataChip(label: 'v${manifest.version}'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            preview.scriptUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime date) {
  final Duration difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) {
    return 'now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h ago';
  }
  return '${difference.inDays}d ago';
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
