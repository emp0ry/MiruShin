import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';

enum IncludeExcludeState { neutral, included, excluded }

IncludeExcludeState includeExcludeStateOf<T>(
  T value,
  Set<T> included,
  Set<T> excluded,
) {
  if (included.contains(value)) return IncludeExcludeState.included;
  if (excluded.contains(value)) return IncludeExcludeState.excluded;
  return IncludeExcludeState.neutral;
}

void setIncludeExcludeSelection<T>({
  required Set<T> included,
  required Set<T> excluded,
  required T value,
  required IncludeExcludeState state,
}) {
  switch (state) {
    case IncludeExcludeState.neutral:
      included.remove(value);
      excluded.remove(value);
    case IncludeExcludeState.included:
      excluded.remove(value);
      included.add(value);
    case IncludeExcludeState.excluded:
      included.remove(value);
      excluded.add(value);
  }
}

class IncludeExcludeFilterChip extends StatelessWidget {
  const IncludeExcludeFilterChip({
    required this.label,
    required this.state,
    required this.onInclude,
    required this.onExclude,
    required this.onClear,
    this.tooltip,
    super.key,
  });

  final String label;
  final IncludeExcludeState state;
  final VoidCallback onInclude;
  final VoidCallback onExclude;
  final VoidCallback onClear;
  final String? tooltip;

  void _toggleInclude() {
    if (state == IncludeExcludeState.included) {
      onClear();
    } else {
      onInclude();
    }
  }

  void _toggleExclude() {
    if (state == IncludeExcludeState.excluded) {
      onClear();
    } else {
      onExclude();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool included = state == IncludeExcludeState.included;
    final bool excluded = state == IncludeExcludeState.excluded;
    final Color? selectedColor = excluded
        ? cs.errorContainer
        : included
        ? cs.secondaryContainer
        : null;
    final Color? foreground = excluded
        ? cs.onErrorContainer
        : included
        ? cs.onSecondaryContainer
        : null;

    return Tooltip(
      message:
          tooltip ??
          context.t('Tap to include. Hold or right-click to exclude.'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _toggleExclude,
        onSecondaryTap: _toggleExclude,
        child: FilterChip(
          selected: included || excluded,
          showCheckmark: false,
          selectedColor: selectedColor,
          avatar: included
              ? Icon(Icons.check_rounded, size: 18, color: foreground)
              : excluded
              ? Icon(Icons.block_rounded, size: 18, color: foreground)
              : null,
          label: Text(label),
          labelStyle: foreground == null ? null : TextStyle(color: foreground),
          onSelected: (_) => _toggleInclude(),
        ),
      ),
    );
  }
}
