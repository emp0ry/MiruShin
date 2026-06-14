import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/addon_source_models.dart';
import '../domain/sora_models.dart';
import 'sora_addons_provider.dart';

/// Fetches and parses the module catalog for a single source URL. Family key is
/// the catalog URL so each source caches independently and exposes its own
/// loading/error state.
final addonCatalogProvider =
    FutureProvider.family<List<AddonCatalogEntry>, String>((
      Ref ref,
      String url,
    ) async {
      return ref.read(soraAddonStoreProvider).fetchCatalog(url);
    });

final addonSourcesProvider =
    NotifierProvider<AddonSourcesController, AddonSourcesState>(
      AddonSourcesController.new,
    );

class AddonSourcesState {
  const AddonSourcesState({
    this.sources = const <AddonSource>[],
    this.loading = true,
    this.error,
  });

  final List<AddonSource> sources;
  final bool loading;
  final String? error;

  bool get isEmpty => sources.isEmpty;

  bool containsUrl(String url) {
    final String normalized = url.trim().toLowerCase();
    return sources.any(
      (AddonSource source) => source.url.trim().toLowerCase() == normalized,
    );
  }

  AddonSourcesState copyWith({
    List<AddonSource>? sources,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AddonSourcesState(
      sources: sources ?? this.sources,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AddonSourcesController extends Notifier<AddonSourcesState> {
  static const String _key = 'sora.moduleSources';

  @override
  AddonSourcesState build() {
    scheduleMicrotask(load);
    return const AddonSourcesState();
  }

  Future<void> load() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? raw = preferences.getString(_key);
      state = state.copyWith(
        sources: _decode(raw),
        loading: false,
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  /// Validates a catalog URL by fetching it, then persists the source. Returns
  /// the created source, or throws [SoraAddonException] on a bad URL/catalog.
  Future<AddonSource> addSource(String url, {String name = ''}) async {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const SoraAddonException('Enter a catalog URL.');
    }
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SoraAddonException(
        'Enter a valid catalog URL (e.g. https://example.com/modules.json).',
      );
    }
    if (state.containsUrl(trimmed)) {
      throw const SoraAddonException('This source is already added.');
    }
    // Fetch once up front so an unreachable or malformed catalog is rejected
    // before it is saved.
    await ref.read(soraAddonStoreProvider).fetchCatalog(trimmed);
    final AddonSource source = AddonSource.create(url: trimmed, name: name);
    final List<AddonSource> next = <AddonSource>[...state.sources, source];
    await _save(next);
    state = state.copyWith(sources: next, clearError: true);
    return source;
  }

  Future<void> removeSource(String id) async {
    final List<AddonSource> next = state.sources
        .where((AddonSource source) => source.id != id)
        .toList(growable: false);
    await _save(next);
    state = state.copyWith(sources: next);
  }

  Future<void> renameSource(String id, String name) async {
    final List<AddonSource> next = <AddonSource>[
      for (final AddonSource source in state.sources)
        source.id == id ? source.copyWith(name: name.trim()) : source,
    ];
    await _save(next);
    state = state.copyWith(sources: next);
  }

  /// Refetches every source's catalog (used by pull-to-refresh / Refresh All).
  void refresh() {
    for (final AddonSource source in state.sources) {
      ref.invalidate(addonCatalogProvider(source.url));
    }
  }

  Future<void> _save(List<AddonSource> sources) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(
        sources.map((AddonSource source) => source.toJson()).toList(),
      ),
    );
  }

  List<AddonSource> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <AddonSource>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <AddonSource>[];
      }
      return <AddonSource>[
        for (final Object? entry in decoded)
          if (entry is Map)
            AddonSource.fromJson(
              entry.map(
                (Object? key, Object? value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              ),
            ),
      ].where((AddonSource source) => source.url.isNotEmpty).toList();
    } on Object {
      return const <AddonSource>[];
    }
  }
}
