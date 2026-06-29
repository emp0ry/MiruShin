#!/usr/bin/env node

const API_BASE = 'https://api.cloudflare.com/client/v4';
const RULE_REF_PREFIX = 'mirushin_auth_';

const argv = new Set(process.argv.slice(2));
const dryRun = argv.has('--dry-run') || process.env.DRY_RUN === '1';
const host = argValue('--host') ?? process.env.AUTH_WORKER_HOST ?? 'auth.emp0ry.com';
const zoneId = argValue('--zone-id') ?? process.env.CLOUDFLARE_ZONE_ID ?? '';
const token = process.env.CLOUDFLARE_API_TOKEN ?? '';
const ratePeriod = numberEnv('AUTH_RATE_LIMIT_PERIOD', 10);
const rateRequests = numberEnv('AUTH_RATE_LIMIT_REQUESTS', 30);
const rateMitigation = numberEnv('AUTH_RATE_LIMIT_MITIGATION', 10);

function argValue(name) {
	const prefix = `${name}=`;
	const found = process.argv.slice(2).find((arg) => arg.startsWith(prefix));
	return found?.slice(prefix.length);
}

function numberEnv(name, fallback) {
	const raw = process.env[name];
	if (!raw) return fallback;
	const parsed = Number(raw);
	return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function q(value) {
	return JSON.stringify(value);
}

function expr(strings, ...values) {
	return strings
		.reduce((out, chunk, index) => `${out}${chunk}${values[index] ?? ''}`, '')
		.replace(/\s+/g, ' ')
		.trim();
}

function authHostExpression(expression) {
	return `(http.host eq ${q(host)} and ${expression})`;
}

const protectedApiExpression = expr`(
	((http.request.method eq "POST") and http.request.uri.path in {"/mal/token" "/token" "/watch-party/rooms"}) or
	((http.request.method in {"GET" "POST" "DELETE"}) and starts_with(http.request.uri.path, "/watch-party/rooms/"))
)`;

const knownRouteExpression = expr`(
	http.request.method eq "OPTIONS" or
	((http.request.method eq "GET") and http.request.uri.path in {"/callback" "/mal/authorize" "/shikimori/authorize"}) or
	((http.request.method eq "POST") and http.request.uri.path in {"/mal/token" "/token" "/watch-party/rooms"}) or
	((http.request.method in {"GET" "POST" "DELETE"}) and starts_with(http.request.uri.path, "/watch-party/rooms/"))
)`;

const authWorkerScopeExpression = authHostExpression(expr`(
	starts_with(http.request.uri.path, "/watch-party/") or
	http.request.uri.path in {"/callback" "/mal/authorize" "/mal/token" "/shikimori/authorize" "/token"}
)`);

const wafRules = [
	{
		ref: `${RULE_REF_PREFIX}block_watch_party_candidates`,
		description: 'MiruShin auth: block legacy trickle ICE candidate routes before Worker',
		action: 'block',
		expression: authHostExpression(
			`starts_with(http.request.uri.path, "/watch-party/rooms/") and http.request.uri.path contains "/candidates"`,
		),
		enabled: true,
	},
	{
		ref: `${RULE_REF_PREFIX}block_unknown_auth_routes`,
		description: 'MiruShin auth: block unknown paths/methods before Worker',
		action: 'block',
		expression: authHostExpression(`not ${knownRouteExpression}`),
		enabled: true,
	},
	{
		ref: `${RULE_REF_PREFIX}require_api_proof_headers`,
		description: 'MiruShin auth: require app proof headers for API/signaling calls',
		action: 'block',
		expression: authHostExpression(expr`(
			${protectedApiExpression} and
			(
				not any(http.request.headers["x-mirushin-timestamp"][*] ne "") or
				not any(http.request.headers["x-mirushin-signature"][*] ne "")
			)
		)`),
		enabled: true,
	},
	{
		ref: `${RULE_REF_PREFIX}require_authorize_query_proof`,
		description: 'MiruShin auth: require query proof for browser OAuth authorize redirects',
		action: 'block',
		expression: authHostExpression(expr`(
			(http.request.method eq "GET") and
			http.request.uri.path in {"/mal/authorize" "/shikimori/authorize"} and
			not (http.request.uri.query contains "ms_ts=" and http.request.uri.query contains "ms_sig=")
		)`),
		enabled: true,
	},
];

const rateRules = [
	{
		ref: `${RULE_REF_PREFIX}ip_rate_limit_auth_worker`,
		description: `MiruShin auth: per-IP rate limit (${rateRequests}/${ratePeriod}s, ${rateMitigation}s block)`,
		action: 'block',
		action_parameters: {
			response: {
				status_code: 429,
				content: 'rate limited',
				content_type: 'text/plain',
			},
		},
		expression: authWorkerScopeExpression,
		ratelimit: {
			characteristics: ['cf.colo.id', 'ip.src'],
			period: ratePeriod,
			requests_per_period: rateRequests,
			mitigation_timeout: rateMitigation,
		},
		enabled: true,
	},
];

function sanitizeRule(rule) {
	const allowed = ['ref', 'description', 'action', 'action_parameters', 'expression', 'enabled', 'ratelimit', 'logging'];
	return Object.fromEntries(Object.entries(rule).filter(([key]) => allowed.includes(key)));
}

function upsertManagedRules(existingRules, managedRules) {
	const foreignRules = existingRules
		.map(sanitizeRule)
		.filter((rule) => typeof rule.ref !== 'string' || !rule.ref.startsWith(RULE_REF_PREFIX));
	return [...managedRules, ...foreignRules];
}

async function api(path, init = {}) {
	if (!token) throw new Error('Missing CLOUDFLARE_API_TOKEN.');
	const response = await fetch(`${API_BASE}${path}`, {
		...init,
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json',
			...(init.headers ?? {}),
		},
	});
	const text = await response.text();
	const payload = text ? JSON.parse(text) : {};
	if (!response.ok || payload.success === false) {
		const details = payload.errors?.length ? JSON.stringify(payload.errors, null, 2) : text;
		const error = new Error(`Cloudflare API ${response.status} ${response.statusText}: ${details}`);
		error.status = response.status;
		throw error;
	}
	return payload.result;
}

async function getEntrypoint(phase) {
	try {
		return await api(`/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`);
	} catch (error) {
		if (error.status === 404) return null;
		throw error;
	}
}

async function putEntrypoint(phase, name, description, rules) {
	const existing = await getEntrypoint(phase);
	const nextRules = upsertManagedRules(existing?.rules ?? [], rules);

	if (!existing) {
		return api(`/zones/${zoneId}/rulesets`, {
			method: 'POST',
			body: JSON.stringify({
				name,
				description,
				kind: 'zone',
				phase,
				rules: nextRules,
			}),
		});
	}

	return api(`/zones/${zoneId}/rulesets/phases/${phase}/entrypoint`, {
		method: 'PUT',
		body: JSON.stringify({
			name,
			description,
			rules: nextRules,
		}),
	});
}

function printPlan() {
	console.log(
		JSON.stringify(
			{
				host,
				zoneId: zoneId || '<set CLOUDFLARE_ZONE_ID>',
				customWaf: {
					phase: 'http_request_firewall_custom',
					rules: wafRules,
				},
				rateLimit: {
					phase: 'http_ratelimit',
					rules: rateRules,
				},
			},
			null,
			2,
		),
	);
}

async function main() {
	if (dryRun) {
		printPlan();
		return;
	}
	if (!zoneId) throw new Error('Missing CLOUDFLARE_ZONE_ID.');
	if (!token) throw new Error('Missing CLOUDFLARE_API_TOKEN.');

	const waf = await putEntrypoint(
		'http_request_firewall_custom',
		'MiruShin auth edge guard',
		'Blocks malformed or unauthenticated auth.emp0ry.com requests before they invoke the Worker.',
		wafRules,
	);
	console.log(`Updated WAF entrypoint ${waf.id} (${waf.rules?.length ?? 0} rules).`);

	const rate = await putEntrypoint(
		'http_ratelimit',
		'MiruShin auth rate limits',
		'Caps per-IP traffic to auth.emp0ry.com so abuse cannot burn the Worker free quota quickly.',
		rateRules,
	);
	console.log(`Updated rate-limit entrypoint ${rate.id} (${rate.rules?.length ?? 0} rules).`);
}

main().catch((error) => {
	console.error(error.message);
	process.exit(1);
});
