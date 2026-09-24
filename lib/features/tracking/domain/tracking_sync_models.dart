import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import 'tracker_models.dart';

enum UserMediaField {
  status,
  progress,
  progressVolumes,
  score,
  notes,
  repeat,
  startedAt,
  completedAt,
  priority,
  private,
  hiddenFromStatusLists,
  customLists,
  advancedScores,
  scoreFormat,
  malPriority,
  malRewatchValue,
  malTags,
  favorite,
}

/// Stable, provider-independent identity. [localId] never changes after an
/// identity has been persisted; newly discovered provider ids are merged into
/// the same record.
class MediaIdentity {
  const MediaIdentity({
    required this.localId,
    this.kind,
    this.anilistId,
    this.malId,
    this.shikimoriId,
  });

  factory MediaIdentity.fromExternalIds(
    Map<String, String> externalIds, {
    String? mediaId,
  }) {
    final int? anilistId =
        _positiveInt(externalIds['anilist']) ??
        _idFromMediaId(mediaId, 'anilist');
    final int? malId =
        _positiveInt(externalIds['mal']) ?? _idFromMediaId(mediaId, 'mal');
    final int? shikimoriId =
        _positiveInt(externalIds['shikimori']) ??
        _idFromMediaId(mediaId, 'shikimori');
    final String kind =
        externalIds['anilist_type'] == 'MANGA' ||
            (mediaId ?? '').startsWith('anilist:manga:')
        ? 'manga'
        : 'anime';
    return MediaIdentity(
      localId: _defaultLocalId(
        kind: kind,
        anilistId: anilistId,
        malId: malId,
        shikimoriId: shikimoriId,
      ),
      kind: kind,
      anilistId: anilistId,
      malId: malId,
      shikimoriId: shikimoriId,
    );
  }

  factory MediaIdentity.fromJson(Map<String, dynamic> json) {
    final int? anilistId = _positiveInt(json['anilistId']);
    final int? malId = _positiveInt(json['malId']);
    final int? shikimoriId = _positiveInt(json['shikimoriId']);
    final String stored = '${json['localId'] ?? ''}'.trim();
    final String? kind = switch ('${json['mediaKind'] ?? json['kind'] ?? ''}'
        .trim()
        .toLowerCase()) {
      'manga' => 'manga',
      'anime' => 'anime',
      _ => null,
    };
    return MediaIdentity(
      localId: stored.isEmpty
          ? _defaultLocalId(
              kind: 'anime',
              anilistId: anilistId,
              malId: malId,
              shikimoriId: shikimoriId,
            )
          : stored,
      kind: kind,
      anilistId: anilistId,
      malId: malId,
      shikimoriId: shikimoriId,
    );
  }

  final String localId;
  final String? kind;
  final int? anilistId;
  final int? malId;
  final int? shikimoriId;

  bool get hasProviderId =>
      anilistId != null || malId != null || shikimoriId != null;

  String get mediaKind =>
      kind ?? (localId.startsWith('manga:') ? 'manga' : 'anime');

  int? idFor(TrackerSource provider) => switch (provider) {
    TrackerSource.anilist => anilistId,
    TrackerSource.mal => malId,
    TrackerSource.shikimori => shikimoriId,
  };

  bool matches(MediaIdentity other) {
    if (mediaKind != other.mediaKind) return false;
    if (localId == other.localId) return true;
    return (anilistId != null && anilistId == other.anilistId) ||
        (malId != null && malId == other.malId) ||
        (shikimoriId != null && shikimoriId == other.shikimoriId);
  }

  MediaIdentity merge(MediaIdentity other) {
    return MediaIdentity(
      localId: localId,
      kind: mediaKind,
      anilistId: anilistId ?? other.anilistId,
      malId: malId ?? other.malId,
      shikimoriId: shikimoriId ?? other.shikimoriId,
    );
  }

  Map<String, String> mergeExternalIds(Map<String, String> ids) {
    return <String, String>{
      ...ids,
      if (anilistId != null) 'anilist': '$anilistId',
      if (malId != null) 'mal': '$malId',
      if (shikimoriId != null) 'shikimori': '$shikimoriId',
      if (mediaKind == 'manga') 'anilist_type': 'MANGA',
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'localId': localId,
    'mediaKind': mediaKind,
    if (anilistId != null) 'anilistId': anilistId,
    if (malId != null) 'malId': malId,
    if (shikimoriId != null) 'shikimoriId': shikimoriId,
  };

  static String _defaultLocalId({
    required String kind,
    required int? anilistId,
    required int? malId,
    required int? shikimoriId,
  }) {
    if (malId != null) return '$kind:mal:$malId';
    if (anilistId != null) return '$kind:anilist:$anilistId';
    if (shikimoriId != null) return '$kind:shikimori:$shikimoriId';
    return '$kind:unresolved';
  }

  static int? _idFromMediaId(String? mediaId, String provider) {
    final List<String> parts = (mediaId ?? '').split(':');
    if (parts.length < 2 || parts.first != provider) return null;
    return _positiveInt(parts.last);
  }
}

/// Raw remote representation retained alongside the canonical state. This is
/// deliberately opaque so a write to one provider cannot erase fields owned by
/// another provider.
class ProviderUserMediaState {
  const ProviderUserMediaState({
    required this.provider,
    this.entryId,
    this.rawStatus,
    this.rawScore,
    this.updatedAt,
    this.data = const <String, dynamic>{},
  });

  factory ProviderUserMediaState.fromJson(Map<String, dynamic> json) {
    final Object? rawData = json['data'];
    return ProviderUserMediaState(
      provider: TrackerSource.fromName(json['provider']?.toString()),
      entryId: _positiveInt(json['entryId']),
      rawStatus: json['rawStatus']?.toString(),
      rawScore: (json['rawScore'] as num?)?.toDouble(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      data: rawData is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
    );
  }

  final TrackerSource provider;
  final int? entryId;
  final String? rawStatus;
  final double? rawScore;
  final DateTime? updatedAt;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'provider': provider.name,
    if (entryId != null) 'entryId': entryId,
    if (rawStatus != null) 'rawStatus': rawStatus,
    if (rawScore != null) 'rawScore': rawScore,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    if (data.isNotEmpty) 'data': data,
  };
}

class UserMediaState {
  const UserMediaState({
    required this.identity,
    required this.mediaItem,
    required this.status,
    required this.progress,
    this.progressVolumes = 0,
    this.score,
    this.notes = '',
    this.repeat = 0,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.nextEpisode,
    this.airingAt,
    this.avgScore,
    this.format,
    required this.source,
    this.providerStates = const <TrackerSource, ProviderUserMediaState>{},
  });

  factory UserMediaState.fromJson(Map<String, dynamic> json) {
    final Object? providerStatesJson = json['providerStates'];
    final Map<TrackerSource, ProviderUserMediaState> providerStates =
        <TrackerSource, ProviderUserMediaState>{};
    if (providerStatesJson is Map) {
      for (final Object? value in providerStatesJson.values) {
        if (value is! Map) continue;
        final ProviderUserMediaState state = ProviderUserMediaState.fromJson(
          Map<String, dynamic>.from(value),
        );
        providerStates[state.provider] = state;
      }
    }
    final DateTime updatedAt =
        DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime(1970);
    return UserMediaState(
      identity: MediaIdentity.fromJson(
        Map<String, dynamic>.from(json['identity'] as Map? ?? const {}),
      ),
      mediaItem: MediaItem.fromJson(
        Map<String, dynamic>.from(json['mediaItem'] as Map? ?? const {}),
      ),
      status: _statusFromName(json['status']?.toString()),
      progress: _nonNegativeInt(json['progress']),
      progressVolumes: _nonNegativeInt(json['progressVolumes']),
      score: (json['score'] as num?)?.toDouble(),
      notes: '${json['notes'] ?? ''}',
      repeat: _nonNegativeInt(json['repeat']),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? updatedAt,
      updatedAt: updatedAt,
      startedAt: DateTime.tryParse('${json['startedAt'] ?? ''}'),
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      nextEpisode: _positiveInt(json['nextEpisode']),
      airingAt: DateTime.tryParse('${json['airingAt'] ?? ''}'),
      avgScore: _positiveInt(json['avgScore']),
      format: _nullableTrimmedString(json['format']),
      source: TrackerSource.fromName(json['source']?.toString()),
      providerStates: providerStates,
    );
  }

  final MediaIdentity identity;
  final MediaItem mediaItem;
  final AniListListStatus status;
  final int progress;
  final int progressVolumes;
  final double? score;
  final String notes;
  final int repeat;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? nextEpisode;
  final DateTime? airingAt;
  final int? avgScore;
  final String? format;
  final TrackerSource source;
  final Map<TrackerSource, ProviderUserMediaState> providerStates;

  UserMediaState apply(
    UserMediaPatch patch,
    DateTime timestamp, {
    TrackerSource? providerSource,
  }) {
    if (patch.delete) return this;
    final AniListListStatus nextStatus = patch.touches(UserMediaField.status)
        ? patch.status ?? status
        : status;
    final int nextProgress = patch.touches(UserMediaField.progress)
        ? canonicalEpisodeProgress(
            patch.progress ?? progress,
            mediaItem.episodeCount,
          )
        : canonicalEpisodeProgress(progress, mediaItem.episodeCount);
    final bool hasStarted =
        nextProgress > 0 ||
        nextStatus == AniListListStatus.current ||
        nextStatus == AniListListStatus.repeating ||
        nextStatus == AniListListStatus.completed;
    final bool touchesStartedState =
        patch.touches(UserMediaField.status) ||
        patch.touches(UserMediaField.progress);
    final TrackerSource snapshotSource = providerSource ?? source;
    final ProviderUserMediaState? currentProvider =
        providerStates[snapshotSource];
    final Map<String, dynamic> providerData = <String, dynamic>{
      ...?currentProvider?.data,
      if (patch.touches(UserMediaField.progressVolumes))
        'progressVolumes': patch.progressVolumes,
      if (patch.touches(UserMediaField.startedAt))
        'startedAt': patch.startedAt?.toIso8601String(),
      if (patch.touches(UserMediaField.completedAt))
        'completedAt': patch.completedAt?.toIso8601String(),
    };
    final Map<TrackerSource, ProviderUserMediaState> nextProviderStates =
        <TrackerSource, ProviderUserMediaState>{...providerStates};
    if (currentProvider != null || providerData.isNotEmpty) {
      nextProviderStates[snapshotSource] = ProviderUserMediaState(
        provider: snapshotSource,
        entryId: currentProvider?.entryId,
        rawStatus: currentProvider?.rawStatus,
        rawScore: currentProvider?.rawScore,
        updatedAt: timestamp,
        data: providerData,
      );
    }
    if (patch.touches(UserMediaField.priority) ||
        patch.touches(UserMediaField.private) ||
        patch.touches(UserMediaField.hiddenFromStatusLists) ||
        patch.touches(UserMediaField.customLists) ||
        patch.touches(UserMediaField.advancedScores) ||
        patch.touches(UserMediaField.scoreFormat)) {
      final ProviderUserMediaState? aniList =
          nextProviderStates[TrackerSource.anilist];
      nextProviderStates[TrackerSource.anilist] = ProviderUserMediaState(
        provider: TrackerSource.anilist,
        entryId: aniList?.entryId,
        rawStatus: aniList?.rawStatus,
        rawScore: aniList?.rawScore,
        updatedAt: timestamp,
        data: <String, dynamic>{
          ...?aniList?.data,
          if (patch.touches(UserMediaField.priority))
            'priority': patch.priority,
          if (patch.touches(UserMediaField.private)) 'private': patch.private,
          if (patch.touches(UserMediaField.hiddenFromStatusLists))
            'hiddenFromStatusLists': patch.hiddenFromStatusLists,
          if (patch.touches(UserMediaField.customLists))
            'customLists': patch.customLists,
          if (patch.touches(UserMediaField.advancedScores))
            'advancedScores': patch.advancedScores,
          if (patch.touches(UserMediaField.scoreFormat))
            'scoreFormat': patch.scoreFormat,
        },
      );
    }
    if (patch.touches(UserMediaField.malPriority) ||
        patch.touches(UserMediaField.malRewatchValue) ||
        patch.touches(UserMediaField.malTags)) {
      final ProviderUserMediaState? mal = nextProviderStates[TrackerSource.mal];
      nextProviderStates[TrackerSource.mal] = ProviderUserMediaState(
        provider: TrackerSource.mal,
        entryId: mal?.entryId,
        rawStatus: mal?.rawStatus,
        rawScore: mal?.rawScore,
        updatedAt: timestamp,
        data: <String, dynamic>{
          ...?mal?.data,
          if (patch.touches(UserMediaField.malPriority))
            'priority': patch.malPriority,
          if (patch.touches(UserMediaField.malRewatchValue))
            (identity.mediaKind == 'manga' ? 'rereadValue' : 'rewatchValue'):
                patch.malRewatchValue,
          if (patch.touches(UserMediaField.malTags)) 'tags': patch.malTags,
        },
      );
    }
    return UserMediaState(
      identity: identity,
      mediaItem: mediaItem,
      status: nextStatus,
      progress: nextProgress,
      progressVolumes: patch.touches(UserMediaField.progressVolumes)
          ? (patch.progressVolumes ?? progressVolumes).clamp(0, 0x7fffffff)
          : progressVolumes,
      score: patch.touches(UserMediaField.score)
          ? normalizeCanonicalScore(patch.score)
          : score,
      notes: patch.touches(UserMediaField.notes) ? patch.notes ?? notes : notes,
      repeat: patch.touches(UserMediaField.repeat)
          ? (patch.repeat ?? repeat).clamp(0, 0x7fffffff)
          : repeat,
      createdAt: createdAt,
      updatedAt: timestamp,
      startedAt: patch.touches(UserMediaField.startedAt)
          ? patch.startedAt
          : startedAt ?? (touchesStartedState && hasStarted ? timestamp : null),
      completedAt: patch.touches(UserMediaField.completedAt)
          ? patch.completedAt
          : completedAt ??
                (patch.touches(UserMediaField.status) &&
                        nextStatus == AniListListStatus.completed
                    ? timestamp
                    : null),
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      avgScore: avgScore,
      format: format,
      source: source,
      providerStates: nextProviderStates,
    );
  }

  UserMediaState withIdentity(MediaIdentity next) {
    return UserMediaState(
      identity: next,
      mediaItem: mediaItem.copyWith(
        externalIds: next.mergeExternalIds(mediaItem.externalIds),
      ),
      status: status,
      progress: progress,
      progressVolumes: progressVolumes,
      score: score,
      notes: notes,
      repeat: repeat,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      avgScore: avgScore,
      format: format,
      source: source,
      providerStates: providerStates,
    );
  }

  UserMediaState withMediaItem(MediaItem next) {
    return UserMediaState(
      identity: identity,
      mediaItem: next.copyWith(
        externalIds: identity.mergeExternalIds(next.externalIds),
      ),
      status: status,
      progress: progress,
      progressVolumes: progressVolumes,
      score: score,
      notes: notes,
      repeat: repeat,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      avgScore: avgScore,
      format: format,
      source: source,
      providerStates: providerStates,
    );
  }

  UserMediaState withProviderSnapshot(
    ProviderUserMediaState snapshot, {
    MediaIdentity? identity,
    MediaItem? mediaItem,
  }) {
    final MediaIdentity nextIdentity = identity ?? this.identity;
    final MediaItem nextMedia = (mediaItem ?? this.mediaItem).copyWith(
      externalIds: nextIdentity.mergeExternalIds(
        (mediaItem ?? this.mediaItem).externalIds,
      ),
    );
    return UserMediaState(
      identity: nextIdentity,
      mediaItem: nextMedia,
      status: status,
      progress: progress,
      progressVolumes: progressVolumes,
      score: score,
      notes: notes,
      repeat: repeat,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      avgScore: avgScore,
      format: format,
      source: source,
      providerStates: <TrackerSource, ProviderUserMediaState>{
        ...providerStates,
        snapshot.provider: snapshot,
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'identity': identity.toJson(),
    'mediaItem': mediaItem.toJson(),
    'status': status.name,
    'progress': progress,
    'progressVolumes': progressVolumes,
    if (score != null) 'score': score,
    'notes': notes,
    'repeat': repeat,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (nextEpisode != null) 'nextEpisode': nextEpisode,
    if (airingAt != null) 'airingAt': airingAt!.toIso8601String(),
    if (avgScore != null) 'avgScore': avgScore,
    if (format != null) 'format': format,
    'source': source.name,
    'providerStates': <String, dynamic>{
      for (final MapEntry<TrackerSource, ProviderUserMediaState> entry
          in providerStates.entries)
        entry.key.name: entry.value.toJson(),
    },
  };
}

/// Favorite is independent from list membership: favoriting a title must not
/// create a synthetic Planning entry in the user's anime list.
class LocalMediaFavoriteState {
  const LocalMediaFavoriteState({
    required this.identity,
    required this.favorite,
    required this.updatedAt,
  });

  factory LocalMediaFavoriteState.fromJson(Map<String, dynamic> json) {
    return LocalMediaFavoriteState(
      identity: MediaIdentity.fromJson(
        Map<String, dynamic>.from(json['identity'] as Map? ?? const {}),
      ),
      favorite: json['favorite'] == true,
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime(1970),
    );
  }

  final MediaIdentity identity;
  final bool favorite;
  final DateTime updatedAt;

  LocalMediaFavoriteState withIdentity(MediaIdentity next) {
    return LocalMediaFavoriteState(
      identity: next,
      favorite: favorite,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'identity': identity.toJson(),
    'favorite': favorite,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class UserMediaPatch {
  UserMediaPatch({
    this.status,
    this.progress,
    this.progressVolumes,
    this.score,
    this.notes,
    this.repeat,
    this.startedAt,
    this.completedAt,
    this.priority,
    this.private,
    this.hiddenFromStatusLists,
    this.customLists,
    this.advancedScores,
    this.scoreFormat,
    this.malPriority,
    this.malRewatchValue,
    this.malTags,
    this.favorite,
    this.delete = false,
    Set<UserMediaField>? fields,
  }) : fields = Set<UserMediaField>.unmodifiable(
         fields ??
             <UserMediaField>{
               if (status != null) UserMediaField.status,
               if (progress != null) UserMediaField.progress,
               if (progressVolumes != null) UserMediaField.progressVolumes,
               if (score != null) UserMediaField.score,
               if (notes != null) UserMediaField.notes,
               if (repeat != null) UserMediaField.repeat,
               if (startedAt != null) UserMediaField.startedAt,
               if (completedAt != null) UserMediaField.completedAt,
               if (priority != null) UserMediaField.priority,
               if (private != null) UserMediaField.private,
               if (hiddenFromStatusLists != null)
                 UserMediaField.hiddenFromStatusLists,
               if (customLists != null) UserMediaField.customLists,
               if (advancedScores != null) UserMediaField.advancedScores,
               if (scoreFormat != null) UserMediaField.scoreFormat,
               if (malPriority != null) UserMediaField.malPriority,
               if (malRewatchValue != null) UserMediaField.malRewatchValue,
               if (malTags != null) UserMediaField.malTags,
               if (favorite != null) UserMediaField.favorite,
             },
       );

  factory UserMediaPatch.fromJson(Map<String, dynamic> json) {
    final Set<UserMediaField> fields = ((json['fields'] as List?) ?? const [])
        .map((Object? value) => _fieldFromName('$value'))
        .whereType<UserMediaField>()
        .toSet();
    return UserMediaPatch(
      status: json['status'] == null
          ? null
          : _statusFromName(json['status']?.toString()),
      progress: json['progress'] == null
          ? null
          : _nonNegativeInt(json['progress']),
      progressVolumes: json['progressVolumes'] == null
          ? null
          : _nonNegativeInt(json['progressVolumes']),
      score: (json['score'] as num?)?.toDouble(),
      notes: json['notes']?.toString(),
      repeat: json['repeat'] == null ? null : _nonNegativeInt(json['repeat']),
      startedAt: DateTime.tryParse('${json['startedAt'] ?? ''}'),
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      priority: json['priority'] == null
          ? null
          : _nonNegativeInt(json['priority']),
      private: json['private'] as bool?,
      hiddenFromStatusLists: json['hiddenFromStatusLists'] as bool?,
      customLists: json['customLists'] is Map
          ? _boolMap(json['customLists'])
          : null,
      advancedScores: json['advancedScores'] is Map
          ? _doubleMap(json['advancedScores'])
          : null,
      scoreFormat: json['scoreFormat']?.toString(),
      malPriority: json['malPriority'] == null
          ? null
          : _nonNegativeInt(json['malPriority']),
      malRewatchValue: json['malRewatchValue'] == null
          ? null
          : _nonNegativeInt(json['malRewatchValue']),
      malTags: json['malTags'] is List
          ? List<String>.from(
              (json['malTags'] as List).map((Object? value) => '$value'),
            )
          : null,
      favorite: json['favorite'] as bool?,
      delete: json['delete'] == true,
      fields: fields,
    );
  }

  final AniListListStatus? status;
  final int? progress;
  final int? progressVolumes;
  final double? score;
  final String? notes;
  final int? repeat;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? priority;
  final bool? private;
  final bool? hiddenFromStatusLists;
  final Map<String, bool>? customLists;
  final Map<String, double>? advancedScores;
  final String? scoreFormat;
  final int? malPriority;
  final int? malRewatchValue;
  final List<String>? malTags;
  final bool? favorite;
  final bool delete;
  final Set<UserMediaField> fields;

  bool touches(UserMediaField field) => fields.contains(field);

  bool get touchesLibraryState =>
      fields.any((UserMediaField field) => field != UserMediaField.favorite);

  UserMediaPatch mergedWith(UserMediaPatch newer) {
    final bool newerTouchesLibrary = newer.fields.any(
      (UserMediaField field) => field != UserMediaField.favorite,
    );
    if (newer.delete) {
      final bool keepsFavorite =
          newer.touches(UserMediaField.favorite) ||
          touches(UserMediaField.favorite);
      return UserMediaPatch(
        favorite: newer.touches(UserMediaField.favorite)
            ? newer.favorite
            : favorite,
        delete: true,
        fields: <UserMediaField>{if (keepsFavorite) UserMediaField.favorite},
      );
    }
    final bool replacingDelete = delete && newerTouchesLibrary;
    final bool keepsDelete = delete && !newerTouchesLibrary;
    final Set<UserMediaField> mergedFields = <UserMediaField>{
      if (!replacingDelete)
        ...fields.where(
          (UserMediaField field) => field != UserMediaField.favorite,
        ),
      if (touches(UserMediaField.favorite)) UserMediaField.favorite,
      ...newer.fields,
    };
    return UserMediaPatch(
      status: newer.touches(UserMediaField.status)
          ? newer.status
          : replacingDelete
          ? null
          : status,
      progress: newer.touches(UserMediaField.progress)
          ? newer.progress
          : replacingDelete
          ? null
          : progress,
      progressVolumes: newer.touches(UserMediaField.progressVolumes)
          ? newer.progressVolumes
          : replacingDelete
          ? null
          : progressVolumes,
      score: newer.touches(UserMediaField.score)
          ? newer.score
          : replacingDelete
          ? null
          : score,
      notes: newer.touches(UserMediaField.notes)
          ? newer.notes
          : replacingDelete
          ? null
          : notes,
      repeat: newer.touches(UserMediaField.repeat)
          ? newer.repeat
          : replacingDelete
          ? null
          : repeat,
      startedAt: newer.touches(UserMediaField.startedAt)
          ? newer.startedAt
          : replacingDelete
          ? null
          : startedAt,
      completedAt: newer.touches(UserMediaField.completedAt)
          ? newer.completedAt
          : replacingDelete
          ? null
          : completedAt,
      priority: newer.touches(UserMediaField.priority)
          ? newer.priority
          : replacingDelete
          ? null
          : priority,
      private: newer.touches(UserMediaField.private)
          ? newer.private
          : replacingDelete
          ? null
          : private,
      hiddenFromStatusLists: newer.touches(UserMediaField.hiddenFromStatusLists)
          ? newer.hiddenFromStatusLists
          : replacingDelete
          ? null
          : hiddenFromStatusLists,
      customLists: newer.touches(UserMediaField.customLists)
          ? newer.customLists
          : replacingDelete
          ? null
          : customLists,
      advancedScores: newer.touches(UserMediaField.advancedScores)
          ? newer.advancedScores
          : replacingDelete
          ? null
          : advancedScores,
      scoreFormat: newer.touches(UserMediaField.scoreFormat)
          ? newer.scoreFormat
          : replacingDelete
          ? null
          : scoreFormat,
      malPriority: newer.touches(UserMediaField.malPriority)
          ? newer.malPriority
          : replacingDelete
          ? null
          : malPriority,
      malRewatchValue: newer.touches(UserMediaField.malRewatchValue)
          ? newer.malRewatchValue
          : replacingDelete
          ? null
          : malRewatchValue,
      malTags: newer.touches(UserMediaField.malTags)
          ? newer.malTags
          : replacingDelete
          ? null
          : malTags,
      favorite: newer.touches(UserMediaField.favorite)
          ? newer.favorite
          : favorite,
      delete: keepsDelete,
      fields: mergedFields,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fields': fields.map((UserMediaField field) => field.name).toList(),
    if (touches(UserMediaField.status) && status != null)
      'status': status!.name,
    if (touches(UserMediaField.progress)) 'progress': progress,
    if (touches(UserMediaField.progressVolumes))
      'progressVolumes': progressVolumes,
    if (touches(UserMediaField.score)) 'score': score,
    if (touches(UserMediaField.notes)) 'notes': notes,
    if (touches(UserMediaField.repeat)) 'repeat': repeat,
    if (touches(UserMediaField.startedAt))
      'startedAt': startedAt?.toIso8601String(),
    if (touches(UserMediaField.completedAt))
      'completedAt': completedAt?.toIso8601String(),
    if (touches(UserMediaField.priority)) 'priority': priority,
    if (touches(UserMediaField.private)) 'private': private,
    if (touches(UserMediaField.hiddenFromStatusLists))
      'hiddenFromStatusLists': hiddenFromStatusLists,
    if (touches(UserMediaField.customLists)) 'customLists': customLists,
    if (touches(UserMediaField.advancedScores))
      'advancedScores': advancedScores,
    if (touches(UserMediaField.scoreFormat)) 'scoreFormat': scoreFormat,
    if (touches(UserMediaField.malPriority)) 'malPriority': malPriority,
    if (touches(UserMediaField.malRewatchValue))
      'malRewatchValue': malRewatchValue,
    if (touches(UserMediaField.malTags)) 'malTags': malTags,
    if (touches(UserMediaField.favorite)) 'favorite': favorite,
    if (delete) 'delete': true,
  };
}

class SyncJournalEntry {
  const SyncJournalEntry({
    required this.identity,
    required this.patch,
    required this.pendingTargets,
    this.awaitingRemoteTargets = const <TrackerSource>{},
    required this.createdAt,
    required this.updatedAt,
    this.mediaTitle,
    this.providerEntryIds = const <TrackerSource, int>{},
  });

  factory SyncJournalEntry.fromJson(Map<String, dynamic> json) {
    final Map<TrackerSource, int> entryIds = <TrackerSource, int>{};
    final Object? rawEntryIds = json['providerEntryIds'];
    if (rawEntryIds is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawEntryIds.entries) {
        final TrackerSource source = TrackerSource.fromName('${entry.key}');
        final int? value = _positiveInt(entry.value);
        if (value != null) entryIds[source] = value;
      }
    }
    return SyncJournalEntry(
      identity: MediaIdentity.fromJson(
        Map<String, dynamic>.from(json['identity'] as Map? ?? const {}),
      ),
      patch: UserMediaPatch.fromJson(
        Map<String, dynamic>.from(json['patch'] as Map? ?? const {}),
      ),
      pendingTargets: ((json['pendingTargets'] as List?) ?? const [])
          .map((Object? value) => TrackerSource.fromName('$value'))
          .toSet(),
      awaitingRemoteTargets:
          ((json['awaitingRemoteTargets'] as List?) ?? const [])
              .map((Object? value) => TrackerSource.fromName('$value'))
              .toSet(),
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime(1970),
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime(1970),
      mediaTitle: json['mediaTitle']?.toString(),
      providerEntryIds: entryIds,
    );
  }

  final MediaIdentity identity;
  final UserMediaPatch patch;
  final Set<TrackerSource> pendingTargets;
  final Set<TrackerSource> awaitingRemoteTargets;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? mediaTitle;
  final Map<TrackerSource, int> providerEntryIds;

  SyncJournalEntry mergedWith(SyncJournalEntry newer) {
    return SyncJournalEntry(
      identity: identity.merge(newer.identity),
      patch: patch.mergedWith(newer.patch),
      pendingTargets: <TrackerSource>{
        ...pendingTargets,
        ...newer.pendingTargets,
      },
      awaitingRemoteTargets: <TrackerSource>{
        ...awaitingRemoteTargets,
        ...newer.awaitingRemoteTargets,
      }..removeAll(newer.pendingTargets),
      createdAt: createdAt.isBefore(newer.createdAt)
          ? createdAt
          : newer.createdAt,
      updatedAt: newer.updatedAt,
      mediaTitle: newer.mediaTitle?.trim().isNotEmpty == true
          ? newer.mediaTitle
          : mediaTitle,
      providerEntryIds: <TrackerSource, int>{
        ...providerEntryIds,
        ...newer.providerEntryIds,
      },
    );
  }

  SyncJournalEntry withIdentity(MediaIdentity next) => SyncJournalEntry(
    identity: next,
    patch: patch,
    pendingTargets: pendingTargets,
    awaitingRemoteTargets: awaitingRemoteTargets,
    createdAt: createdAt,
    updatedAt: updatedAt,
    mediaTitle: mediaTitle,
    providerEntryIds: providerEntryIds,
  );

  SyncJournalEntry deliveredTo(
    TrackerSource provider, {
    bool awaitRemoteConfirmation = false,
  }) => SyncJournalEntry(
    identity: identity,
    patch: patch,
    pendingTargets: <TrackerSource>{...pendingTargets}..remove(provider),
    awaitingRemoteTargets: <TrackerSource>{
      ...awaitingRemoteTargets,
      if (awaitRemoteConfirmation) provider,
    },
    createdAt: createdAt,
    updatedAt: updatedAt,
    mediaTitle: mediaTitle,
    providerEntryIds: providerEntryIds,
  );

  SyncJournalEntry confirmedBy(TrackerSource provider) => SyncJournalEntry(
    identity: identity,
    patch: patch,
    pendingTargets: pendingTargets,
    awaitingRemoteTargets: <TrackerSource>{...awaitingRemoteTargets}
      ..remove(provider),
    createdAt: createdAt,
    updatedAt: updatedAt,
    mediaTitle: mediaTitle,
    providerEntryIds: providerEntryIds,
  );

  bool tracks(TrackerSource provider) =>
      pendingTargets.contains(provider) ||
      awaitingRemoteTargets.contains(provider);

  bool get isSettled => pendingTargets.isEmpty && awaitingRemoteTargets.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'identity': identity.toJson(),
    'patch': patch.toJson(),
    'pendingTargets': pendingTargets
        .map((TrackerSource source) => source.name)
        .toList(),
    if (awaitingRemoteTargets.isNotEmpty)
      'awaitingRemoteTargets': awaitingRemoteTargets
          .map((TrackerSource source) => source.name)
          .toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (mediaTitle != null) 'mediaTitle': mediaTitle,
    if (providerEntryIds.isNotEmpty)
      'providerEntryIds': <String, int>{
        for (final MapEntry<TrackerSource, int> entry
            in providerEntryIds.entries)
          entry.key.name: entry.value,
      },
  };
}

class ProviderReconciliationResult {
  const ProviderReconciliationResult({
    required this.states,
    required this.journal,
    this.requiresAccountApproval = false,
    this.quarantined = false,
    this.importedChanges = 0,
    this.destructiveChangesPending = 0,
  });

  final List<UserMediaState> states;
  final List<SyncJournalEntry> journal;
  final bool requiresAccountApproval;
  final bool quarantined;
  final int importedChanges;
  final int destructiveChangesPending;
}

enum TrackerProviderAvailability {
  unknown,
  healthy,
  degraded,
  unavailable,
  authRequired,
}

class TrackerProviderHealth {
  const TrackerProviderHealth({
    required this.provider,
    this.availability = TrackerProviderAvailability.unknown,
    this.consecutiveFailures = 0,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
  });

  factory TrackerProviderHealth.fromJson(Map<String, dynamic> json) {
    return TrackerProviderHealth(
      provider: TrackerSource.fromName(json['provider']?.toString()),
      availability: TrackerProviderAvailability.values.firstWhere(
        (TrackerProviderAvailability value) =>
            value.name == json['availability'],
        orElse: () => TrackerProviderAvailability.unknown,
      ),
      consecutiveFailures: _nonNegativeInt(json['consecutiveFailures']),
      lastSuccessAt: DateTime.tryParse('${json['lastSuccessAt'] ?? ''}'),
      lastFailureAt: DateTime.tryParse('${json['lastFailureAt'] ?? ''}'),
      lastError: json['lastError']?.toString(),
    );
  }

  final TrackerSource provider;
  final TrackerProviderAvailability availability;
  final int consecutiveFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastError;

  TrackerProviderHealth success(DateTime now) => TrackerProviderHealth(
    provider: provider,
    availability: TrackerProviderAvailability.healthy,
    lastSuccessAt: now,
    lastFailureAt: lastFailureAt,
  );

  TrackerProviderHealth failure(
    DateTime now,
    Object error, {
    bool authentication = false,
  }) => TrackerProviderHealth(
    provider: provider,
    availability: authentication
        ? TrackerProviderAvailability.authRequired
        : TrackerProviderAvailability.unavailable,
    consecutiveFailures: consecutiveFailures + 1,
    lastSuccessAt: lastSuccessAt,
    lastFailureAt: now,
    lastError: '$error',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'provider': provider.name,
    'availability': availability.name,
    'consecutiveFailures': consecutiveFailures,
    if (lastSuccessAt != null)
      'lastSuccessAt': lastSuccessAt!.toIso8601String(),
    if (lastFailureAt != null)
      'lastFailureAt': lastFailureAt!.toIso8601String(),
    if (lastError != null) 'lastError': lastError,
  };
}

/// Local-first conflict policy:
/// 1. pending local fields always win;
/// 2. the configured primary provider is canonical whenever its snapshot is
///    available;
/// 3. timestamps are only used within the same authority, or to choose among
///    fallback providers when no primary snapshot exists;
/// 4. ties prefer AniList, then the existing value. Raw provider snapshots are
///    always unioned so provider-specific data is never discarded.
class UserMediaConflictResolver {
  const UserMediaConflictResolver();

  UserMediaState merge({
    required UserMediaState existing,
    required UserMediaState incoming,
    required TrackerSource primary,
    UserMediaPatch? pendingLocal,
    DateTime? pendingLocalUpdatedAt,
    bool incomingProviderIsAuthoritative = false,
    bool incomingAiringIsAuthoritative = false,
  }) {
    final MediaIdentity identity = existing.identity.merge(incoming.identity);
    final bool incomingWins = _incomingWins(
      existing,
      incoming,
      primary,
      incomingProviderIsAuthoritative: incomingProviderIsAuthoritative,
    );
    final UserMediaState winner = incomingWins ? incoming : existing;
    final UserMediaState fallback = incomingWins ? existing : incoming;
    final _AiringSchedule airing = _mergeAiringSchedule(
      existing,
      incoming,
      incomingIsAuthoritative: incomingAiringIsAuthoritative,
    );
    final MediaItem media = _withAiringMetadata(
      _mergeMedia(
        existing.mediaItem,
        incoming.mediaItem,
        preferIncoming: incomingWins,
        identity: identity,
      ),
      airing,
    );
    UserMediaState result = UserMediaState(
      identity: identity,
      mediaItem: media,
      status: winner.status,
      progress: winner.progress,
      progressVolumes: winner.progressVolumes,
      score: winner.score,
      notes: winner.notes,
      repeat: winner.repeat,
      createdAt: _earliest(existing.createdAt, incoming.createdAt),
      updatedAt: winner.updatedAt,
      startedAt: winner.startedAt ?? fallback.startedAt,
      completedAt: winner.completedAt ?? fallback.completedAt,
      nextEpisode: airing.nextEpisode,
      airingAt: airing.airingAt,
      avgScore: winner.avgScore ?? fallback.avgScore,
      format: winner.format ?? fallback.format,
      source: winner.source,
      providerStates: <TrackerSource, ProviderUserMediaState>{
        ...existing.providerStates,
        ...incoming.providerStates,
      },
    );
    if (pendingLocal != null && !pendingLocal.delete) {
      // Replaying a durable optimistic mutation must be idempotent. Giving it
      // a fresh wall-clock timestamp on every provider refresh used to make
      // untouched entries jump to the top of an updated-newest Library.
      result = result.apply(
        pendingLocal,
        pendingLocalUpdatedAt ?? existing.updatedAt,
      );
    }
    return result;
  }

  bool _incomingWins(
    UserMediaState existing,
    UserMediaState incoming,
    TrackerSource primary, {
    required bool incomingProviderIsAuthoritative,
  }) {
    if (incomingProviderIsAuthoritative) {
      // A live snapshot can repair a canonical state whose timestamp was
      // previously polluted by an optimistic replay. A fallback provider must
      // still never replace a primary provider's canonical fields.
      if (incoming.source == primary) return true;
      if (existing.source == incoming.source) return true;
      if (existing.source == primary) return false;
    }
    if (incoming.source != existing.source) {
      if (incoming.source == primary) return true;
      if (existing.source == primary) return false;
    }
    final int compared = incoming.updatedAt.compareTo(existing.updatedAt);
    if (compared != 0) return compared > 0;
    if (incoming.source == existing.source) return false;
    if (incoming.source == TrackerSource.anilist) return true;
    if (existing.source == TrackerSource.anilist) return false;
    return false;
  }
}

class _AiringSchedule {
  const _AiringSchedule({this.nextEpisode, this.airingAt});

  factory _AiringSchedule.fromState(UserMediaState state) =>
      _AiringSchedule(nextEpisode: state.nextEpisode, airingAt: state.airingAt);

  final int? nextEpisode;
  final DateTime? airingAt;

  bool get hasData => nextEpisode != null || airingAt != null;
  bool get isComplete => nextEpisode != null && airingAt != null;
}

_AiringSchedule _mergeAiringSchedule(
  UserMediaState existing,
  UserMediaState incoming, {
  required bool incomingIsAuthoritative,
}) {
  final _AiringSchedule current = _AiringSchedule.fromState(existing);
  final _AiringSchedule fresh = _AiringSchedule.fromState(incoming);

  // Media-list timestamps describe the user's list edit, not the constantly
  // changing next-airing metadata. A live AniList refresh must therefore
  // replace (and sometimes clear) the cached pair even when `updatedAt` did
  // not change. Cached AniList fallbacks deliberately do not set this flag,
  // so an older cache cannot overwrite a newer schedule from another scope.
  if (incomingIsAuthoritative) return fresh;

  // MAL and Shikimori do not currently expose next-airing data. Preserve a
  // cached AniList schedule while they are serving as an outage fallback.
  if (!fresh.hasData) return current;
  if (!current.hasData) return fresh;

  // Keep the fields from one snapshot instead of combining an episode number
  // from one provider with a timestamp from another. Prefer the more complete
  // or later schedule if another provider gains this metadata in the future.
  if (fresh.isComplete != current.isComplete) {
    return fresh.isComplete ? fresh : current;
  }
  final DateTime? currentAt = current.airingAt;
  final DateTime? freshAt = fresh.airingAt;
  if (currentAt != null && freshAt != null && freshAt.isAfter(currentAt)) {
    return fresh;
  }
  final int? currentEpisode = current.nextEpisode;
  final int? freshEpisode = fresh.nextEpisode;
  if (currentEpisode != null &&
      freshEpisode != null &&
      freshEpisode > currentEpisode) {
    return fresh;
  }
  return current;
}

MediaItem _withAiringMetadata(MediaItem media, _AiringSchedule airing) {
  final Map<String, String> externalIds = <String, String>{...media.externalIds}
    ..remove(anilistNextAiringEpisodeKey)
    ..remove(anilistNextAiringAtKey);
  final int? nextEpisode = airing.nextEpisode;
  final DateTime? airingAt = airing.airingAt;
  if (nextEpisode != null) {
    externalIds[anilistNextAiringEpisodeKey] = '$nextEpisode';
  }
  if (airingAt != null) {
    externalIds[anilistNextAiringAtKey] =
        '${airingAt.millisecondsSinceEpoch ~/ 1000}';
  }
  return media.copyWith(externalIds: externalIds);
}

List<UserMediaState> userMediaStatesFromFolders(
  List<AniListAnimeListFolder> folders, {
  required TrackerSource source,
  DateTime? fetchedAt,
}) {
  final DateTime fallbackTime = (fetchedAt ?? DateTime.now()).toUtc();
  return <UserMediaState>[
    for (final AniListAnimeListFolder folder in folders)
      for (final AniListAnimeListEntry entry in folder.entries)
        _stateFromEntry(entry, source, fallbackTime),
  ];
}

List<AniListAnimeListFolder> foldersFromUserMediaStates(
  Iterable<UserMediaState> states,
) {
  final Map<AniListListStatus, List<AniListAnimeListEntry>> grouped =
      <AniListListStatus, List<AniListAnimeListEntry>>{};
  for (final UserMediaState state in states) {
    final ProviderUserMediaState? sourceState =
        state.providerStates[state.source];
    final ProviderUserMediaState? aniListState =
        state.providerStates[TrackerSource.anilist];
    final int displayProgress = canonicalEpisodeProgress(
      state.progress,
      state.mediaItem.episodeCount,
    );
    final int? total = state.mediaItem.episodeCount;
    final AniListListStatus displayStatus =
        state.status == AniListListStatus.current &&
            total != null &&
            total > 0 &&
            displayProgress >= total
        ? AniListListStatus.completed
        : state.status;
    grouped
        .putIfAbsent(displayStatus, () => <AniListAnimeListEntry>[])
        .add(
          AniListAnimeListEntry(
            id: sourceState?.entryId ?? state.identity.idFor(state.source) ?? 0,
            status: displayStatus,
            progress: displayProgress,
            score: state.score,
            scoreRaw: aniListState?.data['scoreRaw'] is num
                ? (aniListState!.data['scoreRaw'] as num).toInt()
                : state.score == null
                ? null
                : (state.score! * 10).round().clamp(0, 100),
            mediaItem: state.mediaItem.copyWith(
              externalIds: state.identity.mergeExternalIds(
                state.mediaItem.externalIds,
              ),
            ),
            notes: state.notes,
            repeat: state.repeat,
            progressVolumes: state.progressVolumes,
            priority: (aniListState?.data['priority'] as num?)?.toInt() ?? 0,
            private: aniListState?.data['private'] == true,
            hiddenFromStatusLists:
                aniListState?.data['hiddenFromStatusLists'] == true,
            customLists: _boolMap(aniListState?.data['customLists']),
            advancedScores: _doubleMap(aniListState?.data['advancedScores']),
            providerData: <String, dynamic>{
              ...?sourceState?.data,
              if (aniListState?.data['scoreFormat'] != null)
                'scoreFormat': aniListState?.data['scoreFormat'],
              'providerSnapshots': <String, dynamic>{
                for (final MapEntry<TrackerSource, ProviderUserMediaState>
                    provider
                    in state.providerStates.entries)
                  provider.key.name: provider.value.data,
              },
            },
            createdAt: state.createdAt.millisecondsSinceEpoch ~/ 1000,
            updatedAt: state.updatedAt.millisecondsSinceEpoch ~/ 1000,
            startedAt: state.startedAt,
            completedAt: state.completedAt,
            nextEpisode: state.nextEpisode,
            airingAt: state.airingAt,
            avgScore: state.avgScore,
            format: state.format,
          ),
        );
  }
  return <AniListAnimeListFolder>[
    for (final AniListListStatus status in AniListListStatus.values)
      if (grouped[status]?.isNotEmpty == true)
        AniListAnimeListFolder(
          name: status.label,
          status: status,
          entries: grouped[status]!,
        ),
  ];
}

double? normalizeCanonicalScore(double? score) {
  if (score == null) return null;
  return score.clamp(0, 10).toDouble();
}

/// AniList/MAL/Shikimori progress can never exceed a known canonical episode
/// total. Addons may expose recaps, specials, or other extra numbered videos;
/// those are still locally watchable but must not produce values like 13/12 in
/// a tracker account.
int canonicalEpisodeProgress(int progress, int? total) {
  final int nonNegative = progress.clamp(0, 0x7fffffff).toInt();
  if (total == null || total <= 0) return nonNegative;
  return nonNegative.clamp(0, total).toInt();
}

int integerProviderScore(double score) => score.round().clamp(0, 10);

UserMediaState _stateFromEntry(
  AniListAnimeListEntry entry,
  TrackerSource source,
  DateTime fallbackTime,
) {
  final MediaIdentity identity = MediaIdentity.fromExternalIds(
    entry.mediaItem.externalIds,
    mediaId: entry.mediaItem.id,
  );
  final DateTime updatedAt = entry.updatedAt == null
      ? fallbackTime
      : DateTime.fromMillisecondsSinceEpoch(
          entry.updatedAt! * 1000,
          isUtc: true,
        );
  final DateTime createdAt = entry.createdAt == null
      ? fallbackTime
      : DateTime.fromMillisecondsSinceEpoch(
          entry.createdAt! * 1000,
          isUtc: true,
        );
  final String rawStatus = switch (source) {
    TrackerSource.anilist => entry.status.graphQlValue,
    TrackerSource.mal => entry.status.malValue,
    TrackerSource.shikimori => entry.status.shikimoriValue,
  };
  return UserMediaState(
    identity: identity,
    mediaItem: entry.mediaItem.copyWith(
      externalIds: identity.mergeExternalIds(entry.mediaItem.externalIds),
    ),
    status: entry.status,
    progress: entry.progress,
    progressVolumes: entry.progressVolumes,
    score: normalizeCanonicalScore(entry.score),
    notes: entry.notes,
    repeat: entry.repeat,
    createdAt: createdAt,
    updatedAt: updatedAt,
    startedAt: entry.startedAt,
    completedAt: entry.completedAt,
    nextEpisode: entry.nextEpisode,
    airingAt: entry.airingAt,
    avgScore: entry.avgScore,
    format: entry.format,
    source: source,
    providerStates: <TrackerSource, ProviderUserMediaState>{
      source: ProviderUserMediaState(
        provider: source,
        entryId: entry.id > 0 ? entry.id : null,
        rawStatus: rawStatus,
        rawScore: entry.score,
        updatedAt: updatedAt,
        data: <String, dynamic>{
          ...entry.providerData,
          'notes': entry.notes,
          'repeat': entry.repeat,
          'progress': entry.progress,
          'progressVolumes': entry.progressVolumes,
          if (entry.scoreRaw != null) 'scoreRaw': entry.scoreRaw,
          'priority': entry.priority,
          'private': entry.private,
          'hiddenFromStatusLists': entry.hiddenFromStatusLists,
          'customLists': entry.customLists,
          'advancedScores': entry.advancedScores,
          if (entry.createdAt != null)
            'createdAt': createdAt.toIso8601String()
          else
            'firstSeenAt': createdAt.toIso8601String(),
          if (entry.startedAt != null)
            'startedAt': entry.startedAt!.toIso8601String(),
          if (entry.completedAt != null)
            'completedAt': entry.completedAt!.toIso8601String(),
        },
      ),
    },
  );
}

MediaItem _mergeMedia(
  MediaItem existing,
  MediaItem incoming, {
  required bool preferIncoming,
  required MediaIdentity identity,
}) {
  final MediaItem preferred = preferIncoming ? incoming : existing;
  final MediaItem fallback = preferIncoming ? existing : incoming;
  return preferred.copyWith(
    title: preferred.title.trim().isEmpty ? fallback.title : preferred.title,
    originalTitle: preferred.originalTitle.trim().isEmpty
        ? fallback.originalTitle
        : preferred.originalTitle,
    overview: preferred.overview.trim().isEmpty
        ? fallback.overview
        : preferred.overview,
    posterUrl: preferred.posterUrl.trim().isEmpty
        ? fallback.posterUrl
        : preferred.posterUrl,
    backdropUrl: preferred.backdropUrl.trim().isEmpty
        ? fallback.backdropUrl
        : preferred.backdropUrl,
    rating: preferred.rating == 0 ? fallback.rating : preferred.rating,
    genres: preferred.genres.isEmpty ? fallback.genres : preferred.genres,
    externalIds: identity.mergeExternalIds(<String, String>{
      ...fallback.externalIds,
      ...preferred.externalIds,
    }),
    episodeCount: preferred.episodeCount ?? fallback.episodeCount,
    runtimeMinutes: preferred.runtimeMinutes ?? fallback.runtimeMinutes,
    seasons: preferred.seasons.isEmpty ? fallback.seasons : preferred.seasons,
    statusLabel: preferred.statusLabel.trim().isEmpty
        ? fallback.statusLabel
        : preferred.statusLabel,
    aliases: preferred.aliases.isEmpty ? fallback.aliases : preferred.aliases,
    originalLanguage: preferred.originalLanguage.trim().isEmpty
        ? fallback.originalLanguage
        : preferred.originalLanguage,
    trailer: preferred.trailer ?? fallback.trailer,
  );
}

DateTime _earliest(DateTime first, DateTime second) {
  return first.isBefore(second) ? first : second;
}

AniListListStatus _statusFromName(String? value) {
  return AniListListStatus.values.firstWhere(
    (AniListListStatus status) => status.name == value,
    orElse: () => AniListListStatus.planning,
  );
}

UserMediaField? _fieldFromName(String value) {
  for (final UserMediaField field in UserMediaField.values) {
    if (field.name == value) return field;
  }
  return null;
}

int _nonNegativeInt(Object? value) {
  final int parsed = value is num
      ? value.toInt()
      : int.tryParse('${value ?? ''}') ?? 0;
  return parsed < 0 ? 0 : parsed;
}

int? _positiveInt(Object? value) {
  final int parsed = value is num
      ? value.toInt()
      : int.tryParse('${value ?? ''}') ?? 0;
  return parsed > 0 ? parsed : null;
}

String? _nullableTrimmedString(Object? value) {
  final String parsed = '${value ?? ''}'.trim();
  return parsed.isEmpty ? null : parsed;
}

Map<String, bool> _boolMap(Object? value) {
  if (value is! Map) return <String, bool>{};
  return <String, bool>{
    for (final MapEntry<dynamic, dynamic> entry in value.entries)
      '${entry.key}': entry.value == true,
  };
}

Map<String, double> _doubleMap(Object? value) {
  if (value is! Map) return <String, double>{};
  return <String, double>{
    for (final MapEntry<dynamic, dynamic> entry in value.entries)
      if (entry.value is num) '${entry.key}': (entry.value as num).toDouble(),
  };
}
