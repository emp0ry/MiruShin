import 'dart:math' as math;

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
import '../../../core/platform/tv_platform.dart';
import '../../../core/platform/url_opener.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/tv_directional_focus.dart';
import '../../../core/widgets/tv_text_field_focus.dart';
import '../../calendar/application/calendar_items_provider.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../downloads/application/downloads_provider.dart';
import '../../metadata/data/tmdb_metadata_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../player/application/player_settings.dart';
import '../../player/data/discord_rpc_service.dart';
import '../../player/domain/player_models.dart';
import '../../../shared/models/anilist_models.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/application/anilist_login_flow.dart';
import '../../tracking/application/tracker_library_provider.dart';
import '../../tracking/application/tracker_login_flow.dart';
import '../../tracking/domain/tracker_models.dart';
import '../application/update_checker_provider.dart';
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
    final Widget content = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: context.t('Settings')),
          const SizedBox(height: AppSpacing.lg),
          const _UpdateSection(),
          if (showAniListProfileUi) ...<Widget>[
            const _AccountSection(),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (showAniListProfileUi && settings.hasAniListSession) ...<Widget>[
            const _AniListSettingsShortcutSection(),
            const SizedBox(height: AppSpacing.lg),
          ],
          const _TrackerConnectionsSection(),
          const SizedBox(height: AppSpacing.lg),
          _AppearanceSection(settings: settings, controller: controller),
          const SizedBox(height: AppSpacing.lg),
          const _PlayerEngineSection(),
          const SizedBox(height: AppSpacing.lg),
          _LanguageSection(
            settings: settings,
            controller: controller,
            showMetadataLanguage: catalogMode == CatalogMode.tmdb,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (DiscordRpcService.isSupported) ...<Widget>[
            _DiscordRpcSection(settings: settings, controller: controller),
            const SizedBox(height: AppSpacing.lg),
          ],
          _ApiConnectionsSection(settings: settings, controller: controller),
          const SizedBox(height: AppSpacing.lg),
          const _DownloadsSection(),
          const SizedBox(height: AppSpacing.lg),
          _CacheSection(settings: settings, controller: controller),
          const SizedBox(height: AppSpacing.lg),
          const _AboutSection(),
        ],
      ),
    );
    return AdaptivePage(
      child: TvPlatform.isAndroidTv
          ? TvDirectionalFocus(child: content)
          : content,
    );
  }
}

class _UpdateSection extends ConsumerWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<UpdateInfo?> update = ref.watch(updateCheckerProvider);
    return update.when(
      data: (UpdateInfo? info) {
        if (info == null || !info.hasUpdate) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SettingsSection(
              title: context.t('Update available'),
              icon: Icons.system_update_alt_rounded,
              children: <Widget>[
                SettingsRow(
                  title: context.t('New version available'),
                  subtitle: info.tagName,
                  trailing: FilledButton.icon(
                    onPressed: () => openExternalUrl(info.releaseUrl),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(context.t('Download')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
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
    final CatalogMode catalogMode = ref.watch(catalogModeProvider);
    final bool showTmdb = catalogMode == CatalogMode.tmdb;
    final bool showAniList = catalogMode == CatalogMode.anilist;
    return SettingsSection(
      title: context.t('API Connections'),
      icon: Icons.cloud_sync_rounded,
      children: <Widget>[
        if (showTmdb) ...<Widget>[
          SettingsRow(
            title: context.t('Use custom API key'),
            subtitle: context.t(
              'Off: use the built-in TMDB key. On: enter your own TMDB Read Access Token.',
            ),
            trailing: Switch(
              value: settings.tmdbUseCustomKey,
              onChanged: controller.setTmdbUseCustomKey,
            ),
          ),
          if (settings.tmdbUseCustomKey)
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
          // Temporarily hidden: TMDB only flags movies as adult, so this toggle
          // can't filter mature anime/series. The filter logic + setting remain
          // (default off) so re-enabling is just restoring this row.
          // SettingsRow(
          //   title: context.t('Show adult content'),
          //   subtitle: context.t(
          //     'Include +18 titles in TMDB search and discovery.',
          //   ),
          //   trailing: Switch(
          //     value: settings.tmdbShowAdultContent,
          //     onChanged: settings.tmdbEnabled
          //         ? controller.setTmdbShowAdultContent
          //         : null,
          //   ),
          // ),
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
        ],
        if (kIsWeb) ...<Widget>[
          if (showTmdb) const Divider(height: AppSpacing.xxl),
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
        ],
        if (showAniList) ...<Widget>[
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
      ],
    );
  }

  Future<void> _testTmdbConnection(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final List<dynamic> results = await TmdbMetadataProvider(
        readAccessToken: settings.effectiveTmdbReadAccessToken,
        language: settings.effectiveTmdbLanguage,
        region: settings.tmdbRegion,
      ).getTrending();
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tf('TMDB OK · {count} trending items', <String, Object?>{
              'count': results.length,
            }),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tf('TMDB connection failed: {error}', <String, Object?>{
              'error': error,
            }),
          ),
        ),
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
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'POINT_100',
                child: Text(context.t('100-point')),
              ),
              DropdownMenuItem<String>(
                value: 'POINT_10_DECIMAL',
                child: Text(context.t('10-point decimal')),
              ),
              DropdownMenuItem<String>(
                value: 'POINT_10',
                child: Text(context.t('10-point')),
              ),
              DropdownMenuItem<String>(
                value: 'POINT_5',
                child: Text(context.t('5-star')),
              ),
              DropdownMenuItem<String>(
                value: 'POINT_3',
                child: Text(context.t('3-point')),
              ),
              DropdownMenuItem<String>(
                value: 'SMILEY',
                child: Text(context.t('Smiley')),
              ),
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
      child: TvTextFieldFocus(
        child: TextFormField(
          key: ValueKey<String>('$hintText:$initialValue'),
          initialValue: initialValue,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hintText),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TrackerConnectionsSection extends ConsumerWidget {
  const _TrackerConnectionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsState settings = ref.watch(settingsProvider);
    final SettingsController controller = ref.read(settingsProvider.notifier);

    return SettingsSection(
      title: context.t('Connections'),
      icon: Icons.link_rounded,
      children: <Widget>[
        // MyAnimeList
        SettingsRow(
          title: 'MyAnimeList',
          subtitle: settings.hasMalSession
              ? (settings.malViewerName ?? context.t('Connected'))
              : context.t('Not connected'),
          trailing: _TrackerConnectButton(
            connected: settings.hasMalSession,
            onConnect: () => loginMal(context, ref),
            onDisconnect: () async {
              await controller.disconnectMal();
              ref.invalidate(trackerAnimeListProvider);
            },
          ),
        ),
        SettingsRow(
          title: context.t('Use custom MyAnimeList credentials'),
          trailing: Switch(
            value: settings.malUseCustomCredentials,
            onChanged: controller.setMalUseCustomCredentials,
          ),
        ),
        if (settings.malUseCustomCredentials) ...<Widget>[
          SettingsRow(
            title: context.t('MyAnimeList Client ID (Desktop)'),
            subtitle: context.t(
              'From the MAL app whose redirect is the localhost callback.',
            ),
            trailing: _TextSettingField(
              initialValue: settings.malCustomClientIdDesktop,
              hintText: '0a1b2c3d...',
              onChanged: controller.setMalCustomClientIdDesktop,
            ),
          ),
          SettingsRow(
            title: context.t('MyAnimeList Client ID (Mobile)'),
            subtitle: context.t(
              'From the MAL app whose redirect is app://mirushin/auth.',
            ),
            trailing: _TextSettingField(
              initialValue: settings.malCustomClientIdMobile,
              hintText: '0a1b2c3d...',
              onChanged: controller.setMalCustomClientIdMobile,
            ),
          ),
        ],
        const Divider(height: AppSpacing.xl),
        // Shikimori
        SettingsRow(
          title: 'Shikimori',
          subtitle: settings.hasShikimoriSession
              ? (settings.shikimoriViewerName ?? context.t('Connected'))
              : context.t('Not connected'),
          trailing: _TrackerConnectButton(
            connected: settings.hasShikimoriSession,
            onConnect: () => loginShikimori(context, ref),
            onDisconnect: () async {
              await controller.disconnectShikimori();
              ref.invalidate(trackerAnimeListProvider);
            },
          ),
        ),
        SettingsRow(
          title: context.t('Use custom Shikimori credentials'),
          trailing: Switch(
            value: settings.shikimoriUseCustomCredentials,
            onChanged: controller.setShikimoriUseCustomCredentials,
          ),
        ),
        if (settings.shikimoriUseCustomCredentials) ...<Widget>[
          SettingsRow(
            title: context.t('Shikimori Client ID'),
            trailing: _TextSettingField(
              initialValue: settings.shikimoriCustomClientId,
              hintText: '0a1b2c3d...',
              onChanged: controller.setShikimoriCustomClientId,
            ),
          ),
          SettingsRow(
            title: context.t('Shikimori Client Secret'),
            subtitle: context.t(
              'Stored in secure platform storage. Do not commit secrets.',
            ),
            trailing: _TextSettingField(
              initialValue: settings.shikimoriCustomClientSecret,
              hintText: '••••••••',
              obscureText: true,
              onChanged: controller.setShikimoriCustomClientSecret,
            ),
          ),
        ],
        const Divider(height: AppSpacing.xl),
        SettingsRow(
          title: context.t('Primary library source'),
          subtitle: context.t('Which tracker fills the Library tab'),
          trailing: DropdownButton<TrackerSource>(
            value: settings.primaryTrackerSource,
            onChanged: (TrackerSource? value) {
              if (value != null) controller.setPrimaryTrackerSource(value);
            },
            items: <DropdownMenuItem<TrackerSource>>[
              for (final TrackerSource source in TrackerSource.values)
                DropdownMenuItem<TrackerSource>(
                  value: source,
                  child: Text(source.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrackerConnectButton extends StatelessWidget {
  const _TrackerConnectButton({
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (connected) {
      return OutlinedButton.icon(
        onPressed: onDisconnect,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(context.t('Disconnect')),
      );
    }
    return FilledButton.icon(
      onPressed: onConnect,
      icon: const Icon(Icons.login_rounded, size: 18),
      label: Text(context.t('Connect')),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final Color color in AppColors.accentOptions)
                _AccentColorSwatch(
                  color: color,
                  selected: settings.accentColor.toARGB32() == color.toARGB32(),
                  onPressed: () => controller.setAccentColor(color),
                ),
              _CustomAccentColorSwatch(
                selected: !AppColors.accentOptions.any(
                  (Color color) =>
                      settings.accentColor.toARGB32() == color.toARGB32(),
                ),
                onPressed: () => _showAccentColorPicker(
                  context,
                  initialColor: settings.accentColor,
                  onChanged: controller.setAccentColor,
                ),
              ),
            ],
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
          title: context.t('Compact cards'),
          trailing: Switch(
            value: settings.compactCards,
            onChanged: controller.setCompactCards,
          ),
        ),
        SettingsRow(
          title: context.t('Startup page'),
          trailing: DropdownButton<AppStartupPage>(
            value: settings.startupPage,
            items: AppStartupPage.values
                .map(
                  (AppStartupPage page) => DropdownMenuItem<AppStartupPage>(
                    value: page,
                    child: Text(page.label),
                  ),
                )
                .toList(),
            onChanged: (AppStartupPage? value) {
              if (value != null) controller.setStartupPage(value);
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _showAccentColorPicker(
  BuildContext context, {
  required Color initialColor,
  required ValueChanged<Color> onChanged,
}) async {
  final Color? color = await showDialog<Color>(
    context: context,
    builder: (BuildContext context) {
      return _AccentColorPickerDialog(initialColor: initialColor);
    },
  );
  if (color != null) {
    onChanged(color);
  }
}

class _AccentColorSwatch extends StatelessWidget {
  const _AccentColorSwatch({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('Accent color'),
      child: Semantics(
        button: true,
        selected: selected,
        label: context.t('Accent color'),
        child: InkWell(
          borderRadius: AppRadius.all(99),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: selected ? 2 : 1,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomAccentColorSwatch extends StatelessWidget {
  const _CustomAccentColorSwatch({
    required this.selected,
    required this.onPressed,
  });

  final bool selected;
  final VoidCallback onPressed;

  static const List<Color> _colors = <Color>[
    AppColors.accentPurple,
    AppColors.accentAqua,
    AppColors.accentMint,
    AppColors.accentRose,
  ];

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('Custom color'),
      child: Semantics(
        button: true,
        selected: selected,
        label: context.t('Custom color'),
        child: InkWell(
          borderRadius: AppRadius.all(99),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipOval(
              child: CustomPaint(
                painter: _SegmentedColorCirclePainter(_colors),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentedColorCirclePainter extends CustomPainter {
  const _SegmentedColorCirclePainter(this.colors);

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Offset center = rect.center;
    final double radius = math.min(size.width, size.height) / 2;
    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Rect circle = Rect.fromCircle(center: center, radius: radius);
    final double sweep = math.pi * 2 / colors.length;
    for (int i = 0; i < colors.length; i++) {
      paint.color = colors[i];
      canvas.drawArc(
        circle,
        -math.pi / 2 + sweep * i,
        sweep + 0.01,
        true,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentedColorCirclePainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}

class _AccentColorPickerDialog extends StatefulWidget {
  const _AccentColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_AccentColorPickerDialog> createState() =>
      _AccentColorPickerDialogState();
}

class _AccentColorPickerDialogState extends State<_AccentColorPickerDialog> {
  late HSVColor _color = HSVColor.fromColor(widget.initialColor);

  Color get _selectedColor => _color.toColor().withValues(alpha: 1);

  @override
  Widget build(BuildContext context) {
    final Color selected = _selectedColor;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.all(AppRadius.xl)),
      title: Text(context.t('Custom color')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ColorPickerArea(
                hue: _color.hue,
                saturation: _color.saturation,
                value: _color.value,
                onChanged: (double saturation, double value) {
                  setState(() {
                    _color = _color.withSaturation(saturation).withValue(value);
                  });
                },
              ),

              const SizedBox(height: AppSpacing.xl),

              Row(
                children: <Widget>[
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: selected,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: selected.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: AppSpacing.lg),

                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _HueSlider(
                          value: _color.hue,
                          onChanged: (double value) {
                            setState(() {
                              _color = _color.withHue(value);
                            });
                          },
                        ),

                        const SizedBox(height: AppSpacing.md),

                        _BrightnessSlider(
                          value: _color.value,
                          color: HSVColor.fromAHSV(
                            1,
                            _color.hue,
                            _color.saturation,
                            1,
                          ).toColor(),
                          onChanged: (double value) {
                            setState(() {
                              _color = _color.withValue(value);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),

              _ColorValueFields(color: selected),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(selected),
          child: Text(context.t('Apply')),
        ),
      ],
    );
  }
}

class _ColorPickerArea extends StatelessWidget {
  const _ColorPickerArea({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;

  void _handlePosition(Offset localPosition, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double nextSaturation = (localPosition.dx / size.width).clamp(
      0.0,
      1.0,
    );
    final double nextValue = (1.0 - localPosition.dy / size.height).clamp(
      0.0,
      1.0,
    );

    onChanged(nextSaturation, nextValue);
  }

  @override
  Widget build(BuildContext context) {
    final Color hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 460;
        const double height = 230;
        final Size areaSize = Size(width, height);

        return GestureDetector(
          onPanDown: (DragDownDetails details) {
            _handlePosition(details.localPosition, areaSize);
          },
          onPanUpdate: (DragUpdateDetails details) {
            _handlePosition(details.localPosition, areaSize);
          },
          onTapDown: (TapDownDetails details) {
            _handlePosition(details.localPosition, areaSize);
          },
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                ClipRRect(
                  borderRadius: AppRadius.all(AppRadius.lg),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: hueColor,
                      borderRadius: AppRadius.all(AppRadius.lg),
                    ),
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.all(AppRadius.lg),
                              gradient: const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: <Color>[
                                  Colors.white,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.all(AppRadius.lg),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Colors.transparent,
                                  Colors.black,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.all(AppRadius.lg),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  left: (saturation * width - 10).clamp(0.0, width - 20),
                  top: ((1.0 - value) * height - 10).clamp(0.0, height - 20),
                  child: IgnorePointer(
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GradientSlider(
      value: value,
      max: 360,
      gradient: const LinearGradient(
        colors: <Color>[
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ),
      onChanged: onChanged,
    );
  }
}

class _BrightnessSlider extends StatelessWidget {
  const _BrightnessSlider({
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GradientSlider(
      value: value,
      max: 1,
      gradient: LinearGradient(colors: <Color>[Colors.black, color]),
      onChanged: onChanged,
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  final double value;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  void _handlePosition(Offset localPosition, double width) {
    if (width <= 0) return;
    final double next = (localPosition.dx / width * max).clamp(0.0, max);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 260;
        final double normalized = max == 0 ? 0 : (value / max).clamp(0.0, 1.0);

        return GestureDetector(
          onPanDown: (DragDownDetails details) {
            _handlePosition(details.localPosition, width);
          },
          onPanUpdate: (DragUpdateDetails details) {
            _handlePosition(details.localPosition, width);
          },
          onTapDown: (TapDownDetails details) {
            _handlePosition(details.localPosition, width);
          },
          child: SizedBox(
            height: 28,
            width: width,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: AppRadius.all(99),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Positioned(
                  left: (normalized * width - 11).clamp(0.0, width - 22),
                  child: IgnorePointer(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColorValueFields extends StatelessWidget {
  const _ColorValueFields({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final int r = (color.r * 255).round();
    final int g = (color.g * 255).round();
    final int b = (color.b * 255).round();

    return Row(
      children: <Widget>[
        Expanded(
          flex: 2,
          child: _ColorValueBox(label: 'HEX', value: _hexColor(color)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ColorValueBox(label: 'R', value: r.toString()),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ColorValueBox(label: 'G', value: g.toString()),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ColorValueBox(label: 'B', value: b.toString()),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: _ColorValueBox(label: 'A', value: '100%'),
        ),
      ],
    );
  }
}

class _ColorValueBox extends StatelessWidget {
  const _ColorValueBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: AppRadius.all(AppRadius.sm),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

String _hexColor(Color color) {
  final int rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
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

class _PlayerEngineSection extends ConsumerWidget {
  const _PlayerEngineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerSettings settings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
    final PlayerSettingsController controller = ref.read(
      playerSettingsProvider.notifier,
    );
    final List<PlayerBackend> backends = availablePlayerBackends();
    final PlayerBackend selectedBackend = visiblePlayerBackend(
      settings.playerBackend,
    );
    return SettingsSection(
      title: context.t('Player'),
      icon: Icons.smart_display_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('Playback engine'),
          subtitle:
              '${context.t(selectedBackend.description)} ${context.t('Applies on the next stream open.')}',
          trailing: DropdownButton<PlayerBackend>(
            value: selectedBackend,
            items: backends
                .map(
                  (PlayerBackend backend) => DropdownMenuItem<PlayerBackend>(
                    value: backend,
                    child: Text(context.t(backend.title)),
                  ),
                )
                .toList(growable: false),
            onChanged: (PlayerBackend? value) {
              if (value != null) {
                controller.setPlayerBackend(value);
              }
            },
          ),
        ),
      ],
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

final _downloadsSizeProvider = FutureProvider.autoDispose<String>((ref) async {
  ref.watch(downloadsProvider);
  final int bytes = await ref.read(downloadStoreProvider).totalSizeBytes();
  return _formatDownloadSize(bytes);
});

String _formatDownloadSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  final int decimals = (size >= 100 || unit == 0) ? 0 : 1;
  return '${size.toStringAsFixed(decimals)} ${units[unit]}';
}

class _DownloadsSection extends ConsumerWidget {
  const _DownloadsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int episodeCount = ref.watch(downloadsProvider).length;
    final String sizeLabel = ref
        .watch(_downloadsSizeProvider)
        .when(data: (String s) => s, loading: () => '…', error: (_, _) => '—');
    return SettingsSection(
      title: context.t('Downloads'),
      icon: Icons.download_rounded,
      children: <Widget>[
        SettingsRow(
          title: context.t('Downloaded episodes'),
          subtitle: '$episodeCount · $sizeLabel',
          trailing: FilledButton(
            onPressed: episodeCount == 0
                ? null
                : () => _confirmDeleteAllDownloads(context, ref),
            child: Text(context.t('Delete all')),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmDeleteAllDownloads(
  BuildContext context,
  WidgetRef ref,
) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(context.t('Delete all')),
      content: Text(
        context.t('Remove every downloaded video from this device?'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.t('Delete')),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(downloadsProvider.notifier).deleteAll();
  ref.invalidate(_downloadsSizeProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t('Downloads deleted'))));
  }
}

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
          subtitle: AppConstants.appVersion.split('+').first,
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
