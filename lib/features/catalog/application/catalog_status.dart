import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_mode.dart';

class CatalogOfflineNotice {
  const CatalogOfflineNotice({
    required this.mode,
    required this.sourceName,
    required this.operation,
    required this.usingCache,
    required this.occurredAt,
    this.detail,
  });

  final CatalogMode mode;
  final String sourceName;
  final String operation;
  final bool usingCache;
  final DateTime occurredAt;
  final String? detail;

  bool get isAniList => sourceName == 'AniList';

  String get title => isAniList
      ? 'AniList is temporarily unavailable'
      : '$sourceName is temporarily unavailable';

  String get message {
    if (isAniList) {
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
  @override
  CatalogOfflineNotice? build() => null;

  void clearIfMode(CatalogMode mode) {
    if (state?.mode == mode) {
      state = null;
    }
  }

  void show(CatalogOfflineNotice notice) {
    state = notice;
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
        ),
      );
}

String? _friendlyError(Object? error) {
  if (error == null) return null;
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
