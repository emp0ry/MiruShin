# MiruShin deep links and share previews

MiruShin has one typed media-link model with two representations:

- canonical public URL: `https://mirushin.emp0ry.com/<provider>/<type>/<id>`
- permanent app URL: `mirushin://<provider>/<type>/<id>`

Supported routes are exactly:

```text
https://mirushin.emp0ry.com/anilist/anime/<positive-id>
https://mirushin.emp0ry.com/anilist/manga/<positive-id>
https://mirushin.emp0ry.com/tmdb/movie/<positive-id>
https://mirushin.emp0ry.com/tmdb/tv/<positive-id>
```

The equivalent `mirushin://` routes remain supported. Incoming public and app
URLs pass through the same length-bounded parser before navigation. Unknown
hosts, non-HTTPS public URLs, unsupported provider/type pairs, non-positive or
out-of-range IDs, credentials, query strings, fragments, duplicate parameters,
and malformed encoding are rejected. A valid provider also selects and saves
the matching catalog before the details page opens.

Media Details copy actions and Discord Rich Presence use the canonical HTTPS
URL. Watch with Friends has different invitation semantics and continues to use
its existing HTTPS opener or relay URL.

## Legacy compatibility

Already-shared query-based media links remain valid:

```text
https://mirushin.emp0ry.com/open.html?target=mirushin%3A%2F%2Fanilist%2Fanime%2F21
```

On the dynamic host, a validated legacy media URL receives a permanent redirect
to its clean canonical URL. The static GitHub Pages bridge performs the same
canonicalization in the browser. The bridge is not an open redirect: it accepts
only the four media routes above or the exact default Watch with Friends room
code route. Arbitrary HTTP, `javascript:`, `data:`, `file:`, nested invite, and
malformed targets are rejected.

Default Watch with Friends invites retain this format:

```text
https://mirushin.emp0ry.com/open.html?target=mirushin%3A%2F%2Fwatch-party%2Fjoin%3Fcode%3DABC123
```

Self-hosted relay rooms still use their relay's canonical HTTPS `/join` URL.
Their bearer invite is not converted to a public media route, logged, or cached.
Older raw `mirushin://` media and Watch with Friends links remain parseable.

## Hosting architecture

At implementation time, GitHub Pages was configured in legacy mode from
`main:/docs`, with `mirushin.emp0ry.com` as its custom domain. GitHub Pages is a
static origin. It cannot fetch arbitrary AniList or TMDB metadata at request
time, and changing `<meta>` tags with browser JavaScript does not create reliable
Discord, Telegram, WhatsApp, Slack, or other crawler previews.

The repository therefore has two deliberately separate layers:

1. `docs/404.html` is a GitHub Pages fallback. It validates clean media paths,
   offers a manual app button, and attempts the matching custom scheme once.
   Its initial response contains only generic MiruShin Open Graph metadata and
   is still an HTTP 404 on GitHub Pages.
2. `netlify/functions/media-preview.mjs` is the workerless dynamic renderer.
   `netlify.toml` serves the existing `docs/` site and rewrites only the four
   supported clean routes to that function. It returns media-specific HTML,
   canonical, Open Graph, Twitter/X Card, and JSON-LD data in the initial HTTP
   response. No Cloudflare Worker is used for this feature.

Moving the custom domain to the included Netlify configuration is required for
arbitrary per-ID social previews. Deploying only `docs/` to GitHub Pages gives
clean app links plus the generic fallback, not real per-media crawler metadata.

### Deployment

1. Create a Netlify site linked to this repository's `main` branch. The checked
   in `netlify.toml` selects `docs` as the publish directory and
   `netlify/functions` as the functions directory.
2. Add `TMDB_READ_ACCESS_TOKEN` as a Netlify runtime environment variable. Use
   a TMDB v4 Read Access Token. It is read only inside the function and never
   appears in returned HTML or browser JavaScript.
3. Attach `mirushin.emp0ry.com` to that site and apply the DNS records Netlify
   provides. After Netlify HTTPS and the well-known association files work on
   the custom domain, disable the old GitHub Pages custom-domain deployment to
   avoid two services competing for the same host.
4. Verify the initial response with `curl` or a social-card debugger. Viewing
   tags added later in browser developer tools is not sufficient.

Example checks:

```bash
curl -i https://mirushin.emp0ry.com/anilist/anime/21
curl -i https://mirushin.emp0ry.com/tmdb/movie/550
curl -i https://mirushin.emp0ry.com/.well-known/assetlinks.json
curl -i https://mirushin.emp0ry.com/.well-known/apple-app-site-association
```

The dynamic pages intentionally use `noindex,follow`; arbitrary media IDs are
not added to the sitemap.

## Metadata policy

AniList uses its public GraphQL endpoint without a secret and requests only the
ID, type, format, deterministic titles, plain description, large cover, banner,
and year. Public titles prefer English, then romaji, then native. A landscape
banner is preferred for social cards, while the extra-large cover is preferred
on the landing page.

TMDB uses its v3 details endpoint in deterministic `en-US`. The Netlify-only
token is sent as a Bearer credential. The renderer uses a `w1280` backdrop for
the social card when present and a `w780` poster for the landing page. No TMDB
token is present in the Flutter sharing URL, static website, or returned HTML.

Descriptions are bounded before processing, stripped of HTML, decoded from
HTML entities, normalized to plain whitespace, shortened on a word boundary,
and escaped separately for HTML attributes, text, and JSON-LD. Remote images
must use HTTPS. Unknown image dimensions are omitted; only MiruShin's known
1200×630 fallback declares width and height.

If either provider is unavailable, the renderer still returns a usable page and
the exact validated app link with MiruShin's generic image and description.
Metadata and protocol opening are independent.

Successful media HTML is cached in Netlify's durable CDN for six hours and may
be served stale for seven days while it revalidates. A metadata-failure fallback
is cached for five minutes and may be served stale for one hour, allowing a fast
recovery. Browser caching is limited to five minutes. Watch with Friends and
invalid legacy responses use `no-store`.

## App Links and Universal Links

The custom `mirushin://` scheme remains registered on every supported platform.
Windows repairs its per-user protocol registration, Linux packages register an
`x-scheme-handler`, and Apple platforms declare the scheme in `Info.plist`.

Android additionally declares verified HTTPS routes. The served
`.well-known/assetlinks.json` uses package `com.emp0ry.mirushin` and the SHA-256
certificate fingerprint extracted from the signed v2.7.8 release APK. If the
Android signing certificate changes, update the file before publishing that
build.

iOS includes the Associated Domains entitlement for
`applinks:mirushin.emp0ry.com`. The AASA file uses the existing application ID
`G4654PAVR5.com.emp0ry.mirushin` and limits handling to the four media route
prefixes. Ensure the Associated Domains capability is enabled for that App ID
in the Apple Developer account and included in the distribution provisioning
profile. macOS retains the custom scheme because the current desktop signing
configuration does not provide enough evidence to promise a verified universal
link association.

The association files must be available over HTTPS without redirects and with
an `application/json` content type. `netlify.toml` sets that content type. OS
activation still needs testing on signed physical Android and iOS builds.

## Local verification

Run the URL/parser, widget, and server-renderer tests with:

```bash
flutter test test/mirushin_deep_link_test.dart test/mirushin_deep_link_queue_test.dart test/widget_test.dart
node --test netlify/test/media-preview.test.mjs
```
