import 'dart:typed_data';

/// An LRU whose budget covers retained backing buffers, not just view lengths.
class BoundedByteCache<K> {
  BoundedByteCache({required this.maximumBytes, required this.maximumEntries});

  final int maximumBytes;
  final int maximumEntries;
  final Map<K, Uint8List> _entries = {};
  int _bytes = 0;

  int get byteCount => _bytes;
  int get entryCount => _entries.length;

  Uint8List? get(K key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void put(K key, Uint8List bytes) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.lengthInBytes;
    if (maximumEntries <= 0 || bytes.lengthInBytes > maximumBytes) return;
    // A sublistView can pin a multi-gigabyte video while exposing a few bytes.
    final owned =
        bytes.offsetInBytes != 0 ||
            bytes.buffer.lengthInBytes != bytes.lengthInBytes
        ? Uint8List.fromList(bytes)
        : bytes;
    _entries[key] = owned;
    _bytes += owned.lengthInBytes;
    while (_entries.length > maximumEntries || _bytes > maximumBytes) {
      _bytes -= _entries.remove(_entries.keys.first)!.lengthInBytes;
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}
