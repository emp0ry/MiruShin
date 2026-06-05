import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../features/catalog/application/catalog_mode.dart';
import '../widgets/app_logo.dart';
import 'app_breakpoints.dart';
import 'app_navigation_item.dart';

const int _visibleDestinationCount = 3;
const double _railMoreHeightBreakpoint = 546;
const double _sidebarMoreHeightBreakpoint = 480;

bool _matchesLocation(AppNavigationItem item, String location) {
  return location.startsWith(item.path);
}

Future<void> _showMoreDestinations(
  BuildContext context, {
  required List<AppNavigationItem> items,
  required String currentLocation,
  required ValueChanged<String> onDestinationSelected,
  required CatalogMode catalogMode,
  required VoidCallback onSwitchCatalogMode,
}) async {
  final AppNavigationItem? selected =
      await showModalBottomSheet<AppNavigationItem>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: AppThemeExtension.of(context).surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.xxl),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (BuildContext context) {
          return _MoreDestinationsSheet(
            items: items,
            currentLocation: currentLocation,
            catalogMode: catalogMode,
            onSwitchCatalogMode: onSwitchCatalogMode,
          );
        },
      );
  if (selected != null) {
    onDestinationSelected(selected.path);
  }
}

class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({
    required this.items,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.sizeClass,
    required this.catalogMode,
    required this.onLogoPressed,
    super.key,
  });

  final List<AppNavigationItem> items;
  final String currentLocation;
  final ValueChanged<String> onDestinationSelected;
  final WindowSizeClass sizeClass;
  final CatalogMode catalogMode;
  final VoidCallback onLogoPressed;

  int get _selectedIndex {
    final int index = items.indexWhere(
      (AppNavigationItem item) => currentLocation.startsWith(item.path),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return switch (sizeClass) {
      WindowSizeClass.compact => _BottomNavigation(
        items: items,
        currentLocation: currentLocation,
        onDestinationSelected: onDestinationSelected,
        catalogMode: catalogMode,
        onSwitchCatalogMode: onLogoPressed,
      ),
      WindowSizeClass.medium => _NavigationRail(
        items: items,
        currentLocation: currentLocation,
        selectedIndex: _selectedIndex,
        onDestinationSelected: onDestinationSelected,
        catalogMode: catalogMode,
        onLogoPressed: onLogoPressed,
      ),
      WindowSizeClass.expanded => _SidebarNavigation(
        items: items,
        currentLocation: currentLocation,
        onDestinationSelected: onDestinationSelected,
        catalogMode: catalogMode,
        onLogoPressed: onLogoPressed,
      ),
    };
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.items,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.catalogMode,
    required this.onSwitchCatalogMode,
  });

  final List<AppNavigationItem> items;
  final String currentLocation;
  final ValueChanged<String> onDestinationSelected;
  final CatalogMode catalogMode;
  final VoidCallback onSwitchCatalogMode;

  bool _isSelected(AppNavigationItem item) =>
      currentLocation.startsWith(item.path);

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final Color accent = Theme.of(context).colorScheme.primary;
    final List<AppNavigationItem> visibleItems = items
        .take(_visibleDestinationCount)
        .toList(growable: false);
    final List<AppNavigationItem> moreItems = items
        .skip(_visibleDestinationCount)
        .toList(growable: false);
    final int visibleIndex = visibleItems.indexWhere(_isSelected);
    final int selectedIndex = visibleIndex >= 0
        ? visibleIndex
        : visibleItems.length;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                palette.glassColor.withValues(alpha: 0.4),
                palette.surfaceColor.withValues(alpha: 0.4),
              ],
            ),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            indicatorColor: accent.withValues(alpha: 0.16),
            selectedIndex: selectedIndex,
            onDestinationSelected: (int index) {
              if (index < visibleItems.length) {
                onDestinationSelected(visibleItems[index].path);
                return;
              }
              _showMoreDestinations(
                context,
                items: moreItems,
                currentLocation: currentLocation,
                onDestinationSelected: onDestinationSelected,
                catalogMode: catalogMode,
                onSwitchCatalogMode: onSwitchCatalogMode,
              );
            },
            destinations: <NavigationDestination>[
              ...visibleItems.map(
                (AppNavigationItem item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: context.t(item.labelKey),
                ),
              ),
              NavigationDestination(
                icon: const Icon(Icons.more_horiz_rounded),
                selectedIcon: const Icon(Icons.more_rounded),
                label: context.t('More'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreDestinationsSheet extends StatelessWidget {
  const _MoreDestinationsSheet({
    required this.items,
    required this.currentLocation,
    required this.catalogMode,
    required this.onSwitchCatalogMode,
  });

  final List<AppNavigationItem> items;
  final String currentLocation;
  final CatalogMode catalogMode;
  final VoidCallback onSwitchCatalogMode;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _CatalogModeSwitchTile(
                catalogMode: catalogMode,
                accent: accent,
                onTap: () {
                  Navigator.of(context).pop();
                  onSwitchCatalogMode();
                },
              ),
            ),
            for (final AppNavigationItem item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _MoreDestinationTile(
                  item: item,
                  selected: currentLocation.startsWith(item.path),
                  accent: accent,
                  onTap: () => Navigator.of(context).pop(item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogModeSwitchTile extends StatelessWidget {
  const _CatalogModeSwitchTile({
    required this.catalogMode,
    required this.accent,
    required this.onTap,
  });

  final CatalogMode catalogMode;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final CatalogMode nextMode = catalogMode.toggled;
    return Semantics(
      button: true,
      label: context.t('Switch Catalog Mode'),
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: AppRadius.all(AppRadius.lg),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: AppRadius.all(AppRadius.md),
                ),
                child: Icon(Icons.swap_horiz_rounded, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.t('Switch Catalog Mode'),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${catalogMode.label} -> ${nextMode.label}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textMutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreDestinationTile extends StatelessWidget {
  const _MoreDestinationTile({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppNavigationItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : palette.glassColor,
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.36)
                : palette.borderColor,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : palette.surfaceSoftColor,
                borderRadius: AppRadius.all(AppRadius.md),
              ),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                color: selected ? accent : palette.textSecondaryColor,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                context.t(item.labelKey),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: selected ? accent : palette.textPrimaryColor,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: selected ? accent : palette.textMutedColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.items,
    required this.currentLocation,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.catalogMode,
    required this.onLogoPressed,
  });

  final List<AppNavigationItem> items;
  final String currentLocation;
  final int selectedIndex;
  final ValueChanged<String> onDestinationSelected;
  final CatalogMode catalogMode;
  final VoidCallback onLogoPressed;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool useMore = constraints.maxHeight < _railMoreHeightBreakpoint;
        final List<AppNavigationItem> visibleItems = useMore
            ? items.take(_visibleDestinationCount).toList(growable: false)
            : items;
        final List<AppNavigationItem> moreItems = useMore
            ? items.skip(_visibleDestinationCount).toList(growable: false)
            : const <AppNavigationItem>[];
        final bool moreSelected = moreItems.any(
          (AppNavigationItem item) => _matchesLocation(item, currentLocation),
        );
        final int visibleSelectedIndex = visibleItems.indexWhere(
          (AppNavigationItem item) => _matchesLocation(item, currentLocation),
        );
        final int railSelectedIndex = moreSelected
            ? visibleItems.length
            : visibleSelectedIndex >= 0
            ? visibleSelectedIndex
            : selectedIndex.clamp(0, visibleItems.length - 1);

        return Container(
          width: 104,
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.glassColor,
            borderRadius: AppRadius.all(AppRadius.xl),
            border: Border.all(color: palette.borderColor),
          ),
          child: NavigationRail(
            scrollable: true,
            leading: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: AppLogo(compact: true, onPressed: onLogoPressed),
            ),
            selectedIndex: railSelectedIndex,
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.75,
            onDestinationSelected: (int index) {
              if (useMore && index == visibleItems.length) {
                _showMoreDestinations(
                  context,
                  items: moreItems,
                  currentLocation: currentLocation,
                  onDestinationSelected: onDestinationSelected,
                  catalogMode: catalogMode,
                  onSwitchCatalogMode: onLogoPressed,
                );
                return;
              }
              onDestinationSelected(visibleItems[index].path);
            },
            destinations: <NavigationRailDestination>[
              ...visibleItems.map(
                (AppNavigationItem item) => NavigationRailDestination(
                  icon: Tooltip(
                    message: context.t(item.labelKey),
                    child: Icon(item.icon),
                  ),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(context.t(item.labelKey)),
                ),
              ),
              if (useMore)
                NavigationRailDestination(
                  icon: Tooltip(
                    message: context.t('More'),
                    child: const Icon(Icons.more_horiz_rounded),
                  ),
                  selectedIcon: const Icon(Icons.more_rounded),
                  label: Text(context.t('More')),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarNavigation extends StatelessWidget {
  const _SidebarNavigation({
    required this.items,
    required this.currentLocation,
    required this.onDestinationSelected,
    required this.catalogMode,
    required this.onLogoPressed,
  });

  final List<AppNavigationItem> items;
  final String currentLocation;
  final ValueChanged<String> onDestinationSelected;
  final CatalogMode catalogMode;
  final VoidCallback onLogoPressed;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double contentHeight =
            constraints.maxHeight - (AppSpacing.lg * 4);
        final bool useMore = contentHeight < _sidebarMoreHeightBreakpoint;
        final List<AppNavigationItem> visibleItems = useMore
            ? items.take(_visibleDestinationCount).toList(growable: false)
            : items;
        final List<AppNavigationItem> moreItems = useMore
            ? items.skip(_visibleDestinationCount).toList(growable: false)
            : const <AppNavigationItem>[];
        final bool moreSelected = moreItems.any(
          (AppNavigationItem item) => _matchesLocation(item, currentLocation),
        );

        return Container(
          width: 256,
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: palette.glassColor,
            borderRadius: AppRadius.all(AppRadius.xxl),
            border: Border.all(color: palette.borderColor),
            gradient: palette.cardGradient,
          ),
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  child: AppLogo(
                    taglineOverride: catalogMode.label,
                    onPressed: onLogoPressed,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  ...visibleItems.map((AppNavigationItem item) {
                    final bool selected = _matchesLocation(
                      item,
                      currentLocation,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _SidebarButton(
                        item: item,
                        selected: selected,
                        accent: accent,
                        onTap: () => onDestinationSelected(item.path),
                      ),
                    );
                  }),
                  if (useMore)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _SidebarMoreButton(
                        selected: moreSelected,
                        accent: accent,
                        onTap: () => _showMoreDestinations(
                          context,
                          items: moreItems,
                          currentLocation: currentLocation,
                          onDestinationSelected: onDestinationSelected,
                          catalogMode: catalogMode,
                          onSwitchCatalogMode: onLogoPressed,
                        ),
                      ),
                    ),
                ]),
              ),
              // if (showFooter) ...<Widget>[
              //   SliverToBoxAdapter(
              //     child: Padding(
              //       padding: const EdgeInsets.only(top: AppSpacing.sm),
              //       child: Text(
              //         AppConstants.appVersion.split('+').first,
              //         style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              //           color: palette.textMutedColor,
              //           fontSize: 12,
              //         ),
              //       ),
              //     ),
              //   ),
              // ],
            ],
          ),
        );
      },
    );
  }
}

class _SidebarMoreButton extends StatelessWidget {
  const _SidebarMoreButton({
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Tooltip(
      message: context.t('More'),
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: AppRadius.all(AppRadius.lg),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.36)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected ? Icons.more_rounded : Icons.more_horiz_rounded,
                color: selected ? accent : palette.textSecondaryColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  context.t('More'),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? accent : palette.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppNavigationItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Tooltip(
      message: context.t(item.labelKey),
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: AppRadius.all(AppRadius.lg),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.36)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: selected ? accent : palette.textSecondaryColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  context.t(item.labelKey),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? accent : palette.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
