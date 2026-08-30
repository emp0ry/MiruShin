import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/io_compat.dart' if (dart.library.io) 'dart:io';
import '../../../core/platform/tv_platform.dart';

const XTypeGroup _backupTypeGroup = XTypeGroup(
  label: 'MiruShin backup',
  extensions: <String>['json'],
  mimeTypes: <String>['application/json'],
);

bool get _useTvFileFallback =>
    !kIsWeb && Platform.isAndroid && TvPlatform.isAndroidTv;

String miruShinBackupFilename() {
  final DateTime now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'mirushin_backup_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
}

Future<String?> pickMiruShinBackupJson() async {
  if (_useTvFileFallback) {
    final File? file = await _newestTvBackup();
    return file?.readAsString();
  }
  final XFile? file = await openFile(
    acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
  );
  return file?.readAsString();
}

Future<String?> saveMiruShinBackupJson(
  BuildContext context,
  String json,
) async {
  final String filename = miruShinBackupFilename();
  final Uint8List bytes = Uint8List.fromList(utf8.encode(json));
  final Rect shareOrigin = _shareOrigin(context);

  if (!kIsWeb && Platform.isIOS) {
    final dynamic temporary = await getTemporaryDirectory();
    final String temporaryPath = p.join(temporary.path as String, filename);
    await File(temporaryPath).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(temporaryPath, mimeType: 'application/json')],
        sharePositionOrigin: shareOrigin,
      ),
    );
    return '';
  }

  if (_useTvFileFallback) {
    final String? directory = await _tvExportsDirectory();
    if (directory == null) return null;
    final String path = p.join(directory, filename);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  if (!kIsWeb && Platform.isAndroid) {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: bytes,
        fileName: filename,
        mimeTypesFilter: const <String>['application/json'],
      ),
    );
  }

  final FileSaveLocation? location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
  );
  if (location == null) return null;
  if (kIsWeb) {
    await XFile.fromData(
      bytes,
      name: filename,
      mimeType: 'application/json',
    ).saveTo(location.path);
    return filename;
  }
  await File(location.path).writeAsBytes(bytes, flush: true);
  return location.path;
}

Future<String?> _tvExportsDirectory() async {
  final dynamic base = await getExternalStorageDirectory();
  if (base == null) return null;
  final String path = p.join(base.path as String, 'exports');
  final Directory directory = Directory(path);
  if (!await directory.exists()) await directory.create(recursive: true);
  return path;
}

Future<File?> _newestTvBackup() async {
  final String? directoryPath = await _tvExportsDirectory();
  if (directoryPath == null) return null;
  final List<File> candidates = <File>[
    await for (final FileSystemEntity entity in Directory(directoryPath).list())
      if (entity is File &&
          p
              .basename(entity.path)
              .toLowerCase()
              .startsWith('mirushin_backup_') &&
          p.extension(entity.path).toLowerCase() == '.json')
        entity,
  ];
  if (candidates.isEmpty) return null;
  candidates.sort((File left, File right) => right.path.compareTo(left.path));
  return candidates.first;
}

Rect _shareOrigin(BuildContext context) {
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
