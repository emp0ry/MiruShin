import 'dart:io' show Directory, File, Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../app/app_routes.dart';
import '../../shared/models/anilist_models.dart';

class AiringNotificationScheduler {
  AiringNotificationScheduler._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _channelsCreated = false;
  static bool _permissionsRequested = false;
  static bool _timeZonesInitialized = false;

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  static Future<void> syncAnimeList(
    List<AniListAnimeListFolder> folders, {
    required bool enabled,
    String titleLanguage = 'ENGLISH',
  }) async {
    if (!isSupported) return;
    if (!enabled) {
      await cancelAll();
      return;
    }

    await _ensureReady();
    await cancelAll();

    final DateTime now = DateTime.now();
    for (final AniListAnimeListFolder folder in folders) {
      for (final AniListAnimeListEntry entry in folder.entries) {
        if (!_shouldSchedule(entry, now)) continue;
        await _scheduleEntry(entry, titleLanguage: titleLanguage);
      }
    }
  }

  static Future<void> cancelAll() async {
    if (!isSupported) return;
    await _ensureInitialized();
    await _plugin.cancelAll();
  }

  static bool _shouldSchedule(AniListAnimeListEntry entry, DateTime now) {
    final DateTime? airingAt = entry.airingAt;
    final int? nextEpisode = entry.nextEpisode;
    if (airingAt == null || nextEpisode == null) return false;
    if (!airingAt.isAfter(now.add(const Duration(minutes: 1)))) return false;
    return entry.status == AniListListStatus.current ||
        entry.status == AniListListStatus.planning ||
        entry.status == AniListListStatus.repeating;
  }

  static Future<void> _scheduleEntry(
    AniListAnimeListEntry entry, {
    String titleLanguage = 'ENGLISH',
  }) async {
    final DateTime airingAt = entry.airingAt!;
    final int episode = entry.nextEpisode!;
    final MediaItemSnapshot media = MediaItemSnapshot.fromEntry(entry);
    final String? imagePath = await _downloadPoster(media);
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(airingAt, tz.local);
    final String body = titleLanguage == 'RUSSIAN'
        ? 'Эпизод $episode уже доступен'
        : 'Episode $episode is now available';

    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'airing_episode_channel',
        'Episode releases',
        channelDescription: 'Notifications when new anime episodes air',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: imagePath == null
            ? null
            : BigPictureStyleInformation(
                FilePathAndroidBitmap(imagePath),
                largeIcon: FilePathAndroidBitmap(imagePath),
                contentTitle: media.title,
                summaryText: body,
              ),
      ),
      iOS: DarwinNotificationDetails(
        attachments: imagePath == null
            ? null
            : <DarwinNotificationAttachment>[
                DarwinNotificationAttachment(imagePath),
              ],
      ),
      macOS: DarwinNotificationDetails(
        attachments: imagePath == null
            ? null
            : <DarwinNotificationAttachment>[
                DarwinNotificationAttachment(imagePath),
              ],
      ),
    );

    final int id = _notificationId(media.anilistId, episode);
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: media.title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        payload: AppRoutes.mediaDetailsPath(media.routeId),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id: id,
        title: media.title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        payload: AppRoutes.mediaDetailsPath(media.routeId),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static Future<void> _ensureReady() async {
    await _ensureInitialized();
    _ensureTimeZones();
    await _ensurePermissions();
    await _ensureAndroidChannel();
  }

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
      ),
    );
    _initialized = true;
  }

  static void _ensureTimeZones() {
    if (_timeZonesInitialized) return;
    tz_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }

  static Future<void> _ensurePermissions() async {
    if (_permissionsRequested) return;
    if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      final MacOSFlutterLocalNotificationsPlugin? mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      await mac?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    }
    _permissionsRequested = true;
  }

  static Future<void> _ensureAndroidChannel() async {
    if (_channelsCreated || !Platform.isAndroid) return;
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'airing_episode_channel',
        'Episode releases',
        description: 'Notifications when new anime episodes air',
        importance: Importance.high,
      ),
    );
    _channelsCreated = true;
  }

  static Future<String?> _downloadPoster(MediaItemSnapshot media) async {
    final Uri? uri = Uri.tryParse(media.posterUrl);
    if (uri == null || !uri.hasScheme) return null;
    try {
      final Directory directory = await getTemporaryDirectory();
      final String fileName = _safeFileName(media.title, media.anilistId);
      final String filePath = p.join(directory.path, fileName);
      final File file = File(filePath);
      if (await file.exists()) return filePath;
      await Dio().downloadUri(uri, filePath);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  static String _safeFileName(String title, int mediaId) {
    final String cleaned = title
        .replaceAll(RegExp(r'[^\w\d]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();
    return 'airing_${mediaId}_$cleaned.jpg';
  }

  static int _notificationId(int mediaId, int episode) {
    return (((mediaId & 0x1fffff) * 1000) + (episode % 1000)) & 0x7fffffff;
  }
}

class MediaItemSnapshot {
  const MediaItemSnapshot({
    required this.anilistId,
    required this.routeId,
    required this.title,
    required this.posterUrl,
  });

  final int anilistId;
  final String routeId;
  final String title;
  final String posterUrl;

  factory MediaItemSnapshot.fromEntry(AniListAnimeListEntry entry) {
    final String? externalId = entry.mediaItem.externalIds['anilist'];
    final int anilistId =
        int.tryParse(externalId ?? '') ??
        int.tryParse(entry.mediaItem.id.split(':').last) ??
        entry.id;
    final String routeId = entry.mediaItem.id.startsWith('anilist')
        ? entry.mediaItem.id
        : 'anilist:$anilistId';
    return MediaItemSnapshot(
      anilistId: anilistId,
      routeId: routeId,
      title: entry.mediaItem.title,
      posterUrl: entry.mediaItem.posterUrl,
    );
  }
}
