import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/playback_attempt_plan.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine_factory.dart';

void main() {
  test('MPV capability excludes only process-unsafe platform combinations', () {
    final bool hlsAvailable = isPlayerEngineBackendAvailable(
      PlayerBackend.mpv,
      streamType: StreamType.hls,
    );
    final bool dashAvailable = isPlayerEngineBackendAvailable(
      PlayerBackend.mpv,
      streamType: StreamType.dash,
    );

    if (Platform.isLinux) {
      expect(hlsAvailable, isFalse);
      expect(dashAvailable, isFalse);
    } else if (Platform.isWindows) {
      expect(hlsAvailable, isTrue);
      expect(dashAvailable, isFalse);
    } else {
      expect(hlsAvailable, isTrue);
      expect(dashAvailable, isTrue);
    }
    expect(
      isPlayerEngineBackendAvailable(
        PlayerBackend.fvp,
        streamType: StreamType.dash,
      ),
      isTrue,
    );

    final bool fvpDashProxy = isPlayerEngineRouteAvailable(
      PlayerBackend.fvp,
      PlaybackRoute.localProxy,
      streamType: StreamType.dash,
    );
    final bool fvpDashDirect = isPlayerEngineRouteAvailable(
      PlayerBackend.fvp,
      PlaybackRoute.direct,
      streamType: StreamType.dash,
    );
    expect(fvpDashProxy, isTrue);
    expect(fvpDashDirect, Platform.isWindows ? isFalse : isTrue);
  });
}
