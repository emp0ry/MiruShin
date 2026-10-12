import 'dart:async';
import '../domain/sora_models.dart';

/// Replays the newest batch to all addons without restarting their searches.
class TitleVariantSession {
  TitleVariantSession(Stream<List<SoraTitleVariant>> batches, {this.onCancel}) {
    _subscription = batches.listen(
      (batch) {
        final unique = {
          for (final v in _variants)
            '${v.languageCode}|${v.title.toLowerCase()}': v,
        };
        for (final v in batch) {
          unique['${v.languageCode}|${v.title.toLowerCase()}'] = v;
        }
        _variants = List.unmodifiable(unique.values);
        if (!_initial.isCompleted) _initial.complete(_variants);
        _notify();
      },
      onError: (Object _) => _finish(),
      onDone: _finish,
    );
  }
  final _initial = Completer<List<SoraTitleVariant>>();
  final void Function()? onCancel;
  bool _cancelled = false;
  int _version = 0;
  final Set<String> _settledLanguages = {};
  final _done = Completer<void>();
  final Set<Completer<void>> _waiters = {};
  late final StreamSubscription<List<SoraTitleVariant>> _subscription;
  List<SoraTitleVariant> _variants = const [];
  Future<List<SoraTitleVariant>> get initial => _initial.future;
  Future<void> get done => _done.future;
  List<SoraTitleVariant> get variants => _variants;

  void markLanguageSettled(String code) {
    if (_settledLanguages.add(code)) _notify();
  }

  /// Replay latest and then new batches. Searches process only untried queries,
  /// rather than awaiting the slowest provider before using a ready language.
  Stream<List<SoraTitleVariant>> watch() async* {
    await initial;
    int observed = -1;
    while (!_cancelled) {
      if (observed != _version) {
        observed = _version;
        yield _variants;
      }
      if (observed != _version) continue;
      if (_done.isCompleted) break;
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
  }

  Future<List<SoraTitleVariant>> forLanguage(String code) async {
    await initial;
    while (!_done.isCompleted &&
        !_settledLanguages.contains(code) &&
        !_variants.any((v) => v.languageCode == code)) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    return _variants;
  }

  void _notify() {
    _version++;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiters.clear();
  }

  void _finish() {
    if (!_initial.isCompleted) _initial.complete(_variants);
    if (!_done.isCompleted) _done.complete();
    _notify();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    onCancel?.call();
    _finish();
    unawaited(_subscription.cancel());
  }
}

/// Bounds each new title batch, keeps late names eligible and never retries an
/// identical addon/language/query just because another provider finished.
class TitleQueryLedger {
  final Map<String, Set<String>> _known = {};
  final Map<String, List<String>> _eligible = {};
  final Set<String> _attempted = {};

  List<String> acceptBatch(String language, Iterable<String> queries) {
    final known = _known.putIfAbsent(language, () => {});
    final fresh = <String>[];
    for (final query in queries) {
      if (known.add(query.trim().toLowerCase())) fresh.add(query);
    }
    final eligible = _eligible.putIfAbsent(language, () => []);
    eligible.insertAll(0, fresh.take(3));
    return List.unmodifiable(eligible);
  }

  bool wasAttempted(String addon, String language, String query) =>
      _attempted.contains('$addon|$language|${query.toLowerCase()}');
  bool claim(String addon, String language, String query) =>
      _attempted.add('$addon|$language|${query.toLowerCase()}');
}
