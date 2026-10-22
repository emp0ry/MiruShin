# Local verification · 23 October 2026

Tested the **production build** at `http://127.0.0.1:4175/` in the available in-app browser. The observations below describe the local production preview; publishing is a separate Git operation.

## Completed

- Visually inspected 1440×900 and 1280×720 desktop, 768×1024 tablet, 390×844 and 320×568 phone, and 844×390 landscape layouts. Inspected the hero, gallery, library, playback features, platform downloads, getting started, FAQ, footer, legal/privacy and 404 pages. No horizontal overflow was observed at these sizes; the document root stays at scroll position 0 while the clipped native content layer scrolls.
- Discovery and Player retain the complete 1400×1310 capture. The viewer label is below the image, so it cannot cover playback controls. All three mobile captures open in a focus-managed viewer. Portrait image content is scrollable to the bottom on a phone.
- Exercised screenshot and platform tabs, arrow/Home keys, image viewer open/close, Escape, mobile menu focus trapping/restoration, source copying, FAQ expansion, same-page anchors, policy contents and cross-page download navigation. Mobile section destinations settled about 92px below the viewport top, accounting for the 68px header and 24px clearance. A direct phone click changed platform without shifting that destination.
- All five OS tabs displayed the correct panel. All nine release assets resolved to official `emp0ry/MiruShin` v2.9.22 URLs with file sizes. Links fall back to the official release page without JavaScript or a usable API result; release payload and missing/malformed asset cases are covered by logic tests. Binary packages were not installed.
- The mathematical mark responds to pointer/keyboard input; successive clicks preserve earlier waves. Reduced-motion mode retains a static pose and removes decorative controls/ambient frames. The no-canvas branch shows the authored SVG. The renderer stops offscreen, including initial fragment/restored lower-page positions, and resumes at the hero. Hidden-document/disposal behavior is covered by lifecycle tests.
- Original privacy/legal wording and dates, source feed, app opener, clean-media bridge, domain, robots and sitemap match their baselines. Local analytics are excluded; the original production GA4 property is retained. Generated HTML, styles/scripts, fonts, images, metadata, CSP hashes and Pages synchronization pass output checks.
- Browser warnings/errors: none in the captured QA tab. No visible missing assets. Buttons use the requested dark material treatment; the repeated bottom CTA is removed.

## Corrections made during review

Removed image cropping and moved the viewer label outside the capture. Fixed mobile copy joining across hidden line breaks. Increased compact OS/copy/contents hit targets to at least 44px. Made long sticky policy contents independently scrollable on short screens. Added explicit scroll-layer visibility checks after observing a delayed intersection update that kept the mark rendering offscreen; added a regression test. Kept generated browser bundles included despite the Flutter repository's general `build/` ignore rule.

## Measured local rendering

These are actual unthrottled localhost observations on the available desktop environment, with a warm browser/cache. They are **not** field Core Web Vitals or physical-phone performance claims.

| Layout | LCP | CLS | Point draw p95 | Render interval median |
| --- | ---: | ---: | ---: | ---: |
| 1440×900, final | 132 ms | 0 | 2.8 ms | 33.3 ms |
| 1280×720, final | 92 ms | 0 | 2.2 ms | 33.3 ms |
| 768×1024 | 96 ms | 0.0055 | 2.6 ms | 33.3 ms |
| 390×844 | 64 ms | 0 | 1.7 ms | 33.3 ms |
| 320×568 | 68 ms | 0 | 1.8 ms | 33.3 ms |
| 844×390 | 80 ms | 0 | 2.2 ms | 33.3 ms |

The mark deliberately renders at 30 fps; its quiet 24-second movement does not need a 60 fps canvas. Timing is sampled by the renderer and reported alongside PerformanceObserver LCP/CLS. Interaction controls updated on the next captured browser state. A portable, numeric INP score was not measured. See `browser-observations.json` for raw observations, including intermediate review states before the offscreen fix.

## Automated checks

`npm test`: **16 passed**. Strict TypeScript/Vite production build: **passed**. `npm run check:output`: **passed**. `git diff --check`: **passed**.

## Evidence and remaining limits

Screenshots: `hero-1440.png`, `hero-1280.png`, `hero-390.png`, `tablet-768.png`, `player-390.png`, `downloads-1440.png`, `fallback-390.png`, `privacy-landscape-844.png`.

Viewport testing was done in the available in-app browser. Physical iPhone Safari dynamic browser chrome, Android hardware, TV browsers, OS-level text enlargement, screen-reader announcements and a broader browser matrix still need device testing. No-JavaScript availability is checked from the production HTML, not a browser with scripting disabled. Reduced motion was exercised with the diagnostic query flag and tested in logic; changing the user's OS preference was unnecessary. Production analytics delivery and social crawler caches were not exercised locally. No upstream design-review bundle or external certification is claimed.

## Final gallery refinement

Discovery, Player and On mobile now use one responsive stage footprint. At 1440px the stage is 671.36px tall in each tab; the desktop screenshot itself is 633px tall plus its viewer label, rather than filling a 976px frame. Captures remain complete and open at full size. The Take a closer look link is retained, and the repeated small 新 is removed from the art signature. The latest upstream AltStore feed update was fast-forwarded before publishing and retained in the build. See gallery-size-observations.json and gallery-player-1440.png for the final layout checks.
