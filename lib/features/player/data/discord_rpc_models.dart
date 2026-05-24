import '../../../shared/models/media_item.dart';

class DiscordRpcPresence {
  const DiscordRpcPresence({
    required this.title,
    required this.mediaType,
    required this.position,
    required this.duration,
    this.subtitle = '',
    this.posterUrl = '',
    this.mediaUrl,
    this.seasonNumber = 1,
    this.episodeNumber = 0,
    this.episodeCount,
    this.isPlaying = true,
  });

  final String title;
  final MediaType mediaType;
  final Duration position;
  final Duration duration;
  final String subtitle;
  final String posterUrl;
  final String? mediaUrl;
  final int seasonNumber;
  final double episodeNumber;
  final int? episodeCount;
  final bool isPlaying;
}
