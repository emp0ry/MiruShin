import 'dart:collection';

/// A read-only projection that does not retain converted elements.
///
/// Useful when a serializer requires a List but each input row contains large
/// JSON documents. Only the row being visited needs its expanded object graph;
/// materializing all converted rows first can multiply memory use by gigabytes.
class LazyMappedList<S, T> extends ListBase<T> {
  LazyMappedList(List<S> source, T Function(S) convert)
    : _source = UnmodifiableListView(source),
      _convert = convert;

  final List<S> _source;
  final T Function(S) _convert;

  @override
  int get length => _source.length;

  @override
  T operator [](int index) => _convert(_source[index]);

  @override
  set length(int value) => throw UnsupportedError('Read-only mapped list.');

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Read-only mapped list.');
}
