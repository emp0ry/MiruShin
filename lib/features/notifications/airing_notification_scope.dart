import '../../shared/models/anilist_models.dart';

enum AiringNotificationScope {
  all('all', 'All'),
  watchingAndRewatching('watchingAndRewatching', 'Watching/Rewatching');

  const AiringNotificationScope(this.cacheValue, this.labelKey);

  final String cacheValue;
  final String labelKey;

  static AiringNotificationScope fromCacheValue(Object? value) {
    final String raw = value?.toString() ?? '';
    return AiringNotificationScope.values.firstWhere(
      (AiringNotificationScope scope) =>
          scope.cacheValue == raw || scope.name == raw,
      orElse: () => AiringNotificationScope.all,
    );
  }

  bool includesStatus(AniListListStatus status) {
    return switch (this) {
      AiringNotificationScope.all =>
        status == AniListListStatus.current ||
            status == AniListListStatus.planning ||
            status == AniListListStatus.repeating,
      AiringNotificationScope.watchingAndRewatching =>
        status == AniListListStatus.current ||
            status == AniListListStatus.repeating,
    };
  }
}
