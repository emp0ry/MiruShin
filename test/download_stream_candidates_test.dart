import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/downloads/application/download_stream_candidates.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';

void main() {
  const SoraEpisode episode = SoraEpisode(
    number: 1,
    href: 'episode',
    title: 'Episode',
    image: '',
    description: '',
    duration: '',
  );
  const NormalizedServer selected = NormalizedServer(
    id: 'selected',
    title: 'Selected',
    streamUrl: '',
    headers: <String, String>{'Referer': 'https://ref.invalid/'},
    qualities: <NormalizedQuality>[
      NormalizedQuality(label: '480p', streamUrl: 'https://media.invalid/480'),
      NormalizedQuality(
        label: '1080p',
        streamUrl: 'https://media.invalid/1080',
      ),
      NormalizedQuality(label: '720p', streamUrl: 'https://media.invalid/720'),
    ],
  );
  const NormalizedServer unrelated = NormalizedServer(
    id: 'other',
    title: 'Other',
    streamUrl: 'https://other.invalid/default',
  );
  const NormalizedStreamBundle bundle = NormalizedStreamBundle(
    addonId: 'module',
    episode: episode,
    selectedServer: selected,
    availableServers: <NormalizedServer>[selected, unrelated],
  );

  test('orders qualities from highest to lowest on the selected server', () {
    final candidates = buildDownloadStreamCandidates(
      bundle,
      DownloadStreamPreference.empty,
    );

    expect(candidates.map((candidate) => candidate.qualityLabel), <String>[
      '1080p',
      '720p',
      '480p',
    ]);
    expect(
      candidates.every((candidate) => candidate.key.startsWith('selected|')),
      isTrue,
    );
  });

  test(
    'tries explicit quality first and keeps lower qualities as fallbacks',
    () {
      final candidates = buildDownloadStreamCandidates(
        bundle,
        const DownloadStreamPreference(
          serverId: 'selected',
          qualityLabel: '720p',
        ),
      );

      expect(candidates.map((candidate) => candidate.qualityLabel), <String>[
        '720p',
        '1080p',
        '480p',
      ]);
    },
  );

  test('resume identity ignores rotated query tokens but not media paths', () {
    const DownloadStreamCandidate first = DownloadStreamCandidate(
      key: 'selected|1080p',
      url: 'https://media.invalid/show/episode.m3u8?token=old',
      headers: <String, String>{},
      qualityLabel: '1080p',
    );
    const DownloadStreamCandidate refreshedToken = DownloadStreamCandidate(
      key: 'selected|1080p',
      url: 'https://media.invalid/show/episode.m3u8?token=new',
      headers: <String, String>{},
      qualityLabel: '1080p',
    );
    const DownloadStreamCandidate changedMedia = DownloadStreamCandidate(
      key: 'selected|1080p',
      url: 'https://media.invalid/show/replacement.m3u8?token=new',
      headers: <String, String>{},
      qualityLabel: '1080p',
    );

    expect(
      stableDownloadCandidateKey(first),
      stableDownloadCandidateKey(refreshedToken),
    );
    expect(
      stableDownloadCandidateKey(first),
      isNot(stableDownloadCandidateKey(changedMedia)),
    );
  });
}
