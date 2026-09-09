import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/downloads/application/offline_playback.dart';
import 'package:mirushin/features/downloads/data/download_store.dart';
import 'package:mirushin/features/downloads/domain/download_identity.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
import 'package:mirushin/features/player/application/playback_controller.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/watch_party/application/watch_party_controller.dart';
import 'package:mirushin/features/watch_party/application/watch_party_download_matcher.dart';
import 'package:mirushin/features/watch_party/application/watch_party_guest_resolver.dart';
import 'package:mirushin/features/watch_party/application/watch_party_source_descriptor.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('download stream identity', () {
    test(
      'quality is local while voiceover separates records and directories',
      () {
        const DownloadStreamPreference aniLibria720 = DownloadStreamPreference(
          serverId: 'server_0',
          voiceoverId: 'AniLibria',
          qualityLabel: '720p',
        );
        const DownloadStreamPreference aniLibria1080 = DownloadStreamPreference(
          serverId: 'server_0',
          voiceoverId: 'AniLibria',
          qualityLabel: '1080p',
        );
        const DownloadStreamPreference aniDub = DownloadStreamPreference(
          serverId: 'server_0',
          voiceoverId: 'AniDub',
          qualityLabel: '720p',
        );

        expect(
          downloadStreamVariantKey(aniLibria720),
          downloadStreamVariantKey(aniLibria1080),
        );
        expect(
          downloadStreamVariantKey(aniLibria720),
          isNot(downloadStreamVariantKey(aniDub)),
        );

        String recordId(DownloadStreamPreference preference) =>
            downloadEpisodeRecordId(
              mediaId: 'anilist:1',
              addonId: 'sora-addon',
              episodeHref: 'https://EXAMPLE.test/episode/1/',
              seasonNumber: 1,
              episodeNumber: 1,
              streamPreference: preference,
            );
        expect(recordId(aniLibria720), recordId(aniLibria1080));
        expect(recordId(aniLibria720), isNot(recordId(aniDub)));

        final DownloadStore store = DownloadStore();
        String relDir(DownloadStreamPreference preference) => store.relDirFor(
          mediaId: 'anilist:1',
          addonId: 'sora-addon',
          seasonNumber: 1,
          episodeNumber: 1,
          streamPreference: preference,
        );
        expect(relDir(aniLibria720), relDir(aniLibria1080));
        expect(relDir(aniLibria720), isNot(relDir(aniDub)));
      },
    );

    test('legacy records keep their existing directory and empty metadata', () {
      final DownloadedEpisode legacy = _download(
        id: 'legacy-record',
        preference: DownloadStreamPreference.empty,
      );
      final Map<String, dynamic> json = legacy.toJson()
        ..remove('streamPreference');
      final DownloadedEpisode restored = DownloadedEpisode.fromJson(json);

      expect(restored.relDir, legacy.relDir);
      expect(restored.streamPreference.isEmpty, isTrue);
      expect(downloadStreamVariantKey(restored.streamPreference), 'legacy');
    });
  });

  group('guest resolver routing policy', () {
    test('local copy wins with or without the module', () {
      for (final bool addonInstalled in <bool>[true, false]) {
        expect(
          watchPartyResolutionTarget(
            hasPlayableDownload: true,
            addonInstalled: addonInstalled,
          ),
          WatchPartyResolutionTarget.local,
        );
      }
    });

    test('missing or broken local copy falls back online exactly once', () {
      expect(
        watchPartyResolutionTarget(
          hasPlayableDownload: false,
          addonInstalled: true,
        ),
        WatchPartyResolutionTarget.online,
      );
      expect(
        watchPartyResolutionTarget(
          hasPlayableDownload: false,
          addonInstalled: false,
        ),
        WatchPartyResolutionTarget.missingAddon,
      );
    });

    test('rapid source events invalidate every earlier resolution', () {
      final WatchPartyResolutionGuard guard = WatchPartyResolutionGuard();
      final int firstEpisode = guard.begin();
      final int secondEpisode = guard.begin();
      final int latestVoiceover = guard.begin();

      expect(guard.isCurrent(firstEpisode), isFalse);
      expect(guard.isCurrent(secondEpisode), isFalse);
      expect(guard.isCurrent(latestVoiceover), isTrue);
    });

    test('matching download replaces an already open online source', () {
      expect(
        shouldReuseCurrentWatchPartySource(
          sameCurrentSource: true,
          currentSourceIsOffline: false,
          hasPlayableDownload: true,
        ),
        isFalse,
      );
      expect(
        shouldReuseCurrentWatchPartySource(
          sameCurrentSource: true,
          currentSourceIsOffline: false,
          hasPlayableDownload: false,
        ),
        isTrue,
      );
    });

    test('matching offline source is reused without a reload', () {
      expect(
        shouldReuseCurrentWatchPartySource(
          sameCurrentSource: true,
          currentSourceIsOffline: true,
          hasPlayableDownload: true,
        ),
        isTrue,
      );
      expect(
        shouldReuseCurrentWatchPartySource(
          sameCurrentSource: false,
          currentSourceIsOffline: true,
          hasPlayableDownload: true,
        ),
        isFalse,
      );
    });
  });

  group('watch-party local match', () {
    test('prefers exact stream and ignores quality', () {
      final DownloadedEpisode exact720 = _download(
        id: 'exact-720',
        preference: const DownloadStreamPreference(
          serverId: 'server_0',
          voiceoverId: 'AniLibria',
          qualityLabel: '720p',
        ),
      );
      final DownloadedEpisode wrongVoiceover = _download(
        id: 'wrong-voiceover',
        preference: const DownloadStreamPreference(
          serverId: 'server_0',
          voiceoverId: 'AniDub',
          qualityLabel: '1080p',
        ),
      );
      final DownloadedEpisode newerLegacy = _download(
        id: 'legacy',
        preference: DownloadStreamPreference.empty,
        updatedAt: DateTime(2026, 2),
      );

      final WatchPartyDownloadMatch? match = selectWatchPartyDownload(
        descriptor: _descriptor(qualityId: '1080p'),
        downloads: <DownloadedEpisode>[wrongVoiceover, newerLegacy, exact720],
        isPlayable: (_) => true,
      );

      expect(match?.episode.id, 'exact-720');
      expect(match?.isLegacyFallback, isFalse);
    });

    test('uses metadata-less legacy download only as episode fallback', () {
      final WatchPartyDownloadMatch? match = selectWatchPartyDownload(
        descriptor: _descriptor(),
        downloads: <DownloadedEpisode>[
          _download(
            id: 'different-href-legacy',
            href: '/old-episode-link',
            preference: DownloadStreamPreference.empty,
          ),
        ],
        isPlayable: (_) => true,
      );

      expect(match?.episode.id, 'different-href-legacy');
      expect(match?.isLegacyFallback, isTrue);
    });

    test('skips missing files and mismatched voiceovers', () {
      final WatchPartyDownloadMatch? match = selectWatchPartyDownload(
        descriptor: _descriptor(),
        downloads: <DownloadedEpisode>[
          _download(
            id: 'missing-file',
            preference: const DownloadStreamPreference(
              serverId: 'server_0',
              voiceoverId: 'AniLibria',
            ),
          ),
          _download(
            id: 'wrong-voiceover',
            preference: const DownloadStreamPreference(
              serverId: 'server_0',
              voiceoverId: 'AniDub',
            ),
          ),
        ],
        isPlayable: (DownloadedEpisode episode) => episode.id != 'missing-file',
      );

      expect(match, isNull);
    });

    test('matches the same media through provider identity', () {
      final DownloadedEpisode malDownload = _download(
        id: 'mal-copy',
        media: _media.copyWith(externalIds: const <String, String>{'mal': '1'}),
        mediaId: 'mal:1',
        preference: const DownloadStreamPreference(
          serverId: 'server_0',
          voiceoverId: 'AniLibria',
        ),
      );
      final SourceDescriptor descriptor = _descriptor(
        mediaId: 'anilist:999',
        externalIds: const <String, String>{'anilist': '999', 'mal': '1'},
      );

      expect(
        selectWatchPartyDownload(
          descriptor: descriptor,
          downloads: <DownloadedEpisode>[malDownload],
          isPlayable: (_) => true,
        )?.episode.id,
        'mal-copy',
      );
    });
  });

  group('controller source policy', () {
    for (final WatchPartyConnectionMode mode
        in WatchPartyConnectionMode.values) {
      test('$mode uses local quality semantics after initial snapshot', () {
        final SourceDescriptor initial = _descriptor(qualityId: '1080p');
        final WatchPartySourceApplyPolicy join = watchPartySourceApplyPolicy(
          connectionMode: mode,
          descriptor: initial,
          lastAppliedSource: null,
          eventType: WatchPartyEventType.stateSnapshot,
          hasPendingGuestStreamRequest: false,
        );
        expect(join.shouldApply, isTrue);
        expect(join.syncInitialQuality, isTrue);

        final SourceDescriptor qualityOnly = _descriptor(qualityId: '720p');
        final WatchPartySourceApplyPolicy heartbeat =
            watchPartySourceApplyPolicy(
              connectionMode: mode,
              descriptor: qualityOnly,
              lastAppliedSource: initial,
              eventType: WatchPartyEventType.positionSync,
              hasPendingGuestStreamRequest: false,
            );
        expect(heartbeat.shouldApply, isFalse);

        final WatchPartySourceApplyPolicy reconnect =
            watchPartySourceApplyPolicy(
              connectionMode: mode,
              descriptor: qualityOnly,
              lastAppliedSource: initial,
              eventType: WatchPartyEventType.stateSnapshot,
              hasPendingGuestStreamRequest: false,
            );
        expect(reconnect.shouldApply, isTrue);
        expect(reconnect.forceReload, isFalse);
        expect(reconnect.syncInitialQuality, isFalse);
      });

      test('$mode reloads only for episode, voiceover, or explicit retry', () {
        final SourceDescriptor current = _descriptor();
        final WatchPartySourceApplyPolicy voiceover =
            watchPartySourceApplyPolicy(
              connectionMode: mode,
              descriptor: _descriptor(voiceoverId: 'AniDub'),
              lastAppliedSource: current,
              eventType: WatchPartyEventType.sourceChanged,
              hasPendingGuestStreamRequest: false,
            );
        expect(voiceover.shouldApply, isTrue);
        expect(voiceover.forceReload, isFalse);

        final WatchPartySourceApplyPolicy retry = watchPartySourceApplyPolicy(
          connectionMode: mode,
          descriptor: current,
          lastAppliedSource: current,
          eventType: WatchPartyEventType.positionSync,
          hasPendingGuestStreamRequest: true,
        );
        expect(retry.shouldApply, isTrue);
        expect(retry.forceReload, isTrue);
      });
    }
  });

  test('offline descriptor preserves origin and never exposes local paths', () {
    final DownloadedEpisode episode = _download(
      id: 'local-download-id',
      media: _media.copyWith(
        posterUrl: 'https://cdn.test/poster.jpg',
        backdropUrl: 'https://cdn.test/backdrop.jpg',
        externalIds: const <String, String>{'anilist': '1', 'mal': '1'},
      ),
      preference: const DownloadStreamPreference(
        serverId: 'server_0',
        voiceoverId: 'AniLibria',
        qualityLabel: '720p',
      ),
      mediaPosterFileName: 'poster.jpg',
      mediaBackdropFileName: 'backdrop.jpg',
    );
    final MediaPlaybackItem item = buildOfflinePlaybackItem(
      episode: episode,
      rootPath: r'C:\downloads',
      moduleEpisodes: <DownloadedEpisode>[episode],
      startPosition: const Duration(seconds: 42),
      startPolicy: PlaybackStartPolicy.explicitPosition,
    );
    final SourceDescriptor descriptor = watchPartySourceDescriptorFor(
      PlaybackState(
        item: item,
        server: item.servers.single,
        quality: StreamQuality.auto,
      ),
    )!;

    expect(descriptor.serverId, 'server_0');
    expect(descriptor.voiceoverId, 'AniLibria');
    expect(descriptor.qualityId, '720p');
    expect(descriptor.posterUrl, 'https://cdn.test/poster.jpg');
    expect(descriptor.backdropUrl, 'https://cdn.test/backdrop.jpg');
    expect(item.startPosition, const Duration(seconds: 42));
    expect(item.startPolicy, PlaybackStartPolicy.explicitPosition);
    expect(
      descriptor.externalIds.keys,
      isNot(contains('mirushin_offline_media_path')),
    );
    expect(descriptor.toJson().toString(), isNot(contains(r'C:\downloads')));
    expect(descriptor.toJson().toString(), isNot(contains('file:')));
    expect(
      descriptor.toJson().toString(),
      isNot(contains('local-download-id')),
    );
  });

  test('offline auto-next stays in the same stream variant', () {
    final DownloadedEpisode current = _download(
      id: 'current',
      preference: _aniLibria,
    );
    final DownloadedEpisode sameVoiceover = _download(
      id: 'same-voiceover',
      number: 2,
      preference: _aniLibria,
    );
    final DownloadedEpisode otherVoiceover = _download(
      id: 'other-voiceover',
      number: 2,
      preference: const DownloadStreamPreference(
        serverId: 'server_0',
        voiceoverId: 'AniDub',
      ),
    );

    final List<DownloadedEpisode> filtered = offlineModuleEpisodesFor(
      current,
      <DownloadedEpisode>[current, otherVoiceover, sameVoiceover],
    );
    expect(filtered.map((DownloadedEpisode episode) => episode.id), <String>[
      'current',
      'same-voiceover',
    ]);
    expect(nextDownloadedEpisode(current, filtered)?.id, 'same-voiceover');
  });
}

const DownloadStreamPreference _aniLibria = DownloadStreamPreference(
  serverId: 'server_0',
  voiceoverId: 'AniLibria',
);

const MediaItem _media = MediaItem(
  id: 'anilist:1',
  title: 'Test Anime',
  originalTitle: 'Test Anime',
  overview: '',
  type: MediaType.anime,
  year: 2026,
  posterUrl: '',
  backdropUrl: '',
  rating: 0,
  genres: <String>[],
  sourceProvider: 'AniList',
  externalIds: <String, String>{'anilist': '1', 'mal': '1'},
  episodeCount: 12,
  statusLabel: 'Releasing',
);

SourceDescriptor _descriptor({
  String mediaId = 'anilist:1',
  Map<String, String> externalIds = const <String, String>{
    'anilist': '1',
    'mal': '1',
  },
  String serverId = 'server_0',
  String voiceoverId = 'AniLibria',
  String? qualityId,
}) {
  return SourceDescriptor(
    mediaId: mediaId,
    title: 'Test Anime',
    originalTitle: 'Test Anime',
    posterUrl: '',
    backdropUrl: '',
    mediaType: MediaType.anime,
    externalIds: externalIds,
    soraAddonId: 'sora-addon',
    soraEpisodeHref: 'https://example.test/episode/1',
    seasonNumber: 1,
    episodeNumber: 1,
    serverId: serverId,
    voiceoverId: voiceoverId,
    qualityId: qualityId,
  );
}

DownloadedEpisode _download({
  required String id,
  int number = 1,
  String href = 'https://example.test/episode/1',
  MediaItem media = _media,
  String? mediaId,
  DownloadStreamPreference preference = _aniLibria,
  DateTime? updatedAt,
  String mediaPosterFileName = '',
  String mediaBackdropFileName = '',
}) {
  final DateTime timestamp = updatedAt ?? DateTime(2026, 1);
  return DownloadedEpisode(
    id: id,
    mediaId: mediaId ?? media.id,
    media: media,
    addonId: 'sora-addon',
    addonName: 'Sora Addon',
    episodeHref: number == 1 ? href : 'https://example.test/episode/$number',
    episodeNumber: number.toDouble(),
    seasonNumber: 1,
    episodeTitle: 'Episode $number',
    episodeImage: '',
    qualityLabel: preference.qualityLabel,
    kind: DownloadKind.mp4,
    relDir: 'media/addon/S1E$number/variant',
    videoFileName: 'video.mp4',
    mediaPosterFileName: mediaPosterFileName,
    mediaBackdropFileName: mediaBackdropFileName,
    streamPreference: preference,
    status: DownloadStatus.completed,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
