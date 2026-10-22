# MiruShin website

Product website for **mirushin.emp0ry.com**, using the EMP0RY graphite/Geist/lavender design system. The Flutter application is independent of this build.

Source: `/Users/emp0ry/Projects/Flutter/MiruShin/website`
Local production preview: **http://127.0.0.1:4175/**
GitHub Pages output: `../docs/`

## Run and build

Requires Node.js 24 or newer and npm. From this directory:

```sh
npm ci
npm run dev
npm test
npm run build
npm run check:output
npm run preview
```

Development uses `http://127.0.0.1:5175/`. Preview serves the built files on port 4175. Both bind only to localhost. Dependencies are pinned in `package-lock.json`.

`build` type-checks, creates `dist/`, and synchronizes the managed pages/assets into the existing `docs/` Pages directory. It removes obsolete generated hashes using `pages-files.json`. Commit the generated `docs/site/build/` files with the HTML when publishing. No npm runtime or server is needed by GitHub Pages. `dist/` and `node_modules/` stay ignored.

The build **retains** `docs/source.json`, `open.html`, `CNAME`, `.nojekyll`, `robots.txt`, `sitemap.xml`, existing app icons and legacy screenshot URLs. Release automation can continue updating the source feed independently. The clean `/media/...` bridge in `404.html` is preserved exactly. Do not replace the feed with a copied build artifact. The original published privacy/legal paragraphs and effective date are preserved and checked against `design/` baselines.

## Edit

- `src/index.html`: semantic content, real screenshots and release-page fallback links.
- `src/header.html`, `footer.html`, `dialogs.html`: shared page fragments.
- `src/styles.css`: shared tokens, authored layouts and responsive behavior.
- `src/main.ts`: accessible tabs, dialogs, image viewer and source copying.
- `src/core/mark*`: original deterministic point rendering of 新, a 24-second loop, bounded pointer response and overlapping waves. Rendering is capped at 30 fps and DPR 2, paused outside the scroll viewport and while hidden, and cleaned up on disposal.
- `src/core/releases.ts`: one near-viewport request to the official latest-release API; validated asset destinations, timeout and useful release-page fallbacks.
- `src/privacy.html`, `legal.html`, `404.html`: secondary pages.

See [DESIGN.md](DESIGN.md) for the product specification, [design/EMP0RY.md](design/EMP0RY.md) for the portable brand contract, and [ASSETS.md](ASSETS.md) for provenance/licenses. The website demonstrates its own presentation controls; it does not simulate app playback or installation.

The original GA4 property `G-QY5L70VTTG` runs only on HTTPS `mirushin.emp0ry.com`, excluding local previews. Canonical, Open Graph, Twitter, structured application metadata, CSP and the manifest are included. App icons retain their existing URLs. The new social PNG is generated from `design/social-preview.svg`, with outlined Geist and mathematical point geometry.

Normal builds use the checked-in social PNG. To regenerate it, install Python `fonttools[woff]` and ImageMagick, then run:

```sh
python3 scripts/generate-brand.py
npm run build
```

## Verification

See [verification/REPORT.md](verification/REPORT.md), the recorded browser observations and screenshots. `npm test` covers anchor navigation, release validation, point geometry, successive waves and renderer lifecycle. `check:output` checks static fallbacks, assets, metadata/CSP, policy wording, retained public endpoints and exact Pages output.

For manual failure-state checks, use `/?reduce-motion` for a static mark and `/?no-canvas` for the SVG fallback. These are local diagnostic flags and do not require changing OS settings.

The revision is prepared locally. No MiruShin deployment or remote repository change is performed by this build.
