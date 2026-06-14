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
    final bool forceCompact = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.compactMode,
      ),
    );
    // Derive the size class from the window width (MediaQuery) instead of a
    // LayoutBuilder. Nesting a LayoutBuilder at every page root inside the
    // shell's outer LayoutBuilder collides with OverlayPortal reactivation
    // during route transitions, throwing the debug-only assert
    // "_RenderLayoutBuilder was mutated in _RenderLayoutBuilder.performLayout".
    // The padding is unchanged: medium and expanded use the same padding, and a
    // compact window has no side rail, so window width and content width
    // classify identically.
    final double width = MediaQuery.sizeOf(context).width;
    final WindowSizeClass sizeClass = AppBreakpoints.classify(
      width,
      forceCompact: forceCompact,
    );
    final bool hasBottomHomebar = width < AppBreakpoints.compact;
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
  }
}
