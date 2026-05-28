import 'dart:convert';
import 'dart:math' as math;

import 'sora_models.dart';
import '../../watch/domain/normalized_models.dart';

Object? decodeSoraPayload(Object? value) {
  Object? current = value;
  for (int depth = 0; depth < 4; depth += 1) {
    if (current is! String) {
      return current;
    }
    final String text = current.trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      current = jsonDecode(text);
    } on FormatException {
      return text;
    }
  }
  return current;
}

List<SoraSearchResult> parseSoraSearchResults({
  required Object? payload,
  required String addonId,
  required String addonName,
  required String languageCode,
  required String query,
  required List<SoraTitleVariant> titleVariants,
}) {
  final Object? decoded = decodeSoraPayload(payload);
  final List<Object?> items = _listFrom(decoded);
  final List<SoraSearchResult> results = <SoraSearchResult>[];
  for (final Object? item in items) {
    final Map<String, dynamic> json = _map(item);
    if (json.isEmpty) {
      continue;
    }
    final String href = _string(
      json['href'],
      fallback: _string(json['url'], fallback: _string(json['link'])),
    );
    if (href.isEmpty) {
      continue;
    }
    final String title = _string(
      json['title'],
      fallback: _string(json['name'], fallback: href),
    );
    final String image = _string(
      json['image'],
      fallback: _string(
        json['img'],
        fallback: _string(json['poster'], fallback: _string(json['thumbnail'])),
      ),
    );
    results.add(
      SoraSearchResult(
        addonId: addonId,
        addonName: addonName,
        title: title,
        image: image,
        href: href,
        languageCode: languageCode,
        query: query,
        score: soraBestTitleSimilarity(title, titleVariants),
        raw: json,
      ),
    );
  }
  return results;
}

SoraSourceDetails parseSoraDetails(Object? payload, String fallbackTitle) {
  final Object? decoded = decodeSoraPayload(payload);
  final Map<String, dynamic> json = _firstMap(decoded);
  if (json.isEmpty) {
    return SoraSourceDetails.empty(fallbackTitle);
  }
  return SoraSourceDetails(
    title: _string(
      json['title'],
      fallback: _string(json['name'], fallback: fallbackTitle),
    ),
    description: _string(
      json['description'],
      fallback: _string(json['desc'], fallback: _string(json['overview'])),
    ),
    aliases: _stringList(json['aliases']).isEmpty
        ? _stringList(json['alias'])
        : _stringList(json['aliases']),
    airdate: _string(
      json['airdate'],
      fallback: _string(json['aired'], fallback: _string(json['year'])),
    ),
    image: _string(
      json['image'],
      fallback: _string(
        json['poster'],
        fallback: _string(json['thumbnail'], fallback: _string(json['img'])),
      ),
    ),
    raw: json,
  );
}

List<SoraEpisode> parseSoraEpisodes(Object? payload) {
  final Object? decoded = decodeSoraPayload(payload);
  final List<Object?> items = _listFrom(decoded);
  final List<SoraEpisode> episodes = <SoraEpisode>[];
  for (int index = 0; index < items.length; index += 1) {
    final Map<String, dynamic> json = _map(items[index]);
    if (json.isEmpty) {
      continue;
    }
    final String href = _string(
      json['href'],
      fallback: _string(json['url'], fallback: _string(json['link'])),
    );
    if (href.isEmpty) {
      continue;
    }
    final _SkipRange opening = _openingRange(json);
    final _SkipRange ending = _endingRange(json);
    episodes.add(
      SoraEpisode(
        number: _double(
          json['number'],
          fallback: _double(
            json['episode'],
            fallback: _double(json['ep'], fallback: index + 1),
          ),
        ),
        href: href,
        title: _string(
          json['title'],
          fallback: _string(json['name'], fallback: 'Episode ${index + 1}'),
        ),
        image: _string(
          json['image'],
          fallback: _string(
            json['img'],
            fallback: _string(
              json['poster'],
              fallback: _string(json['thumbnail']),
            ),
          ),
        ),
        description: _string(
          json['description'],
          fallback: _string(json['desc'], fallback: _string(json['overview'])),
        ),
        duration: _string(json['duration'], fallback: _string(json['runtime'])),
        openingStart: opening.start,
        openingEnd: opening.end,
        endingStart: ending.start,
        endingEnd: ending.end,
        raw: json,
      ),
    );
  }
  episodes.sort((SoraEpisode a, SoraEpisode b) {
    if (a.number <= 0 || b.number <= 0) {
      return 0;
    }
    return a.number.compareTo(b.number);
  });
  return episodes;
}

List<SoraStreamCandidate> parseSoraStreamCandidates(Object? payload) {
  final Object? decoded = decodeSoraPayload(payload);
  return _parseStreamValue(decoded)
      .where((SoraStreamCandidate candidate) {
        return candidate.url.trim().isNotEmpty;
      })
      .toList(growable: false);
}

NormalizedStreamBundle parseSoraStreamBundle(
  SoraResolvedStreams streams, {
  String streamType = '',
  Future<NormalizedStreamBundle> Function()? refresh,
}) {
  final List<SoraStreamCandidate> candidates = streams.candidates;

  if (candidates.isEmpty) {
    final NormalizedServer empty = NormalizedServer(
      id: 'none',
      title: 'No stream',
      streamUrl: '',
    );

    return NormalizedStreamBundle(
      addonId: streams.addonId,
      episode: streams.episode,
      selectedServer: empty,
      availableServers: const <NormalizedServer>[],
      streamType: streamType,
      refresh: refresh,
    );
  }

  final Map<String, List<SoraStreamCandidate>> groups =
      <String, List<SoraStreamCandidate>>{};

  for (final SoraStreamCandidate c in candidates) {
    final String quality = _extractQualityLabel(c);
    final String serverName = _serverName(c, quality);
    final String vo = c.voiceover?.trim() ?? '';
    final String key = '$serverName\x00$vo';

    groups.putIfAbsent(key, () => <SoraStreamCandidate>[]).add(c);
  }

  final List<NormalizedServer> servers = <NormalizedServer>[];
  int serverIndex = 0;

  for (final MapEntry<String, List<SoraStreamCandidate>> entry
      in groups.entries) {
    final List<SoraStreamCandidate> group = entry.value;

    group.sort((SoraStreamCandidate a, SoraStreamCandidate b) {
      return _qualityRank(
        _extractQualityLabel(a),
      ).compareTo(_qualityRank(_extractQualityLabel(b)));
    });

    final SoraStreamCandidate best = group.first;
    final String quality = _extractQualityLabel(best);
    final String rawTitle = _serverName(best, quality);
    final String title = rawTitle.isNotEmpty
        ? rawTitle
        : 'Server ${serverIndex + 1}';

    final List<NormalizedQuality> qualities = <NormalizedQuality>[];
    final Set<String> seenQualityLabels = <String>{};

    for (final SoraStreamCandidate c in group) {
      final String label = _extractQualityLabel(c);
      if (label.isEmpty) continue;

      final String labelKey = label.toLowerCase().trim();
      if (!seenQualityLabels.add(labelKey)) continue;

      qualities.add(
        NormalizedQuality(label: label, streamUrl: c.url, headers: c.headers),
      );
    }

    qualities.sort((NormalizedQuality a, NormalizedQuality b) {
      return _qualityRank(a.label).compareTo(_qualityRank(b.label));
    });

    servers.add(
      NormalizedServer(
        id: 'server_$serverIndex',
        title: title,
        streamUrl: best.url,
        headers: best.headers,
        qualities: qualities,
      ),
    );

    serverIndex++;
  }

  final Set<String> seenVo = <String>{};
  final List<NormalizedVoiceOver> voiceovers = <NormalizedVoiceOver>[];

  for (final SoraStreamCandidate c in candidates) {
    final String? vo = c.voiceover?.trim();

    if (vo != null && vo.isNotEmpty && seenVo.add(vo)) {
      voiceovers.add(NormalizedVoiceOver(id: vo, label: vo));
    }
  }

  final Set<String> seenUrls = <String>{};
  final List<NormalizedSubtitle> subtitles = <NormalizedSubtitle>[];

  for (final SoraStreamCandidate c in candidates) {
    for (final SoraSubtitle s in c.subtitles) {
      if (seenUrls.add(s.url)) {
        subtitles.add(
          NormalizedSubtitle(
            url: s.url,
            language: s.language,
            label: s.label,
            headers: s.headers,
          ),
        );
      }
    }
  }

  final Map<String, dynamic> raw = _firstMap(decodeSoraPayload(streams.raw));
  final _SkipRange opening = _openingRange(raw);
  final _SkipRange ending = _endingRange(raw);
  final NormalizedServer firstServer = servers.first;

  return NormalizedStreamBundle(
    addonId: streams.addonId,
    episode: streams.episode,
    selectedServer: firstServer,
    availableServers: servers,
    selectedVoiceOver: voiceovers.isNotEmpty ? voiceovers.first : null,
    availableVoiceOvers: voiceovers,
    selectedQuality: firstServer.qualities.isNotEmpty
        ? firstServer.qualities.first
        : null,
    availableQualities: firstServer.qualities,
    subtitles: subtitles,
    headers: firstServer.headers,
    streamType: streamType,
    openingStart: opening.start,
    openingEnd: opening.end,
    endingStart: ending.start,
    endingEnd: ending.end,
    refresh: refresh,
  );
}

String _extractQualityLabel(SoraStreamCandidate c) {
  final Object? raw = c.raw['quality'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();

  final RegExpMatch? specialMatch = RegExp(
    r'\b(4K|2K)\b',
    caseSensitive: false,
  ).firstMatch(c.title);

  if (specialMatch != null) {
    final String value = specialMatch.group(1) ?? '';
    if (value.toLowerCase() == '4k') return '4K';
    if (value.toLowerCase() == '2k') return '2K';
  }

  final RegExpMatch? match = RegExp(
    r'\b(2160|1440|1080|720|480|360|240|144)[pP]?\b',
  ).firstMatch(c.title);

  if (match != null) {
    final String value = match.group(1)!;
    if (value == '2160') return '4K';
    if (value == '1440') return '2K';
    return '${value}p';
  }

  return '';
}

int _qualityRank(String label) {
  final String lower = label.toLowerCase().trim();

  if (lower == '4k') return 0;
  if (lower == '2k') return 1;

  final RegExpMatch? match = RegExp(
    r'(2160|1440|1080|720|480|360|240|144)',
  ).firstMatch(lower);

  if (match == null) return 999;

  final String value = match.group(1)!;

  switch (value) {
    case '2160':
      return 0;
    case '1440':
      return 1;
    case '1080':
      return 2;
    case '720':
      return 3;
    case '480':
      return 4;
    case '360':
      return 5;
    case '240':
      return 6;
    case '144':
      return 7;
    default:
      return 999;
  }
}

// Derive a display-only server name. Quality labels must stay only in
// NormalizedQuality/quality picker, not in server titles shown by Choose Stream
// or Choose Stream.
String _serverName(SoraStreamCandidate c, String qualityLabel) {
  final Object? raw = c.raw['server'];
  final String rawServer = raw is String ? raw.trim() : '';

  final String cleanedRawServer = _cleanServerName(rawServer, qualityLabel);
  if (cleanedRawServer.isNotEmpty) return cleanedRawServer;

  return _cleanServerName(c.title, qualityLabel);
}

String _cleanServerName(String value, String qualityLabel) {
  String title = value.trim();
  if (title.isEmpty) return '';

  final List<String> qualityTokens = <String>[
    if (qualityLabel.trim().isNotEmpty) RegExp.escape(qualityLabel.trim()),
    r'4\s*[Kk]',
    r'2\s*[Kk]',
    r'2160\s*[pP]?',
    r'1440\s*[pP]?',
    r'1080\s*[pP]?',
    r'720\s*[pP]?',
    r'480\s*[pP]?',
    r'360\s*[pP]?',
    r'240\s*[pP]?',
    r'144\s*[pP]?',
  ];

  for (final String token in qualityTokens) {
    title = title.replaceAll(
      RegExp(
        '(?:^|[\\s_\\-\\[\\(])$token(?=\$|[\\s_\\-\\]\\)]|\$)',
        caseSensitive: false,
      ),
      ' ',
    );
  }

  title = title
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-_:\|/]+|[\s\-_:\|/]+$'), '')
      .trim();

  if (_looksLikeQualityOnly(title)) return '';
  return title;
}

bool _looksLikeQualityOnly(String value) {
  final String lower = value.toLowerCase().trim();
  if (lower.isEmpty) return true;
  return RegExp(
    r'^(?:4\s*k|2\s*k|2160\s*p?|1440\s*p?|1080\s*p?|720\s*p?|480\s*p?|360\s*p?|240\s*p?|144\s*p?)$',
  ).hasMatch(lower);
}

double soraBestTitleSimilarity(
  String candidate,
  List<SoraTitleVariant> titleVariants,
) {
  if (titleVariants.isEmpty) {
    return soraTitleSimilarity(candidate, '');
  }
  double best = 0;
  for (final SoraTitleVariant variant in titleVariants) {
    best = math.max(best, soraTitleSimilarity(candidate, variant.title));
  }
  return best.clamp(0, 1);
}

double soraTitleSimilarity(String a, String b) {
  final String left = _normalizeTitle(a);
  final String right = _normalizeTitle(b);
  if (left.isEmpty || right.isEmpty) {
    return 0;
  }
  if (left == right) {
    return 1;
  }
  final bool contains = left.contains(right) || right.contains(left);
  final Set<String> leftTokens = _tokens(left).toSet();
  final Set<String> rightTokens = _tokens(right).toSet();
  final int overlap = leftTokens.intersection(rightTokens).length;
  final int union = leftTokens.union(rightTokens).length;
  final double tokenScore = union == 0 ? 0 : overlap / union;
  final int distance = _levenshtein(left, right);
  final int maxLength = math.max(left.length, right.length);
  final double editScore = maxLength == 0 ? 0 : 1 - (distance / maxLength);
  final double score = math.max(editScore, tokenScore);
  return contains ? math.max(score, 0.82) : score.clamp(0, 1);
}

class _QualityUrl {
  const _QualityUrl(this.label, this.url);

  final String label;
  final String url;
}

List<SoraStreamCandidate> _parseStreamValue(Object? value) {
  if (value == null) {
    return const <SoraStreamCandidate>[];
  }

  if (value is String) {
    return <SoraStreamCandidate>[
      SoraStreamCandidate(title: 'Default', url: value),
    ];
  }

  if (value is List) {
    return value
        .expand<SoraStreamCandidate>(_parseStreamValue)
        .toList(growable: false);
  }

  final Map<String, dynamic> json = _map(value);
  if (json.isEmpty) {
    return const <SoraStreamCandidate>[];
  }

  final Object? streams = json['streams'] ?? json['sources'];

  if (streams != null) {
    final List<SoraStreamCandidate> parsed = _parseStreamValue(streams);
    final Map<String, String> inheritedHeaders = _headers(json['headers']);
    final List<SoraSubtitle> inheritedSubtitles = _subtitles(json);

    return parsed
        .map((SoraStreamCandidate candidate) {
          return SoraStreamCandidate(
            title: candidate.title,
            url: candidate.url,
            headers: <String, String>{
              ...inheritedHeaders,
              ...candidate.headers,
            },
            subtitles: candidate.subtitles.isEmpty
                ? inheritedSubtitles
                : candidate.subtitles,
            voiceover: candidate.voiceover,
            raw: candidate.raw,
          );
        })
        .toList(growable: false);
  }

  final String title = _cleanServerName(
    _string(
      json['title'],
      fallback: _string(json['server'], fallback: 'Server'),
    ),
    _string(json['quality']),
  );

  final Map<String, String> headers = _headers(json['headers']);
  final List<SoraSubtitle> subtitles = _subtitles(json);

  final String? voiceover = _nullableString(
    json['voiceover'] ?? json['voiceOver'] ?? json['dub'],
  );

  final List<_QualityUrl> qualityUrls = <_QualityUrl>[
    _QualityUrl('4K', _string(json['url4k'])),
    _QualityUrl('2K', _string(json['url2k'])),
    _QualityUrl('1080p', _string(json['url1080'])),
    _QualityUrl('720p', _string(json['url720'])),
    _QualityUrl('480p', _string(json['url480'])),
    _QualityUrl('360p', _string(json['url360'])),
    _QualityUrl('240p', _string(json['url240'])),
    _QualityUrl('144p', _string(json['url144'])),
  ];

  final List<SoraStreamCandidate> qualityCandidates = <SoraStreamCandidate>[];

  final Set<String> seenLabels = <String>{};

  for (final _QualityUrl quality in qualityUrls) {
    final String url = quality.url.trim();
    if (url.isEmpty) continue;

    final String labelKey = quality.label.toLowerCase().trim();
    if (!seenLabels.add(labelKey)) continue;

    qualityCandidates.add(
      SoraStreamCandidate(
        title: '$title ${quality.label}',
        url: url,
        headers: headers,
        subtitles: subtitles,
        voiceover: voiceover,
        raw: <String, dynamic>{
          ...json,
          'server': title,
          'quality': quality.label,
        },
      ),
    );
  }

  if (qualityCandidates.isNotEmpty) {
    return qualityCandidates;
  }

  final String url = _string(
    json['streamUrl'],
    fallback: _string(
      json['streamURL'],
      fallback: _string(
        json['stream'],
        fallback: _string(json['url'], fallback: _string(json['file'])),
      ),
    ),
  );

  return <SoraStreamCandidate>[
    SoraStreamCandidate(
      title: title,
      url: url,
      headers: headers,
      subtitles: subtitles,
      voiceover: voiceover,
      raw: json,
    ),
  ];
}

List<Object?> _listFrom(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  if (value is Map) {
    for (final String key in <String>[
      'results',
      'data',
      'items',
      'episodes',
      'list',
      'searchResults',
    ]) {
      final Object? child = value[key];
      if (child is List) {
        return child.cast<Object?>();
      }
    }
    return <Object?>[value];
  }
  return const <Object?>[];
}

Map<String, dynamic> _firstMap(Object? value) {
  if (value is Map) {
    return _map(value);
  }
  final List<Object?> list = _listFrom(value);
  for (final Object? item in list) {
    final Map<String, dynamic> json = _map(item);
    if (json.isNotEmpty) {
      return json;
    }
  }
  return <String, dynamic>{};
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

Map<String, String> _headers(Object? value) {
  final Map<String, dynamic> map = _map(value);
  return map.map(
    (String key, dynamic value) =>
        MapEntry<String, String>(key, value == null ? '' : value.toString()),
  )..removeWhere((String _, String value) => value.trim().isEmpty);
}

List<SoraSubtitle> _subtitles(Map<String, dynamic> json) {
  final Object? value =
      json['subtitles'] ?? json['subtitle'] ?? json['subs'] ?? json['tracks'];

  // Top-level headers for a bare string subtitle URL (e.g. BingeBox subtitlesHeaders).
  final Map<String, String> topLevelHeaders =
      _headers(json['subtitlesHeaders'] ?? json['subtitleHeaders']);

  List<SoraSubtitle> primary = const <SoraSubtitle>[];

  if (value == null) {
    primary = const <SoraSubtitle>[];
  } else if (value is String) {
    final String url = value.trim();
    primary = url.isEmpty
        ? const <SoraSubtitle>[]
        : <SoraSubtitle>[
            SoraSubtitle(
              url: url,
              language: '',
              label: 'Subtitle',
              headers: topLevelHeaders,
            ),
          ];
  } else if (value is! List) {
    final Map<String, dynamic> map = _map(value);
    final String url = _string(
      map['url'],
      fallback: _string(map['file'], fallback: _string(map['src'])),
    );
    primary = url.isEmpty
        ? const <SoraSubtitle>[]
        : <SoraSubtitle>[
            SoraSubtitle(
              url: url,
              language: _string(map['language'], fallback: _string(map['lang'])),
              label: _string(
                map['label'],
                fallback: _string(map['title'], fallback: 'Subtitle'),
              ),
              headers: _headers(map['headers']),
            ),
          ];
  } else {
    primary = value
        .map<SoraSubtitle?>((Object? item) {
          if (item is String) {
            final String url = item.trim();
            return url.isEmpty
                ? null
                : SoraSubtitle(url: url, language: '', label: 'Subtitle');
          }
          final Map<String, dynamic> map = _map(item);
          final String url = _string(
            map['url'],
            fallback: _string(map['file'], fallback: _string(map['src'])),
          );
          if (url.isEmpty) return null;
          return SoraSubtitle(
            url: url,
            language: _string(map['language'], fallback: _string(map['lang'])),
            label: _string(
              map['label'],
              fallback: _string(map['title'], fallback: 'Subtitle'),
            ),
            headers: _headers(map['headers']),
          );
        })
        .whereType<SoraSubtitle>()
        .toList(growable: false);
  }

  // Merge allSubtitles array (rich per-track list with headers) alongside any
  // primary tracks already parsed from the default subtitle key.
  final Object? allSubs = json['allSubtitles'];
  if (allSubs is List && allSubs.isNotEmpty) {
    final Set<String> seen = <String>{
      for (final SoraSubtitle s in primary) s.url,
    };
    final List<SoraSubtitle> extras = allSubs
        .map<SoraSubtitle?>((Object? item) {
          final Map<String, dynamic> map = _map(item);
          final String url = _string(map['url'],
              fallback: _string(map['file'], fallback: _string(map['src'])));
          if (url.isEmpty || !seen.add(url)) return null;
          return SoraSubtitle(
            url: url,
            language: _string(map['language'], fallback: _string(map['lang'])),
            label: _string(
              map['label'],
              fallback: _string(map['title'], fallback: 'Subtitle'),
            ),
            headers: _headers(map['headers']),
          );
        })
        .whereType<SoraSubtitle>()
        .toList(growable: false);
    if (extras.isNotEmpty) {
      return <SoraSubtitle>[...primary, ...extras];
    }
  }

  return primary;
}

List<String> _stringList(Object? value) {
  if (value is String) {
    return value
        .split(RegExp(r'[,;/]'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((Object? item) => item?.toString().trim() ?? '')
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
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
  final String text = _string(value);
  return text.isEmpty ? null : text;
}

double _double(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
  }
  return fallback;
}

_SkipRange _skipRange(
  Map<String, dynamic> json, {
  required List<String> objectKeys,
  required List<String> startKeys,
  required List<String> endKeys,
}) {
  int? start;
  int? end;

  for (final String key in objectKeys) {
    final Map<String, dynamic> nested = _map(json[key]);
    if (nested.isEmpty) continue;
    start ??= _seconds(nested['start'] ?? nested['from']);
    end ??= _seconds(nested['stop'] ?? nested['end'] ?? nested['to']);
  }

  start ??= _firstSeconds(json, startKeys);
  end ??= _firstSeconds(json, endKeys);

  if (start == null || end == null || end <= start) {
    return const _SkipRange();
  }
  return _SkipRange(start: start, end: end);
}

_SkipRange _openingRange(Map<String, dynamic> json) {
  return _skipRange(
    json,
    objectKeys: const <String>['opening', 'op', 'intro'],
    startKeys: const <String>[
      'openingStart',
      'opening_start',
      'opening.start',
      'opStart',
      'op_start',
      'introStart',
      'intro_start',
    ],
    endKeys: const <String>[
      'openingEnd',
      'openingStop',
      'opening_end',
      'opening_stop',
      'opening.end',
      'opening.stop',
      'opEnd',
      'opStop',
      'op_end',
      'op_stop',
      'introEnd',
      'introStop',
      'intro_end',
      'intro_stop',
    ],
  );
}

_SkipRange _endingRange(Map<String, dynamic> json) {
  return _skipRange(
    json,
    objectKeys: const <String>['ending', 'ed', 'outro'],
    startKeys: const <String>[
      'endingStart',
      'ending_start',
      'ending.start',
      'edStart',
      'ed_start',
      'outroStart',
      'outro_start',
    ],
    endKeys: const <String>[
      'endingEnd',
      'endingStop',
      'ending_end',
      'ending_stop',
      'ending.end',
      'ending.stop',
      'edEnd',
      'edStop',
      'ed_end',
      'ed_stop',
      'outroEnd',
      'outroStop',
      'outro_end',
      'outro_stop',
    ],
  );
}

int? _firstSeconds(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final int? value = _seconds(_deepValue(json, key));
    if (value != null) return value;
  }
  return null;
}

Object? _deepValue(Map<String, dynamic> json, String key) {
  if (!key.contains('.')) return json[key];
  Object? current = json;
  for (final String part in key.split('.')) {
    if (current is! Map) return null;
    current = current[part];
  }
  return current;
}

int? _seconds(Object? value) {
  if (value is num) {
    return value.round();
  }
  if (value is! String) {
    return null;
  }
  final String text = value.trim();
  if (text.isEmpty) return null;

  final List<String> parts = text.split(':');
  if (parts.length > 1) {
    int total = 0;
    for (final String part in parts) {
      final int? n = int.tryParse(part.trim());
      if (n == null) return null;
      total = total * 60 + n;
    }
    return total;
  }

  final double? parsed = double.tryParse(text.replaceAll(',', '.'));
  return parsed?.round();
}

class _SkipRange {
  const _SkipRange({this.start, this.end});

  final int? start;
  final int? end;
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]+\)|\[[^\]]+\]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9а-яёԱ-Ֆա-ֆぁ-んァ-ン一-龯]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _tokens(String value) {
  return value
      .split(' ')
      .where((String token) => token.isNotEmpty)
      .where(
        (String token) => !<String>{
          'the',
          'a',
          'an',
          'movie',
          'season',
          'сезон',
        }.contains(token),
      )
      .toList(growable: false);
}

int _levenshtein(String a, String b) {
  if (a == b) {
    return 0;
  }
  if (a.isEmpty) {
    return b.length;
  }
  if (b.isEmpty) {
    return a.length;
  }
  List<int> previous = List<int>.generate(b.length + 1, (int index) => index);
  for (int i = 0; i < a.length; i += 1) {
    final List<int> current = <int>[i + 1];
    for (int j = 0; j < b.length; j += 1) {
      final int cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      current.add(
        math.min(
          math.min(current[j] + 1, previous[j + 1] + 1),
          previous[j] + cost,
        ),
      );
    }
    previous = current;
  }
  return previous.last;
}
