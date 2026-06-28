interface Env {
  SHIKIMORI_CLIENT_ID: string;
  SHIKIMORI_CLIENT_SECRET: string;
  SHIKIMORI_REDIRECT_URI: string;
  SHIKIMORI_USER_AGENT: string;

  MAL_CLIENT_ID_DESKTOP: string;
  MAL_CLIENT_ID_MOBILE: string;
  MAL_CLIENT_SECRET_DESKTOP?: string;
  MAL_CLIENT_SECRET_MOBILE?: string;
}

const SHIKIMORI_AUTHORIZE_URL = "https://shikimori.io/oauth/authorize";
const SHIKIMORI_TOKEN_URL = "https://shikimori.io/oauth/token";

const MAL_AUTHORIZE_URL = "https://myanimelist.net/v1/oauth2/authorize";
const MAL_TOKEN_URL = "https://myanimelist.net/v1/oauth2/token";
const MAL_DESKTOP_REDIRECT_URI = "http://localhost:28373/token";
const MAL_MOBILE_REDIRECT_URI = "app://mirushin/auth";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status, headers: corsHeaders });
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

// Desktop listener the app runs during the Shikimori login flow. The redirect
// URI registered with Shikimori stays this Worker's /callback, and this page
// forwards the code to localhost so the app captures it automatically (matching
// the MAL/AniList flow). The manual copy box stays as a fallback.
const SHIKIMORI_DESKTOP_CALLBACK = "http://localhost:28374/";

function callbackPage(url: URL): Response {
  const code = url.searchParams.get("code")?.trim() ?? "";
  const state = url.searchParams.get("state")?.trim() ?? "";
  const error = url.searchParams.get("error")?.trim() ?? "";

  if (!code) {
    return html(
      `<h1>Login failed</h1><p>${escapeHtml(error || "No authorization code received.")}</p>`,
      400,
    );
  }

  const local = new URL(SHIKIMORI_DESKTOP_CALLBACK);
  local.searchParams.set("code", code);
  if (state) local.searchParams.set("state", state);
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

function platformFrom(value: unknown): "desktop" | "mobile" {
  return value === "mobile" ? "mobile" : "desktop";
}

function malClientId(env: Env, platform: "desktop" | "mobile"): string {
  return platform === "mobile"
    ? env.MAL_CLIENT_ID_MOBILE ?? ""
    : env.MAL_CLIENT_ID_DESKTOP ?? "";
}

function malClientSecret(env: Env, platform: "desktop" | "mobile"): string {
  return platform === "mobile"
    ? env.MAL_CLIENT_SECRET_MOBILE ?? ""
    : env.MAL_CLIENT_SECRET_DESKTOP ?? "";
}

function malRedirectUri(platform: "desktop" | "mobile"): string {
  return platform === "mobile"
    ? MAL_MOBILE_REDIRECT_URI
    : MAL_DESKTOP_REDIRECT_URI;
}

function malAuthorize(url: URL, env: Env): Response {
  const platform = platformFrom(url.searchParams.get("platform"));
  const codeChallenge = url.searchParams.get("code_challenge")?.trim() ?? "";
  const state = url.searchParams.get("state")?.trim() || "mal";
  const clientId = malClientId(env, platform).trim();

  if (!clientId) return json({ error: "missing_mal_client_id" }, 500);
  if (!codeChallenge) return json({ error: "missing_code_challenge" }, 400);

  const authUrl = new URL(MAL_AUTHORIZE_URL);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("code_challenge", codeChallenge);
  authUrl.searchParams.set("code_challenge_method", "plain");
  authUrl.searchParams.set("redirect_uri", malRedirectUri(platform));
  authUrl.searchParams.set("state", state);

  return Response.redirect(authUrl.toString(), 302);
}

function shikimoriAuthorize(url: URL, env: Env): Response {
  const state = url.searchParams.get("state")?.trim() || "shikimori";
  const clientId = (env.SHIKIMORI_CLIENT_ID ?? "").trim();

  if (!clientId) return json({ error: "missing_shikimori_client_id" }, 500);

  const authUrl = new URL(SHIKIMORI_AUTHORIZE_URL);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("redirect_uri", env.SHIKIMORI_REDIRECT_URI ?? "");
  authUrl.searchParams.set("scope", "user_rates");
  authUrl.searchParams.set("state", state);

  return Response.redirect(authUrl.toString(), 302);
}

async function malToken(
  payload: Record<string, unknown>,
  env: Env,
): Promise<Response> {
  const platform = platformFrom(payload.platform);
  const grantType = payload.grant_type;
  const clientId = malClientId(env, platform).trim();

  if (!clientId) return json({ error: "missing_mal_client_id" }, 500);

  if (grantType !== "authorization_code" && grantType !== "refresh_token") {
    return json({ error: "unsupported_grant_type" }, 400);
  }

  const form = new FormData();
  form.set("client_id", clientId);
  form.set("grant_type", grantType);

  const clientSecret = malClientSecret(env, platform).trim();
  if (clientSecret) form.set("client_secret", clientSecret);

  if (grantType === "authorization_code") {
    const code = typeof payload.code === "string" ? payload.code.trim() : "";
    const codeVerifier =
      typeof payload.code_verifier === "string"
        ? payload.code_verifier.trim()
        : "";

    if (!code) return json({ error: "missing_code" }, 400);
    if (!codeVerifier) return json({ error: "missing_code_verifier" }, 400);

    form.set("code", code);
    form.set("code_verifier", codeVerifier);
    form.set("redirect_uri", malRedirectUri(platform));
  }

  if (grantType === "refresh_token") {
    const refreshToken =
      typeof payload.refresh_token === "string"
        ? payload.refresh_token.trim()
        : "";

    if (!refreshToken) return json({ error: "missing_refresh_token" }, 400);
    form.set("refresh_token", refreshToken);
  }

  const upstream = await fetch(MAL_TOKEN_URL, { method: "POST", body: form });

  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
    },
  });
}

async function shikimoriToken(
  payload: Record<string, unknown>,
  env: Env,
): Promise<Response> {
  const grantType = payload.grant_type;

  if (grantType !== "authorization_code" && grantType !== "refresh_token") {
    return json({ error: "unsupported_grant_type" }, 400);
  }

  const form = new FormData();
  form.set("grant_type", grantType);
  const clientId = (env.SHIKIMORI_CLIENT_ID ?? "").trim();
  const clientSecret = (env.SHIKIMORI_CLIENT_SECRET ?? "").trim();

  if (!clientId) return json({ error: "missing_shikimori_client_id" }, 500);
  if (!clientSecret) return json({ error: "missing_shikimori_client_secret" }, 500);

  form.set("client_id", clientId);
  form.set("client_secret", clientSecret);

  if (grantType === "authorization_code") {
    const code = typeof payload.code === "string" ? payload.code.trim() : "";
    if (!code) return json({ error: "missing_code" }, 400);

    form.set("code", code);
    form.set("redirect_uri", env.SHIKIMORI_REDIRECT_URI ?? "");
  }

  if (grantType === "refresh_token") {
    const refreshToken =
      typeof payload.refresh_token === "string"
        ? payload.refresh_token.trim()
        : "";

    if (!refreshToken) return json({ error: "missing_refresh_token" }, 400);
    form.set("refresh_token", refreshToken);
  }

  const upstream = await fetch(SHIKIMORI_TOKEN_URL, {
    method: "POST",
    headers: { "User-Agent": env.SHIKIMORI_USER_AGENT },
    body: form,
  });

  return new Response(await upstream.text(), {
    status: upstream.status,
    headers: {
      ...corsHeaders,
      "Content-Type": upstream.headers.get("Content-Type") ?? "application/json",
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return json({ ok: true });

    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/callback") {
      return callbackPage(url);
    }

    if (request.method === "GET" && url.pathname === "/mal/authorize") {
      return malAuthorize(url, env);
    }

    if (request.method === "GET" && url.pathname === "/shikimori/authorize") {
      return shikimoriAuthorize(url, env);
    }

    if (
      request.method !== "POST" ||
      (url.pathname !== "/mal/token" && url.pathname !== "/token")
    ) {
      return json({ error: "not_found" }, 404);
    }

    const body = await request.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return json({ error: "invalid_request" }, 400);
    }

    const payload = body as Record<string, unknown>;

    if (url.pathname === "/mal/token") return malToken(payload, env);
    return shikimoriToken(payload, env);
  },
} satisfies ExportedHandler<Env>;