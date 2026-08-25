enum DesktopUpdatePlatform { windows, macos, linux }

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.digest,
  });

  final String name;
  final String downloadUrl;
  final int size;
  final String? digest;

  String? get sha256Digest => normalizeSha256Digest(digest);
}

class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.releaseUrl,
    required this.hasUpdate,
    this.assets = const <UpdateAsset>[],
    this.releaseNotes = '',
  });

  final String tagName;
  final String releaseUrl;
  final bool hasUpdate;
  final List<UpdateAsset> assets;
  final String releaseNotes;
}

UpdateAsset? selectDesktopUpdateAsset(
  List<UpdateAsset> assets,
  DesktopUpdatePlatform platform,
) {
  final List<UpdateAsset> candidates = assets
      .where((UpdateAsset asset) {
        final String name = asset.name.toLowerCase();
        return switch (platform) {
          DesktopUpdatePlatform.windows =>
            name.contains('windows') &&
                (name.endsWith('.exe') || name.endsWith('.msi')),
          DesktopUpdatePlatform.macos =>
            name.contains('macos') && name.endsWith('.dmg'),
          DesktopUpdatePlatform.linux =>
            name.contains('linux') && name.endsWith('.appimage'),
        };
      })
      .toList(growable: false);

  if (candidates.isEmpty) return null;
  if (platform == DesktopUpdatePlatform.windows) {
    for (final UpdateAsset asset in candidates) {
      final String name = asset.name.toLowerCase();
      if (name.contains('setup') && name.endsWith('.exe')) return asset;
    }
    for (final UpdateAsset asset in candidates) {
      if (asset.name.toLowerCase().endsWith('.msi')) return asset;
    }
  }
  return candidates.first;
}

bool isNewerVersion(String latest, String current) {
  final List<int>? latestParts = _numericVersionParts(latest);
  final List<int>? currentParts = _numericVersionParts(current);
  if (latestParts == null || currentParts == null) return false;

  final int length = latestParts.length > currentParts.length
      ? latestParts.length
      : currentParts.length;
  for (int index = 0; index < length; index++) {
    final int latestPart = index < latestParts.length ? latestParts[index] : 0;
    final int currentPart = index < currentParts.length
        ? currentParts[index]
        : 0;
    if (latestPart != currentPart) return latestPart > currentPart;
  }
  return false;
}

String? normalizeSha256Digest(String? digest) {
  if (digest == null) return null;
  final Match? match = RegExp(
    r'^sha256:([0-9a-f]{64})$',
    caseSensitive: false,
  ).firstMatch(digest.trim());
  return match?.group(1)?.toLowerCase();
}

List<int>? _numericVersionParts(String version) {
  String value = version.trim();
  if (value.toLowerCase().startsWith('v')) value = value.substring(1);
  value = value.split('+').first.split('-').first;
  if (value.isEmpty) return null;

  final List<int> parts = <int>[];
  for (final String part in value.split('.')) {
    final int? number = int.tryParse(part);
    if (number == null || number < 0) return null;
    parts.add(number);
  }
  return parts;
}
