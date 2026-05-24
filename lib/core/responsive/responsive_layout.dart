import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_breakpoints.dart';
import '../../features/settings/presentation/settings_state.dart';

class ResponsiveLayout extends ConsumerWidget {
  const ResponsiveLayout({
    required this.compact,
    required this.medium,
    required this.expanded,
    super.key,
  });

  final Widget compact;
  final Widget medium;
  final Widget expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool forceCompact = ref.watch(
          settingsProvider.select(
            (SettingsState settings) => settings.compactMode,
          ),
        );
        return switch (AppBreakpoints.classify(
          constraints.maxWidth,
          forceCompact: forceCompact,
        )) {
          WindowSizeClass.compact => compact,
          WindowSizeClass.medium => medium,
          WindowSizeClass.expanded => expanded,
        };
      },
    );
  }
}
