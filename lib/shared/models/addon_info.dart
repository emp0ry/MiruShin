class AddonInfo {
  const AddonInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.enabled,
    required this.permissions,
    required this.category,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final bool enabled;
  final List<String> permissions;
  final String category;
}
