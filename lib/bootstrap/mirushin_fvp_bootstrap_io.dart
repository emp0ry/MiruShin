import 'package:fvp/fvp.dart' as fvp;

/// Register FVP once with MiruShin-friendly defaults.
void configureMiruShinFvp() {
  fvp.registerWith(
    options: const <String, Object>{
      'fastSeek': false,
      'player': <String, String>{
        'buffer': '3000+60000',
        'demux.buffer.ranges': '8',
        'demux.buffer.protocols': 'file,http,https',
      },
    },
  );
}
