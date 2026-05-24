import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class CastController {
  bool get isSupported;
  Future<void> startSession();
}

class UnsupportedCastController implements CastController {
  const UnsupportedCastController();

  @override
  bool get isSupported => false;

  @override
  Future<void> startSession() async {}
}

final castControllerProvider = Provider<CastController>(
  (_) => const UnsupportedCastController(),
);
