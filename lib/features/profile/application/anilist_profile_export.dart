import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/io_compat.dart' if (dart.library.io) 'dart:io';
import '../../../shared/models/anilist_models.dart';
import '../../tracking/data/anilist_api_client.dart';

enum AniListExportTarget { myAnimeList, shikimori }

class AniListExportPayload {
  const AniListExportPayload({
    required this.filename,
    required this.bytes,
    required this.mimeType,
    required this.fileExtension,
    required this.shareText,
  });

  final String filename;
  final Uint8List bytes;
  final String mimeType;
  final String fileExtension;
  final String shareText;
}

Future<AniListExportPayload?> buildAniListExportPayload({
  required AniListApiClient client,
  required int userId,
  required String username,
  required bool anime,
  required AniListExportTarget target,
}) async {
  final List<AniListAnimeListFolder> folders = await client
      .fetchMediaListCollection(
        userId: userId,
        type: anime ? 'ANIME' : 'MANGA',
        sort: const <String>['ADDED_TIME_DESC'],
      );
  final List<AniListAnimeListEntry> allEntries = _orderedEntries(folders);
  final List<AniListAnimeListEntry> exportableEntries = allEntries
      .where(
        (AniListAnimeListEntry entry) =>
            entry.mediaItem.externalIds['mal'] != null,
      )
      .toList(growable: false);
  if (exportableEntries.isEmpty) return null;

  final DateTime now = DateTime.now();
  final String stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
  final String content = switch (target) {
    AniListExportTarget.myAnimeList => _buildMalXml(
      entries: allEntries,
      username: username,
      anime: anime,
      generatedAt: now,
    ),
    AniListExportTarget.shikimori => _buildShikimoriJson(
      entries: allEntries,
      anime: anime,
    ),
  };
  final String filename = switch ((target, anime)) {
    (AniListExportTarget.myAnimeList, true) => 'myanimelist_anime_$stamp.xml',
    (AniListExportTarget.myAnimeList, false) => 'myanimelist_manga_$stamp.xml',
    (AniListExportTarget.shikimori, true) => 'shikimori_anime_$stamp.json',
    (AniListExportTarget.shikimori, false) => 'shikimori_manga_$stamp.json',
  };
  final String extension = switch (target) {
    AniListExportTarget.myAnimeList => 'xml',
    AniListExportTarget.shikimori => 'json',
  };
  final String mimeType = switch (target) {
    AniListExportTarget.myAnimeList => 'application/xml',
    AniListExportTarget.shikimori => 'application/json',
  };

  return AniListExportPayload(
    filename: filename,
    bytes: Uint8List.fromList(utf8.encode(content)),
    mimeType: mimeType,
    fileExtension: extension,
    shareText: target == AniListExportTarget.myAnimeList
        ? 'MyAnimeList XML export'
        : 'Shikimori JSON export',
  );
}

Future<String?> saveAniListExportPayload(
  BuildContext context,
  AniListExportPayload payload,
) async {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final Rect origin = _computeShareOrigin(context);

  try {
    if (!kIsWeb && Platform.isIOS) {
      final dynamic tempDir = await getTemporaryDirectory();
      final String tempPath = p.join(tempDir.path, payload.filename);
      await File(tempPath).writeAsBytes(payload.bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(tempPath, mimeType: payload.mimeType)],
          sharePositionOrigin: origin,
        ),
      );
      return '';
    }

    if (!kIsWeb && Platform.isAndroid) {
      final String? savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          data: payload.bytes,
          fileName: payload.filename,
          mimeTypesFilter: <String>[payload.mimeType],
        ),
      );
      if (savedPath == null) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Save cancelled')),
        );
      }
      return savedPath;
    }

    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: payload.filename,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: payload.fileExtension.toUpperCase(),
          extensions: <String>[payload.fileExtension],
          mimeTypes: <String>[payload.mimeType],
        ),
      ],
    );
    if (location == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('Save cancelled')));
      return null;
    }

    if (kIsWeb) {
      await XFile.fromData(
        payload.bytes,
        name: payload.filename,
        mimeType: payload.mimeType,
      ).saveTo(location.path);
      return payload.filename;
    }

    await File(location.path).writeAsBytes(payload.bytes, flush: true);
    return location.path;
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Failed to export: $error')),
    );
    return null;
  }
}

String _buildMalXml({
  required List<AniListAnimeListEntry> entries,
  required String username,
  required bool anime,
  required DateTime generatedAt,
}) {
  final String generatedDate = DateFormat(
    'yyyy-MM-dd HH:mm:ss',
  ).format(generatedAt);
  final StringBuffer xml = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!-- Generated by MiruShin on $generatedDate -->')
    ..writeln('<myanimelist>')
    ..writeln('  <myinfo>')
    ..writeln('    <user_id>0</user_id>')
    ..writeln('    <user_name>${_xmlEscape(username)}</user_name>');

  final Map<String, int> counts = _statusCounts(entries);
  if (anime) {
    xml
      ..writeln('    <user_export_type>1</user_export_type>')
      ..writeln('    <user_total_anime>${entries.length}</user_total_anime>')
      ..writeln(
        '    <user_total_watching>${counts['current'] ?? 0}</user_total_watching>',
      )
      ..writeln(
        '    <user_total_completed>${counts['completed'] ?? 0}</user_total_completed>',
      )
      ..writeln(
        '    <user_total_onhold>${counts['paused'] ?? 0}</user_total_onhold>',
      )
      ..writeln(
        '    <user_total_dropped>${counts['dropped'] ?? 0}</user_total_dropped>',
      )
      ..writeln(
        '    <user_total_plantowatch>${counts['planning'] ?? 0}</user_total_plantowatch>',
      );
  } else {
    xml
      ..writeln('    <user_export_type>2</user_export_type>')
      ..writeln('    <user_total_manga>${entries.length}</user_total_manga>')
      ..writeln(
        '    <user_total_reading>${counts['current'] ?? 0}</user_total_reading>',
      )
      ..writeln(
        '    <user_total_completed>${counts['completed'] ?? 0}</user_total_completed>',
      )
      ..writeln(
        '    <user_total_onhold>${counts['paused'] ?? 0}</user_total_onhold>',
      )
      ..writeln(
        '    <user_total_dropped>${counts['dropped'] ?? 0}</user_total_dropped>',
      )
      ..writeln(
        '    <user_total_plantoread>${counts['planning'] ?? 0}</user_total_plantoread>',
      );
  }
  xml.writeln('  </myinfo>');

  for (final AniListAnimeListEntry entry in entries) {
    final int? malId = int.tryParse(entry.mediaItem.externalIds['mal'] ?? '');
    if (malId == null || malId <= 0) continue;
    if (anime) {
      xml
        ..writeln('  <anime>')
        ..writeln('    <series_animedb_id>$malId</series_animedb_id>')
        ..writeln(
          '    <series_title><![CDATA[${_cdata(entry.mediaItem.title)}]]></series_title>',
        )
        ..writeln(
          '    <series_type>${_xmlEscape(_malAnimeType(entry.format))}</series_type>',
        )
        ..writeln(
          '    <series_episodes>${entry.mediaItem.episodeCount ?? 0}</series_episodes>',
        )
        ..writeln('    <my_id>0</my_id>')
        ..writeln(
          '    <my_watched_episodes>${entry.progress}</my_watched_episodes>',
        )
        ..writeln(
          '    <my_start_date>${_formatMalDate(entry.startedAt)}</my_start_date>',
        )
        ..writeln(
          '    <my_finish_date>${_formatMalDate(entry.completedAt)}</my_finish_date>',
        )
        ..writeln(
          '    <my_score>${_normalizedTenScore(entry.score)}</my_score>',
        )
        ..writeln(
          '    <my_status>${_xmlEscape(_malAnimeStatus(entry.status))}</my_status>',
        )
        ..writeln(
          '    <my_comments><![CDATA[${_cdata(entry.notes)}]]></my_comments>',
        )
        ..writeln('    <my_times_watched>${entry.repeat}</my_times_watched>')
        ..writeln(
          '    <my_rewatching>${entry.status == AniListListStatus.repeating ? 1 : 0}</my_rewatching>',
        )
        ..writeln('    <update_on_import>1</update_on_import>')
        ..writeln('  </anime>');
    } else {
      xml
        ..writeln('  <manga>')
        ..writeln('    <series_mangadb_id>$malId</series_mangadb_id>')
        ..writeln(
          '    <series_title><![CDATA[${_cdata(entry.mediaItem.title)}]]></series_title>',
        )
        ..writeln(
          '    <series_type>${_xmlEscape(_malMangaType(entry.format))}</series_type>',
        )
        ..writeln(
          '    <series_chapters>${entry.mediaItem.episodeCount ?? 0}</series_chapters>',
        )
        ..writeln('    <series_volumes>0</series_volumes>')
        ..writeln('    <my_id>0</my_id>')
        ..writeln('    <my_read_chapters>${entry.progress}</my_read_chapters>')
        ..writeln('    <my_read_volumes>0</my_read_volumes>')
        ..writeln(
          '    <my_start_date>${_formatMalDate(entry.startedAt)}</my_start_date>',
        )
        ..writeln(
          '    <my_finish_date>${_formatMalDate(entry.completedAt)}</my_finish_date>',
        )
        ..writeln(
          '    <my_score>${_normalizedTenScore(entry.score)}</my_score>',
        )
        ..writeln(
          '    <my_status>${_xmlEscape(_malMangaStatus(entry.status))}</my_status>',
        )
        ..writeln(
          '    <my_comments><![CDATA[${_cdata(entry.notes)}]]></my_comments>',
        )
        ..writeln('    <my_times_read>${entry.repeat}</my_times_read>')
        ..writeln(
          '    <my_rereading>${entry.status == AniListListStatus.repeating ? 1 : 0}</my_rereading>',
        )
        ..writeln('    <update_on_import>1</update_on_import>')
        ..writeln('  </manga>');
    }
  }

  xml.writeln('</myanimelist>');
  return xml.toString();
}

String _buildShikimoriJson({
  required List<AniListAnimeListEntry> entries,
  required bool anime,
}) {
  final List<Map<String, Object?>> payload = entries
      .map((AniListAnimeListEntry entry) {
        final int? malId = int.tryParse(
          entry.mediaItem.externalIds['mal'] ?? '',
        );
        if (malId == null || malId <= 0) {
          return null;
        }
        return <String, Object?>{
          'target_title': entry.mediaItem.title,
          'target_title_ru': null,
          'target_id': malId,
          'target_type': anime ? 'Anime' : 'Manga',
          'score': _normalizedTenScore(entry.score),
          'status': anime
              ? _shikiAnimeStatus(entry.status)
              : _shikiMangaStatus(entry.status),
          'rewatches': entry.repeat,
          if (anime) 'episodes': entry.progress,
          if (anime) 'is_fav': false,
          if (!anime) 'volumes': 0,
          if (!anime) 'chapters': entry.progress,
          'text': entry.notes.isEmpty ? null : entry.notes,
        };
      })
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
  return const JsonEncoder.withIndent('  ').convert(payload);
}

Map<String, int> _statusCounts(List<AniListAnimeListEntry> entries) {
  final Map<String, int> counts = <String, int>{
    'current': 0,
    'planning': 0,
    'completed': 0,
    'paused': 0,
    'dropped': 0,
    'repeating': 0,
  };
  for (final AniListAnimeListEntry entry in entries) {
    counts[entry.status.name] = (counts[entry.status.name] ?? 0) + 1;
  }
  return counts;
}

List<AniListAnimeListEntry> _orderedEntries(
  List<AniListAnimeListFolder> folders,
) {
  final Iterable<AniListAnimeListEntry> allEntries = folders.expand(
    (AniListAnimeListFolder folder) => folder.entries,
  );
  final Map<AniListListStatus, List<AniListAnimeListEntry>> grouped =
      <AniListListStatus, List<AniListAnimeListEntry>>{};
  for (final AniListAnimeListEntry entry in allEntries) {
    grouped
        .putIfAbsent(entry.status, () => <AniListAnimeListEntry>[])
        .add(entry);
  }
  return <AniListAnimeListEntry>[
    ...?grouped[AniListListStatus.current]?.reversed,
    ...?grouped[AniListListStatus.repeating]?.reversed,
    ...?grouped[AniListListStatus.completed]?.reversed,
    ...?grouped[AniListListStatus.paused]?.reversed,
    ...?grouped[AniListListStatus.dropped]?.reversed,
    ...?grouped[AniListListStatus.planning]?.reversed,
  ];
}

Rect _computeShareOrigin(BuildContext context) {
  try {
    final RenderBox? overlay =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final RenderBox? box = overlay ?? context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
  } on Object {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}

String _formatMalDate(DateTime? value) {
  if (value == null) return '0000-00-00';
  return DateFormat('yyyy-MM-dd').format(value);
}

int _normalizedTenScore(double? value) {
  if (value == null || value <= 0) return 0;
  return value.round().clamp(0, 10);
}

String _malAnimeStatus(AniListListStatus status) {
  return switch (status) {
    AniListListStatus.current => 'Watching',
    AniListListStatus.completed => 'Completed',
    AniListListStatus.paused => 'On-Hold',
    AniListListStatus.dropped => 'Dropped',
    AniListListStatus.planning => 'Plan to Watch',
    AniListListStatus.repeating => 'Watching',
  };
}

String _malMangaStatus(AniListListStatus status) {
  return switch (status) {
    AniListListStatus.current => 'Reading',
    AniListListStatus.completed => 'Completed',
    AniListListStatus.paused => 'On-Hold',
    AniListListStatus.dropped => 'Dropped',
    AniListListStatus.planning => 'Plan to Read',
    AniListListStatus.repeating => 'Reading',
  };
}

String _shikiAnimeStatus(AniListListStatus status) {
  return switch (status) {
    AniListListStatus.current => 'watching',
    AniListListStatus.completed => 'completed',
    AniListListStatus.paused => 'on_hold',
    AniListListStatus.dropped => 'dropped',
    AniListListStatus.planning => 'planned',
    AniListListStatus.repeating => 'rewatching',
  };
}

String _shikiMangaStatus(AniListListStatus status) {
  return switch (status) {
    AniListListStatus.current => 'reading',
    AniListListStatus.completed => 'completed',
    AniListListStatus.paused => 'on_hold',
    AniListListStatus.dropped => 'dropped',
    AniListListStatus.planning => 'planned',
    AniListListStatus.repeating => 'rereading',
  };
}

String _malAnimeType(String? format) {
  return switch (format?.toUpperCase()) {
    'TV' => 'TV',
    'OVA' => 'OVA',
    'MOVIE' => 'Movie',
    'SPECIAL' => 'Special',
    'ONA' => 'ONA',
    'MUSIC' => 'Music',
    _ => 'Unknown',
  };
}

String _malMangaType(String? format) {
  return switch (format?.toUpperCase()) {
    'MANGA' => 'Manga',
    'NOVEL' || 'LIGHT_NOVEL' => 'Novel',
    'ONE_SHOT' => 'One-shot',
    'DOUJINSHI' || 'DOUJIN' => 'Doujinshi',
    'MANHWA' => 'Manhwa',
    'MANHUA' => 'Manhua',
    _ => 'Unknown',
  };
}

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _cdata(String value) => value.replaceAll(']]>', ']]]]><![CDATA[>');
