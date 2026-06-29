// Watch-party WebRTC signaling. The Worker only brokers the WebRTC handshake
// (offer / answer / ICE candidates) for pairing two MiruShin clients; once the
// peer-to-peer DataChannel is open the clients delete the room and all playback
// sync flows directly P2P. No video ever passes through the Worker.
//
// Storage is a single KV entry per room with a short TTL, so abandoned rooms
// expire automatically and nothing is retained long-term.
import { corsHeaders, json } from './index';

export interface WatchPartyEnv {
	WATCH_PARTY: KVNamespace;
}

// Rooms self-expire well before anyone would reasonably finish pairing, so a
// stale code can never be reused or linger.
const ROOM_TTL_SECONDS = 180;
// Long-polling keeps request count low: the host can wait for the guest answer
// in one Worker request instead of polling every second.
const ANSWER_WAIT_TIMEOUT_MS = 25_000;
const ANSWER_WAIT_INTERVAL_MS = 1_000;
// Signaling payloads (SDP / ICE) are small; cap the body to reject abuse.
const MAX_BODY_BYTES = 64 * 1024;
// Generated codes always satisfy this; the regex also guards path input.
const CODE_RE = /^[A-Z0-9]{6}$/;
// Friendly alphabet: no 0/O/1/I to avoid manual-entry confusion.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
// Bound the candidate lists so a misbehaving client can't grow a room unbounded.
const MAX_CANDIDATES = 60;

interface RoomData {
	offer: unknown;
	answer?: unknown;
	hostCandidates: unknown[];
	guestCandidates: unknown[];
	createdAt: number;
}

function roomKey(code: string): string {
	return `room:${code}`;
}

function generateCode(): string {
	const bytes = crypto.getRandomValues(new Uint8Array(6));
	let out = '';
	for (let i = 0; i < 6; i++) {
		out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
	}
	return out;
}

async function readJsonBody(request: Request): Promise<Record<string, unknown> | null> {
	const text = await request.text();
	if (text.length > MAX_BODY_BYTES) return null;
	try {
		const parsed = JSON.parse(text);
		if (!parsed || typeof parsed !== 'object') return null;
		return parsed as Record<string, unknown>;
	} catch {
		return null;
	}
}

async function loadRoom(env: WatchPartyEnv, code: string): Promise<RoomData | null> {
	const raw = await env.WATCH_PARTY.get(roomKey(code));
	if (!raw) return null;
	try {
		const room = JSON.parse(raw) as RoomData;
		// Defend against partial/legacy room shapes so candidate appends never throw.
		if (!Array.isArray(room.hostCandidates)) room.hostCandidates = [];
		if (!Array.isArray(room.guestCandidates)) room.guestCandidates = [];
		return room;
	} catch {
		return null;
	}
}

async function saveRoom(env: WatchPartyEnv, code: string, room: RoomData): Promise<void> {
	await env.WATCH_PARTY.put(roomKey(code), JSON.stringify(room), {
		expirationTtl: ROOM_TTL_SECONDS,
	});
}

function noContent(): Response {
	return new Response(null, { status: 204, headers: corsHeaders });
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

// Returns a Response for any /watch-party/* request, or null when the path is
// not ours so the main handler can continue with the OAuth routes.
export async function handleWatchParty(request: Request, url: URL, env: WatchPartyEnv): Promise<Response | null> {
	const path = url.pathname;
	if (path !== '/watch-party/rooms' && !path.startsWith('/watch-party/rooms/')) {
		return null;
	}

	// POST /watch-party/rooms — create a room from the host offer.
	if (path === '/watch-party/rooms') {
		if (request.method !== 'POST') {
			return json({ error: 'method_not_allowed' }, 405);
		}
		const body = await readJsonBody(request);
		if (!body || body.offer == null) {
			return json({ error: 'invalid_request' }, 400);
		}
		let code = '';
		for (let attempt = 0; attempt < 5; attempt++) {
			const candidate = generateCode();
			if ((await env.WATCH_PARTY.get(roomKey(candidate))) === null) {
				code = candidate;
				break;
			}
		}
		if (!code) return json({ error: 'code_unavailable' }, 503);
		await saveRoom(env, code, {
			offer: body.offer,
			hostCandidates: [],
			guestCandidates: [],
			createdAt: Date.now(),
		});
		return json({ code });
	}

	const rest = path.slice('/watch-party/rooms/'.length);
	const segments = rest.split('/').filter((s) => s.length > 0);
	const code = (segments[0] ?? '').toUpperCase();
	if (!CODE_RE.test(code)) return json({ error: 'invalid_code' }, 400);
	const sub = segments[1];

	// /watch-party/rooms/:code — fetch the offer or delete the room.
	if (segments.length === 1) {
		if (request.method === 'GET') {
			const room = await loadRoom(env, code);
			if (!room) return json({ error: 'not_found' }, 404);
			return json({ offer: room.offer });
		}
		if (request.method === 'DELETE') {
			await env.WATCH_PARTY.delete(roomKey(code));
			return json({ ok: true });
		}
		return json({ error: 'method_not_allowed' }, 405);
	}

	// /watch-party/rooms/:code/answer — guest stores answer, host fetches it.
	if (segments.length === 2 && sub === 'answer') {
		const room = await loadRoom(env, code);
		if (!room) return json({ error: 'not_found' }, 404);
		if (request.method === 'POST') {
			const body = await readJsonBody(request);
			if (!body || body.answer == null) {
				return json({ error: 'invalid_request' }, 400);
			}
			room.answer = body.answer;
			await saveRoom(env, code, room);
			return json({ ok: true });
		}
		if (request.method === 'GET') {
			const wait = url.searchParams.get('wait') === '1';
			const deadline = Date.now() + ANSWER_WAIT_TIMEOUT_MS;
			let current: RoomData | null = room;
			while (current?.answer == null && wait && Date.now() < deadline) {
				await sleep(ANSWER_WAIT_INTERVAL_MS);
				current = await loadRoom(env, code);
				if (!current) return json({ error: 'not_found' }, 404);
			}
			if (!current || current.answer == null) return noContent();
			return json({ answer: current.answer });
		}
		return json({ error: 'method_not_allowed' }, 405);
	}

	// /watch-party/rooms/:code/candidates — trickle ICE both directions. Each
	// side posts with its own role and polls for the other side's list (?for=).
	if (segments.length === 2 && sub === 'candidates') {
		const room = await loadRoom(env, code);
		if (!room) return json({ error: 'not_found' }, 404);
		if (request.method === 'POST') {
			const body = await readJsonBody(request);
			const role = body?.role;
			if (!body || body.candidate == null || (role !== 'host' && role !== 'guest')) {
				return json({ error: 'invalid_request' }, 400);
			}
			const list = role === 'host' ? room.hostCandidates : room.guestCandidates;
			if (list.length >= MAX_CANDIDATES) {
				return json({ error: 'too_many_candidates' }, 429);
			}
			list.push(body.candidate);
			await saveRoom(env, code, room);
			return json({ ok: true });
		}
		if (request.method === 'GET') {
			const forRole = url.searchParams.get('for');
			if (forRole !== 'host' && forRole !== 'guest') {
				return json({ error: 'invalid_request' }, 400);
			}
			const list = forRole === 'host' ? room.hostCandidates : room.guestCandidates;
			return json({ candidates: list });
		}
		return json({ error: 'method_not_allowed' }, 405);
	}

	return json({ error: 'not_found' }, 404);
}
