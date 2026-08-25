import '../../watch/domain/normalized_models.dart';
import '../domain/download_models.dart';

class DownloadStreamCandidate {
  const DownloadStreamCandidate({
    required this.key,
    required this.url,
    required this.headers,
    required this.qualityLabel,
  });

  final String key;
  final String url;
  final Map<String, String> headers;
  final String qualityLabel;
}

/// A stable identity for resumable media artifacts.
///
/// Signed stream URLs commonly rotate query parameters while continuing to
/// identify the same media path. Excluding the query preserves valid partial
/// segments across descriptor refreshes, while a changed authority or path
/// still forces DownloadEngine to clear incompatible files.
String stableDownloadCandidateKey(DownloadStreamCandidate candidate) {
  final Uri? uri = Uri.tryParse(candidate.url.trim());
  if (uri == null || !uri.hasScheme) {
    return '${candidate.key}|${candidate.url.trim()}';
  }
  final Uri stableUri = uri.replace(query: '', fragment: '');
  return '${candidate.key}|$stableUri';
}

/// Builds an ordered fallback chain without depending on any source or host.
/// The selected server is kept stable so a failed quality cannot silently
/// change language or voice track. Within it, the explicit quality is tried
/// first, followed by the remaining qualities from highest to lowest.
List<DownloadStreamCandidate> buildDownloadStreamCandidates(
  NormalizedStreamBundle bundle,
  DownloadStreamPreference preference,
) {
  final NormalizedServer? preferred = preference.isEmpty
      ? null
      : _preferredServer(bundle, preference);
  if (!preference.isEmpty && preferred == null) {
    return const <DownloadStreamCandidate>[];
  }

  final List<NormalizedServer> orderedServers = preferred != null
      ? <NormalizedServer>[preferred]
      : <NormalizedServer>[
          bundle.selectedServer,
          ...bundle.availableServers.where(
            (NormalizedServer server) => server.id != bundle.selectedServer.id,
          ),
        ];

  for (final NormalizedServer server in orderedServers) {
    final List<DownloadStreamCandidate> candidates = _serverCandidates(
      bundle,
      server,
      preferredQualityLabel: preferred == server ? preference.qualityLabel : '',
    );
    if (candidates.isNotEmpty) return candidates;
  }
  return const <DownloadStreamCandidate>[];
}

List<DownloadStreamCandidate> _serverCandidates(
  NormalizedStreamBundle bundle,
  NormalizedServer server, {
  required String preferredQualityLabel,
}) {
  final String preferred = preferredQualityLabel.trim().toLowerCase();
  final List<NormalizedQuality> qualities =
      server.qualities
          .where((NormalizedQuality quality) => _isHttpUrl(quality.streamUrl))
          .toList(growable: false)
        ..sort((NormalizedQuality a, NormalizedQuality b) {
          final bool aPreferred =
              preferred.isNotEmpty && a.label.trim().toLowerCase() == preferred;
          final bool bPreferred =
              preferred.isNotEmpty && b.label.trim().toLowerCase() == preferred;
          if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
          return _heightFromLabel(b.label).compareTo(_heightFromLabel(a.label));
        });

  final List<DownloadStreamCandidate> result = <DownloadStreamCandidate>[];
  final Set<String> seenUrls = <String>{};
  for (final NormalizedQuality quality in qualities) {
    if (!seenUrls.add(quality.streamUrl)) continue;
    result.add(
      DownloadStreamCandidate(
        key: '${server.id}|${quality.label.trim().toLowerCase()}',
        url: quality.streamUrl,
        headers: _headersFor(bundle, server, quality.headers),
        qualityLabel: quality.label,
      ),
    );
  }

  if (_isHttpUrl(server.streamUrl) && seenUrls.add(server.streamUrl)) {
    final String label = bundle.selectedQuality?.label ?? '';
    result.add(
      DownloadStreamCandidate(
        key: '${server.id}|${label.trim().toLowerCase()}|default',
        url: server.streamUrl,
        headers: _headersFor(bundle, server, const <String, String>{}),
        qualityLabel: label,
      ),
    );
  }
  return result;
}

NormalizedServer? _preferredServer(
  NormalizedStreamBundle bundle,
  DownloadStreamPreference preference,
) {
  final String title = preference.serverTitle.trim().toLowerCase();
  if (title.isNotEmpty) {
    for (final NormalizedServer server in bundle.availableServers) {
      if (server.title.trim().toLowerCase() == title) return server;
    }
  }
  final String id = preference.serverId.trim();
  if (id.isNotEmpty) {
    for (final NormalizedServer server in bundle.availableServers) {
      if (server.id == id) return server;
    }
  }
  return null;
}

Map<String, String> _headersFor(
  NormalizedStreamBundle bundle,
  NormalizedServer server,
  Map<String, String> primary,
) {
  if (primary.isNotEmpty) return primary;
  if (server.headers.isNotEmpty) return server.headers;
  return bundle.headers;
}

bool _isHttpUrl(String url) {
  final Uri? uri = Uri.tryParse(url.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

int _heightFromLabel(String label) {
  final String normalized = label.trim().toLowerCase();
  if (normalized.contains('4k') || normalized.contains('2160')) return 2160;
  if (normalized.contains('1440') || normalized == '2k') return 1440;
  final RegExpMatch? match = RegExp(r'(\d{3,4})').firstMatch(normalized);
  if (match != null) return int.tryParse(match.group(1)!) ?? 0;
  if (normalized.contains('fhd')) return 1080;
  if (normalized.contains('hd')) return 720;
  return 0;
}
