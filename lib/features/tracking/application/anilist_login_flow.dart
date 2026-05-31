import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/models/anilist_models.dart';
import '../../settings/presentation/settings_state.dart';
import '../application/anilist_library_provider.dart';
import '../data/anilist_api_client.dart';
import '../data/anilist_oauth_service.dart';
import '../presentation/anilist_login_page.dart';

/// Launches the platform-appropriate AniList OAuth flow and, on success,
/// stores the token and refreshes the library providers.
Future<void> loginAniList(BuildContext context, WidgetRef ref) async {
  final SettingsController controller = ref.read(settingsProvider.notifier);
  final SettingsState current = ref.read(settingsProvider);
  final bool isMobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final String clientId = isMobile
      ? current.anilistMobileClientId
      : current.anilistDesktopClientId;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  if (clientId.trim().isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.t('Configure an AniList client ID first.')),
      ),
    );
    return;
  }

  try {
    final AniListOAuthService oauthService = const AniListOAuthService();
    AniListOAuthResult? oauth;
    if (kIsWeb) {
      oauth = await _loginOnWeb(context, oauthService, clientId);
    } else if (isMobile) {
      oauth = await Navigator.of(context).push<AniListOAuthResult>(
        MaterialPageRoute<AniListOAuthResult>(
          builder: (BuildContext ctx) => AniListLoginPage(
            authUrl: oauthService
                .buildImplicitAuthUri(clientId: clientId)
                .toString(),
          ),
        ),
      );
    } else {
      oauth = await oauthService.loginWithDesktopBrowser(
        clientId: clientId,
        port: current.anilistDesktopPort,
      );
    }

    if (oauth == null) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.t('AniList login canceled or failed.'))),
      );
      return;
    }

    final AniListViewer viewer = await AniListApiClient(
      accessToken: oauth.accessToken,
    ).fetchViewer();
    await controller.connectAniList(oauth: oauth, viewer: viewer);
    invalidateAniListLibraryProviders(ref.invalidate);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tf('AniList connected · {name}', <String, Object?>{
            'name': viewer.name,
          }),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tf('AniList login failed: {error}', <String, Object?>{
            'error': error,
          }),
        ),
      ),
    );
  }
}

Future<AniListOAuthResult?> _loginOnWeb(
  BuildContext context,
  AniListOAuthService oauthService,
  String clientId,
) async {
  final Uri authUri = oauthService.buildImplicitAuthUri(clientId: clientId);
  String rawInput = '';
  String? errorText;
  return showDialog<AniListOAuthResult>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) {
          return AlertDialog(
            title: Text(ctx.t('Login with AniList')),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ctx.t(
                        'Web cannot listen on localhost. Open AniList, approve access, then paste the redirected URL or access_token here.',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (String value) => rawInput = value,
                      decoration: InputDecoration(
                        labelText: ctx.t('AniList access token'),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(ctx.t('Cancel')),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(authUri, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(ctx.t('Open AniList')),
              ),
              FilledButton.icon(
                onPressed: () {
                  final AniListOAuthResult? result = _parseToken(rawInput);
                  if (result == null) {
                    setState(() {
                      errorText = ctx.t('Paste a valid AniList access token.');
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(result);
                },
                icon: const Icon(Icons.check_rounded),
                label: Text(ctx.t('Connect account')),
              ),
            ],
          );
        },
      );
    },
  );
}

AniListOAuthResult? _parseToken(String rawInput) {
  final String raw = rawInput.trim();
  if (raw.isEmpty) return null;
  String token = raw;
  String? expiresIn;
  final int fragmentIndex = raw.indexOf('#');
  final int queryIndex = raw.indexOf('?');
  final String rawParams = fragmentIndex >= 0
      ? raw.substring(fragmentIndex + 1)
      : queryIndex >= 0
      ? raw.substring(queryIndex + 1)
      : raw;
  if (rawParams.contains('access_token=')) {
    try {
      final Map<String, String> params = Uri.splitQueryString(rawParams);
      token = params['access_token'] ?? '';
      expiresIn = params['expires_in'];
    } catch (_) {
      return null;
    }
  }
  if (token.trim().isEmpty || token.contains(' ')) return null;
  final int validSeconds = int.tryParse(expiresIn ?? '') ?? 31536000;
  return AniListOAuthResult(
    accessToken: token.trim(),
    expiresAt: DateTime.now().add(Duration(seconds: validSeconds)),
  );
}
