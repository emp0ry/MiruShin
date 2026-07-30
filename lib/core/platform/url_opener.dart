import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'io_compat.dart' if (dart.library.io) 'dart:io';

/// Opens [url] in the user's default browser.
///
/// On desktop, it first invokes the operating system's open command. This is
/// the authoritative way to open the default browser and does not depend on
/// url_launcher's macOS `NSWorkspace.open` path, which has been observed to
/// claim success (or fail) without actually opening some URLs. url_launcher is
/// kept as a fallback and remains the primary path on mobile/web.
///
/// Returns `true` if a browser was opened.
Future<bool> openExternalUrl(String url) async {
  // Desktop: native open command first.
  try {
    if (Platform.isMacOS) {
      final ProcessResult r = await Process.run('/usr/bin/open', <String>[url]);
      debugPrint('[DEBUG] openExternalUrl: macOS open exit=${r.exitCode}');
      if (r.exitCode == 0) return true;
    } else if (Platform.isLinux) {
      final ProcessResult r = await Process.run('xdg-open', <String>[url]);
      debugPrint('[DEBUG] openExternalUrl: linux xdg-open exit=${r.exitCode}');
      if (r.exitCode == 0) return true;
    } else if (Platform.isWindows) {
      final ProcessResult r = await Process.run('cmd', <String>[
        '/c',
        'start',
        '',
        url,
      ]);
      debugPrint('[DEBUG] openExternalUrl: windows start exit=${r.exitCode}');
      if (r.exitCode == 0) return true;
    }
  } catch (error) {
    debugPrint('[DEBUG] openExternalUrl: native open failed: $error');
  }

  // Mobile/web (and desktop fallback): url_launcher.
  final Uri uri = Uri.parse(url);
  for (final LaunchMode mode in const <LaunchMode>[
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
  ]) {
    try {
      if (await launchUrl(uri, mode: mode)) {
        debugPrint(
          '[DEBUG] openExternalUrl: launchUrl(${mode.name}) succeeded',
        );
        return true;
      }
      debugPrint(
        '[DEBUG] openExternalUrl: launchUrl(${mode.name}) returned false',
      );
    } catch (error) {
      debugPrint(
        '[DEBUG] openExternalUrl: launchUrl(${mode.name}) threw: $error',
      );
    }
  }
  return false;
}
