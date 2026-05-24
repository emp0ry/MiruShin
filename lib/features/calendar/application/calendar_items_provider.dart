import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/calendar_item.dart';
import '../../catalog/application/catalog_repository.dart';
import '../../metadata/application/metadata_providers.dart';

final calendarItemsProvider = FutureProvider<List<CalendarItem>>((
  Ref ref,
) async {
  final CatalogRepository? catalog = ref.watch(activeCatalogRepositoryProvider);
  if (catalog == null) {
    return <CalendarItem>[];
  }
  final DateTime now = DateTime.now();
  try {
    return await catalog.calendar(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month + 3, now.day),
    );
  } catch (_) {
    return <CalendarItem>[];
  }
});
