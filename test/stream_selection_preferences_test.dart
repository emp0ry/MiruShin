import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/watch/application/stream_selection_preferences.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const SoraEpisode episode = SoraEpisode(
    number: 1,
    href: '/episode-1',
    title: 'Episode 1',
    image: '',
    description: '',
    duration: '',
  );
  const NormalizedServer firstServer = NormalizedServer(
    id: 'server-a',
    title: 'Server A',
    streamUrl: 'https://a.invalid/default',
    qualities: <NormalizedQuality>[
      NormalizedQuality(label: '480p', streamUrl: 'https://a.invalid/480'),
      NormalizedQuality(label: '720p', streamUrl: 'https://a.invalid/720'),
    ],
  );
  const NormalizedServer secondServer = NormalizedServer(
    id: 'server-b',
    title: 'Server B',
    streamUrl: 'https://b.invalid/default',
    qualities: <NormalizedQuality>[
      NormalizedQuality(label: '720p', streamUrl: 'https://b.invalid/720'),
      NormalizedQuality(label: '1080p', streamUrl: 'https://b.invalid/1080'),
    ],
  );
  const NormalizedStreamBundle bundle = NormalizedStreamBundle(
    addonId: 'addon',
    episode: episode,
    selectedServer: firstServer,
    availableServers: <NormalizedServer>[firstServer, secondServer],
    selectedQuality: NormalizedQuality(
      label: '480p',
      streamUrl: 'https://a.invalid/480',
    ),
    availableQualities: <NormalizedQuality>[
      NormalizedQuality(label: '480p', streamUrl: 'https://a.invalid/480'),
      NormalizedQuality(label: '720p', streamUrl: 'https://a.invalid/720'),
    ],
  );

  test('reselects the remembered server and quality', () {
    final AppliedStreamSelection applied = applyStreamSelectionPreference(
      bundle,
      const StreamSelectionPreference(
        serverId: 'server-b',
        serverTitle: 'Server B',
        qualityId: '1080p',
        qualityLabel: '1080P',
      ),
    );

    expect(applied.bundle.selectedServer.id, 'server-b');
    expect(applied.bundle.selectedQuality?.label, '1080p');
    expect(applied.initialQualityLabel, '1080p');
  });

  test(
    'missing remembered server falls back to the first server and quality',
    () {
      final AppliedStreamSelection applied = applyStreamSelectionPreference(
        bundle.withServer(secondServer),
        const StreamSelectionPreference(
          serverId: 'removed-server',
          qualityLabel: '2160p',
        ),
      );

      expect(applied.bundle.selectedServer.id, 'server-a');
      expect(applied.bundle.selectedQuality?.label, '480p');
      expect(applied.initialQualityLabel, '480p');
    },
  );

  test('missing remembered quality falls back to the server first quality', () {
    final AppliedStreamSelection applied = applyStreamSelectionPreference(
      bundle,
      const StreamSelectionPreference(
        serverId: 'server-b',
        qualityLabel: '2160p',
      ),
    );

    expect(applied.bundle.selectedServer.id, 'server-b');
    expect(applied.bundle.selectedQuality?.label, '720p');
    expect(applied.initialQualityLabel, '720p');
  });

  test(
    'selection persists across store instances and is scoped per title',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final StreamSelectionPreferenceStore writer =
          StreamSelectionPreferenceStore(preferences: preferences);
      const StreamSelectionPreference selection = StreamSelectionPreference(
        serverId: 'server-b',
        serverTitle: 'Server B',
        qualityId: '1080p',
        qualityLabel: '1080p',
      );

      await writer.save(
        mediaType: MediaType.anime,
        mediaId: 'title-1',
        preference: selection,
      );

      final StreamSelectionPreferenceStore reader =
          StreamSelectionPreferenceStore(preferences: preferences);
      final StreamSelectionPreference? restored = await reader.read(
        mediaType: MediaType.anime,
        mediaId: 'title-1',
      );
      final StreamSelectionPreference? otherTitle = await reader.read(
        mediaType: MediaType.anime,
        mediaId: 'title-2',
      );
      final StreamSelectionPreference? otherType = await reader.read(
        mediaType: MediaType.movie,
        mediaId: 'title-1',
      );

      expect(restored?.serverId, 'server-b');
      expect(restored?.qualityLabel, '1080p');
      expect(otherTitle, isNull);
      expect(otherType, isNull);
    },
  );
}
