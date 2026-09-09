# Watch with Friends: local-first source resolution

The host remains authoritative for the media, addon, episode, server and
voiceover. Each guest resolves that identity on its own device. Quality is not
part of the shared stream identity and remains device-local.

| Host playback | Matching guest download | Guest addon | Guest result |
| --- | --- | --- | --- |
| Online or offline | Complete file exists | Any | Matching local file |
| Online or offline | Missing or unreadable | Installed | Same stream online |
| Online or offline | Missing or unreadable | Missing | Stay connected and show retryable module error |

Only provider IDs and the canonical Sora selection are shared. File paths,
download IDs, stream URLs and request headers never leave the device. New
downloads use a server-and-voiceover variant key so different voiceovers can
coexist; quality changes reuse the same variant. Existing registry paths stay
unchanged. Metadata-less legacy downloads may match by media, addon and episode
only after no exact stream match is available.
