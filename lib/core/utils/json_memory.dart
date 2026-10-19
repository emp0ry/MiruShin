import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Hash without materializing an additional whole JSON string/UTF-8 buffer.
String jsonSha256(Object? value) {
  final result = _DigestSink();
  final encoder = JsonUtf8Encoder().startChunkedConversion(
    sha256.startChunkedConversion(result),
  );
  encoder.add(value);
  encoder.close();
  return result.value.toString();
}

String utf8ChunksSha256(Iterable<String> chunks) {
  final result = _DigestSink();
  final encoder = utf8.encoder.startChunkedConversion(
    sha256.startChunkedConversion(result),
  );
  for (final chunk in chunks) {
    encoder.add(chunk);
  }
  encoder.close();
  return result.value.toString();
}

int jsonUtf8Size(Object? value) {
  final count = _ByteCountSink();
  final encoder = JsonUtf8Encoder().startChunkedConversion(count);
  encoder.add(value);
  encoder.close();
  return count.value;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}

class _ByteCountSink implements Sink<List<int>> {
  int value = 0;
  @override
  void add(List<int> bytes) => value += bytes.length;
  @override
  void close() {}
}
