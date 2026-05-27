String humanReadableMediaStatus(String raw) {
  final String value = raw.trim();
  if (value.isEmpty || value == 'AniList' || value == 'TMDB') return '';

  return switch (value.toUpperCase()) {
    'RELEASING' => 'Releasing',
    'FINISHED' => 'Finished',
    'NOT_YET_RELEASED' => 'Not Yet Released',
    'CANCELLED' => 'Cancelled',
    'HIATUS' => 'On Hiatus',
    _ => _titleCaseStatus(value),
  };
}

String mediaStatusOrFallback(String raw) {
  final String readable = humanReadableMediaStatus(raw);
  return readable.isEmpty ? raw.trim() : readable;
}

String _titleCaseStatus(String value) {
  if (!value.contains('_')) return value;
  return value
      .split('_')
      .where((String part) => part.isNotEmpty)
      .map((String part) {
        final String lower = part.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}
