import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/tracking_service.dart';
import '../domain/tracking_provider.dart';
import 'anilist_api_client.dart';

class AniListTrackingProvider implements TrackingProvider {
  AniListTrackingProvider({required String accessToken})
    : _client = AniListApiClient(accessToken: accessToken);

  final AniListApiClient _client;

  @override
  String get id => 'anilist';

  @override
  String get name => 'AniList';

  @override
  Future<void> authenticate() async {
    await _client.fetchViewer();
  }

  @override
  Future<void> disconnect() async {
    // Token removal belongs to the settings/auth controller.
  }

  @override
  Future<void> syncLibrary() async {
    await _client.fetchAnimeListCollection();
  }

  @override
  Future<void> updateProgress(String mediaId, double progress) async {
    final int? aniListId = int.tryParse(mediaId.split(':').last);
    if (aniListId == null) {
      throw ArgumentError.value(
        mediaId,
        'mediaId',
        'Expected an AniList media id.',
      );
    }
    await _client.updateProgress(
      mediaId: aniListId,
      progress: progress.round(),
      status: AniListListStatus.current,
    );
  }

  @override
  Future<TrackingStatus> getStatus() async {
    try {
      await _client.fetchViewer();
      return TrackingStatus.connected;
    } catch (_) {
      return TrackingStatus.error;
    }
  }
}
