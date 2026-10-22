# Asset provenance

The rebuild uses existing MiruShin materials and original procedural artwork. No stock illustration, downloaded mock app UI or AI raster image is used.

| Website asset | Source and treatment |
| --- | --- |
| `src/public/site/media/board.webp` | Existing `docs/assets/imgs/board.png`, 1888×1768 → 1400×1310 WebP. Full screenshot, uncropped. |
| `src/public/site/media/player.webp` | Existing `docs/assets/imgs/player.png`, 1888×1768 → 1400×1310 WebP. Full screenshot, uncropped. |
| `src/public/site/media/mobile-board.webp` | Existing `docs/assets/imgs/mobile_tmdb.png`, 1320×2868 → 660×1434 WebP. |
| `src/public/site/media/mobile-detail.webp` | Existing `docs/assets/imgs/mobile_detail.png`, 1320×2868 → 660×1434 WebP. |
| `src/public/site/media/mobile-player.webp` | Existing `docs/assets/imgs/mobile_player.png`, 1320×2868 → 660×1434 WebP. |
| `src/public/site/fonts/Geist.woff2` | Self-hosted Geist variable font from the local EMP0RY homepage assets. Copyright 2024 The Geist Project Authors; SIL OFL 1.1, retained in `fonts/OFL.txt`. Upstream: https://github.com/vercel/geist-font. |
| `mark.svg`, `icon.svg`, `src/core/mark-shape.ts` | Existing authored 新 contours from the EMP0RY homepage, adapted to MiruShin. Point sampling, looping relief, pointer response and overlapping waves are code-native artwork. |
| `design/social-preview.svg`, `../docs/assets/social-preview.png` | Original composition using outlined Geist and deterministic mathematical point samples. Converted to a 1200×630 PNG. |
| Library connection diagram | Original inline SVG illustration; service names describe the app's existing integrations. |
| Retained PNG/ICO app icons | Original MiruShin assets, including the existing manifest icon URLs. |

The source repository is https://github.com/emp0ry/MiruShin, baseline `55e644d8d9e3e71f4fd5adb65230447a1c5fe267`. MiruShin source is licensed under the repository's GPL-3.0 license. Existing app screenshots contain third-party film/anime artwork and service names; those retain their respective owners' rights. They are shown in the context of the actual application, not offered as independently licensed artwork.

Geist's font license is separate from the application license. Brand names remain their owners' trademarks. No affiliation or endorsement by catalog providers, Google, Apple or platform vendors is claimed.
