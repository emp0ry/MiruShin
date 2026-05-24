import '../../../shared/models/media_item.dart';

class AniListUserSettings {
  const AniListUserSettings({
    this.titleLanguage = 'ROMAJI',
    this.staffNameLanguage = 'ROMAJI_WESTERN',
    this.activityMergeTime = 720,
    this.displayAdultContent = false,
    this.airingNotifications = true,
    this.scoreFormat = 'POINT_10_DECIMAL',
    this.rowOrder = 'title',
    this.splitCompletedAnime = false,
    this.splitCompletedManga = false,
    this.advancedScoringEnabled = false,
    this.restrictMessagesToFollowing = false,
    this.advancedScores = const <String>[],
    this.animeCustomLists = const <String>[],
    this.mangaCustomLists = const <String>[],
    this.notificationOptions = const <String, bool>{},
    this.disabledListActivity = const <String, bool>{},
  });

  final String titleLanguage;
  final String staffNameLanguage;
  final int activityMergeTime;
  final bool displayAdultContent;
  final bool airingNotifications;
  final String scoreFormat;
  final String rowOrder;
  final bool splitCompletedAnime;
  final bool splitCompletedManga;
  final bool advancedScoringEnabled;
  final bool restrictMessagesToFollowing;
  final List<String> advancedScores;
  final List<String> animeCustomLists;
  final List<String> mangaCustomLists;
  final Map<String, bool> notificationOptions;
  final Map<String, bool> disabledListActivity;

  factory AniListUserSettings.fromViewerJson(Map<String, dynamic> json) {
    final Object? options = json['options'];
    final Object? mediaListOptions = json['mediaListOptions'];
    final Map<String, dynamic> optionsMap = options is Map<String, dynamic>
        ? options
        : const <String, dynamic>{};
    final Map<String, dynamic> mediaListMap =
        mediaListOptions is Map<String, dynamic>
        ? mediaListOptions
        : const <String, dynamic>{};
    final Map<String, dynamic> animeList =
        mediaListMap['animeList'] is Map<String, dynamic>
        ? mediaListMap['animeList'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final Map<String, dynamic> mangaList =
        mediaListMap['mangaList'] is Map<String, dynamic>
        ? mediaListMap['mangaList'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return AniListUserSettings(
      titleLanguage: _string(optionsMap['titleLanguage'], fallback: 'ROMAJI'),
      staffNameLanguage: _string(
        optionsMap['staffNameLanguage'],
        fallback: 'ROMAJI_WESTERN',
      ),
      activityMergeTime: _int(optionsMap['activityMergeTime'], fallback: 720),
      displayAdultContent: optionsMap['displayAdultContent'] == true,
      airingNotifications: optionsMap['airingNotifications'] != false,
      scoreFormat: _string(
        mediaListMap['scoreFormat'],
        fallback: 'POINT_10_DECIMAL',
      ),
      rowOrder: _string(mediaListMap['rowOrder'], fallback: 'title'),
      splitCompletedAnime: animeList['splitCompletedSectionByFormat'] == true,
      splitCompletedManga: mangaList['splitCompletedSectionByFormat'] == true,
      advancedScoringEnabled: animeList['advancedScoringEnabled'] == true,
      restrictMessagesToFollowing:
          optionsMap['restrictMessagesToFollowing'] == true,
      advancedScores: _stringList(animeList['advancedScoring']),
      animeCustomLists: _stringList(animeList['customLists']),
      mangaCustomLists: _stringList(mangaList['customLists']),
      notificationOptions: _boolMapFromList(optionsMap['notificationOptions']),
      disabledListActivity: _boolMapFromDisabledList(
        optionsMap['disabledListActivity'],
      ),
    );
  }

  factory AniListUserSettings.fromCacheJson(Map<String, dynamic> json) {
    return AniListUserSettings(
      titleLanguage: _string(json['titleLanguage'], fallback: 'ROMAJI'),
      staffNameLanguage: _string(
        json['staffNameLanguage'],
        fallback: 'ROMAJI_WESTERN',
      ),
      activityMergeTime: _int(json['activityMergeTime'], fallback: 720),
      displayAdultContent: json['displayAdultContent'] == true,
      airingNotifications: json['airingNotifications'] != false,
      scoreFormat: _string(json['scoreFormat'], fallback: 'POINT_10_DECIMAL'),
      rowOrder: _string(json['rowOrder'], fallback: 'title'),
      splitCompletedAnime: json['splitCompletedAnime'] == true,
      splitCompletedManga: json['splitCompletedManga'] == true,
      advancedScoringEnabled: json['advancedScoringEnabled'] == true,
      restrictMessagesToFollowing: json['restrictMessagesToFollowing'] == true,
      advancedScores: _stringList(json['advancedScores']),
      animeCustomLists: _stringList(json['animeCustomLists']),
      mangaCustomLists: _stringList(json['mangaCustomLists']),
      notificationOptions: _stringBoolMap(json['notificationOptions']),
      disabledListActivity: _stringBoolMap(json['disabledListActivity']),
    );
  }

  AniListUserSettings copyWith({
    String? titleLanguage,
    String? staffNameLanguage,
    int? activityMergeTime,
    bool? displayAdultContent,
    bool? airingNotifications,
    String? scoreFormat,
    String? rowOrder,
    bool? splitCompletedAnime,
    bool? splitCompletedManga,
    bool? advancedScoringEnabled,
    bool? restrictMessagesToFollowing,
    List<String>? advancedScores,
    List<String>? animeCustomLists,
    List<String>? mangaCustomLists,
    Map<String, bool>? notificationOptions,
    Map<String, bool>? disabledListActivity,
  }) {
    return AniListUserSettings(
      titleLanguage: titleLanguage ?? this.titleLanguage,
      staffNameLanguage: staffNameLanguage ?? this.staffNameLanguage,
      activityMergeTime: activityMergeTime ?? this.activityMergeTime,
      displayAdultContent: displayAdultContent ?? this.displayAdultContent,
      airingNotifications: airingNotifications ?? this.airingNotifications,
      scoreFormat: scoreFormat ?? this.scoreFormat,
      rowOrder: rowOrder ?? this.rowOrder,
      splitCompletedAnime: splitCompletedAnime ?? this.splitCompletedAnime,
      splitCompletedManga: splitCompletedManga ?? this.splitCompletedManga,
      advancedScoringEnabled:
          advancedScoringEnabled ?? this.advancedScoringEnabled,
      restrictMessagesToFollowing:
          restrictMessagesToFollowing ?? this.restrictMessagesToFollowing,
      advancedScores: advancedScores ?? this.advancedScores,
      animeCustomLists: animeCustomLists ?? this.animeCustomLists,
      mangaCustomLists: mangaCustomLists ?? this.mangaCustomLists,
      notificationOptions: notificationOptions ?? this.notificationOptions,
      disabledListActivity: disabledListActivity ?? this.disabledListActivity,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'titleLanguage': titleLanguage,
      'staffNameLanguage': staffNameLanguage,
      'activityMergeTime': activityMergeTime,
      'displayAdultContent': displayAdultContent,
      'airingNotifications': airingNotifications,
      'scoreFormat': scoreFormat,
      'rowOrder': rowOrder,
      'splitCompletedAnime': splitCompletedAnime,
      'splitCompletedManga': splitCompletedManga,
      'advancedScoringEnabled': advancedScoringEnabled,
      'restrictMessagesToFollowing': restrictMessagesToFollowing,
      'advancedScores': advancedScores,
      'animeCustomLists': animeCustomLists,
      'mangaCustomLists': mangaCustomLists,
      'notificationOptions': notificationOptions,
      'disabledListActivity': disabledListActivity,
    };
  }

  Map<String, dynamic> toGraphQlVariables() {
    return <String, dynamic>{
      'titleLanguage': switch (titleLanguage) {
        'ROMAJI' || 'ENGLISH' || 'NATIVE' => titleLanguage,
        'RUSSIAN' => 'ENGLISH',
        _ => 'ENGLISH',
      },
      'staffNameLanguage': staffNameLanguage,
      'activityMergeTime': activityMergeTime,
      'displayAdultContent': displayAdultContent,
      'airingNotifications': airingNotifications,
      'scoreFormat': scoreFormat,
      'rowOrder': rowOrder,
      'notificationOptions': notificationOptions.entries
          .map(
            (MapEntry<String, bool> entry) => <String, dynamic>{
              'type': entry.key,
              'enabled': entry.value,
            },
          )
          .toList(growable: false),
      'splitCompletedAnime': splitCompletedAnime,
      'splitCompletedManga': splitCompletedManga,
      'restrictMessagesToFollowing': restrictMessagesToFollowing,
      'advancedScoringEnabled': advancedScoringEnabled,
      'advancedScoring': advancedScores,
      'disabledListActivity': disabledListActivity.entries
          .map(
            (MapEntry<String, bool> entry) => <String, dynamic>{
              'type': entry.key,
              'disabled': entry.value,
            },
          )
          .toList(growable: false),
    };
  }
}

class AniListUserProfile {
  const AniListUserProfile({
    required this.id,
    required this.name,
    this.about = '',
    this.avatarUrl,
    this.bannerUrl,
    this.siteUrl,
    this.isFollowing = false,
    this.isFollower = false,
    this.isBlocked = false,
    this.animeStats = const AniListUserStatistics(),
    this.mangaStats = const AniListUserStatistics(),
  });

  final int id;
  final String name;
  final String about;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? siteUrl;
  final bool isFollowing;
  final bool isFollower;
  final bool isBlocked;
  final AniListUserStatistics animeStats;
  final AniListUserStatistics mangaStats;
}

class AniListUserStatistics {
  const AniListUserStatistics({
    this.count = 0,
    this.meanScore = 0,
    this.standardDeviation = 0,
    this.minutesWatched = 0,
    this.episodesWatched = 0,
    this.chaptersRead = 0,
    this.volumesRead = 0,
    this.scores = const <AniListStatisticValue>[],
    this.lengths = const <AniListStatisticValue>[],
    this.formats = const <AniListStatisticValue>[],
    this.statuses = const <AniListStatisticValue>[],
    this.countries = const <AniListStatisticValue>[],
  });

  final int count;
  final double meanScore;
  final double standardDeviation;
  final int minutesWatched;
  final int episodesWatched;
  final int chaptersRead;
  final int volumesRead;
  final List<AniListStatisticValue> scores;
  final List<AniListStatisticValue> lengths;
  final List<AniListStatisticValue> formats;
  final List<AniListStatisticValue> statuses;
  final List<AniListStatisticValue> countries;
}

class AniListStatisticValue {
  const AniListStatisticValue({
    required this.label,
    this.count = 0,
    this.meanScore = 0,
    this.minutesWatched = 0,
    this.chaptersRead = 0,
    this.value = 0,
  });

  final String label;
  final int count;
  final double meanScore;
  final int minutesWatched;
  final int chaptersRead;
  final int value;
}

class AniListUserSnippet {
  const AniListUserSnippet({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String? avatarUrl;
}

class AniListReviewItem {
  const AniListReviewItem({
    required this.id,
    required this.mediaId,
    required this.mediaTitle,
    required this.userName,
    required this.summary,
    required this.rating,
    required this.ratingAmount,
    this.score = 0,
    this.body = '',
    this.bannerUrl,
    this.coverUrl,
    this.siteUrl,
  });

  final int id;
  final int mediaId;
  final String mediaTitle;
  final String userName;
  final String summary;
  final int rating;
  final int ratingAmount;
  final int score;
  final String body;
  final String? bannerUrl;
  final String? coverUrl;
  final String? siteUrl;
}

class AniListForumThread {
  const AniListForumThread({
    required this.id,
    required this.title,
    required this.user,
    this.replyUser,
    this.replyCount = 0,
    this.likeCount = 0,
    this.viewCount = 0,
    this.isSticky = false,
    this.isLocked = false,
    this.siteUrl,
    this.createdAt,
    this.repliedAt,
    this.categories = const <String>[],
    this.mediaCategories = const <String>[],
  });

  final int id;
  final String title;
  final AniListUserSnippet user;
  final AniListUserSnippet? replyUser;
  final int replyCount;
  final int likeCount;
  final int viewCount;
  final bool isSticky;
  final bool isLocked;
  final String? siteUrl;
  final DateTime? createdAt;
  final DateTime? repliedAt;
  final List<String> categories;
  final List<String> mediaCategories;
}

class AniListForumComment {
  const AniListForumComment({
    required this.id,
    required this.user,
    required this.threadId,
    required this.threadTitle,
    this.comment = '',
    this.likeCount = 0,
    this.isLiked = false,
    this.isLocked = false,
    this.siteUrl,
    this.createdAt,
  });

  final int id;
  final AniListUserSnippet user;
  final int threadId;
  final String threadTitle;
  final String comment;
  final int likeCount;
  final bool isLiked;
  final bool isLocked;
  final String? siteUrl;
  final DateTime? createdAt;
}

class AniListActivity {
  const AniListActivity({
    required this.id,
    required this.type,
    required this.primaryUser,
    this.secondaryUser,
    this.media,
    this.text = '',
    this.progressLabel,
    this.statusLabel,
    this.replyCount = 0,
    this.likeCount = 0,
    this.isLiked = false,
    this.isSubscribed = false,
    this.isPinned = false,
    this.isPrivate = false,
    this.createdAt,
    this.siteUrl,
  });

  final int id;
  final String type;
  final AniListUserSnippet primaryUser;
  final AniListUserSnippet? secondaryUser;
  final MediaItem? media;
  final String text;
  final String? progressLabel;
  final String? statusLabel;
  final int replyCount;
  final int likeCount;
  final bool isLiked;
  final bool isSubscribed;
  final bool isPinned;
  final bool isPrivate;
  final DateTime? createdAt;
  final String? siteUrl;
}

class AniListPagedChunk<T> {
  const AniListPagedChunk({
    required this.items,
    required this.hasNextPage,
    this.total,
  });

  final List<T> items;
  final bool hasNextPage;
  final int? total;
}

enum AniListFavouriteKind {
  anime('Anime'),
  manga('Manga'),
  characters('Characters'),
  staff('Staff'),
  studios('Studios');

  const AniListFavouriteKind(this.label);
  final String label;
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List<dynamic>) return const <String>[];
  return value
      .whereType<String>()
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, bool> _stringBoolMap(Object? value) {
  if (value is! Map) return const <String, bool>{};
  final Map<String, bool> mapped = <String, bool>{};
  value.forEach((Object? key, Object? rawValue) {
    mapped[key.toString()] = rawValue == true;
  });
  return Map<String, bool>.unmodifiable(mapped);
}

Map<String, bool> _boolMapFromList(Object? value) {
  if (value is! List<dynamic>) return const <String, bool>{};
  final Map<String, bool> mapped = <String, bool>{};
  for (final Object? item in value) {
    if (item is! Map<String, dynamic>) continue;
    final String type = _string(item['type']);
    if (type.isEmpty) continue;
    mapped[type] = item['enabled'] == true;
  }
  return Map<String, bool>.unmodifiable(mapped);
}

Map<String, bool> _boolMapFromDisabledList(Object? value) {
  if (value is! List<dynamic>) return const <String, bool>{};
  final Map<String, bool> mapped = <String, bool>{};
  for (final Object? item in value) {
    if (item is! Map<String, dynamic>) continue;
    final String type = _string(item['type']);
    if (type.isEmpty) continue;
    mapped[type] = item['disabled'] == true;
  }
  return Map<String, bool>.unmodifiable(mapped);
}
