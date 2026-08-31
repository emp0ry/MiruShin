import 'package:flutter/material.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/platform/url_opener.dart';

const String selfHostedRelayGuideUrl =
    'https://github.com/emp0ry/MiruShin/blob/main/watch-party-relay/README.md';

class SelfHostedRelayInfoButton extends StatelessWidget {
  const SelfHostedRelayInfoButton({this.openUrl, super.key});

  final Future<bool> Function(String url)? openUrl;

  Future<void> _openGuide(BuildContext context) async {
    final bool opened = await (openUrl ?? openExternalUrl)(
      selfHostedRelayGuideUrl,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('Could not open the self-hosting guide.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey<String>('self-hosted-relay-info'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: () => _openGuide(context),
      icon: const Icon(Icons.info_outline_rounded),
      label: Text(context.t('Setup guide')),
    );
  }
}
