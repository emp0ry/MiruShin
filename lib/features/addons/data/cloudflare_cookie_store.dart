import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/platform/io_compat.dart' if (dart.library.io) 'dart:io';

/// Persists the `cf_clearance` cookie (plus the User-Agent it was minted for)
/// per host, so a Cloudflare challenge only has to be solved once per ~30 min
/// rather than on every Sora fetch.
///
/// Cloudflare ties a clearance cookie to the exact User-Agent that solved the
/// challenge, so both are stored together and replayed together. Entries are
/// keyed by host and matched by domain suffix, which lets a clearance minted on
/// `example.com` cover `www.example.com` / `api.example.com` the way Cloudflare
/// scopes the cookie itself.
class CloudflareCookieStore {
  CloudflareCookieStore({Future<dynamic> Function()? supportDirectoryProvider})
    : _supportDirectoryProvider = supportDirectoryProvider;

  final Future<dynamic> Function()? _supportDirectoryProvider;

  /// Cloudflare clearance cookies are short-lived; re-solve once stale.
  static const Duration _ttl = Duration(minutes: 30);

  final Map<String, _CfEntry> _entries = <String, _CfEntry>{};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final File file = await _file();
      if (!await file.exists()) return;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      decoded.forEach((String host, dynamic value) {
        if (value is Map<String, dynamic>) {
          final _CfEntry? entry = _CfEntry.fromJson(value);
          if (entry != null && !entry.isExpired(_ttl)) {
            _entries[host] = entry;
          }
        }
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cloudflare] Failed to load cookie store: $error');
      }
    }
  }

  /// The stored `Cookie` header value for [url], or null if none is fresh.
  Future<String?> cookieFor(Uri url) async {
    final _CfEntry? entry = await _match(url);
    return entry?.cookies;
  }

  /// The User-Agent the stored clearance for [url] was minted with, if any.
  Future<String?> userAgentFor(Uri url) async {
    final _CfEntry? entry = await _match(url);
    return entry?.userAgent;
  }

  Future<_CfEntry?> _match(Uri url) async {
    await _ensureLoaded();
    final String host = url.host.toLowerCase();
    if (host.isEmpty) return null;
    _CfEntry? best;
    String bestKey = '';
    _entries.forEach((String key, _CfEntry entry) {
      final bool matches = host == key || host.endsWith('.$key');
      if (matches && !entry.isExpired(_ttl) && key.length > bestKey.length) {
        best = entry;
        bestKey = key;
      }
    });
    return best;
  }

  /// Records the [cookies] / [userAgent] captured by solving the challenge for
  /// [url], keyed by its host.
  Future<void> save(Uri url, String cookies, String userAgent) async {
    await _ensureLoaded();
    final String host = url.host.toLowerCase();
    if (host.isEmpty || cookies.trim().isEmpty) return;
    _entries[host] = _CfEntry(
      cookies: cookies.trim(),
      userAgent: userAgent,
      savedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
  }

  /// Drops the stored clearance for [url]'s host. Called when a replayed cookie
  /// turns out to be stale (the retry was still walled) so the next attempt
  /// solves afresh instead of looping on a bad cookie.
  Future<void> clear(Uri url) async {
    await _ensureLoaded();
    if (_entries.remove(url.host.toLowerCase()) != null) {
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      // Prune expired entries on every write so the file stays small.
      _entries.removeWhere((_, _CfEntry entry) => entry.isExpired(_ttl));
      final File file = await _file();
      await file.parent.create(recursive: true);
      final Map<String, dynamic> json = <String, dynamic>{
        for (final MapEntry<String, _CfEntry> e in _entries.entries)
          e.key: e.value.toJson(),
      };
      await file.writeAsString(jsonEncode(json));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cloudflare] Failed to persist cookie store: $error');
      }
    }
  }

  Future<File> _file() async {
    final Future<dynamic> Function()? provider = _supportDirectoryProvider;
    final dynamic base = provider == null
        ? await getApplicationSupportDirectory()
        : await provider();
    return File('${base.path}/sora_addons/cloudflare_cookies.json');
  }
}

class _CfEntry {
  const _CfEntry({
    required this.cookies,
    required this.userAgent,
    required this.savedAtMillis,
  });

  final String cookies;
  final String userAgent;
  final int savedAtMillis;

  bool isExpired(Duration ttl) =>
      DateTime.now().millisecondsSinceEpoch - savedAtMillis > ttl.inMilliseconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cookies': cookies,
    'userAgent': userAgent,
    'savedAt': savedAtMillis,
  };

  static _CfEntry? fromJson(Map<String, dynamic> json) {
    final Object? cookies = json['cookies'];
    if (cookies is! String || cookies.trim().isEmpty) return null;
    return _CfEntry(
      cookies: cookies,
      userAgent: json['userAgent'] is String ? json['userAgent'] as String : '',
      savedAtMillis: json['savedAt'] is int ? json['savedAt'] as int : 0,
    );
  }
}
