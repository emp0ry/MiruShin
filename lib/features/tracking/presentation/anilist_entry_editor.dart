import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/tv_text_field_focus.dart';
import '../../../shared/models/anilist_models.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../profile/domain/anilist_profile_models.dart';
import '../application/anilist_library_provider.dart';
import '../application/local_first_sync_engine.dart';
import '../application/tracker_library_provider.dart';
import '../application/tracker_sync_coordinator.dart';
import '../data/anilist_api_client.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';
import 'anilist_favorite_button.dart';

// Draft model

class AniListEntryEditDraft {
  const AniListEntryEditDraft({
    required this.status,
    required this.progress,
    required this.score,
    required this.notes,
    required this.repeat,
    this.progressVolumes = 0,
    this.startedAt,
    this.completedAt,
    this.priority = 0,
    this.private = false,
    this.hiddenFromStatusLists = false,
    this.customLists = const <String, bool>{},
    this.advancedScores = const <String, double>{},
    this.scoreFormat = 'POINT_10_DECIMAL',
    this.malPriority = 0,
    this.malRewatchValue = 0,
    this.malTags = const <String>[],
    this.extendedFieldsProvided = false,
  }) : remove = false;

  const AniListEntryEditDraft.remove()
    : status = null,
      progress = 0,
      score = null,
      notes = '',
      repeat = 0,
      progressVolumes = 0,
      startedAt = null,
      completedAt = null,
      priority = 0,
      private = false,
      hiddenFromStatusLists = false,
      customLists = const <String, bool>{},
      advancedScores = const <String, double>{},
      scoreFormat = 'POINT_10_DECIMAL',
      malPriority = 0,
      malRewatchValue = 0,
      malTags = const <String>[],
      extendedFieldsProvided = false,
      remove = true;

  final AniListListStatus? status;
  final int progress;
  final double? score;
  final String notes;
  final int repeat;
  final int progressVolumes;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int priority;
  final bool private;
  final bool hiddenFromStatusLists;
  final Map<String, bool> customLists;
  final Map<String, double> advancedScores;
  final String scoreFormat;
  final int malPriority;
  final int malRewatchValue;
  final List<String> malTags;
  final bool extendedFieldsProvided;
  final bool remove;

  double get queuedScore => score ?? 0;
  int get apiScoreRaw => aniListDisplayScoreToRaw(score ?? 0);
}

enum AniListEntrySaveResult { saved, queued, failed }

const String _aniListStatusNoneKey = '__none__';

AniListListStatus? _statusFromEditorKey(String key) {
  if (key == _aniListStatusNoneKey) return null;
  for (final AniListListStatus status in AniListListStatus.values) {
    if (status.graphQlValue == key) return status;
  }
  return null;
}

// Entry lookup

int? entryAniListId(AniListAnimeListEntry entry) {
  final String? externalId = entry.mediaItem.externalIds['anilist'];
  final int? parsedExternal = int.tryParse(externalId ?? '');
  if (parsedExternal != null) return parsedExternal;

  final List<String> parts = entry.mediaItem.id.split(':');
  if (parts.length >= 2 && parts.first == 'anilist') {
    return int.tryParse(parts.last);
  }
  return null;
}

bool _isMangaEntry(AniListAnimeListEntry entry) {
  return entry.mediaItem.externalIds['anilist_type'] == 'MANGA' ||
      entry.mediaItem.id.toLowerCase().startsWith('anilist:manga:');
}

Map<String, dynamic> _providerData(
  AniListAnimeListEntry entry,
  String provider,
) {
  final Object? rawSnapshots = entry.providerData['providerSnapshots'];
  if (rawSnapshots is Map && rawSnapshots[provider] is Map) {
    return Map<String, dynamic>.from(rawSnapshots[provider] as Map);
  }
  return entry.providerData;
}

bool _sameDate(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == right;
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _sameStringSet(Iterable<String> left, Iterable<String> right) {
  final Set<String> leftSet = left.toSet();
  final Set<String> rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

// Editor sheet

Future<AniListEntryEditDraft?> showAniListEntryEditor(
  BuildContext context, {
  required WidgetRef ref,
  required AniListAnimeListEntry entry,
  required AniListListStatus? status,
  required int progress,
  required double? score,
  required String notes,
  required int repeat,
  required String scoreFormat,
  bool allowRemove = true,
}) async {
  final int? total = entry.mediaItem.episodeCount;
  final bool isManga = _isMangaEntry(entry);
  final AniListUserSettings? listOptions = ref
      .read(aniListUserSettingsProvider)
      .value;
  final Set<String> customListNames = <String>{
    ...entry.customLists.keys,
    if (listOptions != null)
      ...(isManga
          ? listOptions.mangaCustomLists
          : listOptions.animeCustomLists),
  };
  final Set<String> advancedScoreNames = <String>{
    ...entry.advancedScores.keys,
    ...?listOptions?.advancedScores,
  };
  final Object? rawProviderSnapshots = entry.providerData['providerSnapshots'];
  final Map<String, dynamic> providerSnapshots = rawProviderSnapshots is Map
      ? Map<String, dynamic>.from(rawProviderSnapshots)
      : const <String, dynamic>{};
  final Object? rawMalData = providerSnapshots['mal'];
  final Object? rawAniListData = providerSnapshots['anilist'];
  final Map<String, dynamic> aniListData = rawAniListData is Map
      ? Map<String, dynamic>.from(rawAniListData)
      : entry.providerData;
  final Map<String, dynamic> malData = rawMalData is Map
      ? Map<String, dynamic>.from(rawMalData)
      : entry.providerData;
  String draftStatusKey = status?.graphQlValue ?? _aniListStatusNoneKey;
  int draftProgress = progress;
  double draftScore = score ?? 0;
  int draftRepeat = repeat;
  int draftProgressVolumes = entry.progressVolumes;
  DateTime? draftStartedAt = entry.startedAt;
  DateTime? draftCompletedAt = entry.completedAt;
  int draftPriority =
      ((aniListData['priority'] as num?)?.toInt() ?? entry.priority)
          .clamp(0, 100)
          .toInt();
  bool draftPrivate = aniListData['private'] as bool? ?? entry.private;
  bool draftHiddenFromStatusLists =
      aniListData['hiddenFromStatusLists'] as bool? ??
      entry.hiddenFromStatusLists;
  final Map<String, bool> draftCustomLists = <String, bool>{
    for (final String name in customListNames)
      name: (aniListData['customLists'] is Map
          ? (aniListData['customLists'] as Map)[name] == true
          : entry.customLists[name] == true),
  };
  final Map<String, double> draftAdvancedScores = <String, double>{
    for (final String name in advancedScoreNames)
      name:
          ((aniListData['advancedScores'] is Map
                          ? (aniListData['advancedScores'] as Map)[name]
                          : entry.advancedScores[name])
                      as num? ??
                  0)
              .clamp(0, 100)
              .toDouble(),
  };
  int draftMalPriority = ((malData['priority'] as num?)?.toInt() ?? 0)
      .clamp(0, 2)
      .toInt();
  int draftMalRewatchValue =
      ((malData[isManga ? 'rereadValue' : 'rewatchValue'] as num?)?.toInt() ??
              0)
          .clamp(0, 5)
          .toInt();
  final List<String> initialMalTags = malData['tags'] is List
      ? (malData['tags'] as List)
            .map((Object? value) => '$value'.trim())
            .where((String value) => value.isNotEmpty)
            .toList(growable: false)
      : const <String>[];
  final TextEditingController progressController = TextEditingController(
    text: progress.toString(),
  );
  final TextEditingController notesController = TextEditingController(
    text: notes,
  );
  final TextEditingController repeatController = TextEditingController(
    text: repeat.toString(),
  );
  final TextEditingController volumesController = TextEditingController(
    text: draftProgressVolumes.toString(),
  );
  final TextEditingController malTagsController = TextEditingController(
    text: initialMalTags.join(', '),
  );

  int clampProgress(int value) {
    final int max = total == null || total <= 0 ? 100000 : total;
    return value.clamp(0, max).toInt();
  }

  try {
    return await showModalBottomSheet<AniListEntryEditDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext sheetContext, StateSetter setSheetState) {
            void setProgress(int value) {
              draftProgress = clampProgress(value);
              progressController.text = draftProgress.toString();
            }

            void setRepeat(int value) {
              draftRepeat = value.clamp(0, 999).toInt();
              repeatController.text = draftRepeat.toString();
            }

            void setVolumes(int value) {
              draftProgressVolumes = value.clamp(0, 100000).toInt();
              volumesController.text = draftProgressVolumes.toString();
            }

            Future<void> pickDate({required bool started}) async {
              final DateTime now = DateTime.now();
              final DateTime? current = started
                  ? draftStartedAt
                  : draftCompletedAt;
              final DateTime? selected = await showDatePicker(
                context: sheetContext,
                initialDate: current ?? now,
                firstDate: DateTime(1900),
                lastDate: DateTime(now.year + 2, 12, 31),
              );
              if (selected == null || !sheetContext.mounted) return;
              setSheetState(() {
                if (started) {
                  draftStartedAt = selected;
                } else {
                  draftCompletedAt = selected;
                }
              });
            }

            Widget dateTile({
              required String label,
              required DateTime? value,
              required bool started,
            }) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  started
                      ? Icons.play_circle_outline_rounded
                      : Icons.flag_outlined,
                ),
                title: Text(label),
                subtitle: Text(
                  value == null
                      ? sheetContext.t('Not set')
                      : MaterialLocalizations.of(
                          sheetContext,
                        ).formatCompactDate(value),
                ),
                onTap: () => pickDate(started: started),
                trailing: value == null
                    ? const Icon(Icons.calendar_month_outlined)
                    : IconButton(
                        tooltip: sheetContext.t('Clear'),
                        onPressed: () => setSheetState(() {
                          if (started) {
                            draftStartedAt = null;
                          } else {
                            draftCompletedAt = null;
                          }
                        }),
                        icon: const Icon(Icons.close_rounded),
                      ),
              );
            }

            final String progressLimit = total == null ? '?' : total.toString();

            return AniListSheetSurface(
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.md,
                    bottom:
                        MediaQuery.viewInsetsOf(sheetContext).bottom +
                        AppSpacing.lg,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppThemeExtension.of(
                                context,
                              ).textMutedColor.withValues(alpha: 0.7),
                              borderRadius: AppRadius.all(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                entry.mediaItem.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            AniListFavoriteButton(item: entry.mediaItem),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          initialValue: draftStatusKey,
                          decoration: InputDecoration(
                            labelText: sheetContext.t('Status'),
                            border: const OutlineInputBorder(),
                          ),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: _aniListStatusNoneKey,
                              child: Text(sheetContext.t('Not chosen')),
                            ),
                            ...AniListListStatus.values.map(
                              (AniListListStatus value) =>
                                  DropdownMenuItem<String>(
                                    value: value.graphQlValue,
                                    child: Text(sheetContext.t(value.label)),
                                  ),
                            ),
                          ],
                          onChanged: (String? value) {
                            if (value == null) return;
                            setSheetState(() => draftStatusKey = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: TvTextFieldFocus(
                                child: TextField(
                                  controller: progressController,
                                  decoration: InputDecoration(
                                    labelText: sheetContext.t('Progress'),
                                    helperText: sheetContext.tf(
                                      'of {total}',
                                      <String, Object?>{'total': progressLimit},
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (String value) {
                                    draftProgress = clampProgress(
                                      int.tryParse(value) ?? 0,
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: AniListStepperButtons(
                                onMinus: () => setSheetState(
                                  () => setProgress(draftProgress - 1),
                                ),
                                onPlus: () => setSheetState(
                                  () => setProgress(draftProgress + 1),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AniListScoreEditor(
                          score: draftScore,
                          format: scoreFormat,
                          onChanged: (double value) {
                            setSheetState(() => draftScore = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TvTextFieldFocus(
                                child: TextField(
                                  controller: repeatController,
                                  decoration: InputDecoration(
                                    labelText: sheetContext.t('Repeat count'),
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (String value) {
                                    draftRepeat = (int.tryParse(value) ?? 0)
                                        .clamp(0, 999)
                                        .toInt();
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            AniListStepperButtons(
                              onMinus: () => setSheetState(
                                () => setRepeat(draftRepeat - 1),
                              ),
                              onPlus: () => setSheetState(
                                () => setRepeat(draftRepeat + 1),
                              ),
                            ),
                          ],
                        ),
                        if (isManga) ...<Widget>[
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: TvTextFieldFocus(
                                  child: TextField(
                                    controller: volumesController,
                                    decoration: InputDecoration(
                                      labelText: sheetContext.t('Volumes read'),
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: <TextInputFormatter>[
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    onChanged: (String value) {
                                      draftProgressVolumes =
                                          (int.tryParse(value) ?? 0)
                                              .clamp(0, 100000)
                                              .toInt();
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: AniListStepperButtons(
                                  onMinus: () => setSheetState(
                                    () => setVolumes(draftProgressVolumes - 1),
                                  ),
                                  onPlus: () => setSheetState(
                                    () => setVolumes(draftProgressVolumes + 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_note_outlined),
                          title: Text(sheetContext.t('Dates')),
                          children: <Widget>[
                            dateTile(
                              label: sheetContext.t('Start date'),
                              value: draftStartedAt,
                              started: true,
                            ),
                            dateTile(
                              label: sheetContext.t('Finish date'),
                              value: draftCompletedAt,
                              started: false,
                            ),
                          ],
                        ),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(
                            bottom: AppSpacing.sm,
                          ),
                          leading: const Icon(Icons.tune_rounded),
                          title: Text(sheetContext.t('AniList options')),
                          subtitle: Text(
                            sheetContext.t(
                              'These fields sync only where supported.',
                            ),
                          ),
                          children: <Widget>[
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(sheetContext.t('Priority')),
                              subtitle: Slider(
                                value: draftPriority.toDouble(),
                                min: 0,
                                max: 100,
                                divisions: 100,
                                label: '$draftPriority',
                                onChanged: (double value) => setSheetState(
                                  () => draftPriority = value.round(),
                                ),
                              ),
                              trailing: Text('$draftPriority'),
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(sheetContext.t('Private entry')),
                              value: draftPrivate,
                              onChanged: (bool value) =>
                                  setSheetState(() => draftPrivate = value),
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                sheetContext.t('Hide from status lists'),
                              ),
                              value: draftHiddenFromStatusLists,
                              onChanged: (bool value) => setSheetState(
                                () => draftHiddenFromStatusLists = value,
                              ),
                            ),
                            if (customListNames.isNotEmpty) ...<Widget>[
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.sm,
                                    bottom: AppSpacing.xs,
                                  ),
                                  child: Text(
                                    sheetContext.t('Custom lists'),
                                    style: Theme.of(
                                      sheetContext,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                              ),
                              for (final String name in customListNames)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(name),
                                  value: draftCustomLists[name] == true,
                                  onChanged: (bool? value) => setSheetState(
                                    () =>
                                        draftCustomLists[name] = value == true,
                                  ),
                                ),
                            ],
                            if (advancedScoreNames.isNotEmpty) ...<Widget>[
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.sm,
                                    bottom: AppSpacing.xs,
                                  ),
                                  child: Text(
                                    sheetContext.t('Advanced scores'),
                                    style: Theme.of(
                                      sheetContext,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                              ),
                              for (final String name in advancedScoreNames)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(name),
                                  subtitle: Slider(
                                    value: draftAdvancedScores[name] ?? 0,
                                    min: 0,
                                    max: 100,
                                    divisions: 100,
                                    label:
                                        '${(draftAdvancedScores[name] ?? 0).round()}',
                                    onChanged: (double value) => setSheetState(
                                      () => draftAdvancedScores[name] = value,
                                    ),
                                  ),
                                  trailing: Text(
                                    '${(draftAdvancedScores[name] ?? 0).round()}',
                                  ),
                                ),
                            ],
                          ],
                        ),
                        if (entry.mediaItem.externalIds['mal'] != null ||
                            malData.isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            leading: const Icon(Icons.extension_outlined),
                            title: Text(sheetContext.t('MyAnimeList options')),
                            children: <Widget>[
                              DropdownButtonFormField<int>(
                                initialValue: draftMalPriority,
                                decoration: InputDecoration(
                                  labelText: sheetContext.t('MAL priority'),
                                  border: const OutlineInputBorder(),
                                ),
                                items: <DropdownMenuItem<int>>[
                                  DropdownMenuItem<int>(
                                    value: 0,
                                    child: Text(sheetContext.t('Low')),
                                  ),
                                  DropdownMenuItem<int>(
                                    value: 1,
                                    child: Text(sheetContext.t('Medium')),
                                  ),
                                  DropdownMenuItem<int>(
                                    value: 2,
                                    child: Text(sheetContext.t('High')),
                                  ),
                                ],
                                onChanged: (int? value) {
                                  if (value == null) return;
                                  setSheetState(() => draftMalPriority = value);
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              DropdownButtonFormField<int>(
                                initialValue: draftMalRewatchValue,
                                decoration: InputDecoration(
                                  labelText: sheetContext.t(
                                    isManga ? 'Reread value' : 'Rewatch value',
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                items: <DropdownMenuItem<int>>[
                                  for (int value = 0; value <= 5; value += 1)
                                    DropdownMenuItem<int>(
                                      value: value,
                                      child: Text('$value'),
                                    ),
                                ],
                                onChanged: (int? value) {
                                  if (value == null) return;
                                  setSheetState(
                                    () => draftMalRewatchValue = value,
                                  );
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TvTextFieldFocus(
                                child: TextField(
                                  controller: malTagsController,
                                  decoration: InputDecoration(
                                    labelText: sheetContext.t('MAL tags'),
                                    helperText: sheetContext.t(
                                      'Separate tags with commas.',
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (entry.mediaItem.externalIds['shikimori'] != null ||
                            providerSnapshots['shikimori'] != null)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            leading: const Icon(Icons.sync_alt_rounded),
                            title: Text(sheetContext.t('Shikimori options')),
                            subtitle: Text(
                              sheetContext.t(
                                'Progress, score, rewatches and notes use the common fields above.',
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: notesController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: sheetContext.t('Notes'),
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: <Widget>[
                            if (allowRemove) ...<Widget>[
                              TextButton.icon(
                                onPressed: () => Navigator.pop(
                                  sheetContext,
                                  const AniListEntryEditDraft.remove(),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                ),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: Text(sheetContext.t('Remove')),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            TextButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              child: Text(sheetContext.t('Cancel')),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: () {
                                final int parsedProgress =
                                    int.tryParse(
                                      progressController.text.trim(),
                                    ) ??
                                    draftProgress;
                                final int parsedRepeat =
                                    int.tryParse(
                                      repeatController.text.trim(),
                                    ) ??
                                    draftRepeat;
                                Navigator.pop(
                                  sheetContext,
                                  AniListEntryEditDraft(
                                    status: _statusFromEditorKey(
                                      draftStatusKey,
                                    ),
                                    progress: clampProgress(parsedProgress),
                                    score: draftScore <= 0 ? null : draftScore,
                                    notes: notesController.text.trim(),
                                    repeat: parsedRepeat.clamp(0, 999).toInt(),
                                    progressVolumes:
                                        int.tryParse(
                                          volumesController.text.trim(),
                                        ) ??
                                        draftProgressVolumes,
                                    startedAt: draftStartedAt,
                                    completedAt: draftCompletedAt,
                                    priority: draftPriority,
                                    private: draftPrivate,
                                    hiddenFromStatusLists:
                                        draftHiddenFromStatusLists,
                                    customLists: Map<String, bool>.from(
                                      draftCustomLists,
                                    ),
                                    advancedScores: Map<String, double>.from(
                                      draftAdvancedScores,
                                    ),
                                    scoreFormat: scoreFormat,
                                    malPriority: draftMalPriority,
                                    malRewatchValue: draftMalRewatchValue,
                                    malTags: malTagsController.text
                                        .split(',')
                                        .map((String value) => value.trim())
                                        .where(
                                          (String value) => value.isNotEmpty,
                                        )
                                        .toSet()
                                        .toList(growable: false),
                                    extendedFieldsProvided: true,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: Text(sheetContext.t('Save')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    progressController.dispose();
    notesController.dispose();
    repeatController.dispose();
    volumesController.dispose();
    malTagsController.dispose();
  }
}

// Save / delete

Future<AniListEntrySaveResult> saveAniListEntryEdit({
  required BuildContext context,
  required AniListAnimeListEntry entry,
  required AniListEntryEditDraft draft,
  bool showSuccessSnack = true,
}) async {
  // WidgetRef is tied to the calling widget's BuildContext and becomes unsafe
  // as soon as that page is popped. The sync operation deliberately outlives
  // the page, so capture the app-level container and coordinator before the
  // first await and never touch [ref] afterward.
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final TrackerSyncCoordinator sync = container.read(
    trackerSyncCoordinatorProvider,
  );
  final int? mediaId = entryAniListId(entry);
  final bool isManga = _isMangaEntry(entry);
  final bool isNewEntry = entry.id <= 0;
  final Map<String, dynamic> malData = _providerData(entry, 'mal');
  final int currentMalRewatchValue =
      ((malData[isManga ? 'rereadValue' : 'rewatchValue'] as num?)?.toInt() ??
              0)
          .clamp(0, 5)
          .toInt();
  final List<String> currentMalTags = malData['tags'] is List
      ? (malData['tags'] as List)
            .map((Object? value) => '$value'.trim())
            .where((String value) => value.isNotEmpty)
            .toList(growable: false)
      : const <String>[];
  final String currentScoreFormat = '${entry.providerData['scoreFormat'] ?? ''}'
      .trim();
  final int currentMalPriority = ((malData['priority'] as num?)?.toInt() ?? 0)
      .clamp(0, 2)
      .toInt();
  // A list entry cannot have no status. For a new item the editor's seed
  // status is the local default; for an existing item choosing "Not chosen"
  // means keep its current status rather than sending an ambiguous null.
  final AniListListStatus effectiveStatus = draft.status ?? entry.status;
  final int optimisticUpdatedAt =
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final Set<UserMediaField> changedFields = <UserMediaField>{
    if (isNewEntry || effectiveStatus != entry.status) UserMediaField.status,
    if (isNewEntry || draft.progress != entry.progress) UserMediaField.progress,
    if (isNewEntry || (draft.score ?? 0) != (entry.score ?? 0))
      UserMediaField.score,
    if (isNewEntry || draft.notes != entry.notes) UserMediaField.notes,
    if (isNewEntry || draft.repeat != entry.repeat) UserMediaField.repeat,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || draft.progressVolumes != entry.progressVolumes))
      UserMediaField.progressVolumes,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || !_sameDate(draft.startedAt, entry.startedAt)))
      UserMediaField.startedAt,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || !_sameDate(draft.completedAt, entry.completedAt)))
      UserMediaField.completedAt,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || draft.priority != entry.priority))
      UserMediaField.priority,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || draft.private != entry.private))
      UserMediaField.private,
    if (draft.extendedFieldsProvided &&
        (isNewEntry ||
            draft.hiddenFromStatusLists != entry.hiddenFromStatusLists))
      UserMediaField.hiddenFromStatusLists,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || !mapEquals(draft.customLists, entry.customLists)))
      UserMediaField.customLists,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || !mapEquals(draft.advancedScores, entry.advancedScores)))
      UserMediaField.advancedScores,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || draft.scoreFormat != currentScoreFormat))
      UserMediaField.scoreFormat,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || draft.malPriority != currentMalPriority))
      UserMediaField.malPriority,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || draft.malRewatchValue != currentMalRewatchValue))
      UserMediaField.malRewatchValue,
    if (draft.extendedFieldsProvided &&
        (isNewEntry || !_sameStringSet(draft.malTags, currentMalTags)))
      UserMediaField.malTags,
  };
  if (!isNewEntry && changedFields.isEmpty) {
    if (showSuccessSnack && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Saved to Library'))));
    }
    return AniListEntrySaveResult.saved;
  }
  final Map<String, dynamic> optimisticProviderData = <String, dynamic>{
    ...entry.providerData,
  };
  if (draft.extendedFieldsProvided) {
    optimisticProviderData['scoreFormat'] = draft.scoreFormat;
    final Object? rawSnapshots = optimisticProviderData['providerSnapshots'];
    final Map<String, dynamic> snapshots = rawSnapshots is Map
        ? Map<String, dynamic>.from(rawSnapshots)
        : <String, dynamic>{};
    final Object? rawMal = snapshots['mal'];
    snapshots['mal'] = <String, dynamic>{
      if (rawMal is Map) ...Map<String, dynamic>.from(rawMal),
      isManga ? 'rereadValue' : 'rewatchValue': draft.malRewatchValue,
      'priority': draft.malPriority,
      'tags': draft.malTags,
    };
    optimisticProviderData['providerSnapshots'] = snapshots;
  }
  final AniListAnimeListEntry optimisticEntry = AniListAnimeListEntry(
    id: entry.id,
    status: effectiveStatus,
    progress: draft.progress,
    score: draft.score,
    scoreRaw: draft.score == null
        ? null
        : (draft.score! * 10).round().clamp(0, 100),
    mediaItem: entry.mediaItem,
    notes: draft.notes,
    repeat: draft.repeat,
    progressVolumes: draft.extendedFieldsProvided
        ? draft.progressVolumes
        : entry.progressVolumes,
    priority: draft.extendedFieldsProvided ? draft.priority : entry.priority,
    private: draft.extendedFieldsProvided ? draft.private : entry.private,
    hiddenFromStatusLists: draft.extendedFieldsProvided
        ? draft.hiddenFromStatusLists
        : entry.hiddenFromStatusLists,
    customLists: draft.extendedFieldsProvided
        ? draft.customLists
        : entry.customLists,
    advancedScores: draft.extendedFieldsProvided
        ? draft.advancedScores
        : entry.advancedScores,
    providerData: optimisticProviderData,
    createdAt: entry.createdAt,
    updatedAt: optimisticUpdatedAt,
    startedAt: draft.extendedFieldsProvided ? draft.startedAt : entry.startedAt,
    completedAt: draft.extendedFieldsProvided
        ? draft.completedAt
        : entry.completedAt,
    nextEpisode: entry.nextEpisode,
    airingAt: entry.airingAt,
    avgScore: entry.avgScore,
    format: entry.format,
  );

  void applyLocalEdit() {
    if (isManga) {
      invalidateAniListMangaLibraryProviders(container.invalidate);
      return;
    }
    // This is the canonical immediate UI mutation. It is provider-neutral, so
    // MAL/Shikimori-only entries update without waiting for an AniList id or a
    // network list refresh.
    container
        .read(trackerLibraryOptimisticMutationsProvider.notifier)
        .upsert(optimisticEntry);
    if (mediaId != null) {
      container
          .read(anilistAnimeListProvider.notifier)
          .replaceEntry(
            mediaId: mediaId,
            entry: optimisticEntry,
            publishToTrackerLibrary: false,
          );
    }
  }

  late final SyncDispatchResult result;
  try {
    result = await sync.pushEntryEdit(
      externalIds: entry.mediaItem.externalIds,
      mediaId: entry.mediaItem.id,
      mediaTitle: entry.mediaItem.title,
      mediaItem: entry.mediaItem,
      status: effectiveStatus,
      progress: draft.progress,
      score: draft.score ?? 0,
      notes: draft.notes,
      repeat: draft.repeat,
      progressVolumes: draft.extendedFieldsProvided
          ? draft.progressVolumes
          : null,
      startedAt: draft.extendedFieldsProvided ? draft.startedAt : null,
      completedAt: draft.extendedFieldsProvided ? draft.completedAt : null,
      priority: draft.extendedFieldsProvided ? draft.priority : null,
      private: draft.extendedFieldsProvided ? draft.private : null,
      hiddenFromStatusLists: draft.extendedFieldsProvided
          ? draft.hiddenFromStatusLists
          : null,
      customLists: draft.extendedFieldsProvided ? draft.customLists : null,
      advancedScores: draft.extendedFieldsProvided
          ? draft.advancedScores
          : null,
      scoreFormat: draft.extendedFieldsProvided ? draft.scoreFormat : null,
      malPriority: draft.extendedFieldsProvided ? draft.malPriority : null,
      malRewatchValue: draft.extendedFieldsProvided
          ? draft.malRewatchValue
          : null,
      malTags: draft.extendedFieldsProvided ? draft.malTags : null,
      fields: changedFields,
      providerEntryIds: <TrackerSource, int>{
        if (mediaId != null) TrackerSource.anilist: entry.id,
      },
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(aniListEditFailureMessage(error))));
    }
    return AniListEntrySaveResult.failed;
  }

  // SQLite is canonical: expose the optimistic UI only after the atomic local
  // state + operation + outbox transaction has committed successfully.
  applyLocalEdit();
  container.invalidate(trackerLocalAnimeLibraryProvider);
  final bool queued = result.pendingTargets.isNotEmpty;
  if (showSuccessSnack && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t('Saved to Library'))));
  }
  return queued ? AniListEntrySaveResult.queued : AniListEntrySaveResult.saved;
}

Future<void> deleteAniListEntry({
  required BuildContext context,
  required AniListAnimeListEntry entry,
}) async {
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final TrackerSyncCoordinator sync = container.read(
    trackerSyncCoordinatorProvider,
  );
  final int? mediaId = entryAniListId(entry);
  final bool isManga = _isMangaEntry(entry);

  void applyLocalDelete() {
    if (isManga) {
      invalidateAniListMangaLibraryProviders(container.invalidate);
      return;
    }
    container
        .read(trackerLibraryOptimisticMutationsProvider.notifier)
        .remove(entry.mediaItem);
    if (mediaId != null) {
      container
          .read(anilistAnimeListProvider.notifier)
          .removeEntry(
            mediaId,
            mediaItem: entry.mediaItem,
            publishToTrackerLibrary: false,
          );
    }
  }

  try {
    await sync.deleteEntry(
      externalIds: entry.mediaItem.externalIds,
      mediaId: entry.mediaItem.id,
      mediaTitle: entry.mediaItem.title,
      providerEntryIds: <TrackerSource, int>{
        if (mediaId != null) TrackerSource.anilist: entry.id,
      },
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(aniListEditFailureMessage(error))));
    }
    return;
  }

  applyLocalDelete();
  container.invalidate(trackerLocalAnimeLibraryProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t('Removed from Library'))));
  }
}

bool isQueueableAniListEditError(Object error) {
  if (error is! DioException) return false;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => true,
    DioExceptionType.badResponse => _isRetryableAniListStatus(
      error.response?.statusCode,
    ),
    DioExceptionType.badCertificate || DioExceptionType.cancel => false,
  };
}

bool _isRetryableAniListStatus(int? statusCode) {
  if (statusCode == null) return true;
  return statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

String aniListEditFailureMessage(Object error) {
  if (error is DioException) {
    final int? statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return 'AniList rejected the saved login. Reconnect AniList in Settings.';
    }
    if (statusCode != null) {
      return 'AniList save failed (HTTP $statusCode).';
    }
    return 'AniList save failed. Check your connection.';
  }

  String message = error.toString();
  const String statePrefix = 'Bad state: ';
  if (message.startsWith(statePrefix)) {
    message = message.substring(statePrefix.length);
  }
  final RegExpMatch? graphQlMessage = RegExp(
    r'message:\s*([^,}]+)',
  ).firstMatch(message);
  if (graphQlMessage != null) {
    message = graphQlMessage.group(1)!.trim();
  }
  return message.isEmpty
      ? 'AniList save failed.'
      : 'AniList save failed: $message';
}

// Score helpers

String formatAniListScore(double score, String format) {
  if (score <= 0) return '';
  return switch (format) {
    'POINT_100' => '${(score * 10).round()}',
    'POINT_10' => score.round().toString(),
    'POINT_5' => '★' * (score / 2).round(),
    'POINT_3' || 'SMILEY' => aniListSmileyScoreSymbol(score),
    _ => score % 1 == 0 ? score.toInt().toString() : score.toStringAsFixed(1),
  };
}

String aniListSmileyScoreSymbol(double score) {
  if (score <= 3) {
    if (score < 1.5) return ':(';
    if (score < 2.5) return ':|';
    return ':)';
  }
  if (score < 5) return ':(';
  if (score < 7.5) return ':|';
  return ':)';
}

IconData aniListSmileyScoreIcon(double score) {
  if (score <= 3) {
    if (score < 1.5) return Icons.sentiment_very_dissatisfied;
    if (score < 2.5) return Icons.sentiment_neutral;
    return Icons.sentiment_very_satisfied;
  }
  if (score < 5) return Icons.sentiment_very_dissatisfied;
  if (score < 7.5) return Icons.sentiment_neutral;
  return Icons.sentiment_very_satisfied;
}

bool isSmileyAniListFormat(String format) =>
    format == 'SMILEY' || format == 'POINT_3';

// Widgets

class AniListSheetSurface extends StatelessWidget {
  const AniListSheetSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceColor,
          border: Border(top: BorderSide(color: palette.borderColor)),
        ),
        child: child,
      ),
    );
  }
}

class AniListStepperButtons extends StatelessWidget {
  const AniListStepperButtons({
    required this.onMinus,
    required this.onPlus,
    super.key,
  });

  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final ButtonStyle stepStyle = IconButton.styleFrom(
      backgroundColor: palette.surfaceSoftColor,
      foregroundColor: cs.primary,
      side: BorderSide(color: palette.borderColor),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          style: stepStyle,
          tooltip: context.t('Decrease'),
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          style: stepStyle,
          tooltip: context.t('Increase'),
          onPressed: onPlus,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class AniListScoreEditor extends StatelessWidget {
  const AniListScoreEditor({
    required this.score,
    required this.format,
    required this.onChanged,
    super.key,
  });

  final double score;
  final String format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final String label = score <= 0
        ? context.t('No score')
        : formatAniListScore(score, format);
    return switch (format) {
      'SMILEY' ||
      'POINT_3' => AniListSmileyPicker(score: score, onChanged: onChanged),
      'POINT_5' => AniListStarPicker(score: score, onChanged: onChanged),
      'POINT_100' => AniListSliderScore(
        score: score,
        displayValue: score <= 0
            ? context.t('No score')
            : '${(score * 10).round()}',
        min: 0,
        max: 10,
        divisions: 100,
        label: label,
        onChanged: onChanged,
      ),
      'POINT_10' => AniListSliderScore(
        score: score,
        displayValue: label,
        min: 0,
        max: 10,
        divisions: 10,
        label: label,
        onChanged: onChanged,
      ),
      _ => AniListSliderScore(
        score: score,
        displayValue: label,
        min: 0,
        max: 10,
        divisions: 20,
        label: label,
        onChanged: onChanged,
      ),
    };
  }
}

class AniListSliderScore extends StatelessWidget {
  const AniListSliderScore({
    required this.score,
    required this.displayValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final double score;
  final String displayValue;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                context.t('Score'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Text(displayValue, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        Slider(
          value: score.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class AniListSmileyPicker extends StatelessWidget {
  const AniListSmileyPicker({
    required this.score,
    required this.onChanged,
    super.key,
  });

  final double score;
  final ValueChanged<double> onChanged;

  static const List<({IconData icon, String tooltip, double value})> _options =
      <({IconData icon, String tooltip, double value})>[
        (
          icon: Icons.sentiment_very_dissatisfied,
          tooltip: 'Score Disliked',
          value: 3.5,
        ),
        (icon: Icons.sentiment_neutral, tooltip: 'Score Neutral', value: 6.0),
        (
          icon: Icons.sentiment_very_satisfied,
          tooltip: 'Score Liked',
          value: 8.5,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: context.t('Score'),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _options
            .map((({IconData icon, String tooltip, double value}) opt) {
              final bool selected = (score - opt.value).abs() < 0.1;
              return IconButton(
                tooltip: context.t(selected ? 'Unscore' : opt.tooltip),
                iconSize: 30,
                icon: Icon(opt.icon),
                color: selected
                    ? colors.primary
                    : colors.surfaceContainerHighest,
                onPressed: () => onChanged(selected ? 0 : opt.value),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class AniListStarPicker extends StatelessWidget {
  const AniListStarPicker({
    required this.score,
    required this.onChanged,
    super.key,
  });

  final double score;
  final ValueChanged<double> onChanged;

  static const List<double> _values = <double>[2.0, 4.0, 6.0, 8.0, 10.0];

  int get _selectedIndex {
    if (score <= 0) return -1;
    double best = double.infinity;
    int idx = -1;
    for (int i = 0; i < _values.length; i++) {
      final double diff = (_values[i] - score).abs();
      if (diff < best) {
        best = diff;
        idx = i;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final int activeIdx = _selectedIndex;
    final Color active = Theme.of(context).colorScheme.primary;
    final Color inactive = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                context.t('Score'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (score > 0)
              TextButton(
                onPressed: () => onChanged(0),
                child: Text(context.t('Clear')),
              ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(
            5,
            (int i) => GestureDetector(
              onTap: () => onChanged(activeIdx == i ? 0 : _values[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  i <= activeIdx
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: i <= activeIdx ? active : inactive,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
