import { handleWatchParty } from './watch-party';

interface Env {
	SHIKIMORI_CLIENT_ID: string;
	SHIKIMORI_CLIENT_SECRET: string;
	SHIKIMORI_REDIRECT_URI: string;
	SHIKIMORI_USER_AGENT: string;

	MAL_CLIENT_ID_DESKTOP: string;
	MAL_CLIENT_ID_MOBILE: string;
	MAL_CLIENT_SECRET_DESKTOP?: string;
	MAL_CLIENT_SECRET_MOBILE?: string;

	GOOGLE_DESKTOP_CLIENT_ID: string;
	GOOGLE_DESKTOP_CLIENT_SECRET: string;
	GOOGLE_WEB_CLIENT_ID: string;
	GOOGLE_WEB_CLIENT_SECRET: string;

	// Watch-party WebRTC signaling (temporary pairing data, TTL-expired).
	WATCH_PARTY: KVNamespace;

	// Optional override for the lightweight app proof. If set, the Flutter app
	// must use the same value or protected routes will return 401.
	APP_PROOF_SECRET?: string;
}

const SHIKIMORI_AUTHORIZE_URL = 'https://shikimori.io/oauth/authorize';
const SHIKIMORI_TOKEN_URL = 'https://shikimori.io/oauth/token';

const MAL_AUTHORIZE_URL = 'https://myanimelist.net/v1/oauth2/authorize';
const MAL_TOKEN_URL = 'https://myanimelist.net/v1/oauth2/token';
const MAL_DESKTOP_REDIRECT_URI = 'http://localhost:28373/token';
const MAL_MOBILE_REDIRECT_URI = 'app://mirushin/auth';

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_AUTHORIZE_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_DRIVE_APPDATA_SCOPE = 'https://www.googleapis.com/auth/drive.appdata';
const GOOGLE_DESKTOP_REDIRECT_URI = 'http://127.0.0.1:28375/';
const GOOGLE_TV_REDIRECT_URI = 'https://auth.emp0ry.com/callback';
const GOOGLE_DEVICE_GRANT = 'urn:ietf:params:oauth:grant-type:device_code';
const GOOGLE_TV_STATE_PREFIX = 'google_tv_';
const GOOGLE_TV_SESSION_TTL_SECONDS = 10 * 60;

export const corsHeaders = {
	'Access-Control-Allow-Origin': '*',
	'Access-Control-Allow-Headers': 'content-type, x-mirushin-timestamp, x-mirushin-signature',
	'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
};

export function json(data: unknown, status = 200): Response {
	return Response.json(data, { status, headers: corsHeaders });
}

const APP_PROOF_HEADER_TS = 'x-mirushin-timestamp';
const APP_PROOF_HEADER_SIG = 'x-mirushin-signature';
const APP_PROOF_QUERY_TS = 'ms_ts';
const APP_PROOF_QUERY_SIG = 'ms_sig';
const APP_PROOF_WINDOW_SECONDS = 5 * 60;
// This is an abuse speed-bump for the bundled app, not a true secret: clients
// can be reverse-engineered. Real quota protection should live in Cloudflare
// WAF/rate limiting before the Worker is invoked.
const DEFAULT_APP_PROOF_SECRET = 'mirushin-auth-proof-v1-2e2f2fe7f1194af4a2c0d517d316fd3a';

function unauthorized(): Response {
	return json({ error: 'unauthorized' }, 401);
}

function appProofSecret(env: Env): string {
	return (env.APP_PROOF_SECRET ?? DEFAULT_APP_PROOF_SECRET).trim();
}

function isOpenRoute(request: Request, url: URL): boolean {
	// CORS preflight must stay open, and Shikimori calls /callback directly after
	// OAuth authorization so it cannot carry the app proof.
	return request.method === 'OPTIONS' || url.pathname === '/callback';
}

function appProofParts(request: Request, url: URL): { timestamp: string; signature: string } {
	return {
		timestamp: request.headers.get(APP_PROOF_HEADER_TS) ?? url.searchParams.get(APP_PROOF_QUERY_TS) ?? '',
		signature: request.headers.get(APP_PROOF_HEADER_SIG) ?? url.searchParams.get(APP_PROOF_QUERY_SIG) ?? '',
	};
}

function isFreshTimestamp(value: string): boolean {
	if (!/^\d{10}$/.test(value)) return false;
	const timestamp = Number(value);
	if (!Number.isFinite(timestamp)) return false;
	const now = Math.floor(Date.now() / 1000);
	return Math.abs(now - timestamp) <= APP_PROOF_WINDOW_SECONDS;
}

function hex(buffer: ArrayBuffer): string {
	return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function safeEqualHex(a: string, b: string): boolean {
	if (a.length !== b.length) return false;
	let diff = 0;
	for (let i = 0; i < a.length; i++) {
		diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
	}
	return diff === 0;
}

async function signAppProof(timestamp: string, secret: string): Promise<string> {
	const encoder = new TextEncoder();
	const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
	return hex(await crypto.subtle.sign('HMAC', key, encoder.encode(timestamp)));
}

async function hasValidAppProof(request: Request, url: URL, env: Env): Promise<boolean> {
	if (isOpenRoute(request, url)) return true;
	const { timestamp, signature } = appProofParts(request, url);
	if (!isFreshTimestamp(timestamp) || !/^[a-f0-9]{64}$/i.test(signature)) {
		return false;
	}
	const secret = appProofSecret(env);
	if (!secret) return false;
	const expected = await signAppProof(timestamp, secret);
	return safeEqualHex(signature.toLowerCase(), expected);
}

function html(body: string, status = 200): Response {
	return new Response(body, {
		status,
		headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
	});
}

function escapeHtml(value: string): string {
	return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

// Desktop listener the app runs during the Shikimori login flow. The redirect
// URI registered with Shikimori stays this Worker's /callback, and this page
// forwards the code to localhost so the app captures it automatically (matching
// the MAL/AniList flow). The manual copy box stays as a fallback.
const SHIKIMORI_DESKTOP_CALLBACK = 'http://localhost:28374/';

interface GoogleTvSession {
	codeChallenge: string;
	code?: string;
	error?: string;
	errorDescription?: string;
}

function googleTvSessionKey(state: string): string {
	return `google-oauth:${state}`;
}

async function callbackPage(url: URL, env: Env): Promise<Response> {
	const code = url.searchParams.get('code')?.trim() ?? '';
	const state = url.searchParams.get('state')?.trim() ?? '';
	const error = url.searchParams.get('error')?.trim() ?? '';
	const errorDescription = url.searchParams.get('error_description')?.trim() ?? '';

	if (state.startsWith(GOOGLE_TV_STATE_PREFIX)) {
		const key = googleTvSessionKey(state);
		const rawSession = await env.WATCH_PARTY.get(key);
		if (!rawSession) return html('<h1>Login expired</h1><p>Return to MiruShin and start again.</p>', 400);
		const session = JSON.parse(rawSession) as GoogleTvSession;
		if (error || !code) {
			await env.WATCH_PARTY.put(
				key,
				JSON.stringify({ ...session, error: error || 'missing_code', errorDescription }),
				{ expirationTtl: 2 * 60 },
			);
			return html(`<h1>Login failed</h1><p>${escapeHtml(errorDescription || error || 'No authorization code received.')}</p>`, 400);
		}
		await env.WATCH_PARTY.put(key, JSON.stringify({ ...session, code }), { expirationTtl: 5 * 60 });
		return html(`
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MiruShin connected</title>
<body style="font-family: system-ui; padding: 24px; line-height: 1.5;">
  <h1>Google Drive connected</h1>
  <p>You can close this page and return to MiruShin on your TV.</p>
</body>
`);
	}

	if (!code) {
		return html(`<h1>Login failed</h1><p>${escapeHtml(error || 'No authorization code received.')}</p>`, 400);
	}

	const local = new URL(SHIKIMORI_DESKTOP_CALLBACK);
	local.searchParams.set('code', code);
	if (state) local.searchParams.set('state', state);
	const target = JSON.stringify(local.toString());

	return html(`
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Authorization code</title>
<script>setTimeout(function () { try { window.location.replace(${target}); } catch (e) {} }, 50);</script>
<body style="font-family: system-ui; padding: 24px; line-height: 1.5;">
  <h1>Authorization code</h1>
  <p>Returning to MiruShin… if the app did not pick it up, copy this code in by hand:</p>
  <input value="${escapeHtml(code)}" readonly style="width: 100%; font-size: 16px; padding: 12px;">
</body>
`);
}

function platformFrom(value: unknown): 'desktop' | 'mobile' {
	return value === 'mobile' ? 'mobile' : 'desktop';
}

function malClientId(env: Env, platform: 'desktop' | 'mobile'): string {
	return platform === 'mobile' ? (env.MAL_CLIENT_ID_MOBILE ?? '') : (env.MAL_CLIENT_ID_DESKTOP ?? '');
}

function malClientSecret(env: Env, platform: 'desktop' | 'mobile'): string {
	return platform === 'mobile' ? (env.MAL_CLIENT_SECRET_MOBILE ?? '') : (env.MAL_CLIENT_SECRET_DESKTOP ?? '');
}

function malRedirectUri(platform: 'desktop' | 'mobile'): string {
	return platform === 'mobile' ? MAL_MOBILE_REDIRECT_URI : MAL_DESKTOP_REDIRECT_URI;
}

function malAuthorize(url: URL, env: Env): Response {
	const platform = platformFrom(url.searchParams.get('platform'));
	const codeChallenge = url.searchParams.get('code_challenge')?.trim() ?? '';
	const state = url.searchParams.get('state')?.trim() || 'mal';
	const clientId = malClientId(env, platform).trim();

	if (!clientId) return json({ error: 'missing_mal_client_id' }, 500);
	if (!codeChallenge) return json({ error: 'missing_code_challenge' }, 400);

	const authUrl = new URL(MAL_AUTHORIZE_URL);
	authUrl.searchParams.set('response_type', 'code');
	authUrl.searchParams.set('client_id', clientId);
	authUrl.searchParams.set('code_challenge', codeChallenge);
	authUrl.searchParams.set('code_challenge_method', 'plain');
	authUrl.searchParams.set('redirect_uri', malRedirectUri(platform));
	authUrl.searchParams.set('state', state);

	return Response.redirect(authUrl.toString(), 302);
}

function shikimoriAuthorize(url: URL, env: Env): Response {
	const state = url.searchParams.get('state')?.trim() || 'shikimori';
	const clientId = (env.SHIKIMORI_CLIENT_ID ?? '').trim();

	if (!clientId) return json({ error: 'missing_shikimori_client_id' }, 500);

	const authUrl = new URL(SHIKIMORI_AUTHORIZE_URL);
	authUrl.searchParams.set('response_type', 'code');
	authUrl.searchParams.set('client_id', clientId);
	authUrl.searchParams.set('redirect_uri', env.SHIKIMORI_REDIRECT_URI ?? '');
	authUrl.searchParams.set('scope', 'user_rates');
	authUrl.searchParams.set('state', state);

	return Response.redirect(authUrl.toString(), 302);
}

async function malToken(payload: Record<string, unknown>, env: Env): Promise<Response> {
	const platform = platformFrom(payload.platform);
	const grantType = payload.grant_type;
	const clientId = malClientId(env, platform).trim();

	if (!clientId) return json({ error: 'missing_mal_client_id' }, 500);

	if (grantType !== 'authorization_code' && grantType !== 'refresh_token') {
		return json({ error: 'unsupported_grant_type' }, 400);
	}

	const form = new FormData();
	form.set('client_id', clientId);
	form.set('grant_type', grantType);

	const clientSecret = malClientSecret(env, platform).trim();
	if (clientSecret) form.set('client_secret', clientSecret);

	if (grantType === 'authorization_code') {
		const code = typeof payload.code === 'string' ? payload.code.trim() : '';
		const codeVerifier = typeof payload.code_verifier === 'string' ? payload.code_verifier.trim() : '';

		if (!code) return json({ error: 'missing_code' }, 400);
		if (!codeVerifier) return json({ error: 'missing_code_verifier' }, 400);

		form.set('code', code);
		form.set('code_verifier', codeVerifier);
		form.set('redirect_uri', malRedirectUri(platform));
	}

	if (grantType === 'refresh_token') {
		const refreshToken = typeof payload.refresh_token === 'string' ? payload.refresh_token.trim() : '';

		if (!refreshToken) return json({ error: 'missing_refresh_token' }, 400);
		form.set('refresh_token', refreshToken);
	}

	const upstream = await fetch(MAL_TOKEN_URL, { method: 'POST', body: form });

	return new Response(await upstream.text(), {
		status: upstream.status,
		headers: {
			...corsHeaders,
			'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
		},
	});
}

async function shikimoriToken(payload: Record<string, unknown>, env: Env): Promise<Response> {
	const grantType = payload.grant_type;

	if (grantType !== 'authorization_code' && grantType !== 'refresh_token') {
		return json({ error: 'unsupported_grant_type' }, 400);
	}

	const form = new FormData();
	form.set('grant_type', grantType);
	const clientId = (env.SHIKIMORI_CLIENT_ID ?? '').trim();
	const clientSecret = (env.SHIKIMORI_CLIENT_SECRET ?? '').trim();

	if (!clientId) return json({ error: 'missing_shikimori_client_id' }, 500);
	if (!clientSecret) return json({ error: 'missing_shikimori_client_secret' }, 500);

	form.set('client_id', clientId);
	form.set('client_secret', clientSecret);

	if (grantType === 'authorization_code') {
		const code = typeof payload.code === 'string' ? payload.code.trim() : '';
		if (!code) return json({ error: 'missing_code' }, 400);

		form.set('code', code);
		form.set('redirect_uri', env.SHIKIMORI_REDIRECT_URI ?? '');
	}

	if (grantType === 'refresh_token') {
		const refreshToken = typeof payload.refresh_token === 'string' ? payload.refresh_token.trim() : '';

		if (!refreshToken) return json({ error: 'missing_refresh_token' }, 400);
		form.set('refresh_token', refreshToken);
	}

	const upstream = await fetch(SHIKIMORI_TOKEN_URL, {
		method: 'POST',
		headers: { 'User-Agent': env.SHIKIMORI_USER_AGENT },
		body: form,
	});

	return new Response(await upstream.text(), {
		status: upstream.status,
		headers: {
			...corsHeaders,
			'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
		},
	});
}

type GooglePlatform = 'desktop' | 'tv';

function googlePlatform(value: unknown): GooglePlatform | null {
	if (value === 'desktop' || value === 'tv') return value;
	return null;
}

function googleCredentials(env: Env, platform: GooglePlatform): { clientId: string; clientSecret: string } {
	return platform === 'tv'
		? { clientId: (env.GOOGLE_WEB_CLIENT_ID ?? '').trim(), clientSecret: (env.GOOGLE_WEB_CLIENT_SECRET ?? '').trim() }
		: {
				clientId: (env.GOOGLE_DESKTOP_CLIENT_ID ?? '').trim(),
				clientSecret: (env.GOOGLE_DESKTOP_CLIENT_SECRET ?? '').trim(),
			};
}

async function sha256Base64Url(value: string): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
	const binary = String.fromCharCode(...new Uint8Array(digest));
	return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function payloadString(payload: Record<string, unknown>, key: string, maxLength: number): string {
	const value = typeof payload[key] === 'string' ? payload[key].trim() : '';
	return value.length <= maxLength ? value : '';
}

async function googleUpstream(url: string, form: URLSearchParams): Promise<Response> {
	const upstream = await fetch(url, {
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: form.toString(),
	});

	return new Response(await upstream.text(), {
		status: upstream.status,
		headers: {
			...corsHeaders,
			'Cache-Control': 'no-store',
			'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
		},
	});
}

async function googleDeviceCode(payload: Record<string, unknown>, env: Env): Promise<Response> {
	if (payload.platform !== 'tv') return json({ error: 'unsupported_platform' }, 400);
	const { clientId, clientSecret } = googleCredentials(env, 'tv');
	if (!clientId) return json({ error: 'missing_google_tv_client_id' }, 500);
	if (!clientSecret) return json({ error: 'missing_google_tv_client_secret' }, 500);
	const codeChallenge = payloadString(payload, 'code_challenge', 128);
	if (!/^[A-Za-z0-9._~-]{43,128}$/.test(codeChallenge)) return json({ error: 'invalid_code_challenge' }, 400);

	const state = `${GOOGLE_TV_STATE_PREFIX}${crypto.randomUUID().replaceAll('-', '')}`;
	const session: GoogleTvSession = { codeChallenge };
	await env.WATCH_PARTY.put(googleTvSessionKey(state), JSON.stringify(session), {
		expirationTtl: GOOGLE_TV_SESSION_TTL_SECONDS,
	});

	const authorizeUrl = new URL(GOOGLE_AUTHORIZE_URL);
	authorizeUrl.searchParams.set('client_id', clientId);
	authorizeUrl.searchParams.set('redirect_uri', GOOGLE_TV_REDIRECT_URI);
	authorizeUrl.searchParams.set('response_type', 'code');
	authorizeUrl.searchParams.set('scope', GOOGLE_DRIVE_APPDATA_SCOPE);
	authorizeUrl.searchParams.set('code_challenge', codeChallenge);
	authorizeUrl.searchParams.set('code_challenge_method', 'S256');
	authorizeUrl.searchParams.set('access_type', 'offline');
	authorizeUrl.searchParams.set('prompt', 'consent');
	authorizeUrl.searchParams.set('state', state);

	return json({
		device_code: state,
		user_code: '',
		verification_uri: authorizeUrl.toString(),
		expires_in: GOOGLE_TV_SESSION_TTL_SECONDS,
		interval: 5,
	});
}

async function googleToken(payload: Record<string, unknown>, env: Env): Promise<Response> {
	const platform = googlePlatform(payload.platform);
	if (!platform) return json({ error: 'unsupported_platform' }, 400);
	const grantType = payloadString(payload, 'grant_type', 128);
	const { clientId, clientSecret } = googleCredentials(env, platform);
	if (!clientId) return json({ error: `missing_google_${platform}_client_id` }, 500);
	if (!clientSecret) return json({ error: `missing_google_${platform}_client_secret` }, 500);

	const form = new URLSearchParams({
		client_id: clientId,
		client_secret: clientSecret,
		grant_type: grantType,
	});

	if (grantType === 'authorization_code') {
		if (platform !== 'desktop') return json({ error: 'unsupported_grant_type' }, 400);
		const code = payloadString(payload, 'code', 4096);
		const codeVerifier = payloadString(payload, 'code_verifier', 256);
		const redirectUri = payloadString(payload, 'redirect_uri', 256);
		if (!code) return json({ error: 'missing_code' }, 400);
		if (!codeVerifier) return json({ error: 'missing_code_verifier' }, 400);
		if (redirectUri !== GOOGLE_DESKTOP_REDIRECT_URI) return json({ error: 'invalid_redirect_uri' }, 400);
		form.set('code', code);
		form.set('code_verifier', codeVerifier);
		form.set('redirect_uri', GOOGLE_DESKTOP_REDIRECT_URI);
	} else if (grantType === 'refresh_token') {
		const refreshToken = payloadString(payload, 'refresh_token', 4096);
		if (!refreshToken) return json({ error: 'missing_refresh_token' }, 400);
		form.set('refresh_token', refreshToken);
	} else if (grantType === GOOGLE_DEVICE_GRANT) {
		if (platform !== 'tv') return json({ error: 'unsupported_grant_type' }, 400);
		const deviceCode = payloadString(payload, 'device_code', 4096);
		const codeVerifier = payloadString(payload, 'code_verifier', 256);
		if (!deviceCode) return json({ error: 'missing_device_code' }, 400);
		if (!codeVerifier) return json({ error: 'missing_code_verifier' }, 400);
		if (!deviceCode.startsWith(GOOGLE_TV_STATE_PREFIX)) return json({ error: 'invalid_device_code' }, 400);
		const key = googleTvSessionKey(deviceCode);
		const rawSession = await env.WATCH_PARTY.get(key);
		if (!rawSession) return json({ error: 'expired_token', error_description: 'Authorization session expired.' }, 400);
		const session = JSON.parse(rawSession) as GoogleTvSession;
		if ((await sha256Base64Url(codeVerifier)) !== session.codeChallenge) {
			return json({ error: 'invalid_grant', error_description: 'PKCE verification failed.' }, 400);
		}
		if (session.error) {
			await env.WATCH_PARTY.delete(key);
			return json({ error: session.error, error_description: session.errorDescription ?? '' }, 400);
		}
		if (!session.code) {
			return json({ error: 'authorization_pending', error_description: 'Waiting for Google authorization.' }, 428);
		}
		form.set('grant_type', 'authorization_code');
		form.set('code', session.code);
		form.set('code_verifier', codeVerifier);
		form.set('redirect_uri', GOOGLE_TV_REDIRECT_URI);
		const response = await googleUpstream(GOOGLE_TOKEN_URL, form);
		await env.WATCH_PARTY.delete(key);
		return response;
	} else {
		return json({ error: 'unsupported_grant_type' }, 400);
	}

	return googleUpstream(GOOGLE_TOKEN_URL, form);
}

export default {
	async fetch(
		request: Request,
		env: Env,
		_context: ExecutionContext,
	): Promise<Response> {
		if (request.method === 'OPTIONS') return json({ ok: true });

		const url = new URL(request.url);

		if (!(await hasValidAppProof(request, url, env))) {
			return unauthorized();
		}

		const watchParty = await handleWatchParty(request, url, env);
		if (watchParty) return watchParty;

		if (request.method === 'GET' && url.pathname === '/callback') {
			return callbackPage(url, env);
		}

		if (request.method === 'GET' && url.pathname === '/mal/authorize') {
			return malAuthorize(url, env);
		}

		if (request.method === 'GET' && url.pathname === '/shikimori/authorize') {
			return shikimoriAuthorize(url, env);
		}

		const postRoutes = new Set(['/mal/token', '/token']);
		if (request.method !== 'POST' || !postRoutes.has(url.pathname)) {
			return json({ error: 'not_found' }, 404);
		}

		const body = await request.json().catch(() => null);
		if (!body || typeof body !== 'object') {
			return json({ error: 'invalid_request' }, 400);
		}

		const payload = body as Record<string, unknown>;

		if (url.pathname === '/mal/token') return malToken(payload, env);
		if (payload.provider === 'google') {
			if (payload.action === 'device_code') return googleDeviceCode(payload, env);
			if (payload.action === 'token') return googleToken(payload, env);
			return json({ error: 'unsupported_google_action' }, 400);
		}
		return shikimoriToken(payload, env);
	},
} satisfies ExportedHandler<Env>;
