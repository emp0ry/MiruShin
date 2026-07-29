import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/notifications/airing_notification_scope.dart';
import 'package:mirushin/features/profile/domain/anilist_profile_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';

void main() {
  test('all scope preserves existing eligible airing statuses', () {
    expect(
      AiringNotificationScope.all.includesStatus(AniListListStatus.current),
      isTrue,
    );
    expect(
      AiringNotificationScope.all.includesStatus(AniListListStatus.planning),
      isTrue,
    );
    expect(
      AiringNotificationScope.all.includesStatus(AniListListStatus.repeating),
      isTrue,
    );
    expect(
      AiringNotificationScope.all.includesStatus(AniListListStatus.paused),
      isFalse,
    );
  });

  test('watching and rewatching scope excludes planned entries', () {
    expect(
      AiringNotificationScope.watchingAndRewatching.includesStatus(
        AniListListStatus.current,
      ),
      isTrue,
    );
    expect(
      AiringNotificationScope.watchingAndRewatching.includesStatus(
        AniListListStatus.repeating,
      ),
      isTrue,
    );
    expect(
      AiringNotificationScope.watchingAndRewatching.includesStatus(
        AniListListStatus.planning,
      ),
      isFalse,
    );
  });

  test('user settings cache persists local airing notification scope', () {
    const AniListUserSettings settings = AniListUserSettings(
      airingNotificationScope: AiringNotificationScope.watchingAndRewatching,
    );

    final Map<String, dynamic> cache = settings.toCacheJson();
    expect(
      cache['airingNotificationScope'],
      AiringNotificationScope.watchingAndRewatching.cacheValue,
    );
    expect(
      AniListUserSettings.fromCacheJson(cache).airingNotificationScope,
      AiringNotificationScope.watchingAndRewatching,
    );
    expect(
      settings.toGraphQlVariables(),
      isNot(contains('airingNotificationScope')),
    );
  });
}
