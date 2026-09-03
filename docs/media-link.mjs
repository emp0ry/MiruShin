import {
  canonicalMediaUrl,
  mediaDeepLink,
  parseLegacyTarget,
  parseMediaPath,
} from './link-routing.mjs';

const body = document.body;
const fallback = body.hasAttribute('data-static-media-fallback');
const route =
  fallback && !location.search && !location.hash
    ? parseMediaPath(location.pathname)
    : null;
const target = body.dataset.mirushinTarget || (route && mediaDeepLink(route));

if (route && fallback) {
  document.getElementById('not-found')?.setAttribute('hidden', '');
  const landing = document.getElementById('media-link-fallback');
  landing?.removeAttribute('hidden');
  const canonical = canonicalMediaUrl(route);
  const canonicalLink = document.querySelector('link[rel="canonical"]');
  canonicalLink?.setAttribute('href', canonical);
}

if (target) {
  const parsed = parseLegacyTarget(target);
  if (parsed) {
    const button = document.getElementById('open-in-mirushin');
    button?.setAttribute('href', target);
    let shouldAttempt = true;
    try {
      const key = `mirushin-opened:${target}`;
      shouldAttempt = sessionStorage.getItem(key) !== '1';
      if (shouldAttempt) sessionStorage.setItem(key, '1');
    } catch (_) {
      // Storage can be blocked; the in-page guard still prevents repeats.
    }
    if (shouldAttempt) {
      setTimeout(() => {
        location.href = target;
      }, 120);
    }
  }
}
