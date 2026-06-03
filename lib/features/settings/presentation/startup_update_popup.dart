import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/app_logo.dart';
import '../application/update_checker_provider.dart';

class StartupUpdatePopup extends ConsumerStatefulWidget {
  const StartupUpdatePopup({super.key});

  @override
  ConsumerState<StartupUpdatePopup> createState() => _StartupUpdatePopupState();
}

class _StartupUpdatePopupState extends ConsumerState<StartupUpdatePopup> {
  static const String _dismissedVersionKey =
      'startup.updatePopup.dismissedVersion';

  String? _dismissedVersion;
  String? _loadedForVersion;
  String? _loadingForVersion;
  String? _hiddenForSession;

  void _ensureDismissedVersionLoaded(String version) {
    if (_loadedForVersion == version || _loadingForVersion == version) {
      return;
    }
    _loadingForVersion = version;
    unawaited(
      SharedPreferences.getInstance().then((SharedPreferences prefs) {
        if (!mounted) return;
        setState(() {
          _dismissedVersion = prefs.getString(_dismissedVersionKey);
          _loadedForVersion = version;
          _loadingForVersion = null;
        });
      }),
    );
  }

  void _hideForSession(String version) {
    setState(() {
      _hiddenForSession = version;
    });
  }

  Future<void> _dismissVersion(String version) async {
    setState(() {
      _dismissedVersion = version;
      _hiddenForSession = version;
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedVersionKey, version);
  }

  Future<void> _download(UpdateInfo info) async {
    _hideForSession(info.tagName);
    await launchUrl(
      Uri.parse(info.releaseUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<UpdateInfo?> update = ref.watch(updateCheckerProvider);
    final UpdateInfo? info = update.asData?.value;
    final bool show =
        info != null &&
        info.hasUpdate &&
        _loadedForVersion == info.tagName &&
        _hiddenForSession != info.tagName &&
        _dismissedVersion != info.tagName;

    if (info != null && info.hasUpdate) {
      _ensureDismissedVersionLoaded(info.tagName);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 460;
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: compact ? AppSpacing.md : AppSpacing.xl,
              top: compact ? AppSpacing.sm : AppSpacing.lg,
              right: compact ? AppSpacing.md : AppSpacing.xl,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: AppAnimations.medium,
                switchInCurve: AppAnimations.standard,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final Animation<double> slide = CurvedAnimation(
                    parent: animation,
                    curve: AppAnimations.standard,
                  );
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.08),
                        end: Offset.zero,
                      ).animate(slide),
                      child: child,
                    ),
                  );
                },
                child: show
                    ? _UpdateNotificationCard(
                        key: ValueKey<String>('update-${info.tagName}'),
                        info: info,
                        onDownload: () => unawaited(_download(info)),
                        onDismissVersion: () =>
                            unawaited(_dismissVersion(info.tagName)),
                        onLater: () => _hideForSession(info.tagName),
                      )
                    : const SizedBox.shrink(key: ValueKey<String>('no-update')),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UpdateNotificationCard extends StatelessWidget {
  const _UpdateNotificationCard({
    required this.info,
    required this.onDownload,
    required this.onDismissVersion,
    required this.onLater,
    super.key,
  });

  final UpdateInfo info;
  final VoidCallback onDownload;
  final VoidCallback onDismissVersion;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);

    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: double.infinity,
          child: ClipRRect(
            borderRadius: AppRadius.all(AppRadius.xl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      palette.glassStrongColor.withValues(alpha: 0.94),
                      palette.glassColor.withValues(alpha: 0.9),
                    ],
                  ),
                  borderRadius: AppRadius.all(AppRadius.xl),
                  border: Border.all(
                    color: palette.borderColor.withValues(alpha: 0.8),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool compact = constraints.maxWidth < 420;
                    return Padding(
                      padding: EdgeInsets.all(
                        compact ? AppSpacing.md : AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              SizedBox(
                                width: compact ? 40 : 44,
                                height: compact ? 40 : 44,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: const AppLogo(compact: true),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: <InlineSpan>[
                                      TextSpan(text: context.t('New Update')),
                                      TextSpan(
                                        text: '  ${info.tagName}',
                                        style: TextStyle(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  maxLines: compact ? 2 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      (compact
                                              ? textTheme.titleSmall
                                              : textTheme.titleMedium)
                                          ?.copyWith(
                                            color: palette.textPrimaryColor,
                                            fontWeight: FontWeight.w800,
                                          ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Transform.translate(
                                offset: const Offset(0, 2),
                                child: FilledButton.icon(
                                  onPressed: onDownload,
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text(context.t('Download')),
                                  style: FilledButton.styleFrom(
                                    visualDensity: compact
                                        ? VisualDensity.compact
                                        : VisualDensity.standard,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact
                                          ? AppSpacing.md
                                          : AppSpacing.lg,
                                      vertical: compact ? 9 : 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _UpdateActions(
                            onDismissVersion: onDismissVersion,
                            onLater: onLater,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateActions extends StatelessWidget {
  const _UpdateActions({required this.onDismissVersion, required this.onLater});

  final VoidCallback onDismissVersion;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _QuietUpdateButton(
            onPressed: onDismissVersion,
            label: context.t("Don't Show Again"),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _QuietUpdateButton(
            onPressed: onLater,
            label: context.t('Later'),
          ),
        ),
      ],
    );
  }
}

class _QuietUpdateButton extends StatelessWidget {
  const _QuietUpdateButton({required this.onPressed, required this.label});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: palette.textSecondaryColor,
        backgroundColor: palette.surfaceSoftColor.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.lg),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}
