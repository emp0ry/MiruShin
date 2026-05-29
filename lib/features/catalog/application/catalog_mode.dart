import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final catalogModeProvider =
    NotifierProvider<CatalogModeController, CatalogMode>(
      CatalogModeController.new,
    );

enum CatalogMode { tmdb, anilist }

extension CatalogModeLabel on CatalogMode {
  String get label => switch (this) {
    CatalogMode.tmdb => 'TMDB',
    CatalogMode.anilist => 'AniList',
  };

  CatalogMode get toggled => switch (this) {
    CatalogMode.tmdb => CatalogMode.anilist,
    CatalogMode.anilist => CatalogMode.tmdb,
  };
}

class CatalogModeController extends Notifier<CatalogMode> {
  static const String _key = 'catalog.mode';
  bool _loading = false;

  @override
  CatalogMode build() {
    if (!_loading) {
      _loading = true;
      unawaited(_load());
    }
    return CatalogMode.anilist;
  }

  Future<void> toggle() => setMode(state.toggled);

  Future<void> setMode(CatalogMode mode) async {
    if (state == mode) return;
    state = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    final CatalogMode loaded = CatalogMode.values.firstWhere(
      (CatalogMode mode) => mode.name == raw,
      orElse: () => CatalogMode.anilist,
    );
    if (state != loaded) {
      state = loaded;
    }
  }
}

bool mediaIdBelongsToMode(String id, CatalogMode mode) {
  final String normalized = id.toLowerCase();
  return switch (mode) {
    CatalogMode.tmdb => normalized.startsWith('tmdb:'),
    CatalogMode.anilist => normalized.startsWith('anilist:'),
  };
}
