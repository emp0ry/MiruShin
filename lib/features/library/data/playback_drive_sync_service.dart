import '../application/canonical_library_repository.dart';
import '../domain/playback_sync_models.dart';

class PlaybackDriveSyncService {
  const PlaybackDriveSyncService({required this.repository});

  final CanonicalLibraryRepository repository;

  Future<void> sync({
    required PlaybackCloudReplica cloud,
    required void Function() requireActive,
  }) async {
    final pending = await repository.pendingPlaybackDeliveryIds();
    final before = await repository.buildPlaybackSnapshot();
    final previousChecksum = await repository.lastPlaybackChecksum();
    // Also seeds existing local history on upgrade, with its original times.
    final needsPush =
        pending.isNotEmpty ||
        (!before.isEmpty && before.contentChecksum != previousChecksum);
    final incoming = await cloud.pullPlaybackSnapshots(
      excluding: await repository.processedPlaybackChecksums(),
    );
    for (final snapshot in incoming.snapshots) {
      requireActive();
      await repository.applyPlaybackSnapshot(snapshot);
    }
    requireActive();
    final outgoing = await repository.buildPlaybackSnapshot();
    // Seed this device on a new/cleared Google account as well. A local
    // fingerprint alone cannot prove that the current Drive holds its file.
    if (!outgoing.isEmpty &&
        (needsPush || !incoming.fileNames.contains(outgoing.fileName))) {
      requireActive();
      await cloud.pushPlaybackSnapshot(outgoing);
      requireActive();
    }
    // Only acknowledge operations captured before networking. A checkpoint
    // saved while uploading remains pending for the next debounced pass.
    await repository.markPlaybackSynced(
      outgoing.contentChecksum,
      deliveryIds: pending,
    );
  }
}
