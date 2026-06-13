import '../../../shared/models/media_item.dart';

class SoraAddonException implements Exception {
  const SoraAddonException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SoraAddonAuthor {
  const SoraAddonAuthor({
    required this.name,
    required this.iconUrl,
    this.extra = const <String, dynamic>{},
  });

  final String name;
  final String iconUrl;
  final Map<String, dynamic> extra;

  factory SoraAddonAuthor.fromJson(Object? value) {
    if (value is String) {
      return SoraAddonAuthor(name: value.trim(), iconUrl: '');
    }
    if (value is! Map) {
      return const SoraAddonAuthor(name: '', iconUrl: '');
    }
    final Map<String, dynamic> json = value.map(
      (Object? key, Object? mapValue) =>
          MapEntry<String, dynamic>(key.toString(), mapValue),
    );
    return SoraAddonAuthor(
      name: _string(json['name']),
      iconUrl: _string(json['icon'], fallback: _string(json['iconUrl'])),
      extra: Map<String, dynamic>.from(json)
        ..removeWhere(
          (String key, dynamic _) =>
              key == 'name' || key == 'icon' || key == 'iconUrl',
        ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{...extra, 'name': name, 'icon': iconUrl};
  }
}

class SoraAddonManifest {
  const SoraAddonManifest({
    required this.sourceName,
    required this.iconUrl,
    required this.author,
    required this.version,
    required this.language,
    required this.streamType,
    required this.quality,
    required this.baseUrl,
    required this.searchBaseUrl,
    required this.scriptUrl,
    required this.type,
    required this.downloadSupport,
    required this.description,
    required this.softsub,
    required this.raw,
  });

  final String sourceName;
  final String iconUrl;
  final SoraAddonAuthor author;
  final String version;
  final String language;
  final String streamType;
  final String quality;
  final String baseUrl;
  final String searchBaseUrl;
  final String scriptUrl;
  final String type;
  final bool downloadSupport;
  final String description;
  final bool softsub;
  final Map<String, dynamic> raw;

  factory SoraAddonManifest.fromJson(Map<String, dynamic> json) {
    final SoraAddonAuthor author = SoraAddonAuthor.fromJson(json['author']);
    return SoraAddonManifest(
      sourceName: _string(
        json['sourceName'],
        fallback: _string(json['name'], fallback: _string(json['title'])),
      ),
      iconUrl: _string(json['iconUrl'], fallback: _string(json['icon'])),
      author: author,
      version: _string(json['version']),
      language: _string(json['language'], fallback: _string(json['lang'])),
      streamType: _string(json['streamType']),
      quality: _string(json['quality']),
      baseUrl: _string(json['baseUrl'], fallback: _string(json['baseURL'])),
      searchBaseUrl: _string(
        json['searchBaseUrl'],
        fallback: _string(
          json['searchBaseURL'],
          fallback: _string(json['baseUrl']),
        ),
      ),
      scriptUrl: _string(
        json['scriptUrl'],
        fallback: _string(
          json['scriptURL'],
          fallback: _string(json['script'], fallback: _string(json['src'])),
        ),
      ),
      type: _string(json['type']),
      downloadSupport: _bool(json['downloadSupport']),
      description: _string(
        json['description'],
        fallback: _string(json['desc'], fallback: _string(json['about'])),
      ),
      softsub: _bool(
        json['softsub'],
        fallback: _bool(json['softSub'], fallback: _bool(json['subtitle'])),
      ),
      raw: Map<String, dynamic>.from(json),
    );
  }

  Uri scriptUri(Uri manifestUri) {
    final Uri? parsed = Uri.tryParse(scriptUrl);
    if (parsed == null) {
      throw const SoraAddonException('Addon script URL is not valid.');
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    return manifestUri.resolveUri(parsed);
  }

  List<String> validationErrors() {
    final List<String> errors = <String>[];
    void requireField(String value, String label) {
      if (value.trim().isEmpty) {
        errors.add('$label is required');
      }
    }

    requireField(sourceName, 'sourceName');
    requireField(scriptUrl, 'scriptUrl');
    return errors;
  }

  void validate() {
    final List<String> errors = validationErrors();
    if (errors.isNotEmpty) {
      throw SoraAddonException('Invalid Sora manifest: ${errors.join(', ')}.');
    }
  }

  bool supportsMediaType(MediaType mediaType) {
    final List<String> tokens = _tokens(type);
    if (tokens.isEmpty ||
        tokens.any(
          (String token) =>
              token == 'all' ||
              token == 'multi' ||
              token == 'media' ||
              token == 'video',
        )) {
      return true;
    }
    return switch (mediaType) {
      MediaType.anime => tokens.any(
        (String token) =>
            token.contains('anime') ||
            token.contains('ani') ||
            token.contains('donghua'),
      ),
      MediaType.movie => tokens.any(
        (String token) =>
            token.contains('movie') ||
            token.contains('film') ||
            token.contains('cinema'),
      ),
      MediaType.series => tokens.any(
        (String token) =>
            token.contains('series') ||
            token.contains('tv') ||
            token.contains('show') ||
            token.contains('drama'),
      ),
    };
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...raw,
      'sourceName': sourceName,
      'iconUrl': iconUrl,
      'author': author.toJson(),
      'version': version,
      'language': language,
      'streamType': streamType,
      'quality': quality,
      'baseUrl': baseUrl,
      'searchBaseUrl': searchBaseUrl,
      'scriptUrl': scriptUrl,
      'type': type,
      'downloadSupport': downloadSupport,
      if (description.isNotEmpty) 'description': description,
      if (softsub) 'softsub': softsub,
    };
  }
}

class SoraAddonPreview {
  const SoraAddonPreview({
    required this.manifestUrl,
    required this.manifest,
    required this.manifestJson,
    required this.scriptCode,
    required this.scriptUrl,
  });

  final String manifestUrl;
  final SoraAddonManifest manifest;
  final Map<String, dynamic> manifestJson;
  final String scriptCode;
  final String scriptUrl;
}

class SoraInstalledAddon {
  const SoraInstalledAddon({
    required this.id,
    required this.manifestUrl,
    required this.manifest,
    required this.manifestPath,
    required this.scriptPath,
    required this.enabled,
    required this.order,
    required this.installedAt,
    required this.updatedAt,
    required this.lastCheckedAt,
    required this.lastError,
  });

  final String id;
  final String manifestUrl;
  final SoraAddonManifest manifest;
  final String manifestPath;
  final String scriptPath;
  final bool enabled;
  final int order;
  final DateTime installedAt;
  final DateTime updatedAt;
  final DateTime? lastCheckedAt;
  final String? lastError;

  SoraInstalledAddon copyWith({
    SoraAddonManifest? manifest,
    String? manifestPath,
    String? scriptPath,
    bool? enabled,
    int? order,
    DateTime? installedAt,
    DateTime? updatedAt,
    DateTime? lastCheckedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return SoraInstalledAddon(
      id: id,
      manifestUrl: manifestUrl,
      manifest: manifest ?? this.manifest,
      manifestPath: manifestPath ?? this.manifestPath,
      scriptPath: scriptPath ?? this.scriptPath,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  factory SoraInstalledAddon.fromJson(Map<String, dynamic> json) {
    return SoraInstalledAddon(
      id: _string(json['id']),
      manifestUrl: _string(json['manifestUrl']),
      manifest: SoraAddonManifest.fromJson(_map(json['manifest'])),
      manifestPath: _string(json['manifestPath']),
      scriptPath: _string(json['scriptPath']),
      enabled: _bool(json['enabled'], fallback: true),
      order: json['order'] is int ? json['order'] as int : 0,
      installedAt: _date(json['installedAt']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
      lastCheckedAt: _date(json['lastCheckedAt']),
      lastError: _nullableString(json['lastError']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'manifestUrl': manifestUrl,
      'manifest': manifest.toJson(),
      'manifestPath': manifestPath,
      'scriptPath': scriptPath,
      'enabled': enabled,
      'order': order,
      'installedAt': installedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastCheckedAt': lastCheckedAt?.toIso8601String(),
      'lastError': lastError,
    };
  }
}

class SoraSourceDetails {
  const SoraSourceDetails({
    required this.title,
    required this.description,
    required this.aliases,
    required this.airdate,
    required this.image,
    this.raw = const <String, dynamic>{},
  });

  final String title;
  final String description;
  final List<String> aliases;
  final String airdate;
  final String image;
  final Map<String, dynamic> raw;

  factory SoraSourceDetails.empty(String title) {
    return SoraSourceDetails(
      title: title,
      description: '',
      aliases: const <String>[],
      airdate: '',
      image: '',
    );
  }
}

class SoraSearchResult {
  const SoraSearchResult({
    required this.addonId,
    required this.addonName,
    required this.title,
    required this.image,
    required this.href,
    required this.languageCode,
    required this.query,
    required this.score,
    this.raw = const <String, dynamic>{},
  });

  final String addonId;
  final String addonName;
  final String title;
  final String image;
  final String href;
  final String languageCode;
  final String query;
  final double score;
  final Map<String, dynamic> raw;
}

class SoraEpisode {
  const SoraEpisode({
    required this.number,
    required this.href,
    required this.title,
    required this.image,
    required this.description,
    required this.duration,
    this.openingStart,
    this.openingEnd,
    this.endingStart,
    this.endingEnd,
    this.metadataTitle = '',
    this.metadataImage = '',
    this.tvdbTitle = '',
    this.raw = const <String, dynamic>{},
  });

  final double number;
  final String href;
  final String title;
  final String image;
  final String description;
  final String duration;
  final int? openingStart;
  final int? openingEnd;
  final int? endingStart;
  final int? endingEnd;
  final String metadataTitle;
  final String metadataImage;
  final String tvdbTitle;
  final Map<String, dynamic> raw;

  String get displayNumber {
    if (number <= 0) {
      return '';
    }
    if (number == number.roundToDouble()) {
      return number.round().toString();
    }
    return number.toString();
  }

  /// Season number supplied by the addon (0 when it doesn't provide one). Read
  /// from the raw episode data so multi-season sources (e.g. TMDB shows) can be
  /// grouped by the addon's own seasons instead of guessing from number resets.
  int get season {
    for (final String key in const <String>[
      'season',
      'seasonNumber',
      'season_number',
      'seasonNum',
      's',
    ]) {
      final Object? value = raw[key];
      if (value is num && value > 0) return value.toInt();
      if (value is String) {
        final int? parsed = int.tryParse(value.trim());
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return 0;
  }

  SoraEpisode copyWith({
    double? number,
    String? href,
    String? title,
    String? image,
    String? description,
    String? duration,
    int? openingStart,
    int? openingEnd,
    int? endingStart,
    int? endingEnd,
    String? metadataTitle,
    String? metadataImage,
    String? tvdbTitle,
    Map<String, dynamic>? raw,
  }) {
    return SoraEpisode(
      number: number ?? this.number,
      href: href ?? this.href,
      title: title ?? this.title,
      image: image ?? this.image,
      description: description ?? this.description,
      duration: duration ?? this.duration,
      openingStart: openingStart ?? this.openingStart,
      openingEnd: openingEnd ?? this.openingEnd,
      endingStart: endingStart ?? this.endingStart,
      endingEnd: endingEnd ?? this.endingEnd,
      metadataTitle: metadataTitle ?? this.metadataTitle,
      metadataImage: metadataImage ?? this.metadataImage,
      tvdbTitle: tvdbTitle ?? this.tvdbTitle,
      raw: raw ?? this.raw,
    );
  }
}

class SoraStreamCandidate {
  const SoraStreamCandidate({
    required this.title,
    required this.url,
    this.headers = const <String, String>{},
    this.subtitles = const <SoraSubtitle>[],
    this.voiceover,
    this.raw = const <String, dynamic>{},
  });

  final String title;
  final String url;
  final Map<String, String> headers;
  final List<SoraSubtitle> subtitles;
  final String? voiceover;
  final Map<String, dynamic> raw;
}

class SoraSubtitle {
  const SoraSubtitle({
    required this.url,
    required this.language,
    required this.label,
    this.headers = const <String, String>{},
  });

  final String url;
  final String language;
  final String label;
  final Map<String, String> headers;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'url': url,
      'language': language,
      'label': label,
      if (headers.isNotEmpty) 'headers': headers,
    };
  }
}

class SoraResolvedStreams {
  const SoraResolvedStreams({
    required this.addonId,
    required this.episode,
    required this.candidates,
    required this.raw,
  });

  final String addonId;
  final SoraEpisode episode;
  final List<SoraStreamCandidate> candidates;
  final Object? raw;

  bool get isEmpty => candidates.isEmpty;
}

class SoraSearchLanguage {
  const SoraSearchLanguage({
    required this.code,
    required this.name,
    required this.tmdbLanguage,
  });

  final String code;
  final String name;
  final String tmdbLanguage;

  static const List<SoraSearchLanguage> supported = <SoraSearchLanguage>[
    SoraSearchLanguage(code: 'en', name: 'English', tmdbLanguage: 'en-US'),
    SoraSearchLanguage(code: 'ru', name: 'Russian', tmdbLanguage: 'ru-RU'),
    SoraSearchLanguage(code: 'ja', name: 'Japanese', tmdbLanguage: 'ja-JP'),
  ];

  static const List<String> defaultPriority = <String>['en', 'ru', 'ja'];

  static SoraSearchLanguage byCode(String code) {
    return supported.firstWhere(
      (SoraSearchLanguage language) => language.code == code,
      orElse: () => supported.first,
    );
  }
}

class SoraTitleVariant {
  const SoraTitleVariant({
    required this.languageCode,
    required this.title,
    this.source = '',
  });

  final String languageCode;
  final String title;
  final String source;

  @override
  bool operator ==(Object other) {
    return other is SoraTitleVariant &&
        other.languageCode == languageCode &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(languageCode, title);
}

class SoraSourceSearchRequest {
  const SoraSourceSearchRequest({
    required this.media,
    required this.languageCodes,
    this.addonId,
    this.customQuery,
  });

  final MediaItem media;
  final List<String> languageCodes;
  final String? addonId;
  final String? customQuery;

  @override
  bool operator ==(Object other) {
    return other is SoraSourceSearchRequest &&
        other.media.id == media.id &&
        other.media.title == media.title &&
        other.media.originalTitle == media.originalTitle &&
        other.media.externalIds['sora_season_number'] ==
            media.externalIds['sora_season_number'] &&
        other.media.externalIds['sora_season_name'] ==
            media.externalIds['sora_season_name'] &&
        other.media.externalIds['sora_season_original_name'] ==
            media.externalIds['sora_season_original_name'] &&
        other.media.externalIds['sora_season_aliases'] ==
            media.externalIds['sora_season_aliases'] &&
        other.addonId == addonId &&
        other.customQuery == customQuery &&
        _listEquals(other.languageCodes, languageCodes);
  }

  @override
  int get hashCode => Object.hash(
    media.id,
    media.title,
    media.originalTitle,
    media.externalIds['sora_season_number'],
    media.externalIds['sora_season_name'],
    media.externalIds['sora_season_original_name'],
    media.externalIds['sora_season_aliases'],
    addonId,
    customQuery,
    Object.hashAll(languageCodes),
  );
}

class SoraSourceRequest {
  const SoraSourceRequest({required this.addonId, required this.result});

  final String addonId;
  final SoraSearchResult result;

  @override
  bool operator ==(Object other) {
    return other is SoraSourceRequest &&
        other.addonId == addonId &&
        other.result.href == result.href;
  }

  @override
  int get hashCode => Object.hash(addonId, result.href);
}

class SoraStreamRequest {
  const SoraStreamRequest({
    required this.addonId,
    required this.episode,
    this.voiceover,
  });

  final String addonId;
  final SoraEpisode episode;
  final String? voiceover;

  @override
  bool operator ==(Object other) {
    return other is SoraStreamRequest &&
        other.addonId == addonId &&
        other.episode.href == episode.href &&
        other.episode.metadataTitle == episode.metadataTitle &&
        other.episode.tvdbTitle == episode.tvdbTitle &&
        other.voiceover == voiceover;
  }

  @override
  int get hashCode => Object.hash(
    addonId,
    episode.href,
    episode.metadataTitle,
    episode.tvdbTitle,
    voiceover,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return fallback;
}

String? _nullableString(Object? value) {
  final String parsed = _string(value);
  return parsed.isEmpty ? null : parsed;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (<String>{'true', 'yes', '1', 'supported'}.contains(normalized)) {
      return true;
    }
    if (<String>{'false', 'no', '0', 'unsupported'}.contains(normalized)) {
      return false;
    }
  }
  return fallback;
}

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) {
    return <String, dynamic>{};
  }
  return value.map(
    (Object? key, Object? mapValue) =>
        MapEntry<String, dynamic>(key.toString(), mapValue),
  );
}

List<String> _tokens(String value) {
  return value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .map((String token) => token.trim())
      .where((String token) => token.isNotEmpty)
      .toList(growable: false);
}
