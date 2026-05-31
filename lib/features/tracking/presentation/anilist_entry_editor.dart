import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../shared/models/anilist_models.dart';
import '../../settings/presentation/settings_state.dart';
import '../application/anilist_library_provider.dart';
import '../data/anilist_api_client.dart';
import 'anilist_favorite_button.dart';

// ─── Draft model ─────────────────────────────────────────────────────────────

class AniListEntryEditDraft {
  const AniListEntryEditDraft({
    required this.status,
    required this.progress,
    required this.score,
    required this.notes,
    required this.repeat,
  }) : remove = false;

  const AniListEntryEditDraft.remove()
    : status = AniListListStatus.dropped,
      progress = 0,
      score = null,
      notes = '',
      repeat = 0,
      remove = true;

  final AniListListStatus status;
  final int progress;
  final double? score;
  final String notes;
  final int repeat;
  final bool remove;

  double get queuedScore => score ?? 0;
  int get apiScoreRaw => aniListDisplayScoreToRaw(score ?? 0);
}

enum AniListEntrySaveResult { saved, queued, failed }

// ─── Entry lookup ─────────────────────────────────────────────────────────────

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

// ─── Editor sheet ─────────────────────────────────────────────────────────────

Future<AniListEntryEditDraft?> showAniListEntryEditor(
  BuildContext context, {
  required WidgetRef ref,
  required AniListAnimeListEntry entry,
  required AniListListStatus status,
  required int progress,
  required double? score,
  required String notes,
  required int repeat,
  required String scoreFormat,
}) async {
  final int? total = entry.mediaItem.episodeCount;
  AniListListStatus draftStatus = status;
  int draftProgress = progress;
  double draftScore = score ?? 0;
  int draftRepeat = repeat;
  final TextEditingController progressController = TextEditingController(
    text: progress.toString(),
  );
  final TextEditingController notesController = TextEditingController(
    text: notes,
  );
  final TextEditingController repeatController = TextEditingController(
    text: repeat.toString(),
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
                        DropdownButtonFormField<AniListListStatus>(
                          initialValue: draftStatus,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          items: AniListListStatus.values
                              .map(
                                (AniListListStatus value) =>
                                    DropdownMenuItem<AniListListStatus>(
                                      value: value,
                                      child: Text(value.label),
                                    ),
                              )
                              .toList(growable: false),
                          onChanged: (AniListListStatus? value) {
                            if (value == null) return;
                            setSheetState(() => draftStatus = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: progressController,
                                decoration: InputDecoration(
                                  labelText: 'Progress',
                                  helperText: 'of $progressLimit',
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
                              child: TextField(
                                controller: repeatController,
                                decoration: const InputDecoration(
                                  labelText: 'Repeat count',
                                  border: OutlineInputBorder(),
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
                                    status: draftStatus,
                                    progress: clampProgress(parsedProgress),
                                    score: draftScore <= 0 ? null : draftScore,
                                    notes: notesController.text.trim(),
                                    repeat: parsedRepeat.clamp(0, 999).toInt(),
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
  }
}

// ─── Save / delete ────────────────────────────────────────────────────────────

Future<AniListEntrySaveResult> saveAniListEntryEdit({
  required BuildContext context,
  required WidgetRef ref,
  required AniListAnimeListEntry entry,
  required AniListEntryEditDraft draft,
  bool showSuccessSnack = true,
}) async {
  final int? mediaId = entryAniListId(entry);
  if (mediaId == null) return AniListEntrySaveResult.failed;
  final bool isManga = _isMangaEntry(entry);

  void applyLocalEdit() {
    if (isManga) {
      invalidateAniListMangaLibraryProviders(ref.invalidate);
      return;
    }
    ref
        .read(anilistAnimeListProvider.notifier)
        .updateEntry(
          mediaId: mediaId,
          progress: draft.progress,
          status: draft.status,
          score: draft.score,
          notes: draft.notes,
          repeat: draft.repeat,
        );
    invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
  }

  Future<AniListEntrySaveResult> queueEdit() async {
    await ref
        .read(anilistEditQueueProvider)
        .queueEntry(
          mediaId: mediaId,
          status: draft.status,
          progress: draft.progress,
          score: draft.queuedScore,
          notes: draft.notes,
          repeat: draft.repeat,
        );
    applyLocalEdit();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('AniList edit queued'))));
    }
    return AniListEntrySaveResult.queued;
  }

  final SettingsState settings = ref.read(settingsProvider);
  final String token = settings.anilistAccessToken.trim();
  if (token.isEmpty) {
    return queueEdit();
  }

  try {
    final AniListApiClient client = AniListApiClient(accessToken: token);
    await client.updateListEntry(
      mediaId: mediaId,
      status: draft.status,
      progress: draft.progress,
      scoreRaw: draft.apiScoreRaw,
      notes: draft.notes,
      repeat: draft.repeat,
    );
    try {
      final AniListAnimeListEntry? updatedEntry = await client
          .fetchMediaListEntry(
            userId: settings.anilistViewerId,
            mediaId: mediaId,
          );
      if (updatedEntry == null) {
        applyLocalEdit();
      } else {
        if (isManga) {
          invalidateAniListMangaLibraryProviders(ref.invalidate);
        } else {
          ref
              .read(anilistAnimeListProvider.notifier)
              .replaceEntry(mediaId: mediaId, entry: updatedEntry);
          invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
        }
      }
    } catch (_) {
      applyLocalEdit();
    }
    if (showSuccessSnack && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('AniList entry saved'))));
    }
    return AniListEntrySaveResult.saved;
  } catch (error) {
    if (isQueueableAniListEditError(error)) {
      return queueEdit();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(aniListEditFailureMessage(error))));
    }
    return AniListEntrySaveResult.failed;
  }
}

Future<void> deleteAniListEntry({
  required BuildContext context,
  required WidgetRef ref,
  required AniListAnimeListEntry entry,
}) async {
  final int? mediaId = entryAniListId(entry);
  if (mediaId == null) return;
  final bool isManga = _isMangaEntry(entry);

  Future<void> queueDelete() async {
    await ref
        .read(anilistEditQueueProvider)
        .queueDelete(entryId: entry.id, mediaId: mediaId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('AniList removal queued'))),
      );
    }
    if (isManga) {
      invalidateAniListMangaLibraryProviders(ref.invalidate);
    } else {
      ref.read(anilistAnimeListProvider.notifier).removeEntry(mediaId);
      invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
    }
  }

  final String token = ref.read(settingsProvider).anilistAccessToken.trim();
  if (token.isEmpty) {
    await queueDelete();
    return;
  }

  try {
    await AniListApiClient(accessToken: token).deleteListEntry(entry.id);
    if (isManga) {
      invalidateAniListMangaLibraryProviders(ref.invalidate);
    } else {
      ref.read(anilistAnimeListProvider.notifier).removeEntry(mediaId);
      invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('Removed from AniList'))),
      );
    }
  } catch (error) {
    if (isQueueableAniListEditError(error)) {
      await queueDelete();
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(aniListEditFailureMessage(error))));
    }
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

// ─── Score helpers ────────────────────────────────────────────────────────────

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

// ─── Widgets ──────────────────────────────────────────────────────────────────

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
          tooltip: 'Decrease',
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          style: stepStyle,
          tooltip: 'Increase',
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
        ? 'No score'
        : formatAniListScore(score, format);
    return switch (format) {
      'SMILEY' ||
      'POINT_3' => AniListSmileyPicker(score: score, onChanged: onChanged),
      'POINT_5' => AniListStarPicker(score: score, onChanged: onChanged),
      'POINT_100' => AniListSliderScore(
        score: score,
        displayValue: score <= 0 ? 'No score' : '${(score * 10).round()}',
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
                'Score',
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
      decoration: const InputDecoration(
        labelText: 'Score',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
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
                tooltip: selected ? 'Unscore' : opt.tooltip,
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
