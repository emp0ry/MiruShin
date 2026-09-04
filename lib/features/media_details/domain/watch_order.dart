import '../../../shared/models/media_item.dart';

/// A partial date stays partial; an unknown release is never replaced by today.
class WatchOrderDate implements Comparable<WatchOrderDate> {
  const WatchOrderDate({this.year, this.month, this.day});

  final int? year;
  final int? month;
  final int? day;

  factory WatchOrderDate.fromJson(Map<String, dynamic> json) {
    int? part(String key, int max) {
      final value = json[key];
      return value is int && value > 0 && value <= max ? value : null;
    }

    final year = part('year', 9999);
    final month = year == null ? null : part('month', 12);
    final day = month == null
        ? null
        : part('day', DateTime.utc(year!, month + 1, 0).day);
    return WatchOrderDate(year: year, month: month, day: day);
  }

  Map<String, dynamic> toJson() => {'year': year, 'month': month, 'day': day};

  @override
  int compareTo(WatchOrderDate other) {
    // Missing lower precision sorts after known dates in the same period.
    final a = [year ?? 10000, month ?? 13, day ?? 32];
    final b = [other.year ?? 10000, other.month ?? 13, other.day ?? 32];
    for (var i = 0; i < a.length; i++) {
      final order = a[i].compareTo(b[i]);
      if (order != 0) return order;
    }
    return 0;
  }
}

class WatchOrderRelation {
  const WatchOrderRelation(this.targetId, this.type);
  final int targetId;
  final String type;

  Map<String, dynamic> toJson() => {'targetId': targetId, 'type': type};
}

class WatchOrderMedia {
  const WatchOrderMedia({
    required this.item,
    required this.id,
    required this.malId,
    required this.format,
    required this.startDate,
    this.relations = const [],
  });

  final MediaItem item;
  final int id;
  final int malId;
  final String format;
  final WatchOrderDate startDate;
  final List<WatchOrderRelation> relations;

  factory WatchOrderMedia.fromJson(Map<String, dynamic> json) =>
      WatchOrderMedia(
        item: MediaItem.fromJson(json['item'] as Map<String, dynamic>),
        id: json['id'] as int,
        malId: json['malId'] as int,
        format: json['format'] as String,
        startDate: WatchOrderDate.fromJson(
          json['startDate'] as Map<String, dynamic>,
        ),
        relations: (json['relations'] as List)
            .map(
              (dynamic relation) => WatchOrderRelation(
                relation['targetId'] as int,
                relation['type'] as String,
              ),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'id': id,
    'malId': malId,
    'format': format,
    'startDate': startDate.toJson(),
    'relations': relations.map((relation) => relation.toJson()).toList(),
  };
}

class WatchOrderEntry {
  const WatchOrderEntry({
    required this.media,
    required this.isMainline,
    this.parentId,
  });
  final WatchOrderMedia media;
  final bool isMainline;
  final int? parentId;
}

class WatchOrder {
  const WatchOrder({
    this.entries = const [],
    this.hasCycles = false,
    this.missingEntries = 0,
  });
  final List<WatchOrderEntry> entries;
  final bool hasCycles;
  final int missingEntries;
}
