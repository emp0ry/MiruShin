import '../../../shared/models/media_item.dart';
import '../../metadata/domain/anime_episode_metadata.dart';
import '../../watch/domain/normalized_models.dart';

enum StreamType { mp4, hls, dash, unknown }

/// Native playback engine used by PlayerEngineFactory.
///
/// Auto uses FVP on Linux so libmpv is not loaded into the process. Other
/// native platforms use MediaKit first, retry direct when the local proxy
/// fails, then fall back to FVP before trying the next source.
enum PlayerBackend { auto, mpv, fvp }

extension PlayerBackendLabel on PlayerBackend {
  String get title {
    switch (this) {
      case PlayerBackend.auto:
        return 'Auto';
      case PlayerBackend.mpv:
        return 'MPV / MediaKit';
      case PlayerBackend.fvp:
        return 'FVP / MDK';
    }
  }

  String get description {
    switch (this) {
      case PlayerBackend.auto:
        return 'Recommended. Uses FVP on Linux; elsewhere tries MPV with proxy, MPV direct, then FVP.';
      case PlayerBackend.mpv:
        return 'MPV-like backend. Best for HLS, buffering, subtitles and speed.';
      case PlayerBackend.fvp:
        return 'Legacy FVP / MDK backend with improved buffering fallback.';
    }
  }
}

StreamType streamTypeFrom(String s) {
  switch (s.toUpperCase()) {
    case 'HLS':
      return StreamType.hls;
    case 'MP4':
      return StreamType.mp4;
    case 'DASH':
      return StreamType.dash;
    default:
      return StreamType.unknown;
  }
}

class StreamQuality {
  const StreamQuality({
    required this.id,
    required this.label,
    required this.url,
    this.headers = const <String, String>{},
    this.height,
    this.bitrate,
    this.isAuto = false,
  });

  final String id;
  final String label;
  final String url;
  final Map<String, String> headers;
  final int? height;
  final int? bitrate;
  final bool isAuto;

  static const StreamQuality auto = StreamQuality(
    id: 'auto',
    label: 'Auto',
    url: '',
    isAuto: true,
  );
}

class VoiceOverTrack {
  const VoiceOverTrack({
    required this.id,
    required this.label,
    this.url,
    this.headers = const <String, String>{},
    this.qualities = const <StreamQuality>[],
    this.subtitles = const <SubtitleTrack>[],
    this.streamType = StreamType.unknown,
  });

  final String id;
  final String label;
  final String? url;
  final Map<String, String> headers;
  final List<StreamQuality> qualities;
  final List<SubtitleTrack> subtitles;
  final StreamType streamType;
}

enum SubtitleFormat { srt, vtt, ass, unknown }

class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.label,
    required this.url,
    this.language = '',
    this.format = SubtitleFormat.unknown,
    this.headers = const <String, String>{},
  });

  final String id;
  final String label;
  final String url;
  final String language;
  final SubtitleFormat format;
  final Map<String, String> headers;
}

class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  bool contains(Duration position, Duration offset) {
    final Duration adjusted = position + offset;
    return adjusted >= start && adjusted <= end;
  }
}

enum SkipMarkersSource { addon, mirushin }

class SkipMarkers {
  const SkipMarkers({
    this.openingStart,
    this.openingEnd,
    this.endingStart,
    this.endingEnd,
  });

  final Duration? openingStart;
  final Duration? openingEnd;
  final Duration? endingStart;
  final Duration? endingEnd;

  bool get hasOpening => openingStart != null && openingEnd != null;
  bool get hasEnding => endingStart != null && endingEnd != null;
  bool get isEmpty => !hasOpening && !hasEnding;

  SkipMarkers withFallback(SkipMarkers fallback) {
    return SkipMarkers(
      openingStart: hasOpening ? openingStart : fallback.openingStart,
      openingEnd: hasOpening ? openingEnd : fallback.openingEnd,
      endingStart: hasEnding ? endingStart : fallback.endingStart,
      endingEnd: hasEnding ? endingEnd : fallback.endingEnd,
    );
  }
}

class Episode {
  const Episode({
    required this.id,
    required this.number,
    required this.title,
    this.thumbnailUrl = '',
    this.duration,
    this.progress = Duration.zero,
  });

  final String id;
  final int number;
  final String title;
  final String thumbnailUrl;
  final Duration? duration;
  final Duration progress;
}

class Season {
  const Season({
    required this.number,
    required this.title,
    required this.episodes,
  });

  final int number;
  final String title;
  final List<Episode> episodes;
}

class MediaServer {
  const MediaServer({
    required this.id,
    required this.name,
    required this.sourceName,
    required this.url,
    this.headers = const <String, String>{},
    this.streamType = StreamType.unknown,
    this.qualities = const <StreamQuality>[],
    this.voiceovers = const <VoiceOverTrack>[],
    this.subtitles = const <SubtitleTrack>[],
  });

  final String id;
  final String name;
  final String sourceName;
  final String url;
  final Map<String, String> headers;
  final StreamType streamType;
  final List<StreamQuality> qualities;
  final List<VoiceOverTrack> voiceovers;
  final List<SubtitleTrack> subtitles;
}

class PlayerSettings {
  const PlayerSettings({
    this.seekInterval = const Duration(seconds: 10),
    this.playbackSpeed = 1,
    this.volume = 1,
    this.verticalStretch = false,
    this.preferredQuality = 'auto',
    this.preferredVoiceover = '',
    this.preferredSubtitleLanguage = '',
    this.subtitlesEnabled = true,
    this.subtitleFontSize = 22,
    this.subtitleBottomOffset = 82,
    this.subtitleDelay = Duration.zero,
    this.subtitleTextColor = 0xFFFFFFFF,
    this.subtitleHasBackground = true,
    this.subtitleBackgroundOpacity = 0.38,
    this.showSkipButtons = true,
    this.showSkipOpeningButton = true,
    this.showSkipEndingButton = true,
    this.showNextEpisodeButton = true,
    this.autoSkipOpening = false,
    this.autoSkipEnding = false,
    this.useAniSkip = true,
    this.skipMarkersSource = SkipMarkersSource.addon,
    this.autoplayNext = true,
    this.discordRpcEnabled = true,
    this.autoAnilistSync = true,
    this.debugStreamInfo = false,
    this.playerBackend = PlayerBackend.auto,
  });

  final Duration seekInterval;
  final double playbackSpeed;
  final double volume;
  final bool verticalStretch;
  final String preferredQuality;
  final String preferredVoiceover;
  final String preferredSubtitleLanguage;
  final bool subtitlesEnabled;
  final double subtitleFontSize;
  final double subtitleBottomOffset;
  final Duration subtitleDelay;
  final int subtitleTextColor;
  final bool subtitleHasBackground;
  final double subtitleBackgroundOpacity;
  final bool showSkipButtons;
  final bool showSkipOpeningButton;
  final bool showSkipEndingButton;
  final bool showNextEpisodeButton;
  final bool autoSkipOpening;
  final bool autoSkipEnding;
  final bool useAniSkip;
  final SkipMarkersSource skipMarkersSource;
  final bool autoplayNext;
  final bool discordRpcEnabled;
  final bool autoAnilistSync;
  final bool debugStreamInfo;
  final PlayerBackend playerBackend;

  PlayerSettings copyWith({
    Duration? seekInterval,
    double? playbackSpeed,
    double? volume,
    bool? verticalStretch,
    String? preferredQuality,
    String? preferredVoiceover,
    String? preferredSubtitleLanguage,
    bool? subtitlesEnabled,
    double? subtitleFontSize,
    double? subtitleBottomOffset,
    Duration? subtitleDelay,
    int? subtitleTextColor,
    bool? subtitleHasBackground,
    double? subtitleBackgroundOpacity,
    bool? showSkipButtons,
    bool? showSkipOpeningButton,
    bool? showSkipEndingButton,
    bool? showNextEpisodeButton,
    bool? autoSkipOpening,
    bool? autoSkipEnding,
    bool? useAniSkip,
    SkipMarkersSource? skipMarkersSource,
    bool? autoplayNext,
    bool? discordRpcEnabled,
    bool? autoAnilistSync,
    bool? debugStreamInfo,
    PlayerBackend? playerBackend,
  }) {
    return PlayerSettings(
      seekInterval: seekInterval ?? this.seekInterval,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      volume: volume ?? this.volume,
      verticalStretch: verticalStretch ?? this.verticalStretch,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      preferredVoiceover: preferredVoiceover ?? this.preferredVoiceover,
      preferredSubtitleLanguage:
          preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleBottomOffset: subtitleBottomOffset ?? this.subtitleBottomOffset,
      subtitleDelay: subtitleDelay ?? this.subtitleDelay,
      subtitleTextColor: subtitleTextColor ?? this.subtitleTextColor,
      subtitleHasBackground:
          subtitleHasBackground ?? this.subtitleHasBackground,
      subtitleBackgroundOpacity:
          subtitleBackgroundOpacity ?? this.subtitleBackgroundOpacity,
      showSkipButtons: showSkipButtons ?? this.showSkipButtons,
      showSkipOpeningButton:
          showSkipOpeningButton ?? this.showSkipOpeningButton,
      showSkipEndingButton: showSkipEndingButton ?? this.showSkipEndingButton,
      showNextEpisodeButton:
          showNextEpisodeButton ?? this.showNextEpisodeButton,
      autoSkipOpening: autoSkipOpening ?? this.autoSkipOpening,
      autoSkipEnding: autoSkipEnding ?? this.autoSkipEnding,
      useAniSkip: useAniSkip ?? this.useAniSkip,
      skipMarkersSource: skipMarkersSource ?? this.skipMarkersSource,
      autoplayNext: autoplayNext ?? this.autoplayNext,
      discordRpcEnabled: discordRpcEnabled ?? this.discordRpcEnabled,
      autoAnilistSync: autoAnilistSync ?? this.autoAnilistSync,
      debugStreamInfo: debugStreamInfo ?? this.debugStreamInfo,
      playerBackend: playerBackend ?? this.playerBackend,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'seekInterval': seekInterval.inSeconds,
    'playbackSpeed': playbackSpeed,
    'volume': volume,
    'verticalStretch': verticalStretch,
    'preferredQuality': preferredQuality,
    'preferredVoiceover': preferredVoiceover,
    'preferredSubtitleLanguage': preferredSubtitleLanguage,
    'subtitlesEnabled': subtitlesEnabled,
    'subtitleFontSize': subtitleFontSize,
    'subtitleBottomOffset': subtitleBottomOffset,
    'subtitleDelayMs': subtitleDelay.inMilliseconds,
    'subtitleTextColor': subtitleTextColor,
    'subtitleHasBackground': subtitleHasBackground,
    'subtitleBackgroundOpacity': subtitleBackgroundOpacity,
    'showSkipButtons': showSkipButtons,
    'showSkipOpeningButton': showSkipOpeningButton,
    'showSkipEndingButton': showSkipEndingButton,
    'showNextEpisodeButton': showNextEpisodeButton,
    'autoSkipOpening': autoSkipOpening,
    'autoSkipEnding': autoSkipEnding,
    'useAniSkip': useAniSkip,
    'skipMarkersSource': skipMarkersSource.name,
    'autoplayNext': autoplayNext,
    'discordRpcEnabled': discordRpcEnabled,
    'autoAnilistSync': autoAnilistSync,
    'debugStreamInfo': debugStreamInfo,
    'playerBackend': playerBackend.name,
  };

  factory PlayerSettings.fromJson(Map<String, Object?> json) {
    final bool legacyShowSkipButtons = json['showSkipButtons'] as bool? ?? true;
    return PlayerSettings(
      seekInterval: Duration(
        seconds: (json['seekInterval'] as num?)?.toInt() ?? 10,
      ),
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1,
      volume: ((json['volume'] as num?)?.toDouble() ?? 1)
          .clamp(0.0, 1.0)
          .toDouble(),
      verticalStretch: json['verticalStretch'] as bool? ?? false,
      preferredQuality: json['preferredQuality'] as String? ?? 'auto',
      preferredVoiceover: json['preferredVoiceover'] as String? ?? '',
      preferredSubtitleLanguage:
          json['preferredSubtitleLanguage'] as String? ?? '',
      subtitlesEnabled: json['subtitlesEnabled'] as bool? ?? true,
      subtitleFontSize: (json['subtitleFontSize'] as num?)?.toDouble() ?? 22,
      subtitleBottomOffset:
          (json['subtitleBottomOffset'] as num?)?.toDouble() ?? 82,
      subtitleDelay: Duration(
        milliseconds: (json['subtitleDelayMs'] as num?)?.toInt() ?? 0,
      ),
      subtitleTextColor:
          (json['subtitleTextColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
      subtitleHasBackground: json['subtitleHasBackground'] as bool? ?? true,
      subtitleBackgroundOpacity:
          (json['subtitleBackgroundOpacity'] as num?)?.toDouble() ?? 0.38,
      showSkipButtons: legacyShowSkipButtons,
      showSkipOpeningButton:
          json['showSkipOpeningButton'] as bool? ?? legacyShowSkipButtons,
      showSkipEndingButton:
          json['showSkipEndingButton'] as bool? ?? legacyShowSkipButtons,
      showNextEpisodeButton: json['showNextEpisodeButton'] as bool? ?? true,
      autoSkipOpening: json['autoSkipOpening'] as bool? ?? false,
      autoSkipEnding: json['autoSkipEnding'] as bool? ?? false,
      useAniSkip: json['useAniSkip'] as bool? ?? true,
      skipMarkersSource: SkipMarkersSource.values.firstWhere(
        (SkipMarkersSource s) => s.name == json['skipMarkersSource'],
        orElse: () => SkipMarkersSource.addon,
      ),
      autoplayNext: json['autoplayNext'] as bool? ?? true,
      discordRpcEnabled: json['discordRpcEnabled'] as bool? ?? true,
      autoAnilistSync: json['autoAnilistSync'] as bool? ?? true,
      debugStreamInfo: json['debugStreamInfo'] as bool? ?? false,
      playerBackend: PlayerBackend.values.firstWhere(
        (PlayerBackend value) => value.name == json['playerBackend'],
        orElse: () => PlayerBackend.auto,
      ),
    );
  }
}

class MediaPlaybackItem {
  const MediaPlaybackItem({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.servers,
    this.subtitle = '',
    this.originalTitle = '',
    this.posterUrl = '',
    this.backdropUrl = '',
    this.externalIds = const <String, String>{},
    this.seasons = const <Season>[],
    this.currentEpisodeId,
    this.skipMarkers = const SkipMarkers(),
    this.startPosition = Duration.zero,
    this.seasonNumber = 1,
    this.episodeNumber = 1.0,
    this.episodeCount,
    this.ignoreProgress = false,
  });

  final String id;
  final String title;
  final MediaType mediaType;
  final String originalTitle;
  final String subtitle;
  final String posterUrl;
  final String backdropUrl;
  final Map<String, String> externalIds;
  final List<MediaServer> servers;
  final List<Season> seasons;
  final String? currentEpisodeId;
  final SkipMarkers skipMarkers;
  final Duration startPosition;
  final int seasonNumber;
  final double episodeNumber;
  final int? episodeCount;
  final bool ignoreProgress;

  Episode? get currentEpisode {
    for (final Season season in seasons) {
      for (final Episode episode in season.episodes) {
        if (episode.id == currentEpisodeId) return episode;
      }
    }
    return null;
  }

  factory MediaPlaybackItem.fromBundle(
    NormalizedStreamBundle bundle,
    MediaItem item,
    int seasonNumber, {
    Duration startPosition = Duration.zero,
    bool ignoreProgress = false,
  }) {
    final StreamType streamType = streamTypeFrom(bundle.streamType);

    final List<SubtitleTrack> subtitleTracks = bundle.subtitles
        .map(
          (NormalizedSubtitle s) => SubtitleTrack(
            id: s.url,
            label: s.label.isNotEmpty ? s.label : s.language,
            url: s.url,
            language: s.language,
            format: _subtitleFormat(s.url),
            headers: s.headers,
          ),
        )
        .toList(growable: false);

    final List<VoiceOverTrack> voiceovers = bundle.availableVoiceOvers
        .map(
          (NormalizedVoiceOver v) => VoiceOverTrack(id: v.id, label: v.label),
        )
        .toList(growable: false);

    final String selectedServerId = bundle.selectedServer.id;

    final List<NormalizedServer> orderedServers = <NormalizedServer>[
      ...bundle.availableServers.where(
        (NormalizedServer s) => s.id == selectedServerId,
      ),
      ...bundle.availableServers.where(
        (NormalizedServer s) => s.id != selectedServerId,
      ),
    ];

    final List<MediaServer> servers = orderedServers
        .map((NormalizedServer s) {
          final List<StreamQuality> serverQualities = s.qualities
              .map(
                (NormalizedQuality q) => StreamQuality(
                  id: q.label,
                  label: q.label,
                  url: q.streamUrl,
                  headers: q.headers.isNotEmpty ? q.headers : s.headers,
                ),
              )
              .toList(growable: false);

          return MediaServer(
            id: s.id,
            name: s.title,
            sourceName: bundle.addonId,
            url: s.streamUrl,
            headers: s.headers.isNotEmpty ? s.headers : bundle.headers,
            streamType: streamType,
            qualities: serverQualities,
            voiceovers: voiceovers,
            subtitles: subtitleTracks,
          );
        })
        .toList(growable: false);

    final double episodeNumber = bundle.episode.number;

    final String episodeSubtitle = bestPlayerEpisodeTitle(
      moduleTitle: bundle.episode.title,
      tvdbTitle: bundle.episode.tvdbTitle,
      metadataTitle: bundle.episode.metadataTitle,
      number: episodeNumber,
    );

    return MediaPlaybackItem(
      id: item.id,
      title: item.title,
      mediaType: item.type,
      originalTitle: item.originalTitle,
      subtitle: episodeSubtitle,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      externalIds: item.externalIds,
      servers: servers,
      currentEpisodeId: '${seasonNumber}_$episodeNumber',
      skipMarkers: _skipMarkersFromBundle(bundle),
      startPosition: startPosition,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeCount: _episodeCountForPlayback(item, seasonNumber),
      ignoreProgress: ignoreProgress,
    );
  }
}

int? _episodeCountForPlayback(MediaItem item, int seasonNumber) {
  if (item.type == MediaType.movie) {
    return 1;
  }

  final int? preservedTotal = int.tryParse(
    item.externalIds['mirushin_total_episode_count'] ?? '',
  );
  if (preservedTotal != null && preservedTotal > 0) {
    return preservedTotal;
  }

  final int? fallback = item.episodeCount;
  if (fallback != null && fallback > 0) {
    return fallback;
  }
  return null;
}

SkipMarkers _skipMarkersFromBundle(NormalizedStreamBundle bundle) {
  final int? openingStart = bundle.openingStart ?? bundle.episode.openingStart;
  final int? openingEnd = bundle.openingEnd ?? bundle.episode.openingEnd;
  final int? endingStart = bundle.endingStart ?? bundle.episode.endingStart;
  final int? endingEnd = bundle.endingEnd ?? bundle.episode.endingEnd;

  Duration? opStart;
  Duration? opEnd;
  if (openingStart != null &&
      openingEnd != null &&
      openingStart >= 0 &&
      openingEnd > openingStart) {
    opStart = Duration(seconds: openingStart);
    opEnd = Duration(seconds: openingEnd);
  }

  Duration? edStart;
  Duration? edEnd;
  if (endingStart != null &&
      endingEnd != null &&
      endingStart >= 0 &&
      endingEnd > endingStart) {
    edStart = Duration(seconds: endingStart);
    edEnd = Duration(seconds: endingEnd);
  }

  return SkipMarkers(
    openingStart: opStart,
    openingEnd: opEnd,
    endingStart: edStart,
    endingEnd: edEnd,
  );
}

SubtitleFormat _subtitleFormat(String url) {
  final String lower = url.toLowerCase();
  if (lower.contains('.vtt')) return SubtitleFormat.vtt;
  if (lower.contains('.srt')) return SubtitleFormat.srt;
  if (lower.contains('.ass') || lower.contains('.ssa')) {
    return SubtitleFormat.ass;
  }
  return SubtitleFormat.unknown;
}

class CastDevice {
  const CastDevice({required this.id, required this.name, required this.kind});

  final String id;
  final String name;
  final String kind;
}

class PlayerError {
  const PlayerError({
    required this.title,
    required this.message,
    this.canRetry = true,
  });

  final String title;
  final String message;
  final bool canRetry;
}
