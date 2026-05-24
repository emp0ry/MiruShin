import '../../../shared/models/tracking_service.dart';

abstract interface class TrackingProvider {
  String get id;
  String get name;

  Future<void> authenticate();
  Future<void> disconnect();
  Future<void> syncLibrary();
  Future<void> updateProgress(String mediaId, double progress);
  Future<TrackingStatus> getStatus();
}
