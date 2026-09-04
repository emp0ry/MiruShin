import '../../../core/cache/metadata_cache_store.dart';
import '../../metadata/data/shikimori_client.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../domain/watch_order.dart';
import '../domain/watch_order_resolver.dart';

class WatchOrderRepository {
  WatchOrderRepository({
    required this.shikimori,
    required this.anilist,
    required this.cache,
  });

  final ShikimoriClient shikimori;
  final AniListApiClient anilist;
  final MetadataCacheStore cache;
  final Map<int, Future<WatchOrder>> _pending = {};

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
    final cached = await cache.read(key);
    if (cached != null) {
      try {
        final fetchedAt = DateTime.fromMillisecondsSinceEpoch(
          cached['fetchedAt'] as int,
        );
        if (DateTime.now().difference(fetchedAt) < const Duration(hours: 12)) {
          return const WatchOrderResolver().resolve(
            (cached['media'] as List).map(
              (dynamic node) =>
                  WatchOrderMedia.fromJson(node as Map<String, dynamic>),
            ),
            missingEntries: cached['missingEntries'] as int,
          );
        }
      } catch (_) {
        // Old or incomplete cache data must not block fresh discovery.
      }
    }

    final franchise = await shikimori.fetchAnimeFranchise(malId);
    if (franchise.malIds.isEmpty) return const WatchOrder();
    final media = await anilist.fetchWatchOrderMedia(franchise.malIds);
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
    final missing =
        franchise.unmappedCount +
        franchise.malIds.where((id) => !byMal.containsKey(id)).length;
    // Errors propagate and stay retryable; no failed/empty discovery is cached.
    if (enriched.isNotEmpty) {
      await cache.write(key, {
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'media': enriched.map((node) => node.toJson()).toList(),
        'missingEntries': missing,
      });
    }
    return const WatchOrderResolver().resolve(
      enriched,
      missingEntries: missing,
    );
  }
}
