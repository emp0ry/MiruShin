import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.shellGradient,
    required this.cardGradient,
    required this.heroOverlayGradient,
    required this.glassColor,
    required this.glassStrongColor,
    required this.surfaceColor,
    required this.surfaceSoftColor,
    required this.borderColor,
    required this.textPrimaryColor,
    required this.textSecondaryColor,
    required this.textMutedColor,
    required this.posterFallbackGradient,
  });

  final LinearGradient shellGradient;
  final LinearGradient cardGradient;
  final LinearGradient heroOverlayGradient;
  final Color glassColor;
  final Color glassStrongColor;
  final Color surfaceColor;
  final Color surfaceSoftColor;
  final Color borderColor;
  final Color textPrimaryColor;
  final Color textSecondaryColor;
  final Color textMutedColor;
  final LinearGradient posterFallbackGradient;

  static AppThemeExtension of(BuildContext context) {
    return Theme.of(context).extension<AppThemeExtension>() ??
        AppThemeExtension.dark();
  }

  factory AppThemeExtension.dark() {
    return const AppThemeExtension(
      shellGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[AppColors.background, AppColors.background],
      ),
      cardGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0x1CFFFFFF), Color(0x1CFFFFFF)],
      ),
      heroOverlayGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0x24070A12),
          Color(0xD6070A12),
          AppColors.background,
        ],
      ),
      glassColor: AppColors.surfaceGlass,
      glassStrongColor: Color(0xE6121A2A),
      surfaceColor: AppColors.surface,
      surfaceSoftColor: AppColors.surfaceSoft,
      borderColor: AppColors.border,
      textPrimaryColor: AppColors.textPrimary,
      textSecondaryColor: AppColors.textSecondary,
      textMutedColor: AppColors.textMuted,
      posterFallbackGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF111827), Color(0xFF111827)],
      ),
    );
  }

  factory AppThemeExtension.light() {
    return const AppThemeExtension(
      shellGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFFF3F6FB), Color(0xFFF3F6FB)],
      ),
      cardGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xEFFFFFFF), Color(0xEFFFFFFF)],
      ),
      heroOverlayGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0x0AFFFFFF),
          Color(0xB8070A12),
          Color(0xEE070A12),
        ],
      ),
      glassColor: Color(0xD9FFFFFF),
      glassStrongColor: Color(0xF7FFFFFF),
      surfaceColor: Color(0xFFFFFFFF),
      surfaceSoftColor: Color(0xFFE8EDF7),
      borderColor: Color(0x24314557),
      textPrimaryColor: Color(0xFF101624),
      textSecondaryColor: Color(0xFF465064),
      textMutedColor: Color(0xFF697487),
      posterFallbackGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF242A3A), Color(0xFF242A3A)],
      ),
    );
  }

  factory AppThemeExtension.oled() {
    return const AppThemeExtension(
      shellGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Colors.black, Colors.black],
      ),
      cardGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0x14000000), Color(0x14000000)],
      ),
      heroOverlayGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0x10000000), Color(0xDC000000), Colors.black],
      ),
      glassColor: Color(0xD9000000),
      glassStrongColor: Color(0xF7000000),
      surfaceColor: Color(0xFF050505),
      surfaceSoftColor: Color(0xFF0E0E12),
      borderColor: Color(0x30FFFFFF),
      textPrimaryColor: Color(0xFFFFFFFF),
      textSecondaryColor: Color(0xFFC5CBD8),
      textMutedColor: Color(0xFF858B98),
      posterFallbackGradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF050505), Color(0xFF050505)],
      ),
    );
  }

  @override
  AppThemeExtension copyWith({
    LinearGradient? shellGradient,
    LinearGradient? cardGradient,
    LinearGradient? heroOverlayGradient,
    Color? glassColor,
    Color? glassStrongColor,
    Color? surfaceColor,
    Color? surfaceSoftColor,
    Color? borderColor,
    Color? textPrimaryColor,
    Color? textSecondaryColor,
    Color? textMutedColor,
    LinearGradient? posterFallbackGradient,
  }) {
    return AppThemeExtension(
      shellGradient: shellGradient ?? this.shellGradient,
      cardGradient: cardGradient ?? this.cardGradient,
      heroOverlayGradient: heroOverlayGradient ?? this.heroOverlayGradient,
      glassColor: glassColor ?? this.glassColor,
      glassStrongColor: glassStrongColor ?? this.glassStrongColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      surfaceSoftColor: surfaceSoftColor ?? this.surfaceSoftColor,
      borderColor: borderColor ?? this.borderColor,
      textPrimaryColor: textPrimaryColor ?? this.textPrimaryColor,
      textSecondaryColor: textSecondaryColor ?? this.textSecondaryColor,
      textMutedColor: textMutedColor ?? this.textMutedColor,
      posterFallbackGradient:
          posterFallbackGradient ?? this.posterFallbackGradient,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) {
      return this;
    }
    return AppThemeExtension(
      shellGradient: t < 0.5 ? shellGradient : other.shellGradient,
      cardGradient: t < 0.5 ? cardGradient : other.cardGradient,
      heroOverlayGradient: t < 0.5
          ? heroOverlayGradient
          : other.heroOverlayGradient,
      glassColor: Color.lerp(glassColor, other.glassColor, t)!,
      glassStrongColor: Color.lerp(
        glassStrongColor,
        other.glassStrongColor,
        t,
      )!,
      surfaceColor: Color.lerp(surfaceColor, other.surfaceColor, t)!,
      surfaceSoftColor: Color.lerp(
        surfaceSoftColor,
        other.surfaceSoftColor,
        t,
      )!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      textPrimaryColor: Color.lerp(
        textPrimaryColor,
        other.textPrimaryColor,
        t,
      )!,
      textSecondaryColor: Color.lerp(
        textSecondaryColor,
        other.textSecondaryColor,
        t,
      )!,
      textMutedColor: Color.lerp(textMutedColor, other.textMutedColor, t)!,
      posterFallbackGradient: t < 0.5
          ? posterFallbackGradient
          : other.posterFallbackGradient,
    );
  }
}
