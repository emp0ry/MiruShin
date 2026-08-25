import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../domain/update_models.dart';

export '../domain/update_models.dart' show UpdateInfo;

final updateCheckerProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    final Response<dynamic> response = await Dio().get<dynamic>(
      'https://api.github.com/repos/emp0ry/MiruShin/releases/latest',
      options: Options(
        headers: <String, String>{'Accept': 'application/vnd.github+json'},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final String tagName = (data['tag_name'] as String? ?? '').trim();
    final String htmlUrl =
        (data['html_url'] as String?)?.trim() ??
        AppConstants.githubLatestReleaseUrl;
    final String releaseNotes = (data['body'] as String? ?? '').trim();
    final List<UpdateAsset> assets =
        (data['assets'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(_parseAsset)
            .whereType<UpdateAsset>()
            .toList(growable: false);

    if (tagName.isEmpty) return null;

    final String latestClean = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    final String currentClean = AppConstants.appVersion.split('+').first.trim();

    return UpdateInfo(
      tagName: tagName,
      releaseUrl: htmlUrl,
      hasUpdate: isNewerVersion(latestClean, currentClean),
      assets: assets,
      releaseNotes: releaseNotes,
    );
  } catch (_) {
    return null;
  }
});

UpdateAsset? _parseAsset(Map<String, dynamic> data) {
  final String name = (data['name'] as String? ?? '').trim();
  final String downloadUrl = (data['browser_download_url'] as String? ?? '')
      .trim();
  final Uri? uri = Uri.tryParse(downloadUrl);
  if (name.isEmpty || uri == null || uri.scheme != 'https') return null;

  return UpdateAsset(
    name: name,
    downloadUrl: downloadUrl,
    size: (data['size'] as num?)?.toInt() ?? 0,
    digest: (data['digest'] as String?)?.trim(),
  );
}
