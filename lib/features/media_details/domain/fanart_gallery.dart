enum FanartMediaKind { movie, tv }

class FanartIdentity {
  const FanartIdentity({required this.id, required this.kind});

  final int id;
  final FanartMediaKind kind;

  String get cacheKey => '${kind.name}:$id';

  @override
  bool operator ==(Object other) {
    return other is FanartIdentity && other.id == id && other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(id, kind);
}

class FanartBackground {
  const FanartBackground({
    required this.id,
    required this.url,
    required this.width,
    required this.height,
    required this.likes,
    required this.language,
    this.added,
  });

  final String id;
  final String url;
  final int width;
  final int height;
  final int likes;
  final String language;
  final DateTime? added;

  bool get isLandscape => width > height && width > 0 && height > 0;
  bool get is4K => isLandscape && width >= 3840;
  int get pixelCount => width * height;

  factory FanartBackground.fromJson(Map<String, dynamic> json) {
    return FanartBackground(
      id: _string(json['id']),
      url: _string(json['url']),
      width: _int(json['width']),
      height: _int(json['height']),
      likes: _int(json['likes']),
      language: _string(json['lang']),
      added: _dateTime(json['added']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'url': url,
    'width': width,
    'height': height,
    'likes': likes,
    'lang': language,
    if (added != null) 'added': added!.toIso8601String(),
  };
}

class FanartGallery {
  FanartGallery({
    required List<FanartBackground> fourKBackgrounds,
    required List<FanartBackground> backgrounds,
  }) : fourKBackgrounds = List<FanartBackground>.unmodifiable(fourKBackgrounds),
       backgrounds = List<FanartBackground>.unmodifiable(backgrounds);

  factory FanartGallery.fromBackgrounds(
    Iterable<FanartBackground> backgrounds,
  ) {
    final Set<String> seenIds = <String>{};
    final Set<String> seenUrls = <String>{};
    final List<FanartBackground> usable = <FanartBackground>[];
    for (final FanartBackground background in backgrounds) {
      if (background.url.isEmpty || !background.isLandscape) continue;
      if (background.id.isNotEmpty && !seenIds.add(background.id)) continue;
      if (!seenUrls.add(background.url)) continue;
      usable.add(background);
    }

    final List<FanartBackground> fourK =
        usable
            .where((FanartBackground image) => image.is4K)
            .toList(growable: false)
          ..sort(_compareBackgrounds);
    final List<FanartBackground> regular =
        usable
            .where((FanartBackground image) => !image.is4K)
            .toList(growable: false)
          ..sort(_compareBackgrounds);
    return FanartGallery(fourKBackgrounds: fourK, backgrounds: regular);
  }

  factory FanartGallery.fromJson(Map<String, dynamic> json) {
    return FanartGallery(
      fourKBackgrounds: _backgroundList(json['fourKBackgrounds']),
      backgrounds: _backgroundList(json['backgrounds']),
    );
  }

  static final FanartGallery empty = FanartGallery(
    fourKBackgrounds: const <FanartBackground>[],
    backgrounds: const <FanartBackground>[],
  );

  final List<FanartBackground> fourKBackgrounds;
  final List<FanartBackground> backgrounds;

  bool get isEmpty => fourKBackgrounds.isEmpty && backgrounds.isEmpty;
  bool get isNotEmpty => !isEmpty;
  List<FanartBackground> get allBackgrounds => <FanartBackground>[
    ...fourKBackgrounds,
    ...backgrounds,
  ];

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fourKBackgrounds': fourKBackgrounds
        .map((FanartBackground image) => image.toJson())
        .toList(growable: false),
    'backgrounds': backgrounds
        .map((FanartBackground image) => image.toJson())
        .toList(growable: false),
  };
}

int _compareBackgrounds(FanartBackground a, FanartBackground b) {
  final int likes = b.likes.compareTo(a.likes);
  if (likes != 0) return likes;
  final int pixels = b.pixelCount.compareTo(a.pixelCount);
  if (pixels != 0) return pixels;
  final int added = (b.added?.millisecondsSinceEpoch ?? 0).compareTo(
    a.added?.millisecondsSinceEpoch ?? 0,
  );
  if (added != 0) return added;
  return a.id.compareTo(b.id);
}

List<FanartBackground> _backgroundList(Object? value) {
  if (value is! List) return const <FanartBackground>[];
  return value
      .whereType<Map>()
      .map(
        (Map<dynamic, dynamic> json) => FanartBackground.fromJson(
          json.map(
            (dynamic key, dynamic value) =>
                MapEntry<String, dynamic>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

String _string(Object? value) => value?.toString().trim() ?? '';

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value)) ?? 0;
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
  }
  final String raw = _string(value);
  if (raw.isEmpty) return null;
  final int? seconds = int.tryParse(raw);
  if (seconds != null) {
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return DateTime.tryParse(raw);
}
