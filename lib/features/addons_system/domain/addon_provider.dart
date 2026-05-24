abstract interface class AddonProvider {
  String get id;
  String get name;
  String get version;
  bool get enabled;
  List<String> get permissions;
}

// Placeholder only. Real addon loading, execution, scraping, streaming, and
// parser/source modules are intentionally outside this foundation.
