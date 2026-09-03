import assert from 'node:assert/strict';
import test from 'node:test';

import {
  canonicalMediaUrl,
  mediaDeepLink,
  parseFunctionMediaQuery,
  parseLegacyTarget,
  parseMediaPath,
} from '../../docs/link-routing.mjs';
import handler from '../functions/media-preview.mjs';
import {
  fetchMediaMetadata,
  normalizeDescription,
  renderMediaPage,
} from '../shared/media-preview-core.mjs';

const routes = [
  ['anilist', 'anime', 21],
  ['anilist', 'manga', 30013],
  ['tmdb', 'movie', 550],
  ['tmdb', 'tv', 1399],
];

test('canonical media routes encode and parse all supported combinations', () => {
  for (const [provider, type, id] of routes) {
    const route = { provider, type, id };
    assert.deepEqual(parseMediaPath(`/${provider}/${type}/${id}`), route);
    assert.equal(
      canonicalMediaUrl(route),
      `https://mirushin.emp0ry.com/${provider}/${type}/${id}`,
    );
    assert.equal(mediaDeepLink(route), `mirushin://${provider}/${type}/${id}`);
  }
});

test('route parsing rejects malformed, ambiguous, and unsupported inputs', () => {
  for (const path of [
    '/anilist/anime/not-a-number',
    '/anilist/movie/21',
    '/tmdb/anime/21',
    '/tmdb/movie/-1',
    '/tmdb/movie/0',
    '/tmdb/movie/2147483648',
    '/tmdb/movie/21/extra',
    '/tmdb/movie/21?next=evil',
    '//evil.example/tmdb/movie/21',
  ]) {
    assert.equal(parseMediaPath(path), null, path);
  }
  assert.equal(
    parseFunctionMediaQuery(
      new URLSearchParams('provider=tmdb&type=movie&id=21&next=evil'),
    ),
    null,
  );
  assert.equal(
    parseFunctionMediaQuery(
      new URLSearchParams('provider=tmdb&type=movie&id=21&id=22'),
    ),
    null,
  );
});

test('legacy opener accepts only exact MiruShin media and room-code targets', () => {
  const media = parseLegacyTarget('mirushin://anilist/anime/21');
  assert.equal(media?.kind, 'media');
  assert.deepEqual(media?.route, { provider: 'anilist', type: 'anime', id: 21 });

  const party = parseLegacyTarget('mirushin://watch-party/join?code=abc123');
  assert.deepEqual(party, {
    kind: 'watch-party',
    code: 'ABC123',
    target: 'mirushin://watch-party/join?code=ABC123',
  });

  for (const target of [
    'https://evil.example/anilist/anime/21',
    'javascript:alert(1)',
    'data:text/html,hello',
    'mirushin://tmdb/movie/21?next=https://evil.example',
    'mirushin://watch-party/join?code=ABC123&code=DEF456',
    'mirushin://watch-party/join?invite=https://evil.example',
    'mirushin://../../etc/passwd',
  ]) {
    assert.equal(parseLegacyTarget(target), null, target);
  }
});

test('description normalization removes markup, decodes entities, and truncates safely', () => {
  assert.equal(
    normalizeDescription('  Hello<br><i>world</i> &amp; &#x1F30D;\n\n again  '),
    'Hello world & 🌍 again',
  );
  const long = `${'🙂 '.repeat(130)}final-word`;
  const normalized = normalizeDescription(long, 80);
  assert.ok(normalized.endsWith('…'));
  assert.ok(Array.from(normalized).length <= 81);
  assert.ok(!normalized.includes('\ufffd'));
});

test('AniList metadata uses deterministic titles, plain descriptions, and landscape art', async () => {
  let requestBody;
  const metadata = await fetchMediaMetadata(
    { provider: 'anilist', type: 'anime', id: 21 },
    {
      fetchImpl: async (url, options) => {
        assert.equal(url, 'https://graphql.anilist.co');
        requestBody = JSON.parse(options.body);
        return new Response(
          JSON.stringify({
            data: {
              Media: {
                id: 21,
                type: 'ANIME',
                format: 'TV',
                title: {
                  english: 'One Piece',
                  romaji: 'ONE PIECE',
                  native: 'ワンピース',
                },
                description: 'Gol D. Roger<br>was the <b>Pirate King</b>.',
                coverImage: { extraLarge: 'https://img.anili.st/media/21' },
                bannerImage: 'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21.jpg',
                seasonYear: 1999,
                startDate: { year: 1999 },
              },
            },
          }),
          { status: 200 },
        );
      },
    },
  );
  assert.deepEqual(requestBody.variables, { id: 21, type: 'ANIME' });
  assert.equal(metadata.title, 'One Piece');
  assert.equal(metadata.description, 'Gol D. Roger was the Pirate King.');
  assert.equal(
    metadata.socialImageUrl,
    'https://s4.anilist.co/file/anilistcdn/media/anime/banner/21.jpg',
  );
  assert.equal(metadata.posterUrl, 'https://img.anili.st/media/21');
  assert.equal(metadata.schemaType, 'TVSeries');
});

test('TMDB metadata keeps its credential server-side and selects official CDN sizes', async () => {
  const metadata = await fetchMediaMetadata(
    { provider: 'tmdb', type: 'movie', id: 550 },
    {
      tmdbToken: 'server-only-token',
      fetchImpl: async (url, options) => {
        assert.equal(
          url,
          'https://api.themoviedb.org/3/movie/550?language=en-US',
        );
        assert.equal(options.headers.Authorization, 'Bearer server-only-token');
        return new Response(
          JSON.stringify({
            id: 550,
            title: 'Fight Club',
            overview: 'An insomniac office worker forms an underground club.',
            poster_path: '/poster.jpg',
            backdrop_path: '/backdrop.jpg',
            release_date: '1999-10-15',
          }),
          { status: 200 },
        );
      },
    },
  );
  assert.equal(metadata.posterUrl, 'https://image.tmdb.org/t/p/w780/poster.jpg');
  assert.equal(
    metadata.socialImageUrl,
    'https://image.tmdb.org/t/p/w1280/backdrop.jpg',
  );
  assert.equal(metadata.year, 1999);
  assert.equal(metadata.schemaType, 'Movie');
});

test('rendered response contains crawler metadata in the initial HTML and escapes values', () => {
  const html = renderMediaPage(
    { provider: 'anilist', type: 'anime', id: 21 },
    {
      title: 'A "Title" <unsafe>',
      description: 'Text & more',
      format: 'TV',
      year: 2025,
      posterUrl: 'https://example.com/poster.jpg',
      socialImageUrl: 'https://example.com/banner.jpg',
      schemaType: 'TVSeries',
    },
  );
  assert.match(html, /<link rel="canonical" href="https:\/\/mirushin\.emp0ry\.com\/anilist\/anime\/21">/);
  assert.match(html, /<meta property="og:url" content="https:\/\/mirushin\.emp0ry\.com\/anilist\/anime\/21">/);
  assert.match(html, /<meta property="og:title" content="A &quot;Title&quot; &lt;unsafe&gt;">/);
  assert.match(html, /<meta name="twitter:card" content="summary_large_image">/);
  assert.match(html, /<script type="application\/ld\+json">/);
  assert.ok(!html.includes('<unsafe>'));
  assert.ok(html.includes('mirushin://anilist/anime/21'));
});

test('function redirects legacy media and rejects arbitrary redirect targets', async () => {
  const legacy = await handler(
    new Request(
      'https://example.net/.netlify/functions/media-preview?legacy=1&target=mirushin%3A%2F%2Ftmdb%2Fmovie%2F550',
    ),
  );
  assert.equal(legacy.status, 308);
  assert.equal(
    legacy.headers.get('location'),
    'https://mirushin.emp0ry.com/tmdb/movie/550',
  );

  const malicious = await handler(
    new Request(
      'https://example.net/.netlify/functions/media-preview?legacy=1&target=https%3A%2F%2Fevil.example',
    ),
  );
  assert.equal(malicious.status, 400);
  assert.equal(malicious.headers.get('cache-control'), 'no-store');
});

test('function returns a usable fallback when metadata retrieval fails', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => {
    throw new Error('offline');
  };
  try {
    const response = await handler(
      new Request(
        'https://example.net/.netlify/functions/media-preview?provider=anilist&type=manga&id=30013',
      ),
    );
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.match(html, /Open this media directly in MiruShin\./);
    assert.match(html, /mirushin:\/\/anilist\/manga\/30013/);
    assert.match(html, /assets\/social-preview\.png/);
    const csp = response.headers.get('content-security-policy');
    assert.ok(!csp.includes('unsafe-inline'));
    assert.match(csp, /sha256-/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
