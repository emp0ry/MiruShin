import 'mirushin_deep_link.dart';

typedef MiruShinDeepLinkDispatch = void Function(MiruShinDeepLink link);

/// Parses and serializes cold/warm activations until navigation is ready.
/// Keeping this independent from Flutter navigation makes queueing and
/// duplicate suppression deterministic and directly testable.
class MiruShinDeepLinkQueue {
  MiruShinDeepLinkQueue({
    required MiruShinDeepLinkDispatch dispatch,
    DateTime Function()? now,
  }) : _dispatch = dispatch,
       _now = now ?? DateTime.now;

  static const int maximumPendingLinks = 16;
  static const Duration duplicateWindow = Duration(seconds: 2);

  final MiruShinDeepLinkDispatch _dispatch;
  final DateTime Function() _now;
  final List<MiruShinDeepLink> _pending = <MiruShinDeepLink>[];
  bool _ready = false;
  String? _lastKey;
  DateTime? _lastAcceptedAt;

  void accept(String raw) {
    final MiruShinDeepLink? link = MiruShinDeepLink.tryParse(raw);
    if (link == null || _isDuplicate(link)) return;
    if (_ready) {
      _dispatch(link);
      return;
    }
    if (_pending.length == maximumPendingLinks) {
      _pending.removeAt(0);
    }
    _pending.add(link);
  }

  void markReady() {
    if (_ready) return;
    _ready = true;
    final List<MiruShinDeepLink> queued = List<MiruShinDeepLink>.of(_pending);
    _pending.clear();
    for (final MiruShinDeepLink link in queued) {
      _dispatch(link);
    }
  }

  void markNotReady() {
    _ready = false;
  }

  bool _isDuplicate(MiruShinDeepLink link) {
    final DateTime acceptedAt = _now();
    final bool duplicate =
        _lastKey == link.deduplicationKey &&
        _lastAcceptedAt != null &&
        acceptedAt.difference(_lastAcceptedAt!) <= duplicateWindow;
    if (!duplicate) {
      _lastKey = link.deduplicationKey;
      _lastAcceptedAt = acceptedAt;
    }
    return duplicate;
  }
}
