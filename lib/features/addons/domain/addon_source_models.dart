import 'sora_models.dart';

/// A user-added module catalog endpoint (e.g. `example.com/modules.json`) that
/// lists modules the user can browse and install. There are no bundled
/// sources; the user adds them on the Sources page.
class AddonSource {
  const AddonSource({
    required this.id,
    required this.url,
    required this.name,
    required this.addedAt,
  });

  final String id;
  final String url;

  /// Optional friendly name. Falls back to the catalog host when empty.
  final String name;
  final DateTime addedAt;

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
    return url;
  }

  AddonSource copyWith({String? name}) {
    return AddonSource(
      id: id,
      url: url,
      name: name ?? this.name,
      addedAt: addedAt,
    );
  }

  factory AddonSource.create({required String url, String name = ''}) {
    final String trimmed = url.trim();
    return AddonSource(
      id: _idForUrl(trimmed),
      url: trimmed,
      name: name.trim(),
      addedAt: DateTime.now(),
    );
  }

  factory AddonSource.fromJson(Map<String, dynamic> json) {
    final String url = (json['url'] ?? '').toString().trim();
    return AddonSource(
      id: (json['id'] ?? '').toString().trim().isEmpty
          ? _idForUrl(url)
          : json['id'].toString().trim(),
      url: url,
      name: (json['name'] ?? '').toString().trim(),
      addedAt:
          DateTime.tryParse((json['addedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'url': url,
      'name': name,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  static String _idForUrl(String url) {
    final String normalized = url.trim().toLowerCase();
    int hash = 0x811c9dc5;
    for (final int codeUnit in normalized.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'src-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

/// One module entry parsed from a catalog response. Mirrors the public Sora
/// module catalog shape; only the fields MiruShin needs to display and install
/// are kept. [manifestUrl] is the key used to install the module through the
/// existing preview/install pipeline.
class AddonCatalogEntry {
  const AddonCatalogEntry({
    required this.id,
    required this.sourceName,
    required this.iconUrl,
    required this.version,
    required this.language,
    required this.streamType,
    required this.quality,
    required this.type,
    required this.note,
    required this.manifestUrl,
    required this.scriptUrl,
    required this.baseUrl,
    required this.softsub,
    required this.downloadSupport,
    required this.author,
  });

  final String id;
  final String sourceName;
  final String iconUrl;
  final String version;
  final String language;
  final String streamType;
  final String quality;
  final String type;
  final String note;
  final String manifestUrl;
  final String scriptUrl;
  final String baseUrl;
  final bool softsub;
  final bool downloadSupport;
  final SoraAddonAuthor author;

  /// The install pipeline resolves the manifest URL into a manifest + script,
  /// so a usable catalog entry must expose one.
  bool get isInstallable => manifestUrl.trim().isNotEmpty;

  String get installUrl => manifestUrl.trim();

  static AddonCatalogEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final Map<String, dynamic> json = value.map(
      (Object? key, Object? mapValue) =>
          MapEntry<String, dynamic>(key.toString(), mapValue),
    );
    final String name = _string(json, const <String>[
      'sourceName',
      'name',
      'title',
    ]);
    final String manifestUrl = _string(json, const <String>[
      'manifestUrl',
      'manifestURL',
      'jsonUrl',
      'url',
    ]);
    final String scriptUrl = _string(json, const <String>[
      'scriptUrl',
      'scriptURL',
      'script',
      'src',
    ]);
    if (name.isEmpty && manifestUrl.isEmpty && scriptUrl.isEmpty) {
      return null;
    }
    return AddonCatalogEntry(
      id: _string(json, const <String>['id', 'sourceId']),
      sourceName: name,
      iconUrl: _string(json, const <String>['iconUrl', 'icon', 'image']),
      version: _string(json, const <String>['version']),
      language: _string(json, const <String>['language', 'lang']),
      streamType: _string(json, const <String>['streamType']),
      quality: _string(json, const <String>['quality']),
      type: _string(json, const <String>['type']),
      note: _string(json, const <String>['note']),
      manifestUrl: manifestUrl,
      scriptUrl: scriptUrl,
      baseUrl: _string(json, const <String>['baseUrl', 'baseURL']),
      softsub: _bool(json['softsub']),
      downloadSupport: _bool(json['downloadSupport']),
      author: SoraAddonAuthor.fromJson(json['author']),
    );
  }

  static String _string(Map<String, dynamic> json, List<String> keys) {
    for (final String key in keys) {
      final Object? value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num || value is bool) {
        return value.toString();
      }
    }
    return '';
  }

  static bool _bool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == 'yes' || normalized == '1';
    }
    return false;
  }
}
