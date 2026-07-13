import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/downloads/application/offline_playback.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
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
}) {
  final DateTime now = DateTime(2026);
  return DownloadedEpisode(
    id: 'episode-$season-$number',
    mediaId: _media.id,
    media: _media,
    addonId: 'addon',
    addonName: 'Addon',
    episodeHref: '/episode-$number',
    episodeNumber: number.toDouble(),
    seasonNumber: season,
    episodeTitle: 'Episode $number',
    episodeImage: '',
    qualityLabel: '720p',
    kind: DownloadKind.mp4,
    relDir: 'anilist-1/addon/S${season}E$number',
    videoFileName: 'video.mp4',
    mediaPosterFileName: mediaPosterFileName,
    mediaBackdropFileName: mediaBackdropFileName,
    episodeImageFileName: episodeImageFileName,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}
