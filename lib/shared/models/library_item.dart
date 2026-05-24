import 'media_item.dart';

enum LibraryStatus { watching, completed, planned, dropped, favorite, local }

extension LibraryStatusLabel on LibraryStatus {
  String get label {
    return switch (this) {
      LibraryStatus.watching => 'Continue Later',
      LibraryStatus.completed => 'Completed',
      LibraryStatus.planned => 'Watchlist',
      LibraryStatus.dropped => 'Dropped',
      LibraryStatus.favorite => 'Favorites',
      LibraryStatus.local => 'Local',
    };
  }
}

class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.mediaItem,
    required this.status,
    required this.progress,
    required this.addedAt,
    required this.updatedAt,
    required this.trackingSyncState,
  });

  final String id;
  final MediaItem mediaItem;
  final LibraryStatus status;
  final double progress;
  final DateTime addedAt;
  final DateTime updatedAt;
  final String trackingSyncState;

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    final Object? mediaJson = json['mediaItem'];
    return LibraryItem(
      id: json['id'] is String ? json['id'] as String : '',
      mediaItem: mediaJson is Map<String, dynamic>
          ? MediaItem.fromJson(mediaJson)
          : MediaItem(
              id: '',
              title: '',
              originalTitle: '',
              overview: '',
              type: MediaType.movie,
              year: DateTime.now().year,
              posterUrl: '',
              backdropUrl: '',
              rating: 0,
              genres: const <String>[],
              sourceProvider: '',
              externalIds: const <String, String>{},
              statusLabel: '',
            ),
      status: LibraryStatus.values.firstWhere(
        (LibraryStatus status) => status.name == json['status'],
        orElse: () => LibraryStatus.planned,
      ),
      progress: _double(json['progress']),
      addedAt: DateTime.tryParse(_string(json['addedAt'])) ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(_string(json['updatedAt'])) ?? DateTime.now(),
      trackingSyncState: _string(json['trackingSyncState']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'mediaItem': mediaItem.toJson(),
      'status': status.name,
      'progress': progress,
      'addedAt': addedAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'trackingSyncState': trackingSyncState,
    };
  }

  static String _string(Object? value) {
    return value is String ? value : '';
  }

  static double _double(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}
