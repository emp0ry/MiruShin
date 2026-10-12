import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';

/// A frozen, provider-independent view of one workspace. Export never pulls
/// remote state or changes the library while creating a file.
class LibraryExportSnapshot {
  LibraryExportSnapshot({
    required this.workspaceId,
    required Iterable<LibraryExportEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final String workspaceId;
  final List<LibraryExportEntry> entries;
}

class LibraryExportDate {
  const LibraryExportDate({this.year, this.month, this.day});
  final int? year;
  final int? month;
  final int? day;

  String get malDate =>
      '${(year ?? 0).toString().padLeft(4, '0')}-'
      '${(month ?? 0).toString().padLeft(2, '0')}-'
      '${(day ?? 0).toString().padLeft(2, '0')}';
}

class LibraryExportEntry {
  const LibraryExportEntry({
    required this.localId,
    required this.mediaItem,
    required this.status,
    required this.progress,
    this.progressVolumes = 0,
    this.totalVolumes = 0,
    this.repeat = 0,
    this.scoreRaw,
    this.notes = '',
    this.format,
    this.startedAt = const LibraryExportDate(),
    this.completedAt = const LibraryExportDate(),
    this.providerIds = const {},
  });

  final String localId;
  final MediaItem mediaItem;
  final AniListListStatus status;
  final int progress;
  final int progressVolumes;
  final int totalVolumes;
  final int repeat;
  final int? scoreRaw;
  final String notes;
  final String? format;
  final LibraryExportDate startedAt;
  final LibraryExportDate completedAt;

  /// Only verified, non-quarantined bindings, never a guessed cross-provider ID.
  final Map<String, int> providerIds;
  int get tenPointScore => ((scoreRaw ?? 0).clamp(0, 100) / 10).round();
}
