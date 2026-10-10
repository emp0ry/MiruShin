import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'catalog_mode.dart';

class CatalogOfflineNotice {
  const CatalogOfflineNotice({
    required this.mode,
    required this.sourceName,
    required this.operation,
    required this.usingCache,
    required this.occurredAt,
    this.detail,
    this.fallbackSourceName,
    this.isLocalFailure = false,
  });

  final CatalogMode mode;
  final String sourceName;
  final String operation;
  final bool usingCache;
  final DateTime occurredAt;
  final String? detail;
  final String? fallbackSourceName;
  final bool isLocalFailure;

  bool get isAniList => sourceName == 'AniList';

  String get title => isLocalFailure
      ? 'Library sync needs attention'
      : isAniList
      ? 'AniList is temporarily unavailable'
      : '$sourceName is temporarily unavailable';

  String get message {
    if (isLocalFailure) {
      return 'A local sync error prevented this update. Your saved library is still available. This does not mean the catalog is down.';
    }
    if (isAniList) {
      if (fallbackSourceName != null) {
        return 'MiruShin is temporarily using $fallbackSourceName while AniList is unavailable.';
      }
      if (usingCache) {
        return 'MiruShin is using your saved anime data while AniList is down. You can keep browsing cached pages and try again later.';
      }
      return 'MiruShin cannot load this page yet because there is no saved AniList data. Please try again later, or check AniList Discord announcements for outage updates.';
    }
    if (usingCache) {
      return 'MiruShin is showing saved $operation data while $sourceName is down.';
    }
    return 'MiruShin cannot load this $operation page yet because there is no saved $sourceName data.';
  }
}

final catalogOfflineNoticeProvider =
    NotifierProvider<CatalogOfflineNoticeController, CatalogOfflineNotice?>(
      CatalogOfflineNoticeController.new,
    );

class CatalogOfflineNoticeController extends Notifier<CatalogOfflineNotice?> {
  final Set<CatalogMode> _dismissedUntilOnline = <CatalogMode>{};

  @override
  CatalogOfflineNotice? build() => null;

  void clearIfMode(CatalogMode mode) {
    _dismissedUntilOnline.remove(mode);
    if (state?.mode == mode) {
      state = null;
    }
  }

  void show(CatalogOfflineNotice notice) {
    if (_dismissedUntilOnline.contains(notice.mode)) return;
    state = notice;
  }

  void dismiss(CatalogOfflineNotice notice) {
    if (!identical(state, notice)) return;
    _dismissedUntilOnline.add(notice.mode);
    state = null;
  }
}

void markCatalogOnline(Ref ref, CatalogMode mode) {
  ref.read(catalogOfflineNoticeProvider.notifier).clearIfMode(mode);
}

void markCatalogOffline(
  Ref ref, {
  required CatalogMode mode,
  required String sourceName,
  required String operation,
  required bool usingCache,
  Object? error,
  String? fallbackSourceName,
  bool localProcessingFailure = false,
}) {
  ref
      .read(catalogOfflineNoticeProvider.notifier)
      .show(
        CatalogOfflineNotice(
          mode: mode,
          sourceName: sourceName,
          operation: operation,
          usingCache: usingCache,
          occurredAt: DateTime.now(),
          detail: _friendlyError(error),
          fallbackSourceName: fallbackSourceName,
          isLocalFailure: localProcessingFailure || error is SqliteException,
        ),
      );
}

String? _friendlyError(Object? error) {
  if (error == null) return null;
  if (error is SqliteException) {
    return 'Local library database error (${error.extendedResultCode}). Please retry sync.';
  }
  final String raw = error.toString();
  if (raw.trim().isEmpty) return null;
  if (raw.contains('SocketException') || raw.contains('Connection')) {
    return 'Network connection failed.';
  }
  if (raw.contains('timed out') || raw.contains('TimeoutException')) {
    return 'Request timed out.';
  }
  if (raw.contains('429')) {
    return 'Too many requests were sent. Please wait a bit and try again.';
  }
  if (raw.contains('403')) {
    return 'AniList may be temporarily blocking API requests.';
  }
  if (raw.contains('500') || raw.contains('502') || raw.contains('503')) {
    return 'Service is temporarily unavailable.';
  }
  final String trimmed = raw.replaceAll('StateError: ', '').trim();
  return trimmed.length > 150 ? '${trimmed.substring(0, 150)}…' : trimmed;
}
