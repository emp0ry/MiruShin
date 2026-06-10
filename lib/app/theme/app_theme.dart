import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_theme_extension.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData dark({Color accent = AppColors.accentPurple}) {
    final AppThemeExtension palette = AppThemeExtension.dark();
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          secondary: AppColors.accentViolet,
          surface: palette.surfaceColor,
          onSurface: palette.textPrimaryColor,
          error: AppColors.danger,
        );

    return _base(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      palette: palette,
    );
  }

  static ThemeData light({Color accent = AppColors.accentPurple}) {
    final AppThemeExtension palette = AppThemeExtension.light();
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: accent,
          secondary: AppColors.accentViolet,
          surface: palette.surfaceColor,
          onSurface: palette.textPrimaryColor,
          error: AppColors.danger,
        );

    return _base(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F6FB),
      palette: palette,
    );
  }

  static ThemeData oled({Color accent = AppColors.accentPurple}) {
    final AppThemeExtension palette = AppThemeExtension.oled();
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          secondary: AppColors.accentViolet,
          surface: palette.surfaceColor,
          onSurface: palette.textPrimaryColor,
          error: AppColors.danger,
        );

    return _base(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      palette: palette,
    );
  }

  static ThemeData _base({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required AppThemeExtension palette,
  }) {
    final bool isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: AppTypography.textTheme(brightness),
      canvasColor: scaffoldBackgroundColor,
      cardColor: palette.glassColor,
      dividerColor: palette.borderColor,
      splashFactory: InkSparkle.splashFactory,
      // Strong, accent-tinted focus highlight so D-pad / keyboard navigation is
      // clearly visible on every ink-based surface (InkWell, ListTile, etc.).
      // This is the backbone of the 10-foot (Android TV) experience and is
      // inert on touch, where widgets never take focus. InkResponse falls back
      // to this color when a widget doesn't set its own focusColor.
      focusColor: colorScheme.primary.withValues(alpha: 0.30),
      extensions: <ThemeExtension<dynamic>>[palette],
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimaryColor,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.glassColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.lg),
          side: BorderSide(color: palette.borderColor),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceColor,
        modalBackgroundColor: palette.surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          side: BorderSide(color: palette.borderColor),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(
            palette.textSecondaryColor,
          ),
          overlayColor: WidgetStateProperty.resolveWith<Color>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.primary.withValues(alpha: 0.22);
            }
            if (states.contains(WidgetState.focused)) {
              return colorScheme.primary.withValues(alpha: 0.30);
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primary.withValues(alpha: 0.12);
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.md)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.glassStrongColor,
        hintStyle: TextStyle(color: palette.textMutedColor),
        prefixIconColor: palette.textSecondaryColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.all(AppRadius.lg),
          borderSide: BorderSide(color: palette.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(AppRadius.lg),
          borderSide: BorderSide(color: palette.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(AppRadius.lg),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.all(AppRadius.md),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ).copyWith(
              // Brighten the fill on focus so the D-pad selection reads clearly.
              overlayColor: WidgetStateProperty.resolveWith<Color?>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.onPrimary.withValues(alpha: 0.20);
                }
                if (states.contains(WidgetState.focused)) {
                  return colorScheme.onPrimary.withValues(alpha: 0.26);
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.onPrimary.withValues(alpha: 0.12);
                }
                return null;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: palette.textPrimaryColor,
              side: BorderSide(color: palette.borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.all(AppRadius.md),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith<Color?>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.pressed)) {
                  return colorScheme.primary.withValues(alpha: 0.18);
                }
                if (states.contains(WidgetState.focused)) {
                  return colorScheme.primary.withValues(alpha: 0.22);
                }
                if (states.contains(WidgetState.hovered)) {
                  return colorScheme.primary.withValues(alpha: 0.10);
                }
                return null;
              }),
              // Accent ring around the outline when focused via remote/keyboard.
              side: WidgetStateProperty.resolveWith<BorderSide>((
                Set<WidgetState> states,
              ) {
                if (states.contains(WidgetState.focused)) {
                  return BorderSide(color: colorScheme.primary, width: 2);
                }
                return BorderSide(color: palette.borderColor);
              }),
            ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.glassStrongColor,
        selectedColor: colorScheme.primary.withValues(alpha: 0.18),
        side: BorderSide(color: palette.borderColor),
        labelStyle: TextStyle(
          color: palette.textSecondaryColor,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.md),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: palette.glassStrongColor,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : palette.textMutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.16),
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: palette.textMutedColor),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: palette.textMutedColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? colorScheme.primary
                : palette.textSecondaryColor,
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: palette.borderColor),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colorScheme.primary
              : palette.textMutedColor,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colorScheme.primary.withValues(alpha: 0.32)
              : palette.surfaceSoftColor,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: palette.surfaceSoftColor,
        thumbColor: colorScheme.primary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? palette.surfaceColor : const Color(0xFF101624),
          borderRadius: AppRadius.all(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}
