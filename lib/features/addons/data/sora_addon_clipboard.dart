import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';

import '../domain/sora_models.dart';

class SoraAddonClipboardFile {
  const SoraAddonClipboardFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class SoraLocalAddonFiles {
  const SoraLocalAddonFiles({required this.manifest, required this.script});

  final SoraAddonClipboardFile manifest;
  final SoraAddonClipboardFile script;

  factory SoraLocalAddonFiles.fromFiles(List<SoraAddonClipboardFile> files) {
    if (files.length != 2) {
      throw const SoraAddonException(
        'Clipboard must contain exactly one .json file and one .js file.',
      );
    }
    SoraAddonClipboardFile? manifest;
    SoraAddonClipboardFile? script;
    for (final SoraAddonClipboardFile file in files) {
      switch (p.extension(file.name).toLowerCase()) {
        case '.json':
          if (manifest != null) {
            throw const SoraAddonException(
              'Clipboard must contain exactly one .json file and one .js file.',
            );
          }
          manifest = file;
        case '.js':
          if (script != null) {
            throw const SoraAddonException(
              'Clipboard must contain exactly one .json file and one .js file.',
            );
          }
          script = file;
        default:
          throw const SoraAddonException(
            'Clipboard must contain exactly one .json file and one .js file.',
          );
      }
    }
    if (manifest == null || script == null) {
      throw const SoraAddonException(
        'Clipboard must contain exactly one .json file and one .js file.',
      );
    }
    return SoraLocalAddonFiles(manifest: manifest, script: script);
  }
}

class SoraAddonClipboardContent {
  const SoraAddonClipboardContent({this.localFiles, this.text = ''});

  final SoraLocalAddonFiles? localFiles;
  final String text;
}

class SoraAddonClipboardReader {
  const SoraAddonClipboardReader();

  static const int _maximumFileBytes = 16 * 1024 * 1024;

  Future<SoraAddonClipboardContent> readSystemClipboard() async {
    final SystemClipboard? clipboard = SystemClipboard.instance;
    if (clipboard != null) {
      try {
        return await read(await clipboard.read());
      } on SoraAddonException {
        rethrow;
      } on Object {
        // Fall through to Flutter's text-only clipboard on unsupported or
        // restricted platforms.
      }
    }
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    return SoraAddonClipboardContent(text: data?.text ?? '');
  }

  Future<SoraAddonClipboardContent> read(ClipboardReader reader) async {
    final List<_NamedClipboardReader> namedReaders = <_NamedClipboardReader>[];
    for (final ClipboardDataReader item in reader.items) {
      final String name = (await item.getSuggestedName())?.trim() ?? '';
      if (name.isNotEmpty) {
        namedReaders.add(_NamedClipboardReader(item: item, name: name));
      }
    }
    if (namedReaders.isNotEmpty) {
      if (namedReaders.length != 2) {
        throw const SoraAddonException(
          'Clipboard must contain exactly one .json file and one .js file.',
        );
      }
      final List<SoraAddonClipboardFile> files = <SoraAddonClipboardFile>[];
      for (final _NamedClipboardReader named in namedReaders) {
        final String extension = p.extension(named.name).toLowerCase();
        if (extension != '.json' && extension != '.js') {
          throw const SoraAddonException(
            'Clipboard must contain exactly one .json file and one .js file.',
          );
        }
        files.add(await _readFile(named));
      }
      return SoraAddonClipboardContent(
        localFiles: SoraLocalAddonFiles.fromFiles(files),
      );
    }
    return SoraAddonClipboardContent(
      text: await reader.readValue(Formats.plainText) ?? '',
    );
  }

  Future<SoraAddonClipboardFile> _readFile(_NamedClipboardReader named) async {
    final Completer<SoraAddonClipboardFile> completer =
        Completer<SoraAddonClipboardFile>();
    final ReadProgress? progress = named.item.getFile(
      null,
      (DataReaderFile file) async {
        try {
          final int? size = file.fileSize;
          if (size != null && size > _maximumFileBytes) {
            throw const SoraAddonException(
              'Clipboard addon file is too large.',
            );
          }
          final Uint8List bytes = await file.readAll();
          if (bytes.length > _maximumFileBytes) {
            throw const SoraAddonException(
              'Clipboard addon file is too large.',
            );
          }
          if (!completer.isCompleted) {
            completer.complete(
              SoraAddonClipboardFile(
                name: file.fileName?.trim().isNotEmpty == true
                    ? file.fileName!.trim()
                    : named.name,
                bytes: bytes,
              ),
            );
          }
        } on Object catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );
    if (progress == null && !completer.isCompleted) {
      completer.completeError(
        SoraAddonException('Could not read ${named.name} from the clipboard.'),
      );
    }
    return completer.future;
  }
}

class _NamedClipboardReader {
  const _NamedClipboardReader({required this.item, required this.name});

  final ClipboardDataReader item;
  final String name;
}
