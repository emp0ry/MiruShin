import 'package:mirushin/features/media_details/domain/watch_order.dart';
import 'package:mirushin/shared/models/media_item.dart';

WatchOrderMedia watchMedia(
  int id, {
  int? year = 2020,
  int? month,
  int? day,
  String format = 'TV',
  List<WatchOrderRelation> relations = const [],
}) => WatchOrderMedia(
  id: id,
  malId: id + 100,
  format: format,
  startDate: WatchOrderDate(year: year, month: month, day: day),
  relations: relations,
  item: MediaItem(
    id: 'anilist:$id',
    title: 'Anime $id',
    originalTitle: 'Anime $id',
    overview: '',
    type: MediaType.anime,
    year: year ?? 0,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const [],
    sourceProvider: 'AniList',
    externalIds: {
      'anilist': '$id',
      'mal': '${id + 100}',
      'anilist_type': 'ANIME',
    },
    statusLabel: 'FINISHED',
    episodeCount: 12,
  ),
);

WatchOrderRelation relation(int target, String type) =>
    WatchOrderRelation(target, type);
