import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/platform/tv_platform.dart';
import '../../tracking/data/oauth_code_listener.dart';
import '../../tracking/data/oauth_token_bundle.dart';
import '../application/google_drive_sync_controller.dart';
import '../data/google_drive_native_auth.dart';
import '../data/google_drive_oauth_service.dart';

Future<void> loginGoogleDrive(BuildContext context, WidgetRef ref) async {
  if (TvPlatform.isAndroidTv) {
    await _loginGoogleDriveTv(context, ref);
    return;
  }
  if (!AppConstants.googleOAuthConfigured) {
    throw StateError('Google OAuth is not configured for this platform.');
  }
  if (GoogleDriveNativeAuthService.isSupported) {
    final String accessToken = await const GoogleDriveNativeAuthService()
        .signIn();
    final GoogleDriveTokenBundle tokens = GoogleDriveTokenBundle(
      accessToken: accessToken,
      refreshToken: '',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 50)),
    );
    await ref.read(googleDriveSyncControllerProvider.notifier).connect(tokens);
    await ref.read(googleDriveSyncControllerProvider.notifier).syncNow();
    return;
  }
  final String clientId = AppConstants.googleOAuthClientId.trim();
  if (clientId.isEmpty) {
    throw StateError(
      'Google OAuth is not configured for this build. Set GOOGLE_OAUTH_CLIENT_ID.',
    );
  }
  const String redirectUri = AppConstants.googleOAuthDesktopRedirectUri;
  final GoogleDriveOAuthService service = GoogleDriveOAuthService();
  final String verifier = GoogleDriveOAuthService.generateCodeVerifier();
  final String state = List<int>.generate(
    24,
    (_) => Random.secure().nextInt(36),
  ).map((int value) => value.toRadixString(36)).join();
  final Uri uri = service.buildAuthorizeUri(
    clientId: clientId,
    redirectUri: redirectUri,
    codeVerifier: verifier,
    state: state,
  );
  final OAuthCodeResult? result = await _obtainCode(
    context,
    uri: uri,
    redirectUri: redirectUri,
  );
  if (result == null) return;
  if (result.state != state) {
    throw StateError('Google OAuth state verification failed.');
  }
  final GoogleDriveTokenBundle tokens = await service.exchangeCode(
    redirectUri: redirectUri,
    code: result.code,
    codeVerifier: verifier,
  );
  await ref.read(googleDriveSyncControllerProvider.notifier).connect(tokens);
  await ref.read(googleDriveSyncControllerProvider.notifier).syncNow();
}

Future<void> _loginGoogleDriveTv(BuildContext context, WidgetRef ref) async {
  if (!AppConstants.googleOAuthTvConfigured) {
    throw StateError('Google TV OAuth is not configured in this build.');
  }
  final GoogleDriveOAuthService service = GoogleDriveOAuthService();
  final GoogleDriveDeviceAuthorization authorization = await service
      .requestDeviceAuthorization();
  if (!context.mounted) return;
  final GoogleDriveTokenBundle? tokens =
      await showDialog<GoogleDriveTokenBundle>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => _GoogleDriveDeviceDialog(
          service: service,
          authorization: authorization,
        ),
      );
  if (tokens == null) return;
  await ref.read(googleDriveSyncControllerProvider.notifier).connect(tokens);
  await ref.read(googleDriveSyncControllerProvider.notifier).syncNow();
}

class _GoogleDriveDeviceDialog extends StatefulWidget {
  const _GoogleDriveDeviceDialog({
    required this.service,
    required this.authorization,
  });

  final GoogleDriveOAuthService service;
  final GoogleDriveDeviceAuthorization authorization;

  @override
  State<_GoogleDriveDeviceDialog> createState() =>
      _GoogleDriveDeviceDialogState();
}

class _GoogleDriveDeviceDialogState extends State<_GoogleDriveDeviceDialog> {
  bool _cancelled = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
  }

  Future<void> _poll() async {
    try {
      final GoogleDriveTokenBundle tokens = await widget.service
          .pollDeviceAuthorization(
            authorization: widget.authorization,
            isCancelled: () => _cancelled,
          );
      if (mounted) Navigator.of(context).pop(tokens);
    } on Object catch (error) {
      debugPrint('Google Drive TV sign-in failed: $error');
      if (mounted && !_cancelled) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Uri verificationUri = widget.authorization.verificationUri;
    return AlertDialog(
      title: Text(context.t('Connect Google Drive')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              context.t(
                'Scan the QR code with your phone, allow access, then return to MiruShin.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: QrImageView(data: verificationUri.toString(), size: 176),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              verificationUri.toString(),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (widget.authorization.userCode.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SelectableText(
                widget.authorization.userCode,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_error == null) ...<Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(context.t('Waiting for Google…')),
            ] else
              Text(
                context.t('Google sign-in failed. Please try again.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: () => Clipboard.setData(
            ClipboardData(
              text: widget.authorization.userCode.isNotEmpty
                  ? widget.authorization.userCode
                  : widget.authorization.verificationUri.toString(),
            ),
          ),
          icon: const Icon(Icons.copy_rounded),
          label: Text(
            widget.authorization.userCode.isNotEmpty
                ? context.t('Copy code')
                : context.t('Copy link'),
          ),
        ),
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop();
          },
          child: Text(context.t('Cancel')),
        ),
      ],
    );
  }
}

Future<OAuthCodeResult?> _obtainCode(
  BuildContext context, {
  required Uri uri,
  required String redirectUri,
}) async {
  if (kIsWeb) return _manualCode(context, uri);
  final OAuthCodeListener listener = await startOAuthCodeListener(
    port: AppConstants.googleOAuthDesktopCallbackPort,
  );
  try {
    final bool opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await listener.cancel();
      return null;
    }
  } catch (_) {
    await listener.cancel();
    rethrow;
  }
  return waitForGoogleDriveOAuthCallback(listener);
}

@visibleForTesting
Future<OAuthCodeResult?> waitForGoogleDriveOAuthCallback(
  OAuthCodeListener listener,
) async {
  try {
    // `await` is essential here. Returning listener.wait() directly from a
    // try/finally executes finally immediately and closes the callback server
    // before the browser can reach it.
    return await listener.wait();
  } finally {
    await listener.cancel();
  }
}

Future<OAuthCodeResult?> _manualCode(BuildContext context, Uri uri) async {
  String input = '';
  return showDialog<OAuthCodeResult>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(context.t('Google Drive')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            context.t(
              'Open Google, then paste the returned link or code here.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(onChanged: (String value) => input = value),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.t('Cancel')),
        ),
        OutlinedButton(
          onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
          child: Text(context.t('Open Google')),
        ),
        FilledButton(
          onPressed: () {
            final Uri? pasted = Uri.tryParse(input.trim());
            final String code = pasted?.queryParameters['code'] ?? input.trim();
            final String? state = pasted?.queryParameters['state'];
            if (code.isNotEmpty) {
              Navigator.of(
                dialogContext,
              ).pop(OAuthCodeResult(code: code, state: state));
            }
          },
          child: Text(context.t('Continue')),
        ),
      ],
    ),
  );
}
