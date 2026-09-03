import {
  canonicalMediaUrl,
  mediaDeepLink,
} from '../../docs/link-routing.mjs';

const SITE_ORIGIN = 'https://mirushin.emp0ry.com';
const DEFAULT_IMAGE = `${SITE_ORIGIN}/assets/social-preview.png`;
const DEFAULT_DESCRIPTION = 'Open this media directly in MiruShin.';
const MAX_SOURCE_TEXT = 20000;
const MAX_DESCRIPTION = 240;

const ENTITIES = Object.freeze({
  amp: '&',
  apos: "'",
  gt: '>',
  hellip: '…',
  lt: '<',
  mdash: '—',
  nbsp: ' ',
  ndash: '–',
  quot: '"',
});

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function decodeEntities(value) {
  return value.replace(
    /&(#x[0-9a-f]{1,6}|#\d{1,7}|[a-z][a-z0-9]{1,31});/gi,
    (entity, code) => {
      const normalized = code.toLowerCase();
      if (normalized in ENTITIES) return ENTITIES[normalized];
      const numeric = normalized.startsWith('#x')
        ? Number.parseInt(normalized.slice(2), 16)
        : normalized.startsWith('#')
          ? Number.parseInt(normalized.slice(1), 10)
          : Number.NaN;
      if (
        !Number.isInteger(numeric) ||
        numeric <= 0 ||
        numeric > 0x10ffff ||
        (numeric >= 0xd800 && numeric <= 0xdfff)
      ) {
        return ' ';
      }
      return String.fromCodePoint(numeric);
    },
  );
}

export function normalizeDescription(value, limit = MAX_DESCRIPTION) {
  let text = stringValue(value).slice(0, MAX_SOURCE_TEXT);
  text = text.replace(/<\s*br\s*\/?\s*>/gi, ' ');
  text = text.replace(/<\s*\/\s*(p|div|li|h[1-6])\s*>/gi, ' ');
  text = text.replace(/<[^>]*>/g, ' ');
  text = decodeEntities(text)
    .replace(/[\u0000-\u001f\u007f]+/g, ' ')
    .replace(/\s+/gu, ' ')
    .replace(/\s+([,.;:!?])/g, '$1')
    .trim();
  if (text.length === 0 || limit <= 0) return '';

  const characters = Array.from(text);
  if (characters.length <= limit) return text;
  const candidate = characters.slice(0, limit + 1);
  const lastSpace = candidate.lastIndexOf(' ');
  const boundary = lastSpace >= Math.floor(limit * 0.6) ? lastSpace : limit;
  return `${candidate.slice(0, boundary).join('').trimEnd()}…`;
}

export function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function httpsUrl(value) {
  try {
    const url = new URL(stringValue(value));
    return url.protocol === 'https:' && !url.username && !url.password
      ? url.href
      : '';
  } catch (_) {
    return '';
  }
}

function firstText(...values) {
  for (const value of values) {
    const normalized = normalizeDescription(value, 160);
    if (normalized) return normalized;
  }
  return '';
}

function validYear(value) {
  return Number.isInteger(value) && value >= 1000 && value <= 9999
    ? value
    : null;
}

function providerPage(route) {
  if (route.provider === 'anilist') {
    return `https://anilist.co/${route.type}/${route.id}`;
  }
  return `https://www.themoviedb.org/${route.type}/${route.id}`;
}

function readableFormat(value) {
  const normalized = stringValue(value).trim().toUpperCase();
  if (!/^[A-Z][A-Z0-9_]{0,31}$/.test(normalized)) return '';
  return normalized.replaceAll('_', ' ');
}

function schemaTypeForAniList(route, format) {
  if (route.type === 'manga') {
    if (format === 'MANGA') return 'ComicSeries';
    if (format === 'NOVEL' || format === 'ONE_SHOT') return 'Book';
    return 'CreativeWorkSeries';
  }
  if (format === 'MOVIE') return 'Movie';
  if (format === 'TV' || format === 'TV_SHORT') return 'TVSeries';
  return 'CreativeWorkSeries';
}

async function fetchJson(url, options, fetchImpl) {
  const response = await fetchImpl(url, {
    ...options,
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(`Metadata request failed: ${response.status}`);
  return response.json();
}

async function fetchAniList(route, fetchImpl) {
  const query = `
    query MiruShinPreview($id: Int, $type: MediaType) {
      Media(id: $id, type: $type) {
        id
        type
        format
        title { english romaji native }
        description(asHtml: false)
        coverImage { extraLarge large }
        bannerImage
        seasonYear
        startDate { year }
      }
    }
  `;
  const data = await fetchJson(
    'https://graphql.anilist.co',
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        query,
        variables: { id: route.id, type: route.type.toUpperCase() },
      }),
    },
    fetchImpl,
  );
  const media = data?.data?.Media;
  if (
    !media ||
    media.id !== route.id ||
    stringValue(media.type).toLowerCase() !== route.type
  ) {
    return null;
  }
  const title = firstText(
    media.title?.english,
    media.title?.romaji,
    media.title?.native,
  );
  if (!title) return null;
  const format = readableFormat(media.format);
  const posterUrl = httpsUrl(media.coverImage?.extraLarge || media.coverImage?.large);
  const bannerUrl = httpsUrl(media.bannerImage);
  return {
    title,
    description: normalizeDescription(media.description),
    format,
    year: validYear(media.seasonYear) ?? validYear(media.startDate?.year),
    posterUrl,
    socialImageUrl: bannerUrl || posterUrl,
    providerUrl: providerPage(route),
    schemaType: schemaTypeForAniList(route, stringValue(media.format)),
  };
}

function tmdbImage(path, size) {
  const value = stringValue(path);
  if (!/^\/[A-Za-z0-9._-]+$/.test(value)) return '';
  return `https://image.tmdb.org/t/p/${size}${value}`;
}

async function fetchTmdb(route, fetchImpl, tmdbToken) {
  const token = stringValue(tmdbToken).trim();
  if (!token) throw new Error('TMDB_READ_ACCESS_TOKEN is not configured.');
  const data = await fetchJson(
    `https://api.themoviedb.org/3/${route.type}/${route.id}?language=en-US`,
    {
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${token}`,
      },
    },
    fetchImpl,
  );
  if (!data || data.id !== route.id) return null;
  const title = route.type === 'movie'
    ? firstText(data.title, data.original_title)
    : firstText(data.name, data.original_name);
  if (!title) return null;
  const date = route.type === 'movie' ? data.release_date : data.first_air_date;
  const yearMatch = /^(\d{4})-/.exec(stringValue(date));
  return {
    title,
    description: normalizeDescription(data.overview),
    format: route.type === 'movie' ? 'MOVIE' : 'TV SERIES',
    year: validYear(yearMatch ? Number(yearMatch[1]) : null),
    posterUrl: tmdbImage(data.poster_path, 'w780'),
    socialImageUrl:
      tmdbImage(data.backdrop_path, 'w1280') ||
      tmdbImage(data.poster_path, 'w780'),
    providerUrl: providerPage(route),
    schemaType: route.type === 'movie' ? 'Movie' : 'TVSeries',
  };
}

export async function fetchMediaMetadata(
  route,
  { fetchImpl = fetch, tmdbToken = '' } = {},
) {
  return route.provider === 'anilist'
    ? fetchAniList(route, fetchImpl)
    : fetchTmdb(route, fetchImpl, tmdbToken);
}

function jsonLd(route, metadata, canonical, image, description) {
  if (!metadata) {
    return {
      '@context': 'https://schema.org',
      '@type': 'WebPage',
      name: 'Open in MiruShin',
      description,
      url: canonical,
      isPartOf: {
        '@type': 'WebSite',
        name: 'MiruShin',
        url: `${SITE_ORIGIN}/`,
      },
    };
  }
  const data = {
    '@context': 'https://schema.org',
    '@type': metadata.schemaType,
    name: metadata.title,
    description,
    url: canonical,
    image,
    sameAs: metadata.providerUrl,
    identifier: {
      '@type': 'PropertyValue',
      propertyID: route.provider === 'anilist' ? 'AniList' : 'TMDB',
      value: String(route.id),
    },
  };
  if (metadata.year) data.datePublished = String(metadata.year);
  return data;
}

function safeJsonForHtml(value) {
  return JSON.stringify(value).replaceAll('<', '\\u003c');
}

function imageMetadata(image, imageAlt, isDefault) {
  return [
    `<meta property="og:image" content="${escapeHtml(image)}">`,
    `<meta property="og:image:secure_url" content="${escapeHtml(image)}">`,
    isDefault ? '<meta property="og:image:type" content="image/png">' : '',
    isDefault ? '<meta property="og:image:width" content="1200">' : '',
    isDefault ? '<meta property="og:image:height" content="630">' : '',
    `<meta property="og:image:alt" content="${escapeHtml(imageAlt)}">`,
  ].filter(Boolean).join('\n    ');
}

export function renderMediaPage(route, metadata) {
  const canonical = canonicalMediaUrl(route);
  const target = mediaDeepLink(route);
  const title = metadata?.title || 'Open in MiruShin';
  const description = metadata?.description || DEFAULT_DESCRIPTION;
  const image = httpsUrl(metadata?.socialImageUrl) || DEFAULT_IMAGE;
  const poster = httpsUrl(metadata?.posterUrl) || image;
  const posterClass = metadata
    ? 'media-poster'
    : 'media-poster media-poster-fallback';
  const isDefaultImage = image === DEFAULT_IMAGE;
  const imageAlt = metadata ? `${title} artwork` : 'MiruShin social preview';
  const pageTitle = metadata ? `${title} • MiruShin` : 'Open in MiruShin';
  const providerName = route.provider === 'anilist' ? 'AniList' : 'TMDB';
  const typeName = route.type === 'tv'
    ? 'TV'
    : route.type.charAt(0).toUpperCase() + route.type.slice(1);
  const metadataLine = [providerName, metadata?.format || typeName, metadata?.year]
    .filter(Boolean)
    .join(' • ');
  const providerUrl = providerPage(route);
  const structured = jsonLd(route, metadata, canonical, image, description);
  const attribution = route.provider === 'tmdb'
    ? ' This product uses the TMDB API but is not endorsed or certified by TMDB.'
    : '';

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="dark light">
    <meta name="theme-color" content="#120b24">
    <meta name="application-name" content="MiruShin">
    <meta name="description" content="${escapeHtml(description)}">
    <meta name="robots" content="noindex,follow,max-image-preview:large">
    <meta name="referrer" content="strict-origin-when-cross-origin">
    <title>${escapeHtml(pageTitle)}</title>
    <link rel="canonical" href="${escapeHtml(canonical)}">
    <link rel="icon" href="/assets/favicon-32x32.png" type="image/png" sizes="32x32">
    <link rel="icon" href="/assets/logo.ico" sizes="any">
    <link rel="apple-touch-icon" sizes="180x180" href="/assets/apple-touch-icon.png">
    <link rel="stylesheet" href="/media-link.css">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="MiruShin">
    <meta property="og:title" content="${escapeHtml(title)}">
    <meta property="og:description" content="${escapeHtml(description)}">
    <meta property="og:url" content="${escapeHtml(canonical)}">
    ${imageMetadata(image, imageAlt, isDefaultImage)}
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${escapeHtml(title)}">
    <meta name="twitter:description" content="${escapeHtml(description)}">
    <meta name="twitter:image" content="${escapeHtml(image)}">
    <meta name="twitter:image:alt" content="${escapeHtml(imageAlt)}">
    <script type="application/ld+json">${safeJsonForHtml(structured)}</script>
    <script type="module" src="/media-link.mjs"></script>
  </head>
  <body data-mirushin-target="${escapeHtml(target)}">
    <img class="media-backdrop" src="${escapeHtml(image)}" alt="" aria-hidden="true" referrerpolicy="no-referrer">
    <main class="media-shell">
      <article class="media-card">
        <div class="media-poster-wrap">
          <img class="${posterClass}" src="${escapeHtml(poster)}" alt="${escapeHtml(imageAlt)}" referrerpolicy="no-referrer">
        </div>
        <div class="media-copy">
          <div class="media-brand"><img src="/assets/logo.png" alt="" width="32" height="32"> MiruShin</div>
          <p class="media-eyebrow">Open media</p>
          <h1>${escapeHtml(title)}</h1>
          <p class="media-meta">${escapeHtml(metadataLine)}</p>
          <p class="media-description">${escapeHtml(description)}</p>
          <div class="media-actions">
            <a id="open-in-mirushin" class="media-button media-button-primary" href="${escapeHtml(target)}">Open in MiruShin</a>
            <a class="media-button" href="${escapeHtml(providerUrl)}" rel="noreferrer">View on ${providerName}</a>
          </div>
          <p class="media-note">If the app does not open automatically, use the button above.${attribution}</p>
        </div>
      </article>
    </main>
  </body>
</html>`;
}

export function renderProtocolPage(target) {
  const title = 'Join Watch with Friends';
  const description = 'Open this Watch with Friends invitation in MiruShin.';
  return renderSimplePage({ title, description, target });
}

export function renderInvalidPage() {
  return renderSimplePage({
    title: 'Invalid MiruShin link',
    description: 'This link is malformed or uses an unsupported media route.',
  });
}

function renderSimplePage({ title, description, target = '' }) {
  const canonical = `${SITE_ORIGIN}/open.html`;
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="dark light">
    <meta name="theme-color" content="#120b24">
    <meta name="application-name" content="MiruShin">
    <meta name="description" content="${escapeHtml(description)}">
    <meta name="robots" content="noindex,nofollow">
    <meta name="referrer" content="no-referrer">
    <title>${escapeHtml(title)} • MiruShin</title>
    <link rel="canonical" href="${canonical}">
    <link rel="icon" href="/assets/favicon-32x32.png" type="image/png" sizes="32x32">
    <link rel="stylesheet" href="/media-link.css">
    <script type="module" src="/media-link.mjs"></script>
  </head>
  <body${target ? ` data-mirushin-target="${escapeHtml(target)}"` : ''}>
    <main class="media-shell">
      <section class="media-card media-simple-card">
        <div class="media-copy">
          <div class="media-brand"><img src="/assets/logo.png" alt="" width="32" height="32"> MiruShin</div>
          <h1>${escapeHtml(title)}</h1>
          <p class="media-description">${escapeHtml(description)}</p>
          ${target ? `<div class="media-actions"><a id="open-in-mirushin" class="media-button media-button-primary" href="${escapeHtml(target)}">Open in MiruShin</a></div>` : '<div class="media-actions"><a class="media-button media-button-primary" href="/">Back to MiruShin</a></div>'}
        </div>
      </section>
    </main>
  </body>
</html>`;
}
