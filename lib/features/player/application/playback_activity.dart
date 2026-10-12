import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Covers the whole player session, including loading, pause and auto-next.
/// Background replicas must not use the engine's frequently changing position
/// or playing flag to decide when it is safe to resume expensive work.
final playbackActivityProvider = NotifierProvider<PlaybackActivity, bool>(
  PlaybackActivity.new,
);

class PlaybackActivity extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool active) {
    if (ref.mounted && state != active) state = active;
  }
}
