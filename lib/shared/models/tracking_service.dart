enum TrackingServiceType { general, anime }

enum TrackingStatus { connected, disconnected, syncing, error, unavailable }

extension TrackingStatusLabel on TrackingStatus {
  String get label {
    return switch (this) {
      TrackingStatus.connected => 'Connected',
      TrackingStatus.disconnected => 'Disconnected',
      TrackingStatus.syncing => 'Syncing',
      TrackingStatus.error => 'Error',
      TrackingStatus.unavailable => 'Unavailable',
    };
  }
}

class TrackingService {
  const TrackingService({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.isConnected,
    required this.isPrimary,
    required this.isBackup,
    required this.priority,
    this.lastSyncAt,
    required this.status,
  });

  final String id;
  final String name;
  final String description;
  final TrackingServiceType type;
  final bool isConnected;
  final bool isPrimary;
  final bool isBackup;
  final int priority;
  final DateTime? lastSyncAt;
  final TrackingStatus status;
}
