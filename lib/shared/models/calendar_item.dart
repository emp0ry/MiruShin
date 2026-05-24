import 'media_item.dart';

enum CalendarItemType { episode, movieRelease, animeAiring, reminder }

extension CalendarItemTypeLabel on CalendarItemType {
  String get label {
    return switch (this) {
      CalendarItemType.episode => 'Episode',
      CalendarItemType.movieRelease => 'Movie Release',
      CalendarItemType.animeAiring => 'Anime Airing',
      CalendarItemType.reminder => 'Reminder',
    };
  }
}

class CalendarItem {
  const CalendarItem({
    required this.id,
    required this.mediaItem,
    required this.date,
    required this.title,
    required this.description,
    required this.type,
    required this.isFromLibrary,
  });

  final String id;
  final MediaItem mediaItem;
  final DateTime date;
  final String title;
  final String description;
  final CalendarItemType type;
  final bool isFromLibrary;
}
