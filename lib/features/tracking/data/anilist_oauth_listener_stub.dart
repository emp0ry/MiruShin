import '../../../shared/models/anilist_models.dart';

class AniListOAuthListener {
  Future<AniListOAuthResult?> wait() async => null;

  Future<void> cancel() async {}
}

Future<AniListOAuthListener> startAniListOAuthListener({required int port}) {
  throw UnsupportedError('Localhost OAuth listener is not available here.');
}
