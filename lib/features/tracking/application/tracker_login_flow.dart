import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../settings/presentation/settings_state.dart';
import '../data/mal_api_client.dart';
import '../data/mal_oauth_service.dart';
import '../data/oauth_code_listener.dart';
import '../data/oauth_token_bundle.dart';
import '../data/shikimori_api_client.dart';
import '../data/shikimori_oauth_service.dart';
import '../domain/tracker_models.dart';
import '../presentation/oauth_code_webview_page.dart';
import 'tracker_library_provider.dart';

bool get _isMobile =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Launches the MyAnimeList OAuth2 (authorization code + PKCE) flow and, on
/// success, stores the tokens and refreshes the tracker library.
Future<void> loginMal(BuildContext context, WidgetRef ref) async {
  final SettingsController controller = ref.read(settingsProvider.notifier);
  final SettingsState settings = ref.read(settingsProvider);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String clientId = settings.effectiveMalClientId(isMobile: _isMobile);
  final String canceledMessage = context.t('Login canceled or failed.');

  if (settings.malUseCustomCredentials && clientId.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.t('Configure a MyAnimeList client ID first.')),
      ),
    );
    return;
  }

  final String verifier = MalOAuthService.generateCodeVerifier();
  final String redirectUri = _isMobile
      ? AppConstants.trackerMobileRedirectUri
      : AppConstants.malDesktopRedirectUri;
  final MalOAuthService service = MalOAuthService();
  final Uri authUri = service.buildAuthorizeUri(
    clientId: clientId,
    codeChallenge: verifier,
    redirectUri: redirectUri,
    state: 'mal',
  );

  try {
    final String? code = await _obtainAuthCode(
      context: context,
      authUri: authUri,
      redirectUri: redirectUri,
      desktopPort: AppConstants.malDesktopCallbackPort,
      title: context.t('MyAnimeList Login'),
    );
    if (code == null) {
      messenger.showSnackBar(SnackBar(content: Text(canceledMessage)));
      return;
    }
    final OAuthTokenBundle tokens = await service.exchangeCode(
      clientId: clientId,
      code: code,
      codeVerifier: verifier,
      redirectUri: redirectUri,
    );
    final TrackerViewer viewer = await MalApiClient(
      accessToken: tokens.accessToken,
    ).fetchViewer();
    await controller.connectMal(tokens: tokens, viewer: viewer);
    ref.invalidate(trackerAnimeListProvider);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tf('MyAnimeList connected · {name}', <String, Object?>{
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
          context.tf('MyAnimeList login failed: {error}', <String, Object?>{
            'error': error,
          }),
        ),
      ),
    );
  }
}

/// Launches the Shikimori OAuth2 authorization code flow.
Future<void> loginShikimori(BuildContext context, WidgetRef ref) async {
  final SettingsController controller = ref.read(settingsProvider.notifier);
  final SettingsState settings = ref.read(settingsProvider);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String clientId = settings.effectiveShikimoriClientId;
  final String clientSecret = settings.effectiveShikimoriClientSecret;
  final String canceledMessage = context.t('Login canceled or failed.');

  if (!settings.shikimoriConfigured) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.t('Configure Shikimori credentials first.')),
      ),
    );
    return;
  }

  const String redirectUri = AppConstants.shikimoriCallbackUrl;
  final ShikimoriOAuthService service = ShikimoriOAuthService();
  final Uri authUri = service.buildAuthorizeUri(
    clientId: clientId,
    redirectUri: redirectUri,
    state: 'shikimori',
  );

  try {
    final String? code = await _obtainAuthCode(
      context: context,
      authUri: authUri,
      redirectUri: redirectUri,
      desktopPort: AppConstants.shikimoriDesktopCallbackPort,
      title: context.t('Shikimori Login'),
    );
    if (code == null) {
      messenger.showSnackBar(SnackBar(content: Text(canceledMessage)));
      return;
    }
    final OAuthTokenBundle tokens = await service.exchangeCode(
      clientId: clientId,
      clientSecret: clientSecret,
      code: code,
      redirectUri: redirectUri,
    );
    final TrackerViewer viewer = await ShikimoriApiClient(
      accessToken: tokens.accessToken,
      userId: 0,
    ).fetchViewer();
    await controller.connectShikimori(tokens: tokens, viewer: viewer);
    ref.invalidate(trackerAnimeListProvider);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          context.tf('Shikimori connected · {name}', <String, Object?>{
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
          context.tf('Shikimori login failed: {error}', <String, Object?>{
            'error': error,
          }),
        ),
      ),
    );
  }
}

/// Obtains an authorization `code` using the platform-appropriate flow.
///
/// - Mobile: in-app WebView (intercepts the redirect, or the OOB code page when
///   [oobCodePathPrefix] is set).
/// - Desktop (MAL, Shikimori): localhost callback server on [desktopPort]. For
///   Shikimori the Worker callback page forwards the code to that listener.
/// - Web: manual URL/code paste.
Future<String?> _obtainAuthCode({
  required BuildContext context,
  required Uri authUri,
  required String redirectUri,
  required String title,
  int? desktopPort,
  bool manualCodeEntry = false,
  String? oobCodePathPrefix,
}) async {
  final bool oob = oobCodePathPrefix != null;
  if (kIsWeb || manualCodeEntry || (oob && !_isMobile)) {
    return _pasteCodeOnWeb(context, authUri, title);
  }
  if (_isMobile) {
    final OAuthCodeResult? result = await Navigator.of(context)
        .push<OAuthCodeResult>(
          MaterialPageRoute<OAuthCodeResult>(
            builder: (BuildContext ctx) => OAuthCodeWebViewPage(
              authUrl: authUri.toString(),
              redirectUri: redirectUri,
              title: title,
              oobCodePathPrefix: oobCodePathPrefix,
            ),
          ),
        );
    return result?.code;
  }
  // Desktop with a real redirect: start the localhost listener, then open the
  // system browser.
  final OAuthCodeListener listener = await startOAuthCodeListener(
    port: desktopPort!,
  );
  try {
    final bool launched = await launchUrl(
      authUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      await listener.cancel();
      return null;
    }
    final OAuthCodeResult? result = await listener.wait();
    return result?.code;
  } catch (_) {
    await listener.cancel();
    rethrow;
  }
}

Future<String?> _pasteCodeOnWeb(
  BuildContext context,
  Uri authUri,
  String title,
) async {
  String rawInput = '';
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                dialogContext.t(
                  'Open the login page, approve access, then paste the redirected URL (or the code) here.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                minLines: 1,
                maxLines: 3,
                onChanged: (String value) => rawInput = value,
                decoration: InputDecoration(
                  labelText: dialogContext.t('Authorization code'),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.t('Cancel')),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                launchUrl(authUri, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(dialogContext.t('Open login page')),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_parseCode(rawInput)),
            icon: const Icon(Icons.check_rounded),
            label: Text(dialogContext.t('Connect account')),
          ),
        ],
      );
    },
  );
}

String? _parseCode(String rawInput) {
  final String raw = rawInput.trim();
  if (raw.isEmpty) return null;
  final Uri? uri = Uri.tryParse(raw);
  if (uri != null) {
    final String? queryCode = uri.queryParameters['code'];
    if (queryCode != null && queryCode.isNotEmpty) return queryCode;
    // Shikimori OOB shows the code at .../oauth/authorize/<code>.
    final int idx = uri.path.indexOf(AppConstants.shikimoriOobCodePathPrefix);
    if (idx >= 0) {
      final String tail = uri.path.substring(
        idx + AppConstants.shikimoriOobCodePathPrefix.length,
      );
      if (tail.isNotEmpty && !tail.contains('/')) return tail;
    }
  }
  return raw;
}
