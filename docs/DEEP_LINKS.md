# MiruShin deep-link contract

`mirushin://` is MiruShin's permanent application URL scheme. Incoming links
are parsed by one typed, length-bounded application service before navigation.
Unknown routes, unsupported provider/type pairs, non-positive IDs, duplicate
query parameters, extra parameters, and malformed encoding are ignored.

## Media

The public media routes are:

```text
mirushin://anilist/anime/<positive-id>
mirushin://anilist/manga/<positive-id>
mirushin://tmdb/movie/<positive-id>
mirushin://tmdb/tv/<positive-id>
```

The provider in the link selects the repository used for that details request.
It does not read or change the user's saved catalog preference.

Discord Rich Presence uses an HTTPS URL because Discord activity URLs are web
links. `https://mirushin.emp0ry.com/open.html?target=...` validates one of the
four canonical media links above and opens that exact in-app target. It never
silently substitutes an AniList or TMDB website/search URL.

## Watch with Friends

The original default connection remains P2P signaling/WebRTC and retains its
existing invite:

```text
mirushin://watch-party/join?code=ABC123
```

Self-hosted relay rooms generate only an HTTPS bearer invite on the configured
relay, preserving any configured base path:

```text
https://relay.example[/base]/join?room=<room-id>&token=<guest-join-token>
```

The relay's self-contained landing page opens the app through the internal
bridge below. The bridge is accepted as input but is not the shared invite:

```text
mirushin://watch-party/join?invite=<percent-encoded-canonical-https-invite>
```

New relay invites contain no `relay`, `transport`, or host-token parameter.
Legacy `mirushin:///watch-party/join?...transport=relay...` links remain
readable for compatibility. A guest token is a short-lived bearer secret and
must not be logged, cached, or placed in a referrer.

## Platform activation

- Android and iOS/macOS register the custom scheme in their application
  manifests. Flutter's competing iOS/Android handler is disabled so the
  centralized `app_links` listener receives each activation once.
- Windows repairs the exact per-user `HKCU\Software\Classes\mirushin`
  registration on every manual launch. A second launch forwards the link to the
  matching running executable and foregrounds its window.
- Linux desktop entries declare `x-scheme-handler/mirushin` and pass one URI
  with `%u`. The GTK application forwards later command lines to the running
  instance. `.deb` and integrated AppImage packages use the packaged desktop
  entry; portable tar archives include `install-url-handler.sh`.

Cold activations are queued until the router's first frame without a timer.
Warm activations use the same queue and dispatcher. Immediate duplicate
platform emissions are suppressed for two seconds.
