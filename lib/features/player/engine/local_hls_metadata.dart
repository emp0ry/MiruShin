import 'dart:convert';
import 'dart:io';

/// Reads the complete duration encoded by a downloaded HLS playlist.
///
/// Native demuxers can temporarily report only the first segment (or zero)
/// while opening local playlists. The playlist itself is authoritative and is
/// available without network I/O, including for a local master playlist.
Future<Duration> readLocalHlsDuration(Uri playlistUri) async {
  if (playlistUri.scheme.toLowerCase() != 'file') return Duration.zero;
  return _readPlaylistDuration(playlistUri, <String>{}, 0);
}

Future<Duration> _readPlaylistDuration(
  Uri playlistUri,
  Set<String> visited,
  int depth,
) async {
  if (depth > 4 || !visited.add(playlistUri.toString())) {
    return Duration.zero;
  }

  try {
    final File file = File.fromUri(playlistUri);
    if (!await file.exists()) return Duration.zero;
    final List<String> lines = const LineSplitter().convert(
      await file.readAsString(),
    );

    double seconds = 0;
    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (!line.startsWith('#EXTINF:')) continue;
      final int comma = line.indexOf(',');
      final String rawDuration = line.substring(
        '#EXTINF:'.length,
        comma < 0 ? line.length : comma,
      );
      final double? value = double.tryParse(rawDuration.trim());
      if (value != null && value.isFinite && value > 0) seconds += value;
    }
    if (seconds > 0) {
      return Duration(microseconds: (seconds * 1000000).round());
    }

    Duration longestChild = Duration.zero;
    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final Uri child = playlistUri.resolve(line);
      if (child.scheme.toLowerCase() != 'file' ||
          !child.path.toLowerCase().endsWith('.m3u8')) {
        continue;
      }
      final Duration duration = await _readPlaylistDuration(
        child,
        visited,
        depth + 1,
      );
      if (duration > longestChild) longestChild = duration;
    }
    return longestChild;
  } on Object {
    return Duration.zero;
  }
}
