# MiruShin Auth Worker

Cloudflare Worker used by MiruShin for default MyAnimeList and Shikimori OAuth.

The Worker keeps shared OAuth app credentials out of the Flutter repository,
GitHub Actions, and release binaries. It builds provider authorization URLs,
handles token exchange/refresh, and serves the shared callback page at
`https://auth.emp0ry.com/callback`.

## Routes

- `GET /mal/authorize`
- `POST /mal/token`
- `GET /shikimori/authorize`
- `POST /token`
- `GET /callback`

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
