import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import worker from '../src/index';

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

// Merge the test-pool env (which carries the WATCH_PARTY KV binding from
// wrangler.jsonc) with the OAuth secrets the existing tests rely on.
const baseEnv = {
	...env,
	SHIKIMORI_CLIENT_ID: 'shiki-client',
	SHIKIMORI_CLIENT_SECRET: 'shiki-secret',
	SHIKIMORI_REDIRECT_URI: 'https://auth.emp0ry.com/callback',
	SHIKIMORI_USER_AGENT: 'MiruShin',
	MAL_CLIENT_ID_DESKTOP: 'mal-desktop',
	MAL_CLIENT_ID_MOBILE: 'mal-mobile',
	GOOGLE_DESKTOP_CLIENT_ID: 'google-desktop-client',
	GOOGLE_DESKTOP_CLIENT_SECRET: 'google-desktop-secret',
	GOOGLE_WEB_CLIENT_ID: 'google-web-client',
	GOOGLE_WEB_CLIENT_SECRET: 'google-web-secret',
	APP_PROOF_SECRET: 'test-app-proof-secret',
};

function hex(buffer: ArrayBuffer): string {
	return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function appProofHeaders(): Promise<Record<string, string>> {
	const timestamp = Math.floor(Date.now() / 1000).toString();
	const encoder = new TextEncoder();
	const key = await crypto.subtle.importKey('raw', encoder.encode(baseEnv.APP_PROOF_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, [
		'sign',
	]);
	const signature = hex(await crypto.subtle.sign('HMAC', key, encoder.encode(timestamp)));
	return {
		'x-mirushin-timestamp': timestamp,
		'x-mirushin-signature': signature,
	};
}

async function appProofQuery(): Promise<string> {
	const headers = await appProofHeaders();
	const params = new URLSearchParams({
		ms_ts: headers['x-mirushin-timestamp'],
		ms_sig: headers['x-mirushin-signature'],
	});
	return params.toString();
}

async function pkceChallenge(verifier: string): Promise<string> {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
	const binary = String.fromCharCode(...new Uint8Array(digest));
	return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

async function fetchWorker(
	path: string,
	init?: RequestInit<IncomingRequestCfProperties>,
	options: { proof?: boolean } = {},
) {
	const headers = new Headers(init?.headers);
	const proof = options.proof ?? path !== '/callback';
	if (proof) {
		const appProof = await appProofHeaders();
		for (const [key, value] of Object.entries(appProof)) {
			headers.set(key, value);
		}
	}

	const request = new IncomingRequest(`https://auth.emp0ry.com${path}`, {
		...init,
		headers,
	});
	const ctx = createExecutionContext();
	const response = await worker.fetch(request, baseEnv, ctx);
	await waitOnExecutionContext(ctx);
	return response;
}

describe('mirushin-auth worker', () => {
	beforeEach(() => {
		fetchMock.activate();
		fetchMock.disableNetConnect();
	});

	afterEach(() => {
		fetchMock.assertNoPendingInterceptors();
		fetchMock.deactivate();
	});

	it('renders a callback error instead of throwing when no code is present', async () => {
		const response = await fetchWorker('/callback');

		expect(response.status).toBe(400);
		expect(await response.text()).toContain('No authorization code received.');
	});

	it('rejects protected routes without an app proof', async () => {
		const response = await fetchWorker(
			'/watch-party/rooms',
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ offer: { type: 'offer', sdp: 'host-sdp' } }),
			},
			{ proof: false },
		);

		expect(response.status).toBe(401);
		expect((await response.json()) as unknown).toEqual({
			error: 'unauthorized',
		});
	});

	it('redirects default Shikimori authorization through the Worker', async () => {
		const response = await fetchWorker('/shikimori/authorize?state=shikimori', {
			redirect: 'manual',
		});

		expect(response.status).toBe(302);
		const location = new URL(response.headers.get('location') ?? '');
		expect(location.origin).toBe('https://shikimori.io');
		expect(location.pathname).toBe('/oauth/authorize');
		expect(location.searchParams.get('client_id')).toBe('shiki-client');
		expect(location.searchParams.get('redirect_uri')).toBe('https://auth.emp0ry.com/callback');
	});

	it('accepts app proof query parameters for browser redirects', async () => {
		const proof = await appProofQuery();
		const response = await fetchWorker(`/shikimori/authorize?state=shikimori&${proof}`, { redirect: 'manual' }, { proof: false });

		expect(response.status).toBe(302);
	});

	it('redirects MAL authorization with the platform-specific client id', async () => {
		const response = await fetchWorker('/mal/authorize?platform=mobile&code_challenge=verifier&state=mal', { redirect: 'manual' });

		expect(response.status).toBe(302);
		const location = new URL(response.headers.get('location') ?? '');
		expect(location.origin).toBe('https://myanimelist.net');
		expect(location.pathname).toBe('/v1/oauth2/authorize');
		expect(location.searchParams.get('client_id')).toBe('mal-mobile');
		expect(location.searchParams.get('redirect_uri')).toBe('app://mirushin/auth');
	});

	it('exchanges a desktop Google code with server-side credentials and fixed redirect', async () => {
		let upstreamForm: URLSearchParams | undefined;
		fetchMock
			.get('https://oauth2.googleapis.com')
			.intercept({
				path: '/token',
				method: 'POST',
				body: (body) => {
					upstreamForm = new URLSearchParams(body);
					return true;
				},
			})
			.reply(200, JSON.stringify({ access_token: 'access', refresh_token: 'refresh', expires_in: 3600 }), {
				headers: { 'content-type': 'application/json' },
			});

		const response = await fetchWorker('/token', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				provider: 'google',
				action: 'token',
				platform: 'desktop',
				grant_type: 'authorization_code',
				code: 'authorization-code',
				code_verifier: 'pkce-verifier',
				redirect_uri: 'http://127.0.0.1:28375/',
				client_id: 'attacker-controlled-client',
				client_secret: 'attacker-controlled-secret',
			}),
		});

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(upstreamForm?.get('client_id')).toBe('google-desktop-client');
		expect(upstreamForm?.get('client_secret')).toBe('google-desktop-secret');
		expect(upstreamForm?.get('code')).toBe('authorization-code');
		expect(upstreamForm?.get('code_verifier')).toBe('pkce-verifier');
		expect(upstreamForm?.get('redirect_uri')).toBe('http://127.0.0.1:28375/');
	});

	it('runs Google TV QR handoff with PKCE and server-side Web credentials', async () => {
		const verifier = 'A'.repeat(64);
		const challenge = await pkceChallenge(verifier);
		const started = await fetchWorker('/token', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				provider: 'google',
				action: 'device_code',
				platform: 'tv',
				code_challenge: challenge,
				client_id: 'ignored',
			}),
		});

		expect(started.status).toBe(200);
		const startPayload = (await started.json()) as { device_code: string; user_code: string; verification_uri: string };
		expect(startPayload.device_code).toMatch(/^google_tv_[a-f0-9]{32}$/);
		expect(startPayload.user_code).toBe('');
		const authorizeUrl = new URL(startPayload.verification_uri);
		expect(authorizeUrl.origin).toBe('https://accounts.google.com');
		expect(authorizeUrl.searchParams.get('client_id')).toBe('google-web-client');
		expect(authorizeUrl.searchParams.get('redirect_uri')).toBe('https://auth.emp0ry.com/callback');
		expect(authorizeUrl.searchParams.get('scope')).toBe('https://www.googleapis.com/auth/drive.appdata');
		expect(authorizeUrl.searchParams.get('code_challenge')).toBe(challenge);
		expect(authorizeUrl.searchParams.get('state')).toBe(startPayload.device_code);

		const pending = await fetchWorker('/token', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				provider: 'google',
				action: 'token',
				platform: 'tv',
				grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
				device_code: startPayload.device_code,
				code_verifier: verifier,
			}),
		});
		expect(pending.status).toBe(428);
		expect((await pending.json()) as unknown).toEqual({
			error: 'authorization_pending',
			error_description: 'Waiting for Google authorization.',
		});

		const callback = await fetchWorker(
			`/callback?code=tv-authorization-code&state=${encodeURIComponent(startPayload.device_code)}`,
			{ redirect: 'manual' },
			{ proof: false },
		);
		expect(callback.status).toBe(200);
		expect(await callback.text()).toContain('Google Drive connected');

		let tokenForm: URLSearchParams | undefined;
		fetchMock
			.get('https://oauth2.googleapis.com')
			.intercept({
				path: '/token',
				method: 'POST',
				body: (body) => {
					tokenForm = new URLSearchParams(body);
					return true;
				},
			})
			.reply(200, JSON.stringify({ access_token: 'tv-access', refresh_token: 'tv-refresh', expires_in: 3600 }), {
				headers: { 'content-type': 'application/json' },
			});

		const completed = await fetchWorker('/token', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				provider: 'google',
				action: 'token',
				platform: 'tv',
				grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
				device_code: startPayload.device_code,
				code_verifier: verifier,
			}),
		});
		expect(completed.status).toBe(200);
		expect(tokenForm?.get('client_id')).toBe('google-web-client');
		expect(tokenForm?.get('client_secret')).toBe('google-web-secret');
		expect(tokenForm?.get('grant_type')).toBe('authorization_code');
		expect(tokenForm?.get('code')).toBe('tv-authorization-code');
		expect(tokenForm?.get('code_verifier')).toBe(verifier);
		expect(tokenForm?.get('redirect_uri')).toBe('https://auth.emp0ry.com/callback');
	});

	it('rejects an unexpected Google redirect before contacting Google', async () => {
		const response = await fetchWorker('/token', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({
				provider: 'google',
				action: 'token',
				platform: 'desktop',
				grant_type: 'authorization_code',
				code: 'authorization-code',
				code_verifier: 'pkce-verifier',
				redirect_uri: 'https://attacker.example/callback',
			}),
		});

		expect(response.status).toBe(400);
		expect((await response.json()) as unknown).toEqual({ error: 'invalid_redirect_uri' });
	});

	it('runs a full watch-party signaling handshake', async () => {
		// Host creates a room with its offer.
		const created = await fetchWorker('/watch-party/rooms', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ offer: { type: 'offer', sdp: 'host-sdp' } }),
		});
		expect(created.status).toBe(200);
		const { code } = (await created.json()) as { code: string };
		expect(code).toMatch(/^[A-Z0-9]{6}$/);

		// Guest fetches the offer.
		const offerRes = await fetchWorker(`/watch-party/rooms/${code}`);
		expect(offerRes.status).toBe(200);
		expect((await offerRes.json()) as unknown).toEqual({
			offer: { type: 'offer', sdp: 'host-sdp' },
		});

		// No answer yet -> 204.
		const emptyAnswer = await fetchWorker(`/watch-party/rooms/${code}/answer`);
		expect(emptyAnswer.status).toBe(204);

		// Guest posts its answer; host fetches it. The wait flag is the production
		// low-request path: one host request can wait for the answer instead of
		// polling every second.
		const postAnswer = await fetchWorker(`/watch-party/rooms/${code}/answer`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ answer: { type: 'answer', sdp: 'guest-sdp' } }),
		});
		expect(postAnswer.status).toBe(200);
		const answerRes = await fetchWorker(`/watch-party/rooms/${code}/answer?wait=1`);
		expect((await answerRes.json()) as unknown).toEqual({
			answer: { type: 'answer', sdp: 'guest-sdp' },
		});

		// After pairing the room is deleted and gone.
		const deleted = await fetchWorker(`/watch-party/rooms/${code}`, {
			method: 'DELETE',
		});
		expect(deleted.status).toBe(200);
		const afterDelete = await fetchWorker(`/watch-party/rooms/${code}`);
		expect(afterDelete.status).toBe(404);
	});

	it('rejects malformed room codes and missing offers', async () => {
		const badCode = await fetchWorker('/watch-party/rooms/abc');
		expect(badCode.status).toBe(400);

		const missingOffer = await fetchWorker('/watch-party/rooms', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({}),
		});
		expect(missingOffer.status).toBe(400);

		const unknownRoom = await fetchWorker('/watch-party/rooms/ZZZZZZ');
		expect(unknownRoom.status).toBe(404);
	});
});
