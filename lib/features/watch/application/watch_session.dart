import '../../../shared/models/media_item.dart';
import '../../addons/domain/sora_models.dart';

enum WatchStep {
  pickSeason,
  pickSource,
  pickEpisode,
  resolveStream,
  streamReady,
}

class WatchSession {
  const WatchSession({
    required this.step,
    this.seasonNumber = 1,
    this.source,
    this.episode,
    this.voiceover,
    this.candidate,
    this.error,
    this.isResolving = false,
    this.seasonPicked = false,
  });

  final WatchStep step;
  final int seasonNumber;
  final SoraSearchResult? source;
  final SoraEpisode? episode;
  final String? voiceover;
  final SoraStreamCandidate? candidate;
  final String? error;
  final bool isResolving;
  final bool seasonPicked;

  factory WatchSession.initial(MediaItem item) {
    final bool skipSeason = _skipSeasonPicker(item);
    return WatchSession(
      step: skipSeason ? WatchStep.pickSource : WatchStep.pickSeason,
      seasonNumber: _defaultSeason(item),
    );
  }

  WatchSession copyWith({
    WatchStep? step,
    int? seasonNumber,
    SoraSearchResult? source,
    bool clearSource = false,
    SoraEpisode? episode,
    bool clearEpisode = false,
    String? voiceover,
    bool clearVoiceover = false,
    SoraStreamCandidate? candidate,
    bool clearCandidate = false,
    String? error,
    bool clearError = false,
    bool? isResolving,
    bool? seasonPicked,
  }) {
    return WatchSession(
      step: step ?? this.step,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      source: clearSource ? null : source ?? this.source,
      episode: clearEpisode ? null : episode ?? this.episode,
      voiceover: clearVoiceover ? null : voiceover ?? this.voiceover,
      candidate: clearCandidate ? null : candidate ?? this.candidate,
      error: clearError ? null : error ?? this.error,
      isResolving: isResolving ?? this.isResolving,
      seasonPicked: seasonPicked ?? this.seasonPicked,
    );
  }

  WatchSession resyncForItem(MediaItem item) {
    if (seasonPicked ||
        source != null ||
        episode != null ||
        candidate != null ||
        (step != WatchStep.pickSeason && step != WatchStep.pickSource)) {
      return this;
    }

    final WatchSession realSession = WatchSession.initial(item);
    if (step == realSession.step && seasonNumber == realSession.seasonNumber) {
      return this;
    }
    return realSession;
  }
}

class AutoNextStreamResolutionState {
  String? _activeKey;
  final Set<String> _autoNextKeys = <String>{};

  String? get activeKey => _activeKey;

  void begin(String key, {required bool autoNext}) {
    _activeKey = key;
    if (autoNext) {
      _autoNextKeys.add(key);
    } else {
      _autoNextKeys.remove(key);
    }
  }

  void clear() {
    _activeKey = null;
  }

  bool isCurrent(String key) => key == _activeKey;

  bool takeAutoNext(String key) {
    final bool autoNext = _autoNextKeys.remove(key);
    if (isCurrent(key)) {
      _activeKey = null;
    }
    return autoNext;
  }

  void forget(String key) {
    _autoNextKeys.remove(key);
    if (isCurrent(key)) {
      _activeKey = null;
    }
  }
}

bool _skipSeasonPicker(MediaItem item) {
  if (item.type == MediaType.movie) return true;
  // AniList IDs are individual seasons — skip the franchise season picker.
  if (item.type == MediaType.anime && item.id.startsWith('anilist:')) {
    return true;
  }
  // No season data yet → show picker while details load.
  if (item.seasons.isEmpty) return false;
  final List<MediaSeason> nonSpecial = _regularSeasons(item);
  if (nonSpecial.isEmpty) return false;
  if (nonSpecial.length > 1) return false;
  final MediaSeason only = nonSpecial.first;
  return only.seasonNumber == 1 && only.episodeCount > 0;
}

int _defaultSeason(MediaItem item) {
  // The initial purple outline must follow the same order as the visible
  // season picker. Anime seasons can include movies/OVA entries marked as
  // `isSpecials`, but they are still shown in Choose Season as chronological
  // entries. Using only regular seasons here makes the UI highlight Season 2
  // while the first visible card is still Season 1/movie.
  final List<MediaSeason> selectable = _orderedSelectableSeasons(item);
  return selectable.isEmpty ? 1 : selectable.first.seasonNumber;
}

List<MediaSeason> _regularSeasons(MediaItem item) {
  final List<MediaSeason> seasons = item.seasons
      .where((MediaSeason s) => !s.isSpecials && s.seasonNumber > 0)
      .toList(growable: false);
  _sortSeasons(seasons);
  return seasons;
}

List<MediaSeason> _orderedSelectableSeasons(MediaItem item) {
  final List<MediaSeason> seasons = item.seasons
      .where((MediaSeason s) => s.seasonNumber > 0)
      .toList(growable: false);
  _sortSeasons(seasons);
  return seasons;
}

void _sortSeasons(List<MediaSeason> seasons) {
  seasons.sort((MediaSeason a, MediaSeason b) {
    final int order = a.seasonNumber.compareTo(b.seasonNumber);
    if (order != 0) {
      return order;
    }
    return a.name.compareTo(b.name);
  });
}
