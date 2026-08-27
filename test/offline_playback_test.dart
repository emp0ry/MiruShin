import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/downloads/application/offline_playback.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/presentation/player_page.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('offlineContinueEpisode', () {
    test('returns the first unwatched download after watched downloads', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2),
        _episode(3),
        _episode(4),
      ];
      final Set<String> watched = <String>{episodes[0].id, episodes[1].id};

      final DownloadedEpisode? result = offlineContinueEpisode(
        episodes,
        isWatched: (DownloadedEpisode episode) => watched.contains(episode.id),
      );

      expect(result?.episodeNumber, 3);
    });

    test('continues from the first available gap episode', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(3),
        _episode(4),
      ];

      final DownloadedEpisode? result = offlineContinueEpisode(
        episodes,
        isWatched: (_) => false,
      );

      expect(result?.episodeNumber, 3);
    });

    test('does not mark a fresh episode 1 download as continue', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2),
      ];

      final DownloadedEpisode? result = offlineContinueEpisode(
        episodes,
        isWatched: (_) => false,
      );

      expect(result, isNull);
    });

    test('returns null when every playable download is watched', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(3),
        _episode(4),
      ];
      final Set<String> watched = episodes
          .map((DownloadedEpisode episode) => episode.id)
          .toSet();

      final DownloadedEpisode? result = offlineContinueEpisode(
        episodes,
        isWatched: (DownloadedEpisode episode) => watched.contains(episode.id),
      );

      expect(result, isNull);
    });
  });

  group('buildOfflinePlaybackItem', () {
    test('uses cached local artwork for offline player metadata', () {
      final DownloadedEpisode episode = _episode(
        3,
        mediaPosterFileName: 'poster.jpg',
        mediaBackdropFileName: 'backdrop.jpg',
        episodeImageFileName: 'episode.jpg',
      );

      final item = buildOfflinePlaybackItem(
        episode: episode,
        rootPath: '/downloads',
        moduleEpisodes: <DownloadedEpisode>[episode],
      );

      expect(
        item.posterUrl,
        Uri.file('/downloads/${episode.relDir}/poster.jpg').toString(),
      );
      expect(
        item.backdropUrl,
        Uri.file('/downloads/${episode.relDir}/backdrop.jpg').toString(),
      );
      expect(
        item.seasons.single.episodes.single.thumbnailUrl,
        Uri.file('/downloads/${episode.relDir}/episode.jpg').toString(),
      );
    });

    test('uses local file URIs for downloaded subtitles', () {
      final DownloadedEpisode episode = _episode(
        3,
        subtitles: const <DownloadedSubtitle>[
          DownloadedSubtitle(
            language: 'en',
            label: 'English',
            fileName: 'sub_en.ass',
          ),
        ],
      );

      final item = buildOfflinePlaybackItem(
        episode: episode,
        rootPath: '/downloads',
      );
      final SubtitleTrack subtitle = item.servers.single.subtitles.single;

      expect(
        subtitle.url,
        Uri.file('/downloads/${episode.relDir}/sub_en.ass').toString(),
      );
      expect(subtitle.format, SubtitleFormat.ass);
    });

    test('preserves downloaded DASH format for safe backend routing', () {
      final DownloadedEpisode episode = _episode(
        3,
        kind: DownloadKind.dash,
        videoFileName: 'index.m3u8',
      );

      final item = buildOfflinePlaybackItem(
        episode: episode,
        rootPath: '/downloads',
      );

      expect(item.servers.single.streamType, StreamType.dash);
      expect(item.servers.single.url, endsWith('index.m3u8'));
    });
  });

  group('offline player continuation', () {
    test('auto-next preserves live fullscreen state', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2),
      ];

      final OfflinePlayerContinuation? continuation =
          offlinePlayerContinuationForResult(
            result: const PlayerNextEpisodeResult(startInFullscreen: true),
            current: episodes.first,
            moduleEpisodes: episodes,
          );

      expect(continuation?.episode.id, episodes.last.id);
      expect(continuation?.startInFullscreen, isTrue);
    });

    test('offline next route builds a fullscreen player page', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2),
      ];
      final OfflinePlayerContinuation continuation =
          offlinePlayerContinuationForResult(
            result: const PlayerNextEpisodeResult(startInFullscreen: true),
            current: episodes.first,
            moduleEpisodes: episodes,
          )!;
      final MediaPlaybackItem nextItem = buildOfflinePlaybackItem(
        episode: continuation.episode,
        rootPath: r'C:\downloads',
        moduleEpisodes: episodes,
      );
      final DirectPlayerRouteArgs routeArgs = DirectPlayerRouteArgs(
        item: nextItem,
        startInFullscreen: continuation.startInFullscreen,
      );

      final PlayerPage page = PlayerPage(
        item: routeArgs.item,
        startInFullscreen: routeArgs.startInFullscreen,
      );

      expect(page.item.servers.single.id, 'offline');
      expect(page.item.servers.single.url, startsWith('file:'));
      expect(page.startInFullscreen, isTrue);
    });

    test('auto-next remains windowed after fullscreen was exited', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2),
      ];

      final OfflinePlayerContinuation? continuation =
          offlinePlayerContinuationForResult(
            result: const PlayerNextEpisodeResult(startInFullscreen: false),
            current: episodes.first,
            moduleEpisodes: episodes,
          );

      expect(continuation?.episode.id, episodes.last.id);
      expect(continuation?.startInFullscreen, isFalse);
    });

    test('in-player selection preserves fullscreen state', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2),
      ];

      final OfflinePlayerContinuation? continuation =
          offlinePlayerContinuationForResult(
            result: PlayerEpisodeSelectionResult(
              episodeHref: episodes.last.episodeHref,
              startInFullscreen: true,
            ),
            current: episodes.first,
            moduleEpisodes: episodes,
          );

      expect(continuation?.episode.id, episodes.last.id);
      expect(continuation?.startInFullscreen, isTrue);
    });

    test('missing next episode produces no continuation', () {
      final DownloadedEpisode episode = _episode(1);

      expect(
        offlinePlayerContinuationForResult(
          result: const PlayerNextEpisodeResult(startInFullscreen: true),
          current: episode,
          moduleEpisodes: <DownloadedEpisode>[episode],
        ),
        isNull,
      );
    });

    test('captures next from snapshot before current is deleted', () {
      final List<DownloadedEpisode> snapshot =
          List<DownloadedEpisode>.unmodifiable(<DownloadedEpisode>[
            _episode(1),
            _episode(2),
          ]);
      final OfflinePlayerContinuation? continuation =
          offlinePlayerContinuationForResult(
            result: const PlayerNextEpisodeResult(startInFullscreen: true),
            current: snapshot.first,
            moduleEpisodes: snapshot,
          );
      final List<DownloadedEpisode> afterDelete = snapshot
          .where((DownloadedEpisode episode) => episode.id != snapshot.first.id)
          .toList(growable: false);

      expect(afterDelete, hasLength(1));
      expect(continuation?.episode.id, snapshot.last.id);
      expect(continuation?.startInFullscreen, isTrue);
    });

    test('changed download id falls back to normalized episode href', () {
      final DownloadedEpisode current = _episode(
        1,
        id: 'new-generated-id',
        href: 'https://provider.test/episode-1/',
      );
      final List<DownloadedEpisode> snapshot = <DownloadedEpisode>[
        _episode(
          1,
          id: 'old-generated-id',
          href: 'https://PROVIDER.test/episode-1',
        ),
        _episode(2),
      ];

      expect(nextDownloadedEpisode(current, snapshot)?.episodeNumber, 2);
    });

    test('missing id and href fall back to addon season and number', () {
      final DownloadedEpisode current = _episode(
        1,
        id: 'changed-id',
        href: '/changed-href',
      );
      final List<DownloadedEpisode> snapshot = <DownloadedEpisode>[
        _episode(1, id: 'snapshot-id', href: '/original-href'),
        _episode(2),
      ];

      expect(nextDownloadedEpisode(current, snapshot)?.episodeNumber, 2);
    });

    test('episode selection accepts normalized href', () {
      final List<DownloadedEpisode> episodes = <DownloadedEpisode>[
        _episode(1),
        _episode(2, href: 'https://provider.test/episode-2/'),
      ];

      final OfflinePlayerContinuation? continuation =
          offlinePlayerContinuationForResult(
            result: const PlayerEpisodeSelectionResult(
              episodeHref: 'https://PROVIDER.test/episode-2',
              startInFullscreen: false,
            ),
            current: episodes.first,
            moduleEpisodes: episodes,
          );

      expect(continuation?.episode.episodeNumber, 2);
    });
  });
}

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
  externalIds: <String, String>{},
  episodeCount: 12,
  statusLabel: 'Releasing',
);

DownloadedEpisode _episode(
  int number, {
  int season = 1,
  DownloadStatus status = DownloadStatus.completed,
  String mediaPosterFileName = '',
  String mediaBackdropFileName = '',
  String episodeImageFileName = '',
  List<DownloadedSubtitle> subtitles = const <DownloadedSubtitle>[],
  DownloadKind kind = DownloadKind.mp4,
  String videoFileName = 'video.mp4',
  String? id,
  String? href,
}) {
  final DateTime now = DateTime(2026);
  return DownloadedEpisode(
    id: id ?? 'episode-$season-$number',
    mediaId: _media.id,
    media: _media,
    addonId: 'addon',
    addonName: 'Addon',
    episodeHref: href ?? '/episode-$number',
    episodeNumber: number.toDouble(),
    seasonNumber: season,
    episodeTitle: 'Episode $number',
    episodeImage: '',
    qualityLabel: '720p',
    kind: kind,
    relDir: 'anilist-1/addon/S${season}E$number',
    videoFileName: videoFileName,
    mediaPosterFileName: mediaPosterFileName,
    mediaBackdropFileName: mediaBackdropFileName,
    episodeImageFileName: episodeImageFileName,
    subtitles: subtitles,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}
