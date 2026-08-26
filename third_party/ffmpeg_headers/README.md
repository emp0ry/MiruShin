# FFmpeg public headers

These are the recursive public-header closure needed by MiruShin's seek
thumbnail bridge. They were copied unmodified from the official FFmpeg `n8.0`
tag (`140fd653aed8cad774f991ba083e2d01e86420c7`). The sole generated companion,
`libavutil/avconfig.h`, supplies the target byte-order macro that installed
FFmpeg development packages normally generate during configuration.

The app does not bundle an additional FFmpeg binary. The bridge dynamically
loads the FFmpeg 8 runtime already shipped by the existing `fvp` dependency and
refuses incompatible libavformat/libavcodec major versions. The accompanying
LGPL license is in `COPYING.LGPLv2.1`.
