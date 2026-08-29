# MiruShin Watch Party Relay Protocol v1

The protocol is transport-neutral compact JSON over WebSockets. Cloudflare is
only the reference host; compatible Node.js, Bun, Deno, Go, Rust, and other
servers may implement the same HTTP and WebSocket contract.

Every WebSocket message has this envelope:

```json
{"v":1,"type":"event","data":{}}
```

Unknown versions must be rejected with `protocol_mismatch`. Unknown or invalid
message shapes must not be routed.

## Room creation and credentials

`POST /rooms` accepts:

```json
{"protocol":"mirushin-watch-party","version":1}
```

It returns a random room ID plus independent cryptographically random host and
join tokens. A compliant server stores token hashes, does not log secrets, and
never places tokens in WebSocket URLs. The host token is never included in an
invite.

The client connects to `/rooms/{roomId}/connect`, then immediately sends:

```json
{
  "v": 1,
  "type": "authenticate",
  "data": {
    "role": "guest",
    "token": "invite join token",
    "sessionId": "stable random session id for this connection"
  }
}
```

The same session ID replaces a stale socket on reconnect and retains its
participant ID. There is exactly one authoritative host.

## Relay messages

- `welcome`: own participant ID and the current participant list.
- `participantJoined`, `participantLeft`, `participantUpdated`, `participants`:
  room membership changes.
- `hostDisconnected`, `hostReconnected`, `roomClosed`: deterministic host
  lifecycle without host election.
- `event`: an existing MiruShin `WatchPartyEvent` plus a sender ID. A host may
  optionally target a snapshot to one participant.
- `error`: stable `code`, user-safe `message`, and optional `fatal` flag.

Host playback events are broadcast to all guests. Guest control requests are
sent only to the host. The relay checks the latest host permissions, then the
host independently validates the request and broadcasts the canonical result.

## Synchronized data

Version 1 carries play, pause, seek, speed, episode/source changes, logical
server/voiceover/quality identifiers, permissions, snapshots, and periodic
position correction. A host sends immediate events for state changes and one
periodic correction approximately every ten seconds.

Raw video/audio bytes are never relayed. Clients resolve and stream content
directly. Provider credentials, cookies, OAuth tokens, local files, and raw
tokenized stream URLs are outside this protocol.

## Errors

Stable error codes include `room_not_found`, `room_full`,
`authentication_failed`, `permission_denied`, `host_unavailable`,
`invalid_message`, `rate_limited`, and `protocol_mismatch`.

Servers must enforce message-size, event-rate, participant, role, room, token,
payload-shape, and protocol-version checks. Events must never cross room
boundaries.
