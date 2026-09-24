# Google Drive OAuth configuration

MiruShin uses the private Drive `appDataFolder` scope only:

```text
https://www.googleapis.com/auth/drive.appdata
```

Enable the Google Drive API, then open Google Auth Platform → Data Access and
add that exact scope.

Android/iOS/Web use Google's supported native/browser SDKs directly. Desktop
and Android TV send token/device requests through `auth.emp0ry.com`, which owns
the Google client secrets. No client secret is compiled into MiruShin.

## Platform clients

| Target | Google client type | Flow | Build-time configuration |
| --- | --- | --- | --- |
| Android phone/tablet | Android + Web | Native Google authorization | Android package/SHA in Google Cloud; the Web client id is used as `serverClientId` |
| Android TV | Web | QR authorization-code handoff through Worker + PKCE | No build secret |
| iOS | iOS | Native Google authorization | `GIDClientID` and reversed client-id URL scheme in `ios/Runner/Info.plist` |
| macOS, Windows, Linux | Desktop | System browser + PKCE + loopback; token exchange through Worker | No build secret |
| Web | Web application | Google Identity Services token model | Authorized JavaScript origins in Google Cloud |

OAuth client ids are public identifiers and are present in the application.
Desktop and Web client secrets exist only as encrypted Cloudflare Worker secrets.
PKCE and OAuth `state` protect each desktop authorization attempt, while the
Worker hardcodes the allowed clients, grant types, scope, and callback.

Google's live TV/Limited Input endpoint currently rejects `drive.appdata` with
`invalid_scope` even though Google's documentation still lists it as allowed.
MiruShin therefore uses the Web client for an ephemeral QR handoff on Android
TV. The phone completes consent in a normal browser, `/callback` stores the
one-time code briefly in Worker KV, and only the TV holding the PKCE verifier
can exchange it. Authorization codes are removed after exchange or TTL expiry.

## Cloudflare Worker secrets

Set these in the `mirushin-auth` Worker. Never put them in `wrangler.jsonc`,
Flutter `--dart-define`, GitHub Actions, or source control:

```bash
npx wrangler secret put GOOGLE_DESKTOP_CLIENT_SECRET
npx wrangler secret put GOOGLE_WEB_CLIENT_SECRET
```

The public client ids are `GOOGLE_DESKTOP_CLIENT_ID` and
`GOOGLE_WEB_CLIENT_ID` vars in `mirushin-auth/wrangler.jsonc`.

## Android signing identity

The Android OAuth client must use package name `com.emp0ry.mirushin` and the
certificate fingerprint of the key that signs the distributed APK.

Current release certificate:

```text
SHA-1   67:4C:EC:B6:08:70:37:FC:C2:04:63:92:4D:51:BC:9E:04:A1:32:F5
SHA-256 F0:9A:3E:1D:E4:74:2A:E8:92:F1:D1:5D:06:52:66:EE:98:4C:A7:8F:6D:79:DD:68:1C:43:8C:6B:A9:BF:7F:BB
```

If a separately signed debug APK is used, create another Android OAuth client
for the same package and that debug certificate's SHA-1.

## Web origins

The Web client must list every actual origin (scheme, host, and port) from
which MiruShin is served. At minimum configure the production origin. For local
development, run Flutter on a fixed port and add that exact localhost origin;
Google does not accept a wildcard port.

For the current deployment configure:

```text
Authorized JavaScript origins
https://mirushin.emp0ry.com
http://localhost
http://localhost:7357

Authorized redirect URIs
https://auth.emp0ry.com/callback
```

The redirect URI is used only by the Android TV QR handoff. MiruShin Web still
uses the Google Identity Services popup/token model and does not redirect there.

Origins contain scheme, host, and optional port only: no path and no trailing
slash. Run local Web builds on the matching fixed port:

```bash
flutter run -d chrome --web-hostname localhost --web-port 7357
```

Web uses short-lived access tokens and cannot keep a refresh token in the
browser. When Google can no longer restore authorization silently, MiruShin
marks Drive disconnected and asks the user to connect again. This does not
affect Local Library or tracker synchronization.

## Synced data

Google Drive Sync stores these app-private, cross-platform records:

- canonical anime and manga library operations and tombstones;
- media/provider bindings needed by those library records;
- episode playback position, duration, completion, and watch cycle;
- preferred addon/source, server, voiceover, and quality;
- tracker delivery ledger and the short cross-device delivery lease;
- online addon URL/configuration, enabled state, and order;
- offline addon manifest and JavaScript content, enabled state, and order;
- user-added addon catalog sources and addon/source deletion tombstones.
- saved AniList accounts, with a separate Local Library workspace for every account;
- the MyAnimeList and Shikimori connections assigned to each AniList account;
- AniList, MyAnimeList, and Shikimori access/refresh tokens needed to restore those connections;
- user-provided tracker OAuth client identifiers and the user-provided Shikimori client secret when custom credentials are enabled.

Offline addon absolute paths are never copied. Each receiving platform writes
the embedded files into its own application-support storage. Addon records use
immutable, checksummed Drive segments so repeated sync is idempotent and a
corrupt segment is rejected before it changes the local registry.

Google Drive OAuth access/refresh tokens, MiruShin-operated OAuth client
secrets, source cookies, downloaded video files, and temporary caches remain
device-local. Tracker tokens are synced only after the user enables Google
Drive Sync, inside that user's private `appDataFolder`. General app settings
and the legacy TMDB library are not currently part of Google Drive Sync.

Library segments use a deterministic AniList-account namespace. Switching the
active AniList account therefore switches its Local Library, provider
snapshots, outbox, playback state, and MAL/Shikimori connections without
reading or overwriting another account's records.
