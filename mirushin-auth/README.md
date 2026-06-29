# MiruShin Auth Worker

Cloudflare Worker used by MiruShin for default MyAnimeList and Shikimori OAuth.

The Worker keeps shared OAuth app credentials out of the Flutter repository,
GitHub Actions, and release binaries. It builds provider authorization URLs,
handles token exchange/refresh, and serves the shared Shikimori callback page at
`https://auth.emp0ry.com/callback`.

## Routes

- `GET /mal/authorize`
- `POST /mal/token`
- `GET /shikimori/authorize`
- `POST /token`
- `GET /callback`

### Watch with Friends signaling

Temporary WebRTC pairing for the "Watch with Friends" feature. The Worker only
brokers the room offer and answer stored in KV with a short TTL. Video, stream
URLs, playback events, and permissions do **not** flow through the Worker after
pairing; they travel over the peer-to-peer WebRTC data channel.

- `POST /watch-party/rooms` — create a room from the host offer → `{ code }`
- `GET /watch-party/rooms/:code` — fetch the host offer
- `POST /watch-party/rooms/:code/answer` — guest stores its answer
- `GET /watch-party/rooms/:code/answer?wait=1` — host waits for the answer
  (returns 204 if nobody joins before the long-poll timeout)
- `DELETE /watch-party/rooms/:code` — legacy cleanup route; current clients let
  rooms expire by TTL

The app uses non-trickle ICE: each device waits briefly for STUN candidates to be
embedded in SDP, then sends only the offer and answer. Legacy trickle candidate
routes are blocked by the edge-security rules before they reach the Worker on
the live domain.

## App proof / 401 guard

All routes except `OPTIONS` and `GET /callback` require a lightweight MiruShin
app proof. Requests without it return `401 Unauthorized` before KV access or
OAuth upstream calls.

- Native/API calls send `x-mirushin-timestamp` and `x-mirushin-signature`
  headers.
- Browser authorization redirects send the same proof as `ms_ts` and `ms_sig`
  query parameters.
- The signature is `HMAC-SHA256(secret, unix_timestamp_seconds)` and is valid
  for five minutes.

This is only a speed bump against generic scripts because the bundled app must
know the proof secret. It does **not** stop Worker invocation quota usage by
itself. Worker-quota protection comes from the Cloudflare edge rules below,
which run before the Worker.

The Worker has a built-in default proof secret matching the Flutter app. If you
override it with a Cloudflare secret, the app constant must be changed at the
same time:

```bash
npx wrangler secret put APP_PROOF_SECRET
```

## Edge security rules

Apply Cloudflare WAF/rate-limit rules in front of the Worker so bad traffic is
blocked before it counts as a Worker invocation.

The script in `scripts/apply-edge-security.mjs` upserts only rules whose `ref`
starts with `mirushin_auth_`; unrelated Cloudflare rules are preserved.

It installs:

- a WAF block for unknown `auth.emp0ry.com` paths/methods;
- a WAF block for legacy `/watch-party/rooms/:code/candidates` trickle routes;
- a WAF block for API/signaling calls missing `x-mirushin-timestamp` or
  `x-mirushin-signature`;
- a WAF block for browser OAuth authorize redirects missing `ms_ts` or `ms_sig`;
- one per-IP rate limit over the auth Worker routes.

Create a Cloudflare API token with these zone permissions:

- Zone Rulesets: Edit
- Zone WAF: Edit
- Zone: Read

Preview the exact rules:

```bash
npm run security:plan
```

Apply them:

```bash
CLOUDFLARE_API_TOKEN=... \
CLOUDFLARE_ZONE_ID=... \
npm run security:apply
```

Optional tuning:

```bash
AUTH_WORKER_HOST=auth.emp0ry.com
AUTH_RATE_LIMIT_REQUESTS=30
AUTH_RATE_LIMIT_PERIOD=10
AUTH_RATE_LIMIT_MITIGATION=10
```

The defaults allow 30 matching requests per IP per 10 seconds, then block for 10
seconds. Free Cloudflare zones may only allow a 10-second mitigation timeout, so
the script uses 10 seconds by default. If normal watch-party pairing ever trips
it, raise `AUTH_RATE_LIMIT_REQUESTS` to 50. If abuse continues, lower it to 15.

Watch-party pairing intentionally uses non-trickle ICE: each device waits briefly
for STUN candidates to be embedded in SDP, then the app sends only the room
offer and answer. Normal successful pairing is roughly:

1. Host `POST /watch-party/rooms`
2. Guest `GET /watch-party/rooms/:code`
3. Guest `POST /watch-party/rooms/:code/answer`
4. Host `GET /watch-party/rooms/:code/answer?wait=1`

Rooms self-expire through KV TTL, so clients do not need to send cleanup DELETEs
after a successful pair.

## Shikimori callback

Shikimori registers a single redirect URL, so both mobile and desktop redirect
to `GET /callback`.

- **Mobile**: the in-app WebView intercepts the redirect and reads the `code`
  before the page loads.
- **Desktop**: the callback page forwards the browser to the app's local
  listener at `http://localhost:28374/?code=…&state=…`, so the code is captured
  automatically (the same experience as MAL/AniList). The page still shows the
  code in a read-only box as a manual-copy fallback.

The redirect URL registered with Shikimori never changes, desktop just adds one
client-side hop from the callback page to localhost. If you change the desktop
port, update `SHIKIMORI_DESKTOP_CALLBACK` in `src/index.ts` and
`AppConstants.shikimoriDesktopCallbackPort` in the Flutter app together.

## Cloudflare Secrets

Set these with `wrangler secret put`; do not add them to `wrangler.jsonc`.

```bash
npx wrangler secret put SHIKIMORI_CLIENT_ID
npx wrangler secret put SHIKIMORI_CLIENT_SECRET
npx wrangler secret put MAL_CLIENT_ID_DESKTOP
npx wrangler secret put MAL_CLIENT_ID_MOBILE
```

If your MAL apps have client secrets, set those too:

```bash
npx wrangler secret put MAL_CLIENT_SECRET_DESKTOP
npx wrangler secret put MAL_CLIENT_SECRET_MOBILE
```

## Plain Vars

`wrangler.jsonc` intentionally keeps only non-secret configuration:

```jsonc
"vars": {
  "SHIKIMORI_REDIRECT_URI": "https://auth.emp0ry.com/callback",
  "SHIKIMORI_USER_AGENT": "MiruShin"
}
```

## KV namespace (watch-party)

The watch-party routes need a KV namespace bound as `WATCH_PARTY`. Create it once
and paste the returned id into `wrangler.jsonc` (replacing the placeholder):

```bash
npx wrangler kv namespace create WATCH_PARTY
```

```jsonc
"kv_namespaces": [{ "binding": "WATCH_PARTY", "id": "<paste-id-here>" }]
```

## Provider Redirects

Configure OAuth apps with these redirect URLs:

- Shikimori: `https://auth.emp0ry.com/callback`
- MAL desktop app: `http://localhost:28373/token`
- MAL mobile app: `app://mirushin/auth`

## Commands

```bash
npm install
npm test
npm run deploy
```

If you run `npm run cf-typegen`, review `worker-configuration.d.ts` before
committing. It should contain binding names and types only, not literal OAuth
client ids or secrets.
