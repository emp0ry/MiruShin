import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/models/calendar_item.dart';
import '../../../shared/models/media_item.dart';
import '../../catalog/presentation/catalog_offline_banner.dart';
import '../../catalog/application/catalog_mode.dart';
import '../application/calendar_items_provider.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  String _view = 'List';
  final Set<MediaType> _filters = <MediaType>{};
  bool _libraryOnly = false;
  DateTime _selectedDate = DateTime.now();

  List<CalendarItem> _visibleItems(List<CalendarItem> source) {
    return source.where((CalendarItem item) {
        final bool typeMatches =
            _filters.isEmpty || _filters.contains(item.mediaItem.type);
        final bool libraryMatches = !_libraryOnly || item.isFromLibrary;
        return typeMatches && libraryMatches;
      }).toList()
      ..sort((CalendarItem a, CalendarItem b) => a.date.compareTo(b.date));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CalendarItem>> asyncItems = ref.watch(
      calendarItemsProvider,
    );
    final List<CalendarItem> items = _visibleItems(
      asyncItems.maybeWhen(
        data: (List<CalendarItem> value) => value,
        orElse: () => <CalendarItem>[],
      ),
    );
    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const CatalogOfflineBanner(),
            SectionHeader(
              title: context.t('Calendar'),
              subtitle: context.t('Upcoming Episodes'),
            ),
            const SizedBox(height: AppSpacing.lg),
            _CalendarControls(
              selectedDate: _selectedDate,
              view: _view,
              onToday: () => setState(() => _selectedDate = DateTime.now()),
              onDateSelected: (DateTime value) =>
                  setState(() => _selectedDate = value),
              onViewChanged: (String value) => setState(() => _view = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            _CalendarFilters(
              filters: _filters,
              libraryOnly: _libraryOnly,
              onToggleType: (MediaType type) {
                setState(() {
                  if (_filters.contains(type)) {
                    _filters.remove(type);
                  } else {
                    _filters.add(type);
                  }
                });
              },
              onLibraryOnlyChanged: (bool value) =>
                  setState(() => _libraryOnly = value),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_view != 'List') _CalendarPlaceholder(view: _view),
            if (_view != 'List') const SizedBox(height: AppSpacing.xl),
            if (asyncItems.isLoading)
              const GlassCard(
                child: SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (items.isEmpty)
              NeutralPlaceholder(
                icon: Icons.event_busy_rounded,
                title: context.t('Calendar Preview'),
                message: context.t(
                  'No metadata source is configured yet. Add your credentials in Settings.',
                ),
                height: 260,
              )
            else
              _GroupedCalendarList(items: items),
          ],
        ),
      ),
    );
  }
}

class _CalendarControls extends StatelessWidget {
  const _CalendarControls({
    required this.selectedDate,
    required this.view,
    required this.onToday,
    required this.onDateSelected,
    required this.onViewChanged,
  });

  final DateTime selectedDate;
  final String view;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<String> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final DateFormat format = DateFormat.yMMMMd(
      Localizations.localeOf(context).toString(),
    );
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        FilledButton.icon(
          onPressed: onToday,
          icon: const Icon(Icons.today_rounded),
          label: Text(context.t('Today')),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) {
              onDateSelected(picked);
            }
          },
          icon: const Icon(Icons.calendar_month_rounded),
          label: Text(format.format(selectedDate)),
        ),
        SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: 'Month',
              label: Text(context.t('Month')),
              icon: const Icon(Icons.calendar_view_month_rounded),
            ),
            ButtonSegment<String>(
              value: 'Week',
              label: Text(context.t('Week')),
              icon: const Icon(Icons.view_week_rounded),
            ),
            ButtonSegment<String>(
              value: 'List',
              label: Text(context.t('List')),
              icon: const Icon(Icons.view_agenda_rounded),
            ),
          ],
          selected: <String>{view},
          onSelectionChanged: (Set<String> values) =>
              onViewChanged(values.first),
        ),
      ],
    );
  }
}

class _CalendarFilters extends StatelessWidget {
  const _CalendarFilters({
    required this.filters,
    required this.libraryOnly,
    required this.onToggleType,
    required this.onLibraryOnlyChanged,
  });

  final Set<MediaType> filters;
  final bool libraryOnly;
  final ValueChanged<MediaType> onToggleType;
  final ValueChanged<bool> onLibraryOnlyChanged;

  @override
  Widget build(BuildContext context) {
    final List<({String label, MediaType type})> types =
        <({String label, MediaType type})>[
          (label: 'Movies', type: MediaType.movie),
          (label: 'Series', type: MediaType.series),
          (label: 'Anime', type: MediaType.anime),
        ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final type in types)
          FilterChip(
            label: Text(context.t(type.label)),
            selected: filters.contains(type.type),
            onSelected: (_) => onToggleType(type.type),
          ),
        FilterChip(
          label: Text(context.t('Library Only')),
          selected: libraryOnly,
          onSelected: onLibraryOnlyChanged,
        ),
      ],
    );
  }
}

class _CalendarPlaceholder extends StatelessWidget {
  const _CalendarPlaceholder({required this.view});

  final String view;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: SizedBox(
        height: view == 'Month' ? 280 : 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                view == 'Month'
                    ? Icons.calendar_view_month_rounded
                    : Icons.view_week_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 42,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${context.t(view)} ${context.t('Calendar Preview')}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.t('Calendar data appears here when available.'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupedCalendarList extends StatelessWidget {
  const _GroupedCalendarList({required this.items});

  final List<CalendarItem> items;

  @override
  Widget build(BuildContext context) {
    final Map<DateTime, List<CalendarItem>> groups =
        <DateTime, List<CalendarItem>>{};
    for (final CalendarItem item in items) {
      final DateTime day = DateTime(
        item.date.year,
        item.date.month,
        item.date.day,
      );
      groups.putIfAbsent(day, () => <CalendarItem>[]).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries
          .map(
            (MapEntry<DateTime, List<CalendarItem>> group) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: _CalendarDayGroup(date: group.key, items: group.value),
            ),
          )
          .toList(),
    );
  }
}

class _CalendarDayGroup extends ConsumerWidget {
  const _CalendarDayGroup({required this.date, required this.items});

  final DateTime date;
  final List<CalendarItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final DateFormat dayFormat = DateFormat.yMMMMEEEEd(
      Localizations.localeOf(context).toString(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: dayFormat.format(date)),
        ...items.map(
          (CalendarItem item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: GlassCard(
              onTap: () => context.push(
                AppRoutes.mediaDetailsPath(item.mediaItem.id),
                extra: item.mediaItem,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: AppRadius.all(AppRadius.md),
                    child: item.mediaItem.posterUrl.isEmpty
                        ? Container(
                            width: 58,
                            height: 86,
                            decoration: BoxDecoration(
                              gradient: palette.posterFallbackGradient,
                            ),
                          )
                        : Image.network(
                            item.mediaItem.posterUrl,
                            width: 58,
                            height: 86,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 58,
                              height: 86,
                              decoration: BoxDecoration(
                                gradient: palette.posterFallbackGradient,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: <Widget>[
                            MetadataChip(label: context.t(item.type.label)),
                            if (mode != CatalogMode.anilist)
                              MetadataChip(
                                label: context.t(item.mediaItem.type.labelKey),
                              ),
                            if (item.isFromLibrary)
                              MetadataChip(label: context.t('Library Only')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
