import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/sora_models.dart';

class SoraAddonImportResult {
  const SoraAddonImportResult({
    required this.installed,
    required this.failed,
    required this.failures,
  });

  final int installed;
  final int failed;
  final List<String> failures;

  bool get hasFailures => failed > 0;
}

class _SoraAddonImportCandidate {
  const _SoraAddonImportCandidate({
    required this.manifestUrl,
    required this.enabled,
    required this.order,
    this.id,
  });

  final String manifestUrl;
  final bool enabled;
  final int order;
  final String? id;
}

class SoraAddonStore {
  SoraAddonStore({
    Dio? dio,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 14),
               receiveTimeout: const Duration(seconds: 22),
               followRedirects: true,
               headers: const <String, String>{
                 'User-Agent': _defaultUserAgent,
                 'Accept': 'application/json,text/plain,*/*',
               },
             ),
           ),
       _supportDirectoryProvider = supportDirectoryProvider;

  static const String _defaultUserAgent =
      'MiruShin/1.0 SoraAddonRuntime (+https://github.com/emp0ry)';

  final Dio _dio;
  final Future<Directory> Function()? _supportDirectoryProvider;

  Future<List<SoraInstalledAddon>> loadInstalled() async {
    final File registry = await _registryFile();
    if (!await registry.exists()) {
      return <SoraInstalledAddon>[];
    }
    try {
      final Object? decoded = jsonDecode(await registry.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return <SoraInstalledAddon>[];
      }
      final Object? addons = decoded['addons'];
      if (addons is! List<dynamic>) {
        return <SoraInstalledAddon>[];
      }
      List<SoraInstalledAddon> installed = addons
          .whereType<Map<String, dynamic>>()
          .map(SoraInstalledAddon.fromJson)
          .where((SoraInstalledAddon addon) => addon.id.isNotEmpty)
          .toList();
      // Migrate: if all orders are 0, assign based on alphabetical position.
      final bool needsMigration =
          installed.isNotEmpty &&
          installed.every((SoraInstalledAddon a) => a.order == 0);
      if (needsMigration) {
        installed.sort(
          (SoraInstalledAddon a, SoraInstalledAddon b) =>
              a.manifest.sourceName.compareTo(b.manifest.sourceName),
        );
        installed = <SoraInstalledAddon>[
          for (int i = 0; i < installed.length; i++)
            installed[i].copyWith(order: i),
        ];
        await _saveRegistry(installed);
      } else {
        installed.sort(
          (SoraInstalledAddon a, SoraInstalledAddon b) =>
              a.order.compareTo(b.order),
        );
      }
      return installed;
    } on Object {
      return <SoraInstalledAddon>[];
    }
  }

  Future<SoraAddonPreview> previewFromUrl(String url) async {
    final Uri manifestUri = _parseUri(url, 'Addon manifest URL is not valid.');
    final Map<String, dynamic> manifestJson = await _fetchJson(manifestUri);
    final Map<String, dynamic> normalizedManifestJson =
        Map<String, dynamic>.from(manifestJson);
    if (_firstString(normalizedManifestJson, const <String>[
      'sourceName',
      'name',
      'title',
    ]).isEmpty) {
      normalizedManifestJson['sourceName'] = _sourceNameFromUrl(manifestUri);
    }
    if (_firstString(normalizedManifestJson, const <String>[
      'scriptUrl',
      'scriptURL',
      'script',
      'src',
    ]).isEmpty) {
      normalizedManifestJson['scriptUrl'] = _inferScriptUrl(manifestUri);
    }
    final SoraAddonManifest manifest = SoraAddonManifest.fromJson(
      normalizedManifestJson,
    );
    manifest.validate();
    final Uri scriptUri = manifest.scriptUri(manifestUri);
    final String scriptCode = await _fetchText(scriptUri, referer: manifestUri);
    if (scriptCode.trim().isEmpty) {
      throw const SoraAddonException('Addon script is empty.');
    }
    return SoraAddonPreview(
      manifestUrl: manifestUri.toString(),
      manifest: manifest,
      manifestJson: normalizedManifestJson,
      scriptCode: scriptCode,
      scriptUrl: scriptUri.toString(),
    );
  }

  Future<SoraInstalledAddon> installFromPreview(
    SoraAddonPreview preview,
  ) async {
    final List<SoraInstalledAddon> installed = await loadInstalled();
    final String id = _addonId(preview.manifestUrl, preview.manifest);
    final DateTime now = DateTime.now();
    final SoraInstalledAddon? previous = _find(installed, id);
    final Directory addonDirectory = await _addonDirectory(id);
    await addonDirectory.create(recursive: true);
    final File manifestFile = File('${addonDirectory.path}/manifest.json');
    final File scriptFile = File('${addonDirectory.path}/module.js');
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(preview.manifestJson),
    );
    await scriptFile.writeAsString(preview.scriptCode);

    final SoraInstalledAddon addon = SoraInstalledAddon(
      id: id,
      manifestUrl: preview.manifestUrl,
      manifest: preview.manifest,
      manifestPath: manifestFile.path,
      scriptPath: scriptFile.path,
      enabled: previous?.enabled ?? true,
      order: previous?.order ?? installed.length,
      installedAt: previous?.installedAt ?? now,
      updatedAt: now,
      lastCheckedAt: now,
      lastError: null,
    );
    await _replace(addon);
    return addon;
  }

  Future<SoraInstalledAddon> setEnabled(String id, bool enabled) async {
    final SoraInstalledAddon addon = await _require(id);
    final SoraInstalledAddon updated = addon.copyWith(enabled: enabled);
    await _replace(updated);
    return updated;
  }

  Future<SoraInstalledAddon> update(SoraInstalledAddon addon) async {
    final DateTime checkedAt = DateTime.now();
    try {
      final SoraAddonPreview preview = await previewFromUrl(addon.manifestUrl);
      final Directory addonDirectory = await _addonDirectory(addon.id);
      await addonDirectory.create(recursive: true);
      final File manifestFile = File('${addonDirectory.path}/manifest.json');
      final File scriptFile = File('${addonDirectory.path}/module.js');
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(preview.manifestJson),
      );
      await scriptFile.writeAsString(preview.scriptCode);
      final SoraInstalledAddon updated = addon.copyWith(
        manifest: preview.manifest,
        manifestPath: manifestFile.path,
        scriptPath: scriptFile.path,
        updatedAt: checkedAt,
        lastCheckedAt: checkedAt,
        clearLastError: true,
      );
      await _replace(updated);
      return updated;
    } on Object catch (error) {
      final SoraInstalledAddon failed = addon.copyWith(
        lastCheckedAt: checkedAt,
        lastError: _friendlyError(error),
      );
      await _replace(failed);
      return failed;
    }
  }

  Future<List<SoraInstalledAddon>> updateAll({
    bool onlyStale = false,
    Duration staleAfter = const Duration(hours: 24),
  }) async {
    final List<SoraInstalledAddon> addons = await loadInstalled();
    final DateTime now = DateTime.now();
    final List<SoraInstalledAddon> updated = <SoraInstalledAddon>[];
    for (final SoraInstalledAddon addon in addons) {
      final DateTime? checkedAt = addon.lastCheckedAt;
      final bool stale =
          checkedAt == null || now.difference(checkedAt) >= staleAfter;
      updated.add(onlyStale && !stale ? addon : await update(addon));
    }
    return updated;
  }

  Future<void> remove(String id) async {
    final List<SoraInstalledAddon> addons = await loadInstalled();
    final List<SoraInstalledAddon> remaining = addons
        .where((SoraInstalledAddon addon) => addon.id != id)
        .toList(growable: false);
    await _saveRegistry(remaining);
    final Directory directory = await _addonDirectory(id);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String> readScript(SoraInstalledAddon addon) async {
    final File file = File(addon.scriptPath);
    if (!await file.exists()) {
      throw SoraAddonException(
        'The local script for ${addon.manifest.sourceName} is missing.',
      );
    }
    return file.readAsString();
  }

  Future<String> exportInstalledJson() async {
    final List<SoraInstalledAddon> installed = await loadInstalled();
    final List<SoraInstalledAddon> ordered = <SoraInstalledAddon>[...installed]
      ..sort(
        (SoraInstalledAddon a, SoraInstalledAddon b) =>
            a.order.compareTo(b.order),
      );
    final List<SoraInstalledAddon> normalized = <SoraInstalledAddon>[
      for (int index = 0; index < ordered.length; index++)
        ordered[index].copyWith(order: index),
    ];
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'format': 'mirushin.sora.addons.v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'addons': normalized
          .map((SoraInstalledAddon addon) => addon.toJson())
          .toList(growable: false),
      // AnimeShin-compatible payload. AnimeShin ignores extra MiruShin keys.
      'remoteModules': normalized
          .map(
            (SoraInstalledAddon addon) => <String, Object?>{
              'id': addon.id,
              'jsonUrl': addon.manifestUrl,
              'enabled': addon.enabled,
              'updatedAt': addon.updatedAt.toUtc().toIso8601String(),
              'order': addon.order,
            },
          )
          .toList(growable: false),
      'disabledModuleIds': normalized
          .where((SoraInstalledAddon addon) => !addon.enabled)
          .map((SoraInstalledAddon addon) => addon.id)
          .toList(growable: false),
      'order': normalized
          .map((SoraInstalledAddon addon) => addon.id)
          .toList(growable: false),
    });
  }

  Future<SoraAddonImportResult> importInstalledJson(String raw) async {
    final List<_SoraAddonImportCandidate> candidates =
        _importCandidatesFromJson(raw);
    if (candidates.isEmpty) {
      throw const SoraAddonException('Import file does not contain addons.');
    }

    var installedCount = 0;
    final List<String> failures = <String>[];
    for (final _SoraAddonImportCandidate candidate in candidates) {
      try {
        final SoraAddonPreview preview = await previewFromUrl(
          candidate.manifestUrl,
        );
        final SoraInstalledAddon addon = await installFromPreview(preview);
        await setEnabled(addon.id, candidate.enabled);
        installedCount++;
      } on Object catch (error) {
        failures.add('${candidate.manifestUrl}: ${_friendlyError(error)}');
      }
    }

    if (installedCount > 0) {
      await _applyImportedOrder(candidates);
    }

    return SoraAddonImportResult(
      installed: installedCount,
      failed: failures.length,
      failures: failures,
    );
  }

  Future<SoraInstalledAddon> _require(String id) async {
    final SoraInstalledAddon? addon = _find(await loadInstalled(), id);
    if (addon == null) {
      throw const SoraAddonException('Addon is not installed.');
    }
    return addon;
  }

  Future<void> _replace(SoraInstalledAddon addon) async {
    final List<SoraInstalledAddon> addons = await loadInstalled();
    final int index = addons.indexWhere(
      (SoraInstalledAddon current) => current.id == addon.id,
    );
    if (index == -1) {
      addons.add(addon);
    } else {
      addons[index] = addon;
    }
    await _saveRegistry(addons);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final List<SoraInstalledAddon> addons = await loadInstalled();
    if (oldIndex < 0 ||
        oldIndex >= addons.length ||
        newIndex < 0 ||
        newIndex >= addons.length) {
      return;
    }
    final SoraInstalledAddon moved = addons.removeAt(oldIndex);
    addons.insert(newIndex, moved);
    final List<SoraInstalledAddon> reordered = <SoraInstalledAddon>[
      for (int i = 0; i < addons.length; i++) addons[i].copyWith(order: i),
    ];
    await _saveRegistry(reordered);
  }

  Future<void> _applyImportedOrder(
    List<_SoraAddonImportCandidate> candidates,
  ) async {
    final List<SoraInstalledAddon> addons = await loadInstalled();
    final Map<String, SoraInstalledAddon> byUrl = <String, SoraInstalledAddon>{
      for (final SoraInstalledAddon addon in addons)
        addon.manifestUrl.trim().toLowerCase(): addon,
    };
    final Map<String, SoraInstalledAddon> byId = <String, SoraInstalledAddon>{
      for (final SoraInstalledAddon addon in addons) addon.id: addon,
    };
    final List<_SoraAddonImportCandidate> ordered =
        <_SoraAddonImportCandidate>[...candidates]..sort(
          (_SoraAddonImportCandidate a, _SoraAddonImportCandidate b) =>
              a.order.compareTo(b.order),
        );
    final List<SoraInstalledAddon> imported = <SoraInstalledAddon>[];
    final Set<String> importedIds = <String>{};
    for (final _SoraAddonImportCandidate candidate in ordered) {
      final SoraInstalledAddon? addon =
          byUrl[candidate.manifestUrl.trim().toLowerCase()] ??
          (candidate.id == null ? null : byId[candidate.id]);
      if (addon == null || importedIds.contains(addon.id)) {
        continue;
      }
      imported.add(addon);
      importedIds.add(addon.id);
    }
    final List<SoraInstalledAddon> remaining = addons
        .where((SoraInstalledAddon addon) => !importedIds.contains(addon.id))
        .toList(growable: false);
    final List<SoraInstalledAddon> reordered = <SoraInstalledAddon>[
      ...imported,
      ...remaining,
    ];
    await _saveRegistry(<SoraInstalledAddon>[
      for (int i = 0; i < reordered.length; i++)
        reordered[i].copyWith(order: i),
    ]);
  }

  Future<void> _saveRegistry(List<SoraInstalledAddon> addons) async {
    final File registry = await _registryFile();
    await registry.parent.create(recursive: true);
    await registry.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'version': 1,
        'addons': addons
            .map((SoraInstalledAddon addon) => addon.toJson())
            .toList(growable: false),
      }),
    );
  }

  List<_SoraAddonImportCandidate> _importCandidatesFromJson(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw SoraAddonException(
        'Import file is not valid JSON: ${error.message}.',
      );
    }

    final List<_SoraAddonImportCandidate> candidates =
        <_SoraAddonImportCandidate>[];
    if (decoded is List<dynamic>) {
      for (int index = 0; index < decoded.length; index++) {
        final _SoraAddonImportCandidate? candidate = _candidateFromValue(
          decoded[index],
          index,
          const <String>{},
        );
        if (candidate != null) candidates.add(candidate);
      }
    } else if (decoded is Map) {
      final Map<String, dynamic> map = decoded.map(
        (Object? key, Object? value) =>
            MapEntry<String, dynamic>(key.toString(), value),
      );
      final Set<String> disabledIds = _stringSet(
        map['disabledModuleIds'] ?? map['disabledModules'],
      );
      final Object? addonList =
          map['addons'] ??
          map['remoteModules'] ??
          map['modules'] ??
          map['sources'] ??
          map['items'];
      if (addonList is List<dynamic>) {
        for (int index = 0; index < addonList.length; index++) {
          final _SoraAddonImportCandidate? candidate = _candidateFromValue(
            addonList[index],
            index,
            disabledIds,
          );
          if (candidate != null) candidates.add(candidate);
        }
      }
    }

    final Map<String, _SoraAddonImportCandidate> byUrl =
        <String, _SoraAddonImportCandidate>{};
    for (final _SoraAddonImportCandidate candidate in candidates) {
      byUrl[candidate.manifestUrl.trim().toLowerCase()] = candidate;
    }
    return byUrl.values.toList(growable: false)..sort(
      (_SoraAddonImportCandidate a, _SoraAddonImportCandidate b) =>
          a.order.compareTo(b.order),
    );
  }

  _SoraAddonImportCandidate? _candidateFromValue(
    Object? value,
    int index,
    Set<String> disabledIds,
  ) {
    if (value is String) {
      final String url = value.trim();
      if (url.isEmpty) return null;
      return _SoraAddonImportCandidate(
        manifestUrl: url,
        enabled: true,
        order: index,
      );
    }
    if (value is! Map) return null;
    final Map<String, dynamic> map = value.map(
      (Object? key, Object? mapValue) =>
          MapEntry<String, dynamic>(key.toString(), mapValue),
    );
    final String url = _firstString(map, const <String>[
      'manifestUrl',
      'jsonUrl',
      'url',
      'sourceUrl',
      'moduleUrl',
      'href',
    ]);
    if (url.isEmpty) return null;
    final String id = _firstString(map, const <String>['id', 'sourceId']);
    final bool enabled = _boolValue(
      map['enabled'],
      fallback: id.isEmpty || !disabledIds.contains(id),
    );
    final int order = int.tryParse(map['order']?.toString() ?? '') ?? index;
    return _SoraAddonImportCandidate(
      manifestUrl: url,
      enabled: enabled,
      order: order,
      id: id.isEmpty ? null : id,
    );
  }

  String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final String key in keys) {
      final String value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _boolValue(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  Set<String> _stringSet(Object? value) {
    if (value is! List) return const <String>{};
    return value
        .map((Object? item) => item?.toString().trim() ?? '')
        .where((String item) => item.isNotEmpty)
        .toSet();
  }

  Future<Map<String, dynamic>> _fetchJson(Uri uri) async {
    final String text = await _fetchText(uri);
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) =>
              MapEntry<String, dynamic>(key.toString(), value),
        );
      }
    } on FormatException catch (error) {
      throw SoraAddonException('Manifest is not valid JSON: ${error.message}.');
    }
    throw const SoraAddonException('Manifest JSON must be an object.');
  }

  Future<String> _fetchText(Uri uri, {Uri? referer}) async {
    final Response<String> response = await _dio.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        headers: <String, String>{
          if (referer != null) 'Referer': referer.toString(),
          'User-Agent': _defaultUserAgent,
          'Accept': 'application/json,text/plain,*/*',
        },
      ),
    );
    final int? statusCode = response.statusCode;
    if (statusCode != null && (statusCode < 200 || statusCode >= 300)) {
      throw SoraAddonException('Request failed with HTTP $statusCode.');
    }
    return response.data ?? '';
  }

  Uri _parseUri(String value, String error) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw SoraAddonException(error);
    }
    return uri;
  }

  String _inferScriptUrl(Uri manifestUri) {
    final String path = manifestUri.path;
    if (path.endsWith('.json')) {
      return manifestUri
          .replace(path: '${path.substring(0, path.length - 5)}.js')
          .toString();
    }
    return manifestUri.replace(path: '$path.js').toString();
  }

  String _sourceNameFromUrl(Uri manifestUri) {
    final String segment = manifestUri.pathSegments.isEmpty
        ? manifestUri.host
        : manifestUri.pathSegments.last;
    final String base = segment.endsWith('.json')
        ? segment.substring(0, segment.length - 5)
        : segment;
    final String cleaned = base
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? manifestUri.host : cleaned;
  }

  Future<File> _registryFile() async {
    final Directory root = await _rootDirectory();
    return File('${root.path}/registry.json');
  }

  Future<Directory> _addonDirectory(String id) async {
    final Directory root = await _rootDirectory();
    return Directory('${root.path}/$id');
  }

  Future<Directory> _rootDirectory() async {
    final Future<Directory> Function()? provider = _supportDirectoryProvider;
    final Directory base = provider == null
        ? await getApplicationSupportDirectory()
        : await provider();
    final Directory root = Directory('${base.path}/sora_addons');
    await root.create(recursive: true);
    return root;
  }

  SoraInstalledAddon? _find(List<SoraInstalledAddon> addons, String id) {
    for (final SoraInstalledAddon addon in addons) {
      if (addon.id == id) {
        return addon;
      }
    }
    return null;
  }

  String _addonId(String manifestUrl, SoraAddonManifest manifest) {
    final String slug = manifest.sourceName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'sora-addon' : slug}-${_fnv1a(manifestUrl)}';
  }

  String _fnv1a(String value) {
    int hash = 0x811c9dc5;
    for (final int codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _friendlyError(Object error) {
    if (error is SoraAddonException) {
      return error.message;
    }
    if (error is DioException) {
      final int? statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return 'HTTP $statusCode while updating addon.';
      }
      return error.message ?? 'Network request failed.';
    }
    return error.toString();
  }
}
