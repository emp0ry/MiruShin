import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/cache/artwork_cache_manager.dart';
import '../../../core/platform/io_compat.dart' if (dart.library.io) 'dart:io';
import '../../../core/platform/tv_platform.dart';

typedef ArtworkBytesLoader = Future<Uint8List> Function(String imageUrl);

Future<void> downloadArtworkImage(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String filenameSuffix,
  ArtworkBytesLoader? loadBytes,
}) async {
  try {
    final Uint8List bytes = await (loadBytes ?? _loadArtworkBytes)(imageUrl);
    final _ArtworkFormat format = _artworkFormat(imageUrl, bytes);
    final String filename = _artworkFilename(
      title: title,
      suffix: filenameSuffix,
      extension: format.extension,
    );
    if (!context.mounted) return;
    final String? path = await _saveArtworkBytes(
      context,
      bytes: bytes,
      filename: filename,
      mimeType: format.mimeType,
    );
    if (!context.mounted) return;
    final String message = path == null
        ? context.t('Image download cancelled')
        : path.isEmpty
        ? context.t('Image shared')
        : context.tf('Image saved to {path}', <String, Object?>{'path': path});
    _showMessage(context, message);
  } on Object catch (error) {
    if (!context.mounted) return;
    _showMessage(
      context,
      context.tf('Image download failed: {error}', <String, Object?>{
        'error': error,
      }),
    );
  }
}

Future<Uint8List> _loadArtworkBytes(String imageUrl) async {
  final dynamic file = await miruShinArtworkCacheManager.getSingleFile(
    imageUrl,
  );
  return file.readAsBytes() as Future<Uint8List>;
}

Future<String?> _saveArtworkBytes(
  BuildContext context, {
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final Rect shareOrigin = _shareOrigin(context);

  if (!kIsWeb && Platform.isIOS) {
    final dynamic temporary = await getTemporaryDirectory();
    final String temporaryPath = p.join(temporary.path as String, filename);
    await File(temporaryPath).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(temporaryPath, mimeType: mimeType)],
        sharePositionOrigin: shareOrigin,
      ),
    );
    return '';
  }

  if (!kIsWeb && Platform.isAndroid && TvPlatform.isAndroidTv) {
    final dynamic base = await getExternalStorageDirectory();
    if (base == null) return null;
    final Directory directory = Directory(
      p.join(base.path as String, 'exports'),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final String path = p.join(directory.path, filename);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  if (!kIsWeb && Platform.isAndroid) {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        data: bytes,
        fileName: filename,
        mimeTypesFilter: <String>[mimeType],
      ),
    );
  }

  final XTypeGroup imageTypeGroup = XTypeGroup(
    label: 'Image',
    extensions: <String>[p.extension(filename).substring(1)],
    mimeTypes: <String>[mimeType],
  );
  final FileSaveLocation? location = await getSaveLocation(
    suggestedName: filename,
    acceptedTypeGroups: <XTypeGroup>[imageTypeGroup],
  );
  if (location == null) return null;
  if (kIsWeb) {
    await XFile.fromData(
      bytes,
      name: filename,
      mimeType: mimeType,
    ).saveTo(location.path);
    return filename;
  }
  await File(location.path).writeAsBytes(bytes, flush: true);
  return location.path;
}

String _artworkFilename({
  required String title,
  required String suffix,
  required String extension,
}) {
  String safe(String value, String fallback) {
    final String cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty) return fallback;
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80).trim();
  }

  return '${safe(title, 'artwork')}_${safe(suffix, 'image')}.$extension';
}

_ArtworkFormat _artworkFormat(String imageUrl, Uint8List bytes) {
  if (_startsWith(bytes, const <int>[0x89, 0x50, 0x4e, 0x47])) {
    return const _ArtworkFormat('png', 'image/png');
  }
  if (_startsWith(bytes, const <int>[0xff, 0xd8, 0xff])) {
    return const _ArtworkFormat('jpg', 'image/jpeg');
  }
  if (_startsWith(bytes, const <int>[0x47, 0x49, 0x46, 0x38])) {
    return const _ArtworkFormat('gif', 'image/gif');
  }
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 4) == 'RIFF' &&
      _ascii(bytes, 8, 12) == 'WEBP') {
    return const _ArtworkFormat('webp', 'image/webp');
  }
  if (bytes.length >= 12 && _ascii(bytes, 4, 8) == 'ftyp') {
    final String brand = _ascii(bytes, 8, 12);
    if (brand == 'avif' || brand == 'avis') {
      return const _ArtworkFormat('avif', 'image/avif');
    }
  }

  final String extension = p
      .extension(Uri.tryParse(imageUrl)?.path ?? '')
      .replaceFirst('.', '')
      .toLowerCase();
  return switch (extension) {
    'png' => const _ArtworkFormat('png', 'image/png'),
    'gif' => const _ArtworkFormat('gif', 'image/gif'),
    'webp' => const _ArtworkFormat('webp', 'image/webp'),
    'avif' => const _ArtworkFormat('avif', 'image/avif'),
    'jpeg' => const _ArtworkFormat('jpeg', 'image/jpeg'),
    _ => const _ArtworkFormat('jpg', 'image/jpeg'),
  };
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (int index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

String _ascii(Uint8List bytes, int start, int end) =>
    String.fromCharCodes(bytes.sublist(start, end));

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

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _ArtworkFormat {
  const _ArtworkFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}
