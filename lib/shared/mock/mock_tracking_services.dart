import '../models/tracking_service.dart';

abstract final class MockTrackingServices {
  static final List<TrackingService> services = <TrackingService>[
    TrackingService(
      id: 'trakt',
      name: 'Trakt',
      description: 'General movie and series progress tracking.',
      type: TrackingServiceType.general,
      isConnected: true,
      isPrimary: true,
      isBackup: false,
      priority: 1,
      lastSyncAt: DateTime(2026, 4, 29, 22, 35),
      status: TrackingStatus.connected,
    ),
    TrackingService(
      id: 'anilist',
      name: 'AniList',
      description: 'Primary anime tracker for progress and planning.',
      type: TrackingServiceType.anime,
      isConnected: true,
      isPrimary: true,
      isBackup: false,
      priority: 1,
      lastSyncAt: DateTime(2026, 4, 29, 20, 12),
      status: TrackingStatus.connected,
    ),
    TrackingService(
      id: 'mal',
      name: 'MyAnimeList',
      description: 'Backup anime sync provider.',
      type: TrackingServiceType.anime,
      isConnected: false,
      isPrimary: false,
      isBackup: true,
      priority: 2,
      lastSyncAt: null,
      status: TrackingStatus.disconnected,
    ),
    TrackingService(
      id: 'shikimori',
      name: 'Shikimori',
      description: 'Optional anime backup sync provider.',
      type: TrackingServiceType.anime,
      isConnected: false,
      isPrimary: false,
      isBackup: true,
      priority: 3,
      lastSyncAt: null,
      status: TrackingStatus.unavailable,
    ),
  ];
}
