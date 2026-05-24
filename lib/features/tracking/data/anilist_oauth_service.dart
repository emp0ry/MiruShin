import 'package:url_launcher/url_launcher.dart';

import '../../../shared/models/anilist_models.dart';
import 'anilist_oauth_listener.dart';

class AniListOAuthService {
  const AniListOAuthService();

  Uri buildImplicitAuthUri({required String clientId}) {
    return Uri.https('anilist.co', '/api/v2/oauth/authorize', <String, String>{
      'client_id': clientId.trim(),
      'response_type': 'token',
    });
  }

  Future<AniListOAuthResult?> loginWithDesktopBrowser({
    required String clientId,
    required int port,
  }) async {
    final AniListOAuthListener listener = await startAniListOAuthListener(
      port: port,
    );
    try {
      final Uri uri = buildImplicitAuthUri(clientId: clientId);
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await listener.cancel();
        return null;
      }
      return listener.wait();
    } catch (_) {
      await listener.cancel();
      rethrow;
    }
  }
}
