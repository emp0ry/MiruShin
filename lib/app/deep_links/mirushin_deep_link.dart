import '../../core/utils/mirushin_web_opener.dart';
import '../../features/watch_party/domain/watch_party_qr.dart';
import '../../shared/models/media_item.dart';

const int mirushinMaximumDeepLinkLength = 4096;
const int mirushinMaximumMediaId = 0x7fffffff;

bool _isValidMediaId(int? value) =>
    value != null && value > 0 && value <= mirushinMaximumMediaId;

sealed class MiruShinDeepLink {
  const MiruShinDeepLink();

  String get deduplicationKey;

  static MiruShinDeepLink? tryParse(String? raw) {
    final String value = raw?.trim() ?? '';
    if (value.isEmpty || value.length > mirushinMaximumDeepLinkLength) {
      return null;
    }
    try {
      final Uri? parsedUri = Uri.tryParse(value);
      if (parsedUri == null) return null;
      final MiruShinMediaDeepLink? publicMedia = _tryParsePublicMedia(
        parsedUri,
      );
      if (publicMedia != null) return publicMedia;
      final Uri uri = tryUnwrapMirushinWebOpenUri(parsedUri) ?? parsedUri;
      if (uri.scheme.toLowerCase() != 'mirushin') return null;

      final MiruShinMediaDeepLink? media = _tryParseMedia(uri);
      if (media != null) return media;

      final WatchPartyInvite? invite = WatchPartyInvite.tryParse(
        uri.toString(),
      );
      return invite == null ? null : MiruShinWatchPartyDeepLink(invite);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static MiruShinMediaDeepLink? _tryParseMedia(Uri uri) {
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return null;
    final String provider = uri.host.toLowerCase();
    final List<String> segments = uri.pathSegments;
    if (segments.length != 2) return null;
    final int? numericId = int.tryParse(segments[1]);
    if (!_isValidMediaId(numericId)) return null;

    return _mediaLinkForRoute(provider, segments[0], numericId!);
  }

  static MiruShinMediaDeepLink? _tryParsePublicMedia(Uri uri) {
    if (!isMirushinWebsiteUri(uri) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 3) {
      return null;
    }
    final List<String> segments = uri.pathSegments;
    final int? numericId = int.tryParse(segments[2]);
    if (!_isValidMediaId(numericId)) return null;
    return _mediaLinkForRoute(segments[0], segments[1], numericId!);
  }

  static MiruShinMediaDeepLink? _mediaLinkForRoute(
    String provider,
    String kind,
    int numericId,
  ) {
    return switch ((provider.toLowerCase(), kind.toLowerCase())) {
      ('anilist', 'anime') => MiruShinMediaDeepLink(
        provider: MiruShinMediaProvider.anilist,
        kind: MiruShinMediaKind.anime,
        numericId: numericId,
      ),
      ('anilist', 'manga') => MiruShinMediaDeepLink(
        provider: MiruShinMediaProvider.anilist,
        kind: MiruShinMediaKind.manga,
        numericId: numericId,
      ),
      ('tmdb', 'movie') => MiruShinMediaDeepLink(
        provider: MiruShinMediaProvider.tmdb,
        kind: MiruShinMediaKind.movie,
        numericId: numericId,
      ),
      ('tmdb', 'tv') => MiruShinMediaDeepLink(
        provider: MiruShinMediaProvider.tmdb,
        kind: MiruShinMediaKind.tv,
        numericId: numericId,
      ),
      _ => null,
    };
  }
}

enum MiruShinMediaProvider { anilist, tmdb }

enum MiruShinMediaKind { anime, manga, movie, tv }

class MiruShinMediaDeepLink extends MiruShinDeepLink {
  const MiruShinMediaDeepLink({
    required this.provider,
    required this.kind,
    required this.numericId,
  });

  final MiruShinMediaProvider provider;
  final MiruShinMediaKind kind;
  final int numericId;

  String get internalMediaId => switch ((provider, kind)) {
    (MiruShinMediaProvider.anilist, MiruShinMediaKind.anime) =>
      'anilist:$numericId',
    (MiruShinMediaProvider.anilist, MiruShinMediaKind.manga) =>
      'anilist:manga:$numericId',
    (MiruShinMediaProvider.tmdb, MiruShinMediaKind.movie) =>
      'tmdb:movie:$numericId',
    (MiruShinMediaProvider.tmdb, MiruShinMediaKind.tv) => 'tmdb:tv:$numericId',
    _ => throw StateError('Unsupported provider/media-kind combination.'),
  };

  Uri get uri => Uri(
    scheme: 'mirushin',
    host: provider.name,
    pathSegments: <String>[kind.name, numericId.toString()],
  );

  Uri get providerUri => switch ((provider, kind)) {
    (MiruShinMediaProvider.anilist, MiruShinMediaKind.anime) => Uri.https(
      'anilist.co',
      '/anime/$numericId',
    ),
    (MiruShinMediaProvider.anilist, MiruShinMediaKind.manga) => Uri.https(
      'anilist.co',
      '/manga/$numericId',
    ),
    (MiruShinMediaProvider.tmdb, MiruShinMediaKind.movie) => Uri.https(
      'www.themoviedb.org',
      '/movie/$numericId',
    ),
    (MiruShinMediaProvider.tmdb, MiruShinMediaKind.tv) => Uri.https(
      'www.themoviedb.org',
      '/tv/$numericId',
    ),
    _ => throw StateError('Unsupported provider/media-kind combination.'),
  };

  /// Canonical public HTTPS link used for sharing.
  Uri get shareUri => mirushinWebsiteUri(<String>[
    provider.name,
    kind.name,
    numericId.toString(),
  ]);

  /// Compatibility alias retained for callers built around the old name.
  Uri get webOpenUri => shareUri;

  /// Previous query-based bridge, retained so already-posted links keep working.
  Uri get legacyWebOpenUri => mirushinWebOpenUri(uri);

  @override
  String get deduplicationKey => uri.toString();
}

class MiruShinWatchPartyDeepLink extends MiruShinDeepLink {
  const MiruShinWatchPartyDeepLink(this.invite);

  final WatchPartyInvite invite;

  @override
  String get deduplicationKey {
    if (!invite.isRelay) return 'watch-party:${invite.roomId}';
    return 'watch-party:${invite.relayUrl}:${invite.roomId}:${invite.joinToken}';
  }
}

/// Returns an in-app URI only when the media identity is unambiguous. The
/// current catalog preference is deliberately not consulted or changed.
Uri? mirushinMediaUri({
  required String internalId,
  required MediaType mediaType,
  Map<String, String> externalIds = const <String, String>{},
}) => mirushinMediaLink(
  internalId: internalId,
  mediaType: mediaType,
  externalIds: externalIds,
)?.uri;

/// Resolves both the permanent MiruShin URI and the matching provider page
/// from one unambiguous media identity.
MiruShinMediaDeepLink? mirushinMediaLink({
  required String internalId,
  required MediaType mediaType,
  Map<String, String> externalIds = const <String, String>{},
}) {
  final MiruShinMediaDeepLink? fromInternal = _mediaLinkFromInternalId(
    internalId,
  );
  if (fromInternal != null) return fromInternal;

  final int? aniListId = int.tryParse(externalIds['anilist'] ?? '');
  if (_isValidMediaId(aniListId) && mediaType == MediaType.anime) {
    return MiruShinMediaDeepLink(
      provider: MiruShinMediaProvider.anilist,
      kind: externalIds['anilist_type']?.toUpperCase() == 'MANGA'
          ? MiruShinMediaKind.manga
          : MiruShinMediaKind.anime,
      numericId: aniListId!,
    );
  }

  final int? tmdbId = int.tryParse(externalIds['tmdb'] ?? '');
  if (!_isValidMediaId(tmdbId)) return null;
  return MiruShinMediaDeepLink(
    provider: MiruShinMediaProvider.tmdb,
    kind: mediaType == MediaType.movie
        ? MiruShinMediaKind.movie
        : MiruShinMediaKind.tv,
    numericId: tmdbId!,
  );
}

MiruShinMediaDeepLink? _mediaLinkFromInternalId(String raw) {
  final List<String> parts = raw.trim().toLowerCase().split(':');
  final int? numericId = int.tryParse(parts.last);
  if (!_isValidMediaId(numericId)) return null;
  if (parts.length == 2 && parts[0] == 'anilist') {
    return MiruShinMediaDeepLink(
      provider: MiruShinMediaProvider.anilist,
      kind: MiruShinMediaKind.anime,
      numericId: numericId!,
    );
  }
  if (parts.length != 3) return null;
  return switch ((parts[0], parts[1])) {
    ('anilist', 'anime') => MiruShinMediaDeepLink(
      provider: MiruShinMediaProvider.anilist,
      kind: MiruShinMediaKind.anime,
      numericId: numericId!,
    ),
    ('anilist', 'manga') => MiruShinMediaDeepLink(
      provider: MiruShinMediaProvider.anilist,
      kind: MiruShinMediaKind.manga,
      numericId: numericId!,
    ),
    ('tmdb', 'movie') => MiruShinMediaDeepLink(
      provider: MiruShinMediaProvider.tmdb,
      kind: MiruShinMediaKind.movie,
      numericId: numericId!,
    ),
    ('tmdb', 'tv') => MiruShinMediaDeepLink(
      provider: MiruShinMediaProvider.tmdb,
      kind: MiruShinMediaKind.tv,
      numericId: numericId!,
    ),
    _ => null,
  };
}
