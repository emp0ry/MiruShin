import '../../addons/domain/sora_models.dart';

class NormalizedSourceMatch {
  const NormalizedSourceMatch({
    required this.addonId,
    required this.addonName,
    required this.addonIconUrl,
    required this.title,
    required this.imageUrl,
    required this.href,
    required this.score,
    required this.languageCode,
  });

  final String addonId;
  final String addonName;
  final String addonIconUrl;
  final String title;
  final String imageUrl;
  final String href;
  final double score;
  final String languageCode;
}

class NormalizedServer {
  const NormalizedServer({
    required this.id,
    required this.title,
    required this.streamUrl,
    this.headers = const <String, String>{},
    this.qualities = const <NormalizedQuality>[],
  });

  final String id;
  final String title;
  final String streamUrl;
  final Map<String, String> headers;
  final List<NormalizedQuality> qualities;
}

class NormalizedVoiceOver {
  const NormalizedVoiceOver({required this.id, required this.label});

  final String id;
  final String label;
}

class NormalizedQuality {
  const NormalizedQuality({
    required this.label,
    required this.streamUrl,
    this.headers = const <String, String>{},
  });

  final String label;
  final String streamUrl;
  final Map<String, String> headers;
}

class NormalizedEpisode {
  const NormalizedEpisode({
    required this.number,
    required this.href,
    required this.title,
    required this.imageUrl,
    required this.overview,
    this.durationLabel = '',
    this.isSpecial = false,
    this.progress,
  });

  final double number;
  final String href;
  final String title;
  final String imageUrl;
  final String overview;
  final String durationLabel;
  final bool isSpecial;
  final EpisodeProgress? progress;

  String get displayNumber {
    if (number <= 0) {
      return '';
    }
    if (number == number.roundToDouble()) {
      return number.round().toString();
    }
    return number.toString();
  }
}

class EpisodeProgress {
  const EpisodeProgress({
    required this.positionSeconds,
    this.durationSeconds,
    required this.updatedAt,
    this.completed = false,
  });

  final int positionSeconds;
  final int? durationSeconds;
  final DateTime updatedAt;
  // true when the episode was watched to completion (near-end save).
  // Kept separate from positionSeconds so isWatched stays true even
  // though positionSeconds is reset to 0 for resume-from-start.
  final bool completed;

  double get fraction {
    final int? d = durationSeconds;
    if (d == null || d <= 0) {
      return 0;
    }
    return (positionSeconds / d).clamp(0.0, 1.0);
  }

  bool get isWatched => completed || fraction >= 0.85;
  bool get isStarted => completed || fraction > 0.02;

  factory EpisodeProgress.fromJson(Map<String, dynamic> json) {
    return EpisodeProgress(
      positionSeconds: _int(json['positionSeconds']),
      durationSeconds: _nullableInt(json['durationSeconds']),
      updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'positionSeconds': positionSeconds,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      'updatedAt': updatedAt.toIso8601String(),
      if (completed) 'completed': true,
    };
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final int v = _int(value);
    return v == 0 ? null : v;
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class NormalizedSubtitle {
  const NormalizedSubtitle({
    required this.url,
    required this.language,
    required this.label,
    this.headers = const <String, String>{},
  });

  final String url;
  final String language;
  final String label;
  final Map<String, String> headers;
}

class NormalizedStreamBundle {
  const NormalizedStreamBundle({
    required this.addonId,
    required this.episode,
    required this.selectedServer,
    required this.availableServers,
    this.selectedVoiceOver,
    this.availableVoiceOvers = const <NormalizedVoiceOver>[],
    this.selectedQuality,
    this.availableQualities = const <NormalizedQuality>[],
    this.subtitles = const <NormalizedSubtitle>[],
    this.headers = const <String, String>{},
    this.streamType = '',
    this.openingStart,
    this.openingEnd,
    this.endingStart,
    this.endingEnd,
    this.refresh,
  });

  final String addonId;
  final SoraEpisode episode;
  final NormalizedServer selectedServer;
  final List<NormalizedServer> availableServers;
  final NormalizedVoiceOver? selectedVoiceOver;
  final List<NormalizedVoiceOver> availableVoiceOvers;
  final NormalizedQuality? selectedQuality;
  final List<NormalizedQuality> availableQualities;
  final List<NormalizedSubtitle> subtitles;
  final Map<String, String> headers;
  final String streamType;
  final int? openingStart;
  final int? openingEnd;
  final int? endingStart;
  final int? endingEnd;
  final Future<NormalizedStreamBundle> Function()? refresh;

  String get activeUrl =>
      selectedQuality?.streamUrl ?? selectedServer.streamUrl;

  NormalizedStreamBundle withServer(NormalizedServer s) =>
      NormalizedStreamBundle(
        addonId: addonId,
        episode: episode,
        selectedServer: s,
        availableServers: availableServers,
        selectedVoiceOver: selectedVoiceOver,
        availableVoiceOvers: availableVoiceOvers,
        selectedQuality: s.qualities.isNotEmpty ? s.qualities.first : null,
        availableQualities: s.qualities,
        subtitles: subtitles,
        headers: s.headers.isNotEmpty ? s.headers : headers,
        streamType: streamType,
        openingStart: openingStart,
        openingEnd: openingEnd,
        endingStart: endingStart,
        endingEnd: endingEnd,
        refresh: refresh,
      );

  NormalizedStreamBundle withVoiceOver(NormalizedVoiceOver? vo) =>
      NormalizedStreamBundle(
        addonId: addonId,
        episode: episode,
        selectedServer: selectedServer,
        availableServers: availableServers,
        selectedVoiceOver: vo,
        availableVoiceOvers: availableVoiceOvers,
        selectedQuality: selectedQuality,
        availableQualities: availableQualities,
        subtitles: subtitles,
        headers: headers,
        streamType: streamType,
        openingStart: openingStart,
        openingEnd: openingEnd,
        endingStart: endingStart,
        endingEnd: endingEnd,
        refresh: refresh,
      );

  NormalizedStreamBundle withQuality(NormalizedQuality? q) =>
      NormalizedStreamBundle(
        addonId: addonId,
        episode: episode,
        selectedServer: selectedServer,
        availableServers: availableServers,
        selectedVoiceOver: selectedVoiceOver,
        availableVoiceOvers: availableVoiceOvers,
        selectedQuality: q,
        availableQualities: availableQualities,
        subtitles: subtitles,
        headers: headers,
        streamType: streamType,
        openingStart: openingStart,
        openingEnd: openingEnd,
        endingStart: endingStart,
        endingEnd: endingEnd,
        refresh: refresh,
      );

  NormalizedStreamBundle withRefresh(
    Future<NormalizedStreamBundle> Function() cb,
  ) => NormalizedStreamBundle(
    addonId: addonId,
    episode: episode,
    selectedServer: selectedServer,
    availableServers: availableServers,
    selectedVoiceOver: selectedVoiceOver,
    availableVoiceOvers: availableVoiceOvers,
    selectedQuality: selectedQuality,
    availableQualities: availableQualities,
    subtitles: subtitles,
    headers: headers,
    streamType: streamType,
    openingStart: openingStart,
    openingEnd: openingEnd,
    endingStart: endingStart,
    endingEnd: endingEnd,
    refresh: cb,
  );
}
