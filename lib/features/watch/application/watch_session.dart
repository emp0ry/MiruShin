import '../../../shared/models/media_item.dart';
import '../../addons/domain/sora_models.dart';

enum WatchStep {
  pickSeason,
  pickSource,
  pickSourceSeason,
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
    if (_usesTmdbSourceFirstFlow(item)) {
      return WatchSession(
        step: WatchStep.pickSource,
        seasonNumber: _defaultSeason(item),
      );
    }
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
  final Map<String, AutoNextStreamResolutionClaim> _claims =
      <String, AutoNextStreamResolutionClaim>{};

  String? get activeKey => _activeKey;

  void begin(
    String key, {
    required bool autoNext,
    int? transitionId,
    int resolutionAttempt = 1,
  }) {
    _activeKey = key;
    _claims[key] = AutoNextStreamResolutionClaim(
      isAutoNext: autoNext,
      transitionId: transitionId,
      resolutionAttempt: resolutionAttempt,
    );
  }

  void clear() {
    _activeKey = null;
    _claims.clear();
  }

  bool isCurrent(String key) => key == _activeKey;

  bool takeAutoNext(String key) {
    return take(key)?.isAutoNext ?? false;
  }

  AutoNextStreamResolutionClaim? take(String key) {
    final AutoNextStreamResolutionClaim? claim = _claims.remove(key);
    if (isCurrent(key)) {
      _activeKey = null;
    }
    return claim;
  }

  void forget(String key) {
    _claims.remove(key);
    if (isCurrent(key)) {
      _activeKey = null;
    }
  }
}

class AutoNextStreamResolutionClaim {
  const AutoNextStreamResolutionClaim({
    required this.isAutoNext,
    required this.transitionId,
    required this.resolutionAttempt,
  });

  final bool isAutoNext;
  final int? transitionId;
  final int resolutionAttempt;
}

enum EpisodeAdvanceState {
  requested,
  findingNext,
  resolvingNext,
  openingNext,
  completed,
  failed,
  noNext,
  cancelled,
}

class EpisodeAdvanceOperation {
  const EpisodeAdvanceOperation({
    required this.id,
    required this.currentKey,
    required this.reason,
    required this.state,
  });

  final int id;
  final String currentKey;
  final String reason;
  final EpisodeAdvanceState state;

  EpisodeAdvanceOperation withState(EpisodeAdvanceState value) =>
      EpisodeAdvanceOperation(
        id: id,
        currentKey: currentKey,
        reason: reason,
        state: value,
      );
}

class EpisodeAdvanceCoordinator {
  int _nextId = 0;
  EpisodeAdvanceOperation? _active;
  final Set<String> _committedCurrentKeys = <String>{};

  EpisodeAdvanceOperation? get active => _active;

  EpisodeAdvanceOperation? begin({
    required String currentKey,
    required String reason,
  }) {
    final EpisodeAdvanceOperation? active = _active;
    if (active != null) return null;
    if (_committedCurrentKeys.contains(currentKey)) return null;
    return _active = EpisodeAdvanceOperation(
      id: ++_nextId,
      currentKey: currentKey,
      reason: reason,
      state: EpisodeAdvanceState.requested,
    );
  }

  bool move(int id, EpisodeAdvanceState state) {
    final EpisodeAdvanceOperation? current = _active;
    if (current == null || current.id != id) return false;
    _active = current.withState(state);
    return true;
  }

  bool complete(int id) {
    final EpisodeAdvanceOperation? current = _active;
    if (current == null || current.id != id) return false;
    _committedCurrentKeys.add(current.currentKey);
    _active = null;
    return true;
  }

  bool fail(int id) => _finishWithoutCommit(id);

  bool noNext(int id) => _finishWithoutCommit(id);

  bool cancel(int id) => _finishWithoutCommit(id);

  bool _finishWithoutCommit(int id) {
    final EpisodeAdvanceOperation? current = _active;
    if (current == null || current.id != id) return false;
    _active = null;
    return true;
  }

  void reset() {
    _active = null;
    _committedCurrentKeys.clear();
  }
}

class SoraNextEpisodeLookup {
  const SoraNextEpisodeLookup({required this.episode, required this.reason});

  final SoraEpisode? episode;
  final String reason;
}

SoraNextEpisodeLookup findNextSoraEpisode({
  required List<SoraEpisode> episodes,
  required String currentHref,
  required int currentSeason,
  required double currentNumber,
}) {
  if (episodes.isEmpty) {
    return const SoraNextEpisodeLookup(
      episode: null,
      reason: 'provider-list-empty',
    );
  }
  final String exactHref = currentHref.trim();
  final String normalizedHref = normalizeEpisodeHref(exactHref);
  SoraEpisode? matched;
  for (final SoraEpisode episode in episodes) {
    if (episode.href.trim() == exactHref) {
      matched = episode;
      break;
    }
  }
  matched ??= episodes.cast<SoraEpisode?>().firstWhere(
    (SoraEpisode? episode) =>
        episode != null &&
        normalizedHref.isNotEmpty &&
        normalizeEpisodeHref(episode.href) == normalizedHref,
    orElse: () => null,
  );
  matched ??= episodes.cast<SoraEpisode?>().firstWhere(
    (SoraEpisode? episode) =>
        episode != null &&
        episode.number == currentNumber &&
        (currentSeason <= 0 || episode.season == currentSeason),
    orElse: () => null,
  );

  final int logicalSeason = matched?.season ?? currentSeason;
  final double logicalNumber = matched?.number ?? currentNumber;
  if (logicalNumber <= 0) {
    final int index = matched == null ? -1 : episodes.indexOf(matched);
    return SoraNextEpisodeLookup(
      episode: index >= 0 && index + 1 < episodes.length
          ? episodes[index + 1]
          : null,
      reason: index < 0 ? 'current-not-found' : 'provider-order-fallback',
    );
  }

  final List<SoraEpisode> candidates =
      episodes
          .where((SoraEpisode episode) {
            if (episode.number <= 0) return false;
            final int season = episode.season;
            if (logicalSeason > 0 && season > 0) {
              return season > logicalSeason ||
                  (season == logicalSeason && episode.number > logicalNumber);
            }
            return episode.number > logicalNumber;
          })
          .toList(growable: false)
        ..sort((SoraEpisode left, SoraEpisode right) {
          if (logicalSeason > 0 && left.season > 0 && right.season > 0) {
            final int season = left.season.compareTo(right.season);
            if (season != 0) return season;
          }
          final int number = left.number.compareTo(right.number);
          if (number != 0) return number;
          return normalizeEpisodeHref(
            left.href,
          ).compareTo(normalizeEpisodeHref(right.href));
        });
  return SoraNextEpisodeLookup(
    episode: candidates.isEmpty ? null : candidates.first,
    reason: candidates.isEmpty ? 'final-episode' : 'logical-successor',
  );
}

String normalizeEpisodeHref(String value) {
  final String trimmed = value.trim();
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
  final Map<String, List<String>> query = <String, List<String>>{
    for (final MapEntry<String, List<String>> entry
        in uri.queryParametersAll.entries)
      if (!_rotatingEpisodeQueryKey(entry.key)) entry.key: entry.value,
  };
  final String path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: path,
        query: query.isEmpty ? '' : null,
        queryParameters: query.isEmpty ? null : query,
        fragment: '',
      )
      .toString();
}

bool sameSoraPlaybackEpisode(SoraEpisode expected, SoraEpisode actual) {
  return expected.href.trim() == actual.href.trim() &&
      expected.number == actual.number &&
      expected.season == actual.season;
}

bool _rotatingEpisodeQueryKey(String value) {
  final String key = value.toLowerCase().replaceAll('_', '-');
  return key == 'token' ||
      key == 'expires' ||
      key == 'expiry' ||
      key == 'exp' ||
      key == 'signature' ||
      key == 'sig' ||
      key.startsWith('x-amz-') ||
      key.startsWith('x-goog-');
}

bool _skipSeasonPicker(MediaItem item) {
  if (item.type == MediaType.movie) return true;
  // Skip the franchise season picker because AniList IDs represent individual seasons.
  if (item.type == MediaType.anime && item.id.startsWith('anilist:')) {
    return true;
  }
  // No season data yet -> show picker while details load.
  if (item.seasons.isEmpty) return false;
  final List<MediaSeason> nonSpecial = _regularSeasons(item);
  if (nonSpecial.isEmpty) return false;
  if (nonSpecial.length > 1) return false;
  final MediaSeason only = nonSpecial.first;
  return only.seasonNumber == 1 && only.episodeCount > 0;
}

bool _usesTmdbSourceFirstFlow(MediaItem item) {
  if (item.type == MediaType.movie) return false;
  if (item.id.startsWith('tmdb:')) return true;
  return item.sourceProvider.trim().toLowerCase() == 'tmdb';
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
