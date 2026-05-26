import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefix = 'mirushin.web_file.';

class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
}

class FileSystemEntity {
  FileSystemEntity(this.path);

  final String path;

  Uri get uri => Uri(path: path);

  Future<FileSystemEntity> delete({bool recursive = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(path));
    return this;
  }
}

class File extends FileSystemEntity {
  File(super.path);

  Directory get parent {
    final int slash = path.lastIndexOf('/');
    if (slash <= 0) return Directory('.');
    return Directory(path.substring(0, slash));
  }

  Future<bool> exists() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(path));
  }

  Future<String> readAsString() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(_key(path));
    if (value == null) {
      throw StateError('File does not exist: $path');
    }
    return value;
  }

  Future<File> writeAsString(String contents, {bool flush = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(path), contents);
    return this;
  }

  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(path), base64Encode(bytes));
    return this;
  }

  Future<int> length() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? value = prefs.getString(_key(path));
    return value == null ? 0 : utf8.encode(value).length;
  }
}

class Directory extends FileSystemEntity {
  Directory(super.path);

  Future<bool> exists() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String prefix = _key(_withTrailingSlash(path));
    return prefs.getKeys().any((String key) => key.startsWith(prefix));
  }

  Future<Directory> create({bool recursive = false}) async => this;

  @override
  Future<Directory> delete({bool recursive = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String prefix = _key(_withTrailingSlash(path));
    final Iterable<String> keys = prefs.getKeys().where(
      (String key) => key.startsWith(prefix),
    );
    for (final String key in keys.toList(growable: false)) {
      await prefs.remove(key);
    }
    return this;
  }

  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String directory = _withTrailingSlash(path);
    final String prefix = _key(directory);
    for (final String key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final String relative = key.substring(prefix.length);
      if (!recursive && relative.contains('/')) continue;
      yield File('$directory$relative');
    }
  }
}

String _key(String path) => '$_prefix$path';

String _withTrailingSlash(String path) => path.endsWith('/') ? path : '$path/';
