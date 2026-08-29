# MiruShin Watch with Friends relay

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/emp0ry/MiruShin/tree/main/watch-party-relay)

This is the official reference implementation of MiruShin's optional,
self-hosted Watch with Friends relay protocol. It uses a Cloudflare Worker,
one Durable Object per room, WebSockets, and the WebSocket Hibernation API.
One host socket can serve many guests because the Durable Object performs the
fan-out.

> Self-hosted/custom relay servers are operated by third parties. MiruShin
> does not control custom relay servers and cannot guarantee their
> availability, privacy, or security.

## What it does

- Routes playback, episode, logical server/quality, permission, participant,
  and periodic drift-correction events.
- Supports one host and up to 49 guests by default. The limit is configurable.
- Keeps the host authoritative. Guest actions go to the host only after relay
  permission checks; the host publishes the resulting authoritative event.
- Keeps a short-lived authoritative snapshot so a joining guest can sync
  immediately, and gives the host 60 seconds to reconnect by default.
- Supports multiple isolated rooms in one deployment.
- Closes sockets that do not authenticate within 15 seconds.

## What it does not do

- It never proxies, downloads, or serves video or audio.
- It does not resolve streaming-provider URLs.
- It does not receive AniList tokens, OAuth credentials, provider cookies,
  provider login credentials, local files, or MiruShin authentication secrets.
- It is not a MiruShin-operated public service and has no built-in MiruShin
  fallback URL.

The operator can observe room identifiers, participant connections, logical
media/source selections, playback events, permissions, and timestamps. Do not
add raw stream URLs or credentials to protocol extensions.

## Requirements

1. A Cloudflare account with Workers and Durable Objects available.
2. Node.js 20 or newer and npm, unless using the deploy button.

## Deploy

### One click

Use the **Deploy to Cloudflare** button above, authorize Cloudflare, and follow
the deployment prompts. Copy the resulting `https://...workers.dev` URL.

### Wrangler

```sh
cd watch-party-relay
npm install
npx wrangler login
npm test
npm run deploy
```

Wrangler prints the Worker URL after deployment. There are no secrets to
configure and no database to provision: the Durable Object binding and SQLite
class migration are declared in `wrangler.jsonc`.

## Configure MiruShin

1. Open **Settings → Watch with Friends**.
2. Set **Connection Mode** to **Self-hosted Relay**.
3. Paste the Worker URL.
4. Select **Test Connection**. It verifies relay identity, protocol version,
   HTTP reachability, and the WebSocket probe.
5. Save the relay and create a room.

The default P2P Watch with Friends connection remains selected for existing
installs. MiruShin never automatically falls back to a public relay.

## Invites

Relay QR/deep links include the room ID, exact relay URL, and guest join token.
They never include the host token. A guest does not have to configure the relay
manually. Before connecting to an untrusted origin, MiruShin shows the exact
origin and a third-party relay warning. Optional trust is scoped to that exact
scheme, host, and port.

Treat an invite as a bearer secret for that ephemeral room. Send it only to the
people you want in the party.

## Configuration

Edit `vars` in `wrangler.jsonc` before deploying:

| Variable | Default | Meaning |
| --- | ---: | --- |
| `MAX_PARTICIPANTS_PER_ROOM` | 50 | Host plus all guests |
| `MAX_MESSAGE_BYTES` | 65536 | Maximum UTF-8 WebSocket message size |
| `MAX_MESSAGES_PER_MINUTE` | 180 | Per-connection event limit |
| `ROOM_IDLE_TIMEOUT_SECONDS` | 21600 | Inactive-room lifetime (6 hours) |
| `HOST_RECONNECT_TIMEOUT_SECONDS` | 60 | Host reconnect grace period |

Values are bounded in code to prevent accidental unsafe configurations.

## Protocol compatibility

This implementation speaks `mirushin-watch-party` protocol version `1`.

- `GET /health` reports identity and protocol version.
- `GET /capabilities` reports non-sensitive capabilities.
- `GET /probe` verifies a WebSocket upgrade.
- `POST /rooms` creates an ephemeral room and returns `roomId`, `hostToken`,
  and `joinToken`.
- `GET /rooms/{roomId}/connect` upgrades to the room WebSocket. Authentication
  is the first WebSocket message, so tokens are not put in URLs or normal
  access logs.

See [PROTOCOL.md](PROTOCOL.md) for the transport-neutral wire format.

## Updating

```sh
git pull
cd watch-party-relay
npm install
npm test
npm run deploy
```

Run the MiruShin **Test Connection** action after an update. The app refuses an
unsupported protocol version instead of attempting an unsafe partial session.

## Troubleshooting

- **Relay unreachable:** confirm the Worker URL and `/health` in a browser,
  then check `npx wrangler tail`.
- **Not a MiruShin relay:** confirm the URL points to this Worker, not a site or
  dashboard URL.
- **Unsupported protocol:** update either MiruShin or this relay so both use the
  same protocol version.
- **WebSocket unavailable:** check that a reverse proxy/CDN in front of a
  non-Cloudflare implementation allows WebSocket upgrades.
- **Room full:** raise `MAX_PARTICIPANTS_PER_ROOM` and redeploy if the account's
  limits can support it.
- **Host disconnected:** reconnect within `HOST_RECONNECT_TIMEOUT_SECONDS` or
  create a new room. Version 1 intentionally has no host migration.
