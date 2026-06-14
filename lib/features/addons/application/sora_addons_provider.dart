import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/settings_state.dart';
import '../data/sora_addon_store.dart';
import '../data/sora_js_runtime.dart';
import '../domain/sora_models.dart';

final soraAddonStoreProvider = Provider<SoraAddonStore>((Ref ref) {
  return SoraAddonStore(
    webProxyUrl: ref.watch(
      settingsProvider.select((SettingsState s) => s.soraWebProxyUrl),
    ),
  );
});

final soraJsRuntimeProvider = Provider<SoraJsRuntime>((Ref ref) {
  final SoraJsRuntime runtime = SoraJsRuntime(
    store: ref.watch(soraAddonStoreProvider),
    webProxyUrl: ref.watch(
      settingsProvider.select((SettingsState s) => s.soraWebProxyUrl),
    ),
  );
  ref.onDispose(runtime.invalidateAll);
  return runtime;
});

final soraAddonsProvider =
    NotifierProvider<SoraAddonsController, SoraAddonsState>(
      SoraAddonsController.new,
    );

class SoraAddonsState {
  const SoraAddonsState({
    this.installed = const <SoraInstalledAddon>[],
    this.preview,
    this.loading = true,
    this.previewing = false,
    this.updating = false,
    this.autoUpdating = false,
    this.error,
  });

  final List<SoraInstalledAddon> installed;
  final SoraAddonPreview? preview;
  final bool loading;
  final bool previewing;
  final bool updating;
  final bool autoUpdating;
  final String? error;

  List<SoraInstalledAddon> get enabled {
    return installed
        .where((SoraInstalledAddon addon) => addon.enabled)
        .toList(growable: false);
  }

  List<SoraInstalledAddon> get enabledOrdered {
    return installed
        .where((SoraInstalledAddon addon) => addon.enabled)
        .toList(growable: false)
      ..sort(
        (SoraInstalledAddon a, SoraInstalledAddon b) =>
            a.order.compareTo(b.order),
      );
  }

  SoraInstalledAddon? byId(String id) {
    for (final SoraInstalledAddon addon in installed) {
      if (addon.id == id) {
        return addon;
      }
    }
    return null;
  }

  SoraAddonsState copyWith({
    List<SoraInstalledAddon>? installed,
    SoraAddonPreview? preview,
    bool? loading,
    bool? previewing,
    bool? updating,
    bool? autoUpdating,
    String? error,
    bool clearPreview = false,
    bool clearError = false,
  }) {
    return SoraAddonsState(
      installed: installed ?? this.installed,
      preview: clearPreview ? null : preview ?? this.preview,
      loading: loading ?? this.loading,
      previewing: previewing ?? this.previewing,
      updating: updating ?? this.updating,
      autoUpdating: autoUpdating ?? this.autoUpdating,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SoraAddonsController extends Notifier<SoraAddonsState> {
  @override
  SoraAddonsState build() {
    scheduleMicrotask(() => load(autoUpdate: true));
    return const SoraAddonsState();
  }

  Future<void> load({bool autoUpdate = false}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final SoraAddonStore store = ref.read(soraAddonStoreProvider);
      final List<SoraInstalledAddon> installed = await store.loadInstalled();
      state = state.copyWith(installed: installed, loading: false);
      if (autoUpdate && installed.isNotEmpty) {
        unawaited(autoUpdateStale());
      }
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: _friendlyError(error));
    }
  }

  Future<SoraAddonPreview?> previewFromUrl(String url) async {
    state = state.copyWith(previewing: true, clearError: true);
    try {
      final SoraAddonPreview preview = await ref
          .read(soraAddonStoreProvider)
          .previewFromUrl(url);
      state = state.copyWith(preview: preview, previewing: false);
      return preview;
    } on Object catch (error) {
      state = state.copyWith(
        previewing: false,
        error: _friendlyError(error),
        clearPreview: true,
      );
      return null;
    }
  }

  Future<SoraInstalledAddon?> installPreview(SoraAddonPreview preview) async {
    state = state.copyWith(updating: true, clearError: true);
    try {
      final SoraInstalledAddon addon = await ref
          .read(soraAddonStoreProvider)
          .installFromPreview(preview);
      ref.read(soraJsRuntimeProvider).invalidate(addon.id);
      await load();
      state = state.copyWith(updating: false, clearPreview: true);
      return addon;
    } on Object catch (error) {
      state = state.copyWith(updating: false, error: _friendlyError(error));
      return null;
    }
  }

  /// Previews and installs an addon directly from a manifest (or script) URL in
  /// one step. Used by the Sources browser where the URL is already known.
  Future<SoraInstalledAddon?> installFromUrl(String url) async {
    state = state.copyWith(updating: true, clearError: true);
    try {
      final SoraAddonStore store = ref.read(soraAddonStoreProvider);
      final SoraAddonPreview preview = await store.previewFromUrl(url);
      final SoraInstalledAddon addon = await store.installFromPreview(preview);
      ref.read(soraJsRuntimeProvider).invalidate(addon.id);
      await load();
      state = state.copyWith(updating: false, clearPreview: true);
      return addon;
    } on Object catch (error) {
      state = state.copyWith(updating: false, error: _friendlyError(error));
      return null;
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final SoraAddonStore store = ref.read(soraAddonStoreProvider);
    final SoraInstalledAddon addon = await store.setEnabled(id, enabled);
    ref.read(soraJsRuntimeProvider).invalidate(id);
    _patch(addon);
  }

  Future<void> updateAddon(String id) async {
    final SoraInstalledAddon? addon = state.byId(id);
    if (addon == null) {
      return;
    }
    state = state.copyWith(updating: true, clearError: true);
    try {
      final SoraInstalledAddon updated = await ref
          .read(soraAddonStoreProvider)
          .update(addon);
      ref.read(soraJsRuntimeProvider).invalidate(id);
      _patch(updated);
    } finally {
      state = state.copyWith(updating: false);
    }
  }

  Future<void> updateAll() async {
    state = state.copyWith(updating: true, clearError: true);
    try {
      final List<SoraInstalledAddon> updated = await ref
          .read(soraAddonStoreProvider)
          .updateAll();
      ref.read(soraJsRuntimeProvider).invalidateAll();
      state = state.copyWith(installed: updated, updating: false);
    } on Object catch (error) {
      state = state.copyWith(updating: false, error: _friendlyError(error));
    }
  }

  Future<String> exportInstalledJson() {
    return ref.read(soraAddonStoreProvider).exportInstalledJson();
  }

  Future<SoraAddonImportResult> importInstalledJson(String raw) async {
    state = state.copyWith(updating: true, clearError: true);
    try {
      final SoraAddonImportResult result = await ref
          .read(soraAddonStoreProvider)
          .importInstalledJson(raw);
      ref.read(soraJsRuntimeProvider).invalidateAll();
      final List<SoraInstalledAddon> installed = await ref
          .read(soraAddonStoreProvider)
          .loadInstalled();
      state = state.copyWith(
        installed: installed,
        updating: false,
        error: result.hasFailures ? result.failures.take(3).join('\n') : null,
        clearError: !result.hasFailures,
      );
      return result;
    } on Object catch (error) {
      state = state.copyWith(updating: false, error: _friendlyError(error));
      rethrow;
    }
  }

  Future<void> autoUpdateStale() async {
    if (state.autoUpdating) {
      return;
    }
    state = state.copyWith(autoUpdating: true);
    try {
      final List<SoraInstalledAddon> updated = await ref
          .read(soraAddonStoreProvider)
          .updateAll(onlyStale: true);
      ref.read(soraJsRuntimeProvider).invalidateAll();
      state = state.copyWith(installed: updated, autoUpdating: false);
    } on Object catch (error) {
      state = state.copyWith(autoUpdating: false, error: _friendlyError(error));
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    await ref.read(soraAddonStoreProvider).reorder(oldIndex, newIndex);
    await load();
  }

  Future<void> remove(String id) async {
    state = state.copyWith(updating: true, clearError: true);
    try {
      await ref.read(soraAddonStoreProvider).remove(id);
      ref.read(soraJsRuntimeProvider).invalidate(id);
      final List<SoraInstalledAddon> installed = await ref
          .read(soraAddonStoreProvider)
          .loadInstalled();
      state = state.copyWith(installed: installed, updating: false);
    } on Object catch (error) {
      state = state.copyWith(updating: false, error: _friendlyError(error));
    }
  }

  void clearPreview() {
    state = state.copyWith(clearPreview: true, clearError: true);
  }

  void _patch(SoraInstalledAddon addon) {
    final List<SoraInstalledAddon> installed = <SoraInstalledAddon>[
      for (final SoraInstalledAddon current in state.installed)
        current.id == addon.id ? addon : current,
    ];
    state = state.copyWith(installed: installed);
  }

  String _friendlyError(Object error) {
    if (error is SoraAddonException) {
      return error.message;
    }
    return error.toString();
  }
}
