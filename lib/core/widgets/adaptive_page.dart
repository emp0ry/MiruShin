import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_spacing.dart';
import '../../features/settings/presentation/settings_state.dart';
import '../responsive/app_breakpoints.dart';

class AdaptivePage extends ConsumerWidget {
  const AdaptivePage({required this.child, this.maxWidth = 1480, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool forceCompact = ref.watch(
          settingsProvider.select(
            (SettingsState settings) => settings.compactMode,
          ),
        );
        final WindowSizeClass sizeClass = AppBreakpoints.classify(
          constraints.maxWidth,
          forceCompact: forceCompact,
        );
        final bool hasBottomHomebar =
            MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
        final EdgeInsets padding = switch (sizeClass) {
          WindowSizeClass.compact => EdgeInsets.fromLTRB(
            AppSpacing.lg,
            hasBottomHomebar ? 0 : AppSpacing.lg,
            AppSpacing.lg,
            hasBottomHomebar ? 0 : AppSpacing.lg,
          ),
          WindowSizeClass.medium => const EdgeInsets.all(AppSpacing.lg),
          WindowSizeClass.expanded => const EdgeInsets.all(AppSpacing.lg),
        };

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}
