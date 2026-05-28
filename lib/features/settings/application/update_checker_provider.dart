import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.releaseUrl,
    required this.hasUpdate,
  });

  final String tagName;
  final String releaseUrl;
  final bool hasUpdate;
}

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
    final Map<String, dynamic> data =
        response.data as Map<String, dynamic>;
    final String tagName =
        (data['tag_name'] as String? ?? '').trim();
    final String htmlUrl =
        (data['html_url'] as String?)?.trim() ??
            AppConstants.githubLatestReleaseUrl;

    if (tagName.isEmpty) return null;

    final String latestClean = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    final String currentClean =
        AppConstants.appVersion.split('+').first.trim();

    return UpdateInfo(
      tagName: tagName,
      releaseUrl: htmlUrl,
      hasUpdate: _isNewerVersion(latestClean, currentClean),
    );
  } catch (_) {
    return null;
  }
});

bool _isNewerVersion(String latest, String current) {
  try {
    final List<int> l =
        latest.split('.').map(int.parse).toList(growable: false);
    final List<int> c =
        current.split('.').map(int.parse).toList(growable: false);
    final int len = l.length > c.length ? l.length : c.length;
    for (int i = 0; i < len; i++) {
      final int lv = i < l.length ? l[i] : 0;
      final int cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  } catch (_) {
    return false;
  }
}
