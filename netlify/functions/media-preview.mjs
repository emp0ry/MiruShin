import { createHash } from 'node:crypto';

import {
  canonicalMediaUrl,
  parseFunctionMediaQuery,
  parseLegacyTarget,
} from '../../docs/link-routing.mjs';
import {
  fetchMediaMetadata,
  renderInvalidPage,
  renderMediaPage,
  renderProtocolPage,
} from '../shared/media-preview-core.mjs';

const BASE_SECURITY_HEADERS = Object.freeze({
  'Content-Type': 'text/html; charset=utf-8',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
});

function securityHeaders(body = '') {
  const jsonLd = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/.exec(
    body,
  )?.[1];
  const scriptSources = ["'self'"];
  if (jsonLd) {
    const digest = createHash('sha256').update(jsonLd).digest('base64');
    scriptSources.push(`'sha256-${digest}'`);
  }
  return {
    ...BASE_SECURITY_HEADERS,
    'Content-Security-Policy':
      "default-src 'none'; base-uri 'none'; connect-src 'none'; font-src 'self'; form-action 'none'; frame-ancestors 'none'; img-src 'self' https:; " +
      `script-src ${scriptSources.join(' ')}; style-src 'self'`,
  };
}

function htmlResponse(body, { status = 200, cache = 'fallback', method = 'GET' } = {}) {
  const cacheHeaders = cache === 'media'
    ? {
        'Cache-Control': 'public, max-age=300',
        'Netlify-CDN-Cache-Control':
          'public, durable, max-age=21600, stale-while-revalidate=604800',
      }
    : cache === 'fallback'
      ? {
          'Cache-Control': 'public, max-age=60',
          'Netlify-CDN-Cache-Control':
            'public, durable, max-age=300, stale-while-revalidate=3600',
        }
      : { 'Cache-Control': 'no-store' };
  return new Response(method === 'HEAD' ? null : body, {
    status,
    headers: { ...securityHeaders(body), ...cacheHeaders },
  });
}

function exactLegacyQuery(searchParams) {
  return (
    [...searchParams.keys()].length === 2 &&
    searchParams.getAll('legacy').length === 1 &&
    searchParams.get('legacy') === '1' &&
    searchParams.getAll('target').length === 1
  );
}

export default async function handler(request) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response(null, {
      status: 405,
      headers: {
        Allow: 'GET, HEAD',
        ...securityHeaders(),
        'Cache-Control': 'no-store',
      },
    });
  }
  const url = new URL(request.url);

  if (url.searchParams.has('legacy')) {
    if (!exactLegacyQuery(url.searchParams)) {
      return htmlResponse(renderInvalidPage(), {
        status: 400,
        cache: 'none',
        method: request.method,
      });
    }
    const parsed = parseLegacyTarget(url.searchParams.get('target'));
    if (!parsed) {
      return htmlResponse(renderInvalidPage(), {
        status: 400,
        cache: 'none',
        method: request.method,
      });
    }
    if (parsed.kind === 'media') {
      return new Response(null, {
        status: 308,
        headers: {
          Location: canonicalMediaUrl(parsed.route),
          'Cache-Control': 'public, max-age=86400',
          'Referrer-Policy': 'no-referrer',
          'X-Content-Type-Options': 'nosniff',
        },
      });
    }
    return htmlResponse(renderProtocolPage(parsed.target), {
      cache: 'none',
      method: request.method,
    });
  }

  const route = parseFunctionMediaQuery(url.searchParams);
  if (!route) {
    return htmlResponse(renderInvalidPage(), {
      status: 404,
      cache: 'none',
      method: request.method,
    });
  }

  let metadata = null;
  try {
    metadata = await fetchMediaMetadata(route, {
      tmdbToken: process.env.TMDB_READ_ACCESS_TOKEN,
    });
  } catch (_) {
    // Metadata failure must never prevent the validated app link from working.
  }
  return htmlResponse(renderMediaPage(route, metadata), {
    cache: metadata ? 'media' : 'fallback',
    method: request.method,
  });
}
