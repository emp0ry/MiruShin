import 'package:fvp/fvp.dart' as fvp;

/// Register FVP once with MiruShin-friendly native defaults.
///
/// Keep the global defaults moderate. FvpPlayerEngine applies stronger
/// per-source/per-speed cache settings after opening each stream.
void configureMiruShinFvp() {
  fvp.registerWith(
    options: const <String, Object>{
      'fastSeek': false,
      'player': <String, String>{
        'buffer': '3000+180000',
        'demux.buffer.protocols': 'file,http,https',
        'demux.buffer.ranges': '16',
        'avformat.strict': 'experimental',
        'avformat.safe': '0',
        'avformat.extension_picky': '0',
        'avformat.allowed_segment_extensions': 'ALL',
        'avio.reconnect': '1',
        'avio.reconnect_streamed': '1',
        'avio.reconnect_at_eof': '1',
        'avio.reconnect_delay_max': '5',
        'avio.rw_timeout': '15000000',
      },
    },
  );
}
