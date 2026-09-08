import '../../../core/cache/metadata_cache_store.dart';
import '../../../shared/models/media_item.dart';
import '../../metadata/data/shikimori_client.dart';
import '../../metadata/domain/shikimori_franchise.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../../tracking/data/mal_api_client.dart';
import '../domain/watch_order.dart';
import '../domain/watch_order_resolver.dart';

class WatchOrderRepository {
  WatchOrderRepository({
    required this.shikimori,
    required this.anilist,
    required this.cache,
    this.malFallback,
    this.onPrimaryFailure,
    this.onPrimarySuccess,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ShikimoriClient shikimori;
  final AniListApiClient anilist;
  final MetadataCacheStore cache;
  final MalApiClient? malFallback;
  final void Function(Object error)? onPrimaryFailure;
  final void Function()? onPrimarySuccess;
  final DateTime Function() _now;
  final Map<int, Future<WatchOrder>> _pending = {};

  static const Duration _primaryCacheTtl = Duration(hours: 12);
  static const Duration _fallbackCacheTtl = Duration(minutes: 10);

  Future<WatchOrder> get(int? malId) {
    if (malId == null || malId <= 0) return Future.value(const WatchOrder());
    return _pending.putIfAbsent(
      malId,
      () => _load(malId).whenComplete(() {
        _pending.remove(malId);
      }),
    );
  }

  Future<WatchOrder> _load(int malId) async {
    final key =
        'anilist.watchOrder.v1.${anilist.titleLanguage}.${anilist.showAdultContent}.$malId';
    final _CachedWatchOrder? cached = await _readCache(key);
    if (cached != null && _isFresh(cached)) return cached.order;

    final ShikimoriFranchise franchise;
    try {
      franchise = await shikimori.fetchAnimeFranchise(malId);
    } catch (_) {
      if (cached != null) return cached.order;
      rethrow;
    }
    if (franchise.malIds.isEmpty) {
      return cached?.order ?? const WatchOrder();
    }

    try {
      final List<WatchOrderMedia> media = await anilist.fetchWatchOrderMedia(
        franchise.malIds,
      );
      onPrimarySuccess?.call();
      return _resolveAndCache(
        key: key,
        franchise: franchise,
        media: _enrichAniList(media, franchise),
        source: 'anilist',
      );
    } catch (error, stackTrace) {
      onPrimaryFailure?.call(error);
      final List<WatchOrderMedia> fallback = await _fallbackMedia(franchise);
      if (fallback.isNotEmpty) {
        if (cached != null && cached.order.entries.length > fallback.length) {
          return cached.order;
        }
        return _resolveAndCache(
          key: key,
          franchise: franchise,
          media: fallback,
          source: 'fallback',
        );
      }
      if (cached != null) return cached.order;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  List<WatchOrderMedia> _enrichAniList(
    List<WatchOrderMedia> media,
    ShikimoriFranchise franchise,
  ) {
    final byMal = {for (final node in media) node.malId: node};
    final enriched = <WatchOrderMedia>[];
    for (final node in media) {
      final relations = [...node.relations];
      // Shikimori can fill missing parent attachments. Only AniList contributes
      // strong sequencing constraints; neither source can add outside members.
      for (final link in franchise.links) {
        if (link.sourceMalId != node.malId ||
            !const {'PARENT', 'SIDE_STORY'}.contains(link.relation)) {
          continue;
        }
        final target = byMal[link.targetMalId];
        if (target == null) continue;
        final child = link.relation == 'PARENT' ? node : target;
        final hasAniListParent =
            child.relations.any((r) => r.type == 'PARENT') ||
            media.any(
              (parent) => parent.relations.any(
                (r) => r.type == 'SIDE_STORY' && r.targetId == child.id,
              ),
            );
        if (!hasAniListParent) {
          relations.add(WatchOrderRelation(target.id, link.relation));
        }
      }
      enriched.add(
        WatchOrderMedia(
          item: node.item,
          id: node.id,
          malId: node.malId,
          format: node.format,
          startDate: node.startDate,
          relations: relations,
        ),
      );
    }
    return enriched;
  }

  Future<List<WatchOrderMedia>> _fallbackMedia(
    ShikimoriFranchise franchise,
  ) async {
    final Map<int, MediaItem> malItems = <int, MediaItem>{};
    final MalApiClient? mal = malFallback;
    if (mal != null) {
      final List<int> ids = franchise.malIds.toSet().toList()..sort();
      for (var offset = 0; offset < ids.length; offset += 6) {
        final List<int> batch = ids.sublist(
          offset,
          (offset + 6).clamp(0, ids.length),
        );
        final List<MediaItem?> results = await Future.wait(
          batch.map((int id) async {
            try {
              return await mal.fetchAnimeDetails(id);
            } catch (_) {
              return null;
            }
          }),
        );
        for (var index = 0; index < batch.length; index++) {
          final MediaItem? item = results[index];
          if (item != null) malItems[batch[index]] = item;
        }
        // A completely failed first batch normally means MAL itself is
        // unavailable. Continue immediately with Shikimori's public metadata.
        if (offset == 0 && malItems.isEmpty) break;
      }
    }

    final Map<int, ShikimoriFranchiseMember> members =
        <int, ShikimoriFranchiseMember>{
          for (final ShikimoriFranchiseMember member in franchise.members)
            member.malId: member,
        };
    final List<WatchOrderMedia> result = <WatchOrderMedia>[];
    for (final int malId in franchise.malIds.toSet().toList()..sort()) {
      final ShikimoriFranchiseMember? member = members[malId];
      MediaItem? item = malItems[malId] ?? _shikimoriItem(member);
      if (item == null || _excludedAdultItem(item)) continue;
      if (anilist.titleLanguage.toUpperCase() == 'RUSSIAN' &&
          member?.russian.trim().isNotEmpty == true) {
        item = item.copyWith(title: member!.russian.trim());
      }
      if (member != null) {
        item = item.copyWith(
          externalIds: <String, String>{
            ...item.externalIds,
            'mal': '$malId',
            'shikimori': '${member.shikimoriId}',
          },
        );
      }
      result.add(
        WatchOrderMedia(
          item: item,
          id: malId,
          malId: malId,
          format: _malFormat(item.externalIds['mal_media_type']),
          startDate: _malStartDate(item),
          relations: <WatchOrderRelation>[
            for (final ShikimoriFranchiseLink link in franchise.links)
              if (link.sourceMalId == malId)
                WatchOrderRelation(link.targetMalId, link.relation),
          ],
        ),
      );
    }
    return result;
  }

  MediaItem? _shikimoriItem(ShikimoriFranchiseMember? member) {
    if (member == null) return null;
    final String title =
        anilist.titleLanguage.toUpperCase() == 'RUSSIAN' &&
            member.russian.trim().isNotEmpty
        ? member.russian.trim()
        : member.name.trim();
    if (title.isEmpty) return null;
    return MediaItem(
      id: 'mal:${member.malId}',
      title: title,
      originalTitle: member.name.trim(),
      overview: '',
      type: MediaType.anime,
      year: 0,
      posterUrl: member.posterUrl,
      backdropUrl: '',
      rating: member.score,
      genres: const <String>[],
      sourceProvider: 'Shikimori',
      externalIds: <String, String>{
        'mal': '${member.malId}',
        'shikimori': '${member.shikimoriId}',
      },
      episodeCount: member.episodes,
      statusLabel: '',
    );
  }

  bool _excludedAdultItem(MediaItem item) {
    if (anilist.showAdultContent) return false;
    final String nsfw = item.externalIds['mal_nsfw']?.toLowerCase() ?? '';
    return nsfw == 'gray' || nsfw == 'black';
  }

  String _malFormat(String? value) {
    return switch (value?.trim().toUpperCase()) {
      'TV' => 'TV',
      'TV_SPECIAL' => 'TV_SHORT',
      'MOVIE' => 'MOVIE',
      'OVA' => 'OVA',
      'ONA' => 'ONA',
      'SPECIAL' => 'SPECIAL',
      'MUSIC' => 'MUSIC',
      _ => '',
    };
  }

  WatchOrderDate _malStartDate(MediaItem item) {
    final DateTime? parsed = DateTime.tryParse(
      item.externalIds['mal_start_date'] ?? '',
    );
    if (parsed != null) {
      return WatchOrderDate(
        year: parsed.year,
        month: parsed.month,
        day: parsed.day,
      );
    }
    return WatchOrderDate(year: item.year > 0 ? item.year : null);
  }

  Future<WatchOrder> _resolveAndCache({
    required String key,
    required ShikimoriFranchise franchise,
    required List<WatchOrderMedia> media,
    required String source,
  }) async {
    final Map<int, WatchOrderMedia> byMal = <int, WatchOrderMedia>{
      for (final WatchOrderMedia node in media) node.malId: node,
    };
    final missing =
        franchise.unmappedCount +
        franchise.malIds.where((id) => !byMal.containsKey(id)).length;
    if (media.isNotEmpty) {
      await cache.write(key, <String, dynamic>{
        'fetchedAt': _now().millisecondsSinceEpoch,
        'source': source,
        'media': media.map((node) => node.toJson()).toList(),
        'missingEntries': missing,
      });
    }
    return const WatchOrderResolver().resolve(media, missingEntries: missing);
  }

  Future<_CachedWatchOrder?> _readCache(String key) async {
    final Map<String, dynamic>? value = await cache.read(key);
    if (value == null) return null;
    try {
      final DateTime fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        value['fetchedAt'] as int,
      );
      final String source = value['source']?.toString() ?? 'anilist';
      final int missing = value['missingEntries'] is int
          ? value['missingEntries'] as int
          : 0;
      final WatchOrder order = const WatchOrderResolver().resolve(
        (value['media'] as List<dynamic>).map(
          (dynamic node) =>
              WatchOrderMedia.fromJson(node as Map<String, dynamic>),
        ),
        missingEntries: missing,
      );
      return _CachedWatchOrder(
        order: order,
        fetchedAt: fetchedAt,
        source: source,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isFresh(_CachedWatchOrder cached) {
    final Duration ttl = cached.source == 'anilist'
        ? _primaryCacheTtl
        : _fallbackCacheTtl;
    return _now().difference(cached.fetchedAt) < ttl;
  }
}

class _CachedWatchOrder {
  const _CachedWatchOrder({
    required this.order,
    required this.fetchedAt,
    required this.source,
  });

  final WatchOrder order;
  final DateTime fetchedAt;
  final String source;
}
