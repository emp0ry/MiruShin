import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/platform/native_exit_handshake.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mirushin/lifecycle');

  Future<Object?> nativeRequest(String method) {
    final reply = Completer<ByteData?>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method)),
      reply.complete,
    );
    return reply.future.then(
      (data) => data == null ? null : channel.codec.decodeEnvelope(data),
    );
  }

  test('native exit is acknowledged only after cleanup completes', () async {
    final handshake = NativeExitHandshake(channel: channel);
    final cleanup = Completer<void>();
    handshake.attach(() => cleanup.future);
    bool replied = false;
    final request = nativeRequest('prepareForExit').then((response) {
      replied = true;
      return response;
    });
    try {
      await Future<void>.delayed(Duration.zero);
      expect(replied, isFalse);
      cleanup.complete();
      expect(await request, isTrue);
    } finally {
      handshake.detach();
    }
  });

  test('failed cleanup never acknowledges unsafe native termination', () async {
    final handshake = NativeExitHandshake(channel: channel);
    handshake.attach(() async => throw StateError('DB is still in use'));
    try {
      await expectLater(
        nativeRequest('prepareForExit'),
        throwsA(isA<PlatformException>()),
      );
    } finally {
      handshake.detach();
    }
  });

  test('overlapping native requests await the same cleanup', () async {
    final handshake = NativeExitHandshake(channel: channel);
    final cleanup = Completer<void>();
    int calls = 0;
    handshake.attach(() {
      calls++;
      return cleanup.future;
    });
    final first = nativeRequest('prepareForExit');
    final second = nativeRequest('prepareForExit');
    try {
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      cleanup.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
    } finally {
      handshake.detach();
    }
  });
}
