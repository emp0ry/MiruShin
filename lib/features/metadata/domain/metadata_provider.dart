import '../../../shared/models/media_item.dart';

abstract interface class MetadataProvider {
  String get id;
  String get name;

  Future<List<MediaItem>> search(String query, {int page = 1});
  Future<List<MediaItem>> getPopular(MediaType type, {int page = 1});
  Future<List<MediaItem>> getTrending({int page = 1});
  Future<MediaItem?> getDetails(String id);
}

abstract interface class PagedDiscoveryProvider implements MetadataProvider {
  Future<List<MediaItem>> discoverPage({
    required String filter,
    required MediaType? type,
    required int page,
  });
}

class MetadataRepository {
  const MetadataRepository({required this.providers});

  final List<MetadataProvider> providers;

  Future<List<MediaItem>> search(
    String query, {
    MediaType? type,
    int page = 1,
  }) async {
    final List<MediaItem> items = await _merge(
      providers.map(
        (MetadataProvider provider) => provider.search(query, page: page),
      ),
    );
    if (type == null) {
      return items;
    }
    return items.where((MediaItem item) => item.type == type).toList();
  }

  Future<List<MediaItem>> getPopular(MediaType type, {int page = 1}) {
    return _merge(
      providers.map(
        (MetadataProvider provider) => provider.getPopular(type, page: page),
      ),
    );
  }

  Future<List<MediaItem>> getTrending({int page = 1}) {
    return _merge(
      providers.map(
        (MetadataProvider provider) => provider.getTrending(page: page),
      ),
    );
  }

  Future<List<MediaItem>> discover({
    required String filter,
    required MediaType? type,
    required int page,
  }) {
    return _merge(
      providers.map((MetadataProvider provider) async {
        if (provider is PagedDiscoveryProvider) {
          return provider.discoverPage(filter: filter, type: type, page: page);
        }
        if (filter == 'Trending') {
          final List<MediaItem> items = await provider.getTrending(page: page);
          return type == null
              ? items
              : items.where((MediaItem item) => item.type == type).toList();
        }
        if (type != null) {
          return provider.getPopular(type, page: page);
        }
        final List<MediaItem> items = await provider.getTrending(page: page);
        return items;
      }),
    );
  }

  Future<MediaItem?> getDetails(String id) async {
    for (final MetadataProvider provider in providers) {
      final MediaItem? item = await provider.getDetails(id);
      if (item != null) {
        return item;
      }
    }
    return null;
  }

  Future<List<MediaItem>> _merge(
    Iterable<Future<List<MediaItem>>> requests,
  ) async {
    Object? firstError;
    final List<List<MediaItem>> responses = await Future.wait(
      requests.map((Future<List<MediaItem>> request) async {
        try {
          return await request;
        } catch (error) {
          firstError ??= error;
          return <MediaItem>[];
        }
      }),
    );
    final Map<String, MediaItem> byId = <String, MediaItem>{};
    for (final List<MediaItem> response in responses) {
      for (final MediaItem item in response) {
        byId.putIfAbsent(item.id, () => item);
      }
    }
    if (byId.isEmpty && firstError != null) {
      throw firstError!;
    }
    return byId.values.toList();
  }
}
