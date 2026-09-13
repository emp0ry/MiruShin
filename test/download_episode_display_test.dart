import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/downloads/application/download_episode_display.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('downloaded episode technical metadata', () {
    test('uses downloaded quality and the human voiceover label', () {
      final DownloadedEpisode episode = _episode(
        qualityLabel: '1080p',
        streamPreference: const DownloadStreamPreference(
          qualityLabel: '720p',
          voiceoverId: 'anilibria',
          voiceoverLabel: 'AniLibria',
        ),
      );

      expect(downloadedEpisodeQualityLabel(episode), '1080p');
      expect(downloadedEpisodeVoiceoverLabel(episode), 'AniLibria');
    });

    test('falls back to persisted selection metadata', () {
      final DownloadedEpisode episode = _episode(
        streamPreference: const DownloadStreamPreference(
          qualityLabel: '720p',
          voiceoverId: 'AniDub',
        ),
      );

      expect(downloadedEpisodeQualityLabel(episode), '720p');
      expect(downloadedEpisodeVoiceoverLabel(episode), 'AniDub');
    });

    test('uses the server label when a module models dubs as servers', () {
      final DownloadedEpisode episode = _episode(
        streamPreference: const DownloadStreamPreference(
          serverId: 'server-1',
          serverTitle: 'AniLibria',
        ),
      );

      expect(downloadedEpisodeVoiceoverLabel(episode), 'AniLibria');
    });

    test('uses received bytes for segmented downloads without a total', () {
      final DownloadedEpisode episode = _episode(
        kind: DownloadKind.hls,
        totalBytes: 0,
        receivedBytes: 734003200,
      );

      expect(downloadedEpisodeSizeBytes(episode), 734003200);
    });

    test('keeps the known total for progressive downloads', () {
      final DownloadedEpisode episode = _episode(
        totalBytes: 1073741824,
        receivedBytes: 1073741800,
      );

      expect(downloadedEpisodeSizeBytes(episode), 1073741824);
    });
  });
}

DownloadedEpisode _episode({
  String qualityLabel = '',
  DownloadStreamPreference streamPreference = DownloadStreamPreference.empty,
  DownloadKind kind = DownloadKind.mp4,
  int totalBytes = 0,
  int receivedBytes = 0,
}) {
  final DateTime now = DateTime.utc(2026);
  return DownloadedEpisode(
    id: 'episode',
    mediaId: 'media',
    media: const MediaItem(
      id: 'media',
      title: 'Title',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: <String>[],
      sourceProvider: 'AniList',
      externalIds: <String, String>{},
      statusLabel: 'Finished',
    ),
    addonId: 'addon',
    addonName: 'Addon',
    episodeHref: '/episode-1',
    episodeNumber: 1,
    seasonNumber: 1,
    episodeTitle: 'Episode 1',
    episodeImage: '',
    qualityLabel: qualityLabel,
    kind: kind,
    relDir: 'media/addon/S1E1/stream',
    videoFileName: kind == DownloadKind.mp4 ? 'video.mp4' : 'index.m3u8',
    streamPreference: streamPreference,
    totalBytes: totalBytes,
    receivedBytes: receivedBytes,
    status: DownloadStatus.completed,
    createdAt: now,
    updatedAt: now,
  );
}
