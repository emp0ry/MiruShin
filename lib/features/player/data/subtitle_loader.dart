import 'package:dio/dio.dart';

import '../../../core/platform/io_compat.dart'
    if (dart.library.io) 'dart:io'
    as io;
import '../domain/player_models.dart';
import 'subtitle_parser.dart';

Future<List<SubtitleCue>> loadSubtitleCues(SubtitleTrack track) async {
  try {
    return const SubtitleParser().parse(await readSubtitleSource(track));
  } on Object {
    return const <SubtitleCue>[];
  }
}

Future<String> readSubtitleSource(SubtitleTrack track) async {
  final Uri? uri = Uri.tryParse(track.url);
  if (!isRemoteSubtitleTrack(track)) {
    final String path = uri != null && uri.scheme == 'file'
        ? uri.toFilePath()
        : track.url;
    return io.File(path).readAsString();
  }
  final Response<String> response = await Dio().get<String>(
    track.url,
    options: track.headers.isNotEmpty ? Options(headers: track.headers) : null,
  );
  return response.data ?? '';
}

bool isRemoteSubtitleTrack(SubtitleTrack track) {
  final Uri? uri = Uri.tryParse(track.url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

bool isLocalSubtitleTrack(SubtitleTrack track) => !isRemoteSubtitleTrack(track);
