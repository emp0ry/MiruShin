import '../../../shared/models/media_item.dart';

enum TmdbMediaKind { movie, tv }

class TmdbMediaIdentity {
  const TmdbMediaIdentity({required this.id, required this.kind});

  final int id;
  final TmdbMediaKind kind;

  static TmdbMediaIdentity? fromMediaItem(MediaItem item) {
    final int? externalId = int.tryParse(item.externalIds['tmdb'] ?? '');
    final List<String> parts = item.id.split(':');
    final int? pathId = parts.length >= 3 && parts.first == 'tmdb'
        ? int.tryParse(parts[2])
        : null;
    final int? id = externalId != null && externalId > 0
        ? externalId
        : pathId != null && pathId > 0
        ? pathId
        : null;
    if (id == null) return null;

    final String externalType = (item.externalIds['tmdb_media_type'] ?? '')
        .trim()
        .toLowerCase();
    if (externalType == 'movie') {
      return TmdbMediaIdentity(id: id, kind: TmdbMediaKind.movie);
    }
    if (externalType == 'tv') {
      return TmdbMediaIdentity(id: id, kind: TmdbMediaKind.tv);
    }

    if (parts.length >= 3 && parts.first == 'tmdb') {
      return TmdbMediaIdentity(
        id: id,
        kind: parts[1] == 'movie' ? TmdbMediaKind.movie : TmdbMediaKind.tv,
      );
    }
    return TmdbMediaIdentity(
      id: id,
      kind: item.type == MediaType.movie
          ? TmdbMediaKind.movie
          : TmdbMediaKind.tv,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TmdbMediaIdentity && other.id == id && other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(id, kind);
}
