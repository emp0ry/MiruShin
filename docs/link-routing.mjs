const WEBSITE_ORIGIN = 'https://mirushin.emp0ry.com';
const MAX_MEDIA_ID = 2147483647;
const MEDIA_PATH = /^\/(anilist|tmdb)\/(anime|manga|movie|tv)\/([1-9]\d*)$/;
const WATCH_PARTY_CODE = /^[A-Z0-9]{6}$/;

function validCombination(provider, type) {
  return (
    (provider === 'anilist' && (type === 'anime' || type === 'manga')) ||
    (provider === 'tmdb' && (type === 'movie' || type === 'tv'))
  );
}

export function parseMediaPath(pathname) {
  if (typeof pathname !== 'string' || pathname.length > 128) return null;
  const match = MEDIA_PATH.exec(pathname);
  if (!match) return null;
  const [, provider, type, rawId] = match;
  if (!validCombination(provider, type)) return null;
  const id = Number(rawId);
  if (!Number.isSafeInteger(id) || id <= 0 || id > MAX_MEDIA_ID) return null;
  return { provider, type, id };
}

export function mediaDeepLink(route) {
  return `mirushin://${route.provider}/${route.type}/${route.id}`;
}

export function canonicalMediaUrl(route) {
  return `${WEBSITE_ORIGIN}/${route.provider}/${route.type}/${route.id}`;
}

export function parseLegacyTarget(raw) {
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > 512) {
    return null;
  }
  let target;
  try {
    target = new URL(raw);
  } catch (_) {
    return null;
  }
  if (
    target.protocol !== 'mirushin:' ||
    target.username ||
    target.password ||
    target.port ||
    target.hash
  ) {
    return null;
  }

  if (!target.search) {
    const route = parseMediaPath(`/${target.hostname}${target.pathname}`);
    if (!route) return null;
    return { kind: 'media', route, target: mediaDeepLink(route) };
  }

  const keys = [...target.searchParams.keys()];
  const codeValues = target.searchParams.getAll('code');
  const code = codeValues[0]?.toUpperCase() ?? '';
  if (
    target.hostname === 'watch-party' &&
    target.pathname === '/join' &&
    keys.length === 1 &&
    keys[0] === 'code' &&
    codeValues.length === 1 &&
    WATCH_PARTY_CODE.test(code)
  ) {
    return {
      kind: 'watch-party',
      code,
      target: `mirushin://watch-party/join?code=${code}`,
    };
  }
  return null;
}

export function parseFunctionMediaQuery(searchParams) {
  const keys = [...searchParams.keys()];
  if (
    keys.length !== 3 ||
    searchParams.getAll('provider').length !== 1 ||
    searchParams.getAll('type').length !== 1 ||
    searchParams.getAll('id').length !== 1
  ) {
    return null;
  }
  return parseMediaPath(
    `/${searchParams.get('provider')}/${searchParams.get('type')}/${searchParams.get('id')}`,
  );
}
