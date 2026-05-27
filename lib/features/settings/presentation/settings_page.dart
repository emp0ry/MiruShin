import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/localization/supported_languages.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/cache/metadata_cache_store.dart';
import '../../../core/platform/io_compat.dart' if (dart.library.io) 'dart:io';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../calendar/application/calendar_items_provider.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../metadata/data/tmdb_metadata_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../player/application/player_settings.dart';
import '../../player/data/discord_rpc_service.dart';
import '../../player/domain/player_models.dart';
import '../../../shared/models/anilist_models.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/application/anilist_login_flow.dart';
import 'settings_state.dart';
import 'widgets/settings_widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);
    final CatalogMode catalogMode = ref.watch(catalogModeProvider);
    final bool showAniListProfileUi = catalogMode == CatalogMode.anilist;
    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: context.t('Settings'),
            ),
            const SizedBox(height: AppSpacing.lg),
            _AccountSection(placeholderOnly: !showAniListProfileUi),
            const SizedBox(height: AppSpacing.lg),
            if (showAniListProfileUi && settings.hasAniListSession) ...<Widget>[
              const _AniListSettingsShortcutSection(),
              const SizedBox(height: AppSpacing.lg),
            ],
            _AppearanceSection(settings: settings, controller: controller),
            const SizedBox(height: AppSpacing.lg),
            _LanguageSection(
              settings: settings,
              controller: controller,
              showMetadataLanguage: catalogMode == CatalogMode.tmdb,
            ),
            const SizedBox(height: AppSpacing.lg),
            _ApiConnectionsSection(settings: settings, controller: controller),
            const SizedBox(height: AppSpacing.lg),
            if (DiscordRpcService.isSupported) ...<Widget>[
              _DiscordRpcSection(settings: settings, controller: controller),
              const SizedBox(height: AppSpacing.lg),
            ],
            _CacheSection(settings: settings, controller: controller),
            const SizedBox(height: AppSpacing.lg),
            const _AboutSection(),
          ],
        ),
      ),
    );
  }
}

class _AniListSettingsShortcutSection extends StatelessWidget {
  const _AniListSettingsShortcutSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('AniList Settings'),
      icon: Icons.tune_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('AniList Settings'),
          subtitle: context.t(
            'Open AniList profile content settings, list preferences, and MiruShin sync options.',
          ),
          trailing: FilledButton.icon(
            onPressed: () => context.go(AppRoutes.profileSettings),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(context.t('Open')),
          ),
        ),
      ],
    );
  }
}

class _DiscordRpcSection extends StatelessWidget {
  const _DiscordRpcSection({required this.settings, required this.controller});

  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Discord RPC',
      icon: Icons.integration_instructions_rounded,
      children: <Widget>[
        SettingsRow(
          title: 'Enable Discord Rich Presence',
          subtitle:
              'Show what you are watching in Discord on desktop. Player Settings can still disable it per player.',
          trailing: Switch(
            value: settings.discordRpcEnabled,
            onChanged: controller.setDiscordRpcEnabled,
          ),
        ),
      ],
    );
  }
}

class _ApiConnectionsSection extends ConsumerWidget {
  const _ApiConnectionsSection({
    required this.settings,
    required this.controller,
  });

  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: context.t('API Connections'),
      icon: Icons.cloud_sync_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('Enable TMDB metadata'),
          subtitle: context.t(
            'Primary source for Board, Discovery, movies, series, and anime visuals.',
          ),
          trailing: Switch(
            value: settings.tmdbEnabled,
            onChanged: controller.setTmdbEnabled,
          ),
        ),
        SettingsRow(
          title: context.t('TMDB Read Access Token'),
          subtitle: context.t(
            'Stored in secure platform storage. Do not commit secrets.',
          ),
          trailing: _TextSettingField(
            initialValue: settings.tmdbReadAccessToken,
            hintText: 'duHahLci2pJIZbQ2MoJ0...',
            obscureText: true,
            onChanged: controller.setTmdbReadAccessToken,
          ),
        ),
        SettingsRow(
          title: context.t('TMDB language'),
          subtitle: context.t(
            'Controlled by Metadata language. App language only changes interface text.',
          ),
          trailing: _TextSettingField(
            initialValue: settings.effectiveTmdbLanguage,
            hintText: 'en-US',
            onChanged: controller.setTmdbLanguage,
          ),
        ),
        SettingsRow(
          title: context.t('TMDB region'),
          trailing: _TextSettingField(
            initialValue: settings.tmdbRegion,
            hintText: 'US',
            onChanged: controller.setTmdbRegion,
          ),
        ),
        SettingsRow(
          title: context.t('TMDB connection'),
          subtitle: settings.hasTmdbToken
              ? context.t('Configured')
              : context.t('Not configured'),
          trailing: OutlinedButton.icon(
            onPressed: settings.hasTmdbToken
                ? () => _testTmdbConnection(context)
                : null,
            icon: const Icon(Icons.verified_rounded),
            label: Text(context.t('Test connection')),
          ),
        ),
        const Divider(height: AppSpacing.xxl),
        if (kIsWeb)
          SettingsRow(
            title: context.t('Sora web proxy URL'),
            subtitle: context.t(
              'Optional CORS proxy for Sora manifest, script, source, and stream requests. Use {url} for the encoded target URL.',
            ),
            trailing: _TextSettingField(
              initialValue: settings.soraWebProxyUrl,
              hintText: 'https://proxy.example.com/?url={url}',
              onChanged: controller.setSoraWebProxyUrl,
            ),
          ),
        if (kIsWeb) const Divider(height: AppSpacing.xxl),
        SettingsRow(
          title: context.t('AniList mobile client ID'),
          subtitle:
              '${context.t('AniList mobile redirect')}: ${AppConstants.aniListMobileRedirectUri}',
          trailing: _TextSettingField(
            initialValue: settings.anilistMobileClientId,
            hintText: AppConstants.aniListMobileClientId,
            onChanged: controller.setAniListMobileClientId,
          ),
        ),
        SettingsRow(
          title: context.t('AniList desktop client ID'),
          subtitle:
              '${context.t('AniList desktop redirect')}: ${AppConstants.aniListDesktopRedirectUri}',
          trailing: _TextSettingField(
            initialValue: settings.anilistDesktopClientId,
            hintText: AppConstants.aniListDesktopClientId,
            onChanged: controller.setAniListDesktopClientId,
          ),
        ),
        SettingsRow(
          title: context.t('AniList desktop callback port'),
          subtitle: 'http://localhost:${settings.anilistDesktopPort}/',
          trailing: _TextSettingField(
            initialValue: settings.anilistDesktopPort.toString(),
            hintText: AppConstants.aniListDesktopCallbackPort.toString(),
            keyboardType: TextInputType.number,
            onChanged: (String value) {
              final int? port = int.tryParse(value);
              if (port != null && port > 0) {
                controller.setAniListDesktopPort(port);
              }
            },
          ),
        ),
      ],
    );
  }

  Future<void> _testTmdbConnection(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final List<dynamic> results = await TmdbMetadataProvider(
        readAccessToken: settings.tmdbReadAccessToken,
        language: settings.effectiveTmdbLanguage,
        region: settings.tmdbRegion,
      ).getTrending();
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('TMDB OK · ${results.length} trending items')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('TMDB connection failed: $error')),
      );
    }
  }
}

// ─── AniList settings section ─────────────────────────────────────────────────

// ignore: unused_element
class _AniListSettingsSection extends ConsumerWidget {
  const _AniListSettingsSection({
    required this.settings,
    required this.controller,
  });

  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerSettings playerSettings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    return SettingsSection(
      title: 'AniList',
      icon: Icons.list_alt_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('Auto track progress'),
          subtitle: context.t(
            'Update AniList when 85% of an episode is watched.',
          ),
          trailing: Switch(
            value: playerSettings.autoAnilistSync,
            onChanged: (bool value) => ref
                .read(playerSettingsProvider.notifier)
                .setAutoAnilistSync(value),
          ),
        ),
        SettingsRow(
          title: context.t('Title language'),
          subtitle: context.t('Language to display anime titles in.'),
          trailing: DropdownButton<String>(
            value: settings.anilistTitleLanguage,
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'ROMAJI',
                child: Text(context.t('Romaji')),
              ),
              DropdownMenuItem<String>(
                value: 'ENGLISH',
                child: Text(context.t('English')),
              ),
              DropdownMenuItem<String>(
                value: 'NATIVE',
                child: Text(context.t('Native')),
              ),
              DropdownMenuItem<String>(
                value: 'RUSSIAN',
                child: Text(context.t('Russian (Shikimori)')),
              ),
            ],
            onChanged: (String? value) {
              if (value != null) controller.setAniListTitleLanguage(value);
            },
          ),
        ),
        SettingsRow(
          title: context.t('Default Library page'),
          subtitle: context.t(
            'Opened first when that AniList folder has entries.',
          ),
          trailing: DropdownButton<AniListLibraryDefaultPage>(
            value: settings.anilistLibraryDefaultPage,
            items: AniListLibraryDefaultPage.values
                .map(
                  (AniListLibraryDefaultPage page) =>
                      DropdownMenuItem<AniListLibraryDefaultPage>(
                        value: page,
                        child: Text(context.t(page.labelKey)),
                      ),
                )
                .toList(growable: false),
            onChanged: (AniListLibraryDefaultPage? value) {
              if (value != null) {
                controller.setAniListLibraryDefaultPage(value);
              }
            },
          ),
        ),
        SettingsRow(
          title: context.t('Score format'),
          subtitle: context.t('How scores are displayed and entered.'),
          trailing: DropdownButton<String>(
            value: settings.anilistScoreFormat,
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'POINT_100',
                child: Text('100-point'),
              ),
              DropdownMenuItem<String>(
                value: 'POINT_10_DECIMAL',
                child: Text('10-point decimal'),
              ),
              DropdownMenuItem<String>(
                value: 'POINT_10',
                child: Text('10-point'),
              ),
              DropdownMenuItem<String>(value: 'POINT_5', child: Text('5-star')),
              DropdownMenuItem<String>(
                value: 'POINT_3',
                child: Text('3-point'),
              ),
              DropdownMenuItem<String>(value: 'SMILEY', child: Text('Smiley')),
            ],
            onChanged: (String? value) {
              if (value != null) controller.setAniListScoreFormat(value);
            },
          ),
        ),
        SettingsRow(
          title: context.t('Show adult content'),
          subtitle: context.t('Display +18 titles in AniList catalog.'),
          trailing: Switch(
            value: settings.anilistShowAdultContent,
            onChanged: controller.setAniListShowAdultContent,
          ),
        ),
      ],
    );
  }
}

class _TextSettingField extends StatelessWidget {
  const _TextSettingField({
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
    this.obscureText = false,
    this.keyboardType,
  });

  final String initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: TextFormField(
        key: ValueKey<String>('$hintText:$initialValue'),
        initialValue: initialValue,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hintText),
        onChanged: onChanged,
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection({this.placeholderOnly = false});

  final bool placeholderOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (placeholderOnly) {
      return SettingsSection(
        title: context.t('Accounts'),
        icon: Icons.manage_accounts_rounded,
        children: <Widget>[
          _AccountCard(
            name: 'AniList',
            avatarUrl: null,
            isActive: true,
            isConnected: false,
            onSignIn: () => loginAniList(context, ref),
          ),
        ],
      );
    }

    final SettingsState settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);

    final bool connected = settings.hasAniListSession;
    final String name = settings.anilistViewerName ?? 'AniList';
    final String? avatarUrl = settings.anilistAvatarUrl;
    final List<AniListSavedAccount> saved = settings.anilistSavedAccounts;

    return SettingsSection(
      title: context.t('Accounts'),
      icon: Icons.manage_accounts_rounded,
      children: <Widget>[
        // Active account
        _AccountCard(
          name: connected ? name : 'AniList',
          avatarUrl: avatarUrl,
          isActive: true,
          isConnected: connected,
          onSync: connected
              ? () {
                  invalidateAniListLibraryProviders(ref.invalidate);
                }
              : null,
          onSignIn: connected ? null : () => loginAniList(context, ref),
          onSignOut: connected
              ? () async {
                  await controller.disconnectAniList();
                  invalidateAniListLibraryProviders(ref.invalidate);
                }
              : null,
        ),
        // Saved accounts
        for (final AniListSavedAccount account in saved) ...<Widget>[
          const Divider(height: AppSpacing.xl),
          _AccountCard(
            name: account.viewerName,
            avatarUrl: account.avatarUrl,
            isActive: false,
            isConnected: account.isValid,
            onSwitch: () async {
              await controller.switchAniListAccount(account);
              invalidateAniListLibraryProviders(ref.invalidate);
            },
            onRemove: () => controller.removeAniListAccount(account.viewerId),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => loginAniList(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.t('Add account')),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.avatarUrl,
    required this.isActive,
    required this.isConnected,
    this.onSync,
    this.onSignIn,
    this.onSignOut,
    this.onSwitch,
    this.onRemove,
  });

  final String name;
  final String? avatarUrl;
  final bool isActive;
  final bool isConnected;
  final VoidCallback? onSync;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;
  final VoidCallback? onSwitch;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 22,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          backgroundImage: avatarUrl != null
              ? CachedNetworkImageProvider(avatarUrl!)
              : null,
          child: avatarUrl == null
              ? Icon(
                  Icons.person_rounded,
                  size: 22,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              Text(
                isConnected
                    ? context.t(isActive ? 'Connected' : 'Saved')
                    : context.t('Expired'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isConnected ? AppColors.success : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: <Widget>[
            if (onSignIn != null)
              FilledButton.icon(
                onPressed: onSignIn,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(context.t('Sign in')),
              ),
            if (onSync != null)
              IconButton(
                onPressed: onSync,
                icon: const Icon(Icons.sync_rounded),
                tooltip: 'Sync',
              ),
            if (onSwitch != null)
              OutlinedButton(
                onPressed: onSwitch,
                child: Text(context.t('Switch')),
              ),
            if (onSignOut != null)
              IconButton(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Sign out',
              ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remove',
              ),
          ],
        ),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings, required this.controller});

  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('Appearance'),
      icon: Icons.palette_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('Theme mode'),
          trailingFlex: 3,
          stackBreakpoint: 620,
          trailing: _ThemeModeSelector(
            value: settings.themeMode,
            onChanged: controller.setThemeMode,
          ),
        ),
        SettingsRow(
          title: context.t('Accent color'),
          trailing: Wrap(
            spacing: AppSpacing.sm,
            children: AppColors.accentOptions
                .map(
                  (Color color) => Tooltip(
                    message: context.t('Accent color'),
                    child: InkWell(
                      borderRadius: AppRadius.all(99),
                      onTap: () => controller.setAccentColor(color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: settings.accentColor == color
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        SettingsRow(
          title: context.t('Poster card style'),
          trailing: DropdownButton<String>(
            value: settings.posterCardStyle,
            items: const <String>['Cinematic', 'Compact', 'Editorial']
                .map(
                  (String style) => DropdownMenuItem<String>(
                    value: style,
                    child: Text(style),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              if (value != null) {
                controller.setPosterCardStyle(value);
              }
            },
          ),
        ),
        SettingsRow(
          title: context.t('Compact mode'),
          trailing: Switch(
            value: settings.compactMode,
            onChanged: controller.setCompactMode,
          ),
        ),
        SettingsRow(
          title: context.t('Reduce motion'),
          trailing: Switch(
            value: settings.reduceMotion,
            onChanged: controller.setReduceMotion,
          ),
        ),
        SettingsRow(
          title: context.t('Background blur intensity'),
          trailing: SizedBox(
            width: 240,
            child: Slider(
              value: settings.backgroundBlurIntensity,
              onChanged: controller.setBackgroundBlurIntensity,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: AppThemeMode.values
              .map(
                (AppThemeMode mode) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _ThemeModeOption(
                    mode: mode,
                    selected: value == mode,
                    accent: accent,
                    onTap: () => onChanged(mode),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.mode,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppThemeMode mode;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t(mode.labelKey),
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minWidth: 104),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.22)
                : Theme.of(context).cardColor.withValues(alpha: 0.12),
            borderRadius: AppRadius.all(AppRadius.md),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.72)
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                mode.icon,
                size: 18,
                color: selected
                    ? accent
                    : Theme.of(context).textTheme.labelMedium?.color,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                context.t(mode.labelKey),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? accent
                      : Theme.of(context).textTheme.labelLarge?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageSection extends StatelessWidget {
  const _LanguageSection({
    required this.settings,
    required this.controller,
    required this.showMetadataLanguage,
  });

  final SettingsState settings;
  final SettingsController controller;
  final bool showMetadataLanguage;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('Language'),
      icon: Icons.language_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('App language'),
          trailing: _LanguageDropdown(
            value: settings.appLocale,
            onChanged: controller.setAppLocale,
          ),
        ),
        if (showMetadataLanguage) ...<Widget>[
          SettingsRow(
            title: context.t('Metadata language'),
            subtitle: context.t('Controls titles and overviews from TMDB.'),
            trailing: _LanguageDropdown(
              value: settings.metadataLocale,
              onChanged: controller.setMetadataLocale,
            ),
          ),
        ],
        SettingsRow(
          title: context.t('Subtitle preferred language'),
          subtitle: context.t('No playback or subtitle logic is implemented.'),
        ),
        if (showMetadataLanguage)
          SettingsRow(
            title: context.t('Region / country preference'),
            subtitle: context.t(
              'Used by TMDB release calendars and localization.',
            ),
            trailing: _TextSettingField(
              initialValue: settings.tmdbRegion,
              hintText: 'US',
              onChanged: controller.setTmdbRegion,
            ),
          ),
      ],
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({required this.value, required this.onChanged});

  final Locale? value;
  final ValueChanged<Locale?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<Locale?>(
      value: value,
      hint: Text(context.t('System')),
      items: <DropdownMenuItem<Locale?>>[
        DropdownMenuItem<Locale?>(
          value: null,
          child: Text(context.t('System')),
        ),
        ...SupportedLanguages.all.map(
          (SupportedLanguage language) => DropdownMenuItem<Locale?>(
            value: language.locale,
            child: Text(
              '${context.t(language.labelKey)} · ${language.nativeName}',
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

String _formatCacheBytes(int bytes) {
  final double mb = bytes / (1024 * 1024);
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(1)} MB';
}

final _imageCacheSizeProvider = FutureProvider.autoDispose<String>((
  Ref ref,
) async {
  if (kIsWeb) return '—';
  try {
    final dynamic tmp = await getTemporaryDirectory();
    int bytes = 0;
    await for (final dynamic entity in tmp.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        bytes += await entity.length().catchError((_) => 0);
      }
    }
    return _formatCacheBytes(bytes);
  } catch (_) {
    return '—';
  }
});

final _metadataCacheSizeProvider = FutureProvider.autoDispose<String>((
  Ref ref,
) async {
  if (kIsWeb) return '0 MB';
  try {
    final dynamic base = await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}/metadata_cache');
    if (!await dir.exists()) return '0 MB';
    int bytes = 0;
    await for (final FileSystemEntity entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        bytes += await entity.length().catchError((_) => 0);
      }
    }
    return _formatCacheBytes(bytes);
  } catch (_) {
    return '—';
  }
});

class _CacheSection extends ConsumerWidget {
  const _CacheSection({required this.settings, required this.controller});

  final SettingsState settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String imageCacheLabel = ref
        .watch(_imageCacheSizeProvider)
        .when(data: (String s) => s, loading: () => '…', error: (_, _) => '—');
    final String metadataCacheLabel = ref
        .watch(_metadataCacheSizeProvider)
        .when(data: (String s) => s, loading: () => '…', error: (_, _) => '—');
    return SettingsSection(
      title: context.t('Cache'),
      icon: Icons.storage_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('Cache limit'),
          subtitle:
              '${context.t('Applies to the in-memory image cache.')} ${context.t('Current')}: $imageCacheLabel',
          trailing: DropdownButton<int>(
            value: settings.cacheLimitMb,
            items: const <int>[256, 512, 1024, 2048, 4096, 8192]
                .map(
                  (int value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text(
                      value >= 1024 ? '${value ~/ 1024} GB' : '$value MB',
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (int? value) {
              if (value != null) {
                controller.setCacheLimitMb(value);
              }
            },
          ),
        ),
        SettingsRow(
          title: context.t('Metadata cache'),
          subtitle:
              '${context.t('Use saved TMDB and AniList metadata when the catalog API is down.')} ${context.t('Current')}: $metadataCacheLabel',
          trailing: Switch(
            value: settings.metadataCacheEnabled,
            onChanged: (bool value) {
              controller.setMetadataCacheEnabled(value);
              _clearMetadataProviders(ref);
            },
          ),
        ),
        SettingsRow(
          title: context.t('Clear cache'),
          subtitle: context.t('Clears image and metadata cache from disk.'),
          trailing: FilledButton(
            onPressed: () => _clearAppCache(context, ref),
            child: Text(context.t('Clear cache')),
          ),
        ),
      ],
    );
  }
}

Future<void> _clearAppCache(BuildContext context, WidgetRef ref) async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  await DefaultCacheManager().emptyCache();
  try {
    final dynamic tmp = await getTemporaryDirectory();
    await for (final dynamic entity in tmp.list(recursive: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  } catch (_) {}
  await _clearMetadataStores(ref);
  _clearMetadataProviders(ref);
  ref.invalidate(_imageCacheSizeProvider);
  ref.invalidate(_metadataCacheSizeProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t('Cache cleared'))));
  }
}

void _clearMetadataProviders(WidgetRef ref) {
  ref.invalidate(activeCatalogRepositoryProvider);
  ref.invalidate(metadataRepositoryProvider);
  ref.invalidate(boardRailsProvider);
  ref.invalidate(discoveryMetadataProvider);
  ref.invalidate(mediaDetailsProvider);
  ref.invalidate(calendarItemsProvider);
  invalidateAniListLibraryProviders(ref.invalidate);
}

Future<void> _clearMetadataStores(WidgetRef ref) async {
  final MetadataCacheStore store = ref.read(metadataCacheStoreProvider);
  await store.removeByPrefix('tmdb');
  await store.removeByPrefix('anilist');
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('About'),
      icon: Icons.info_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('App version'),
          subtitle: AppConstants.appVersion,
        ),
        SettingsRow(
          title: context.t('Credits'),
          subtitle: context.t('Built as a polished Flutter foundation.'),
        ),
        SettingsRow(
          title: context.t('Legal notices'),
          // subtitle: context.t(AppConstants.tmdbAttribution),
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassCard(
          borderColor: AppColors.accentAqua.withValues(alpha: 0.28),
          child: Text(
            context.t(AppConstants.tmdbAttribution),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
