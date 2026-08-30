import { PROTOCOL, PROTOCOL_VERSION, SERVICE, randomToken, sha256 } from "./protocol";
import { WatchPartyRoom } from "./room";
import type { Env } from "./types";

export { WatchPartyRoom };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }
    if (isJoinPath(url.pathname)) {
      if (request.method !== "GET") {
        return json(
          { code: "method_not_allowed", message: "Use GET for invite links." },
          405,
          { Allow: "GET" },
        );
      }
      return inviteLandingPage(url);
    }
    if (request.method === "GET" && url.pathname === "/health") {
      return json({
        service: SERVICE,
        protocol: PROTOCOL,
        protocolVersion: PROTOCOL_VERSION,
        status: "ok",
      });
    }
    if (request.method === "GET" && url.pathname === "/capabilities") {
      return json({
        service: SERVICE,
        protocolVersion: PROTOCOL_VERSION,
        transports: ["websocket"],
        features: [
          "multi-guest",
          "host-authority",
          "reconnection",
          "targeted-state",
          "stream-selection",
        ],
      });
    }
    if (request.method === "GET" && url.pathname === "/probe") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return json({ code: "upgrade_required" }, 426);
      }
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
      server.accept();
      server.send(
        JSON.stringify({ v: PROTOCOL_VERSION, type: "probeOk", data: {} }),
      );
      server.close(1000, "probe complete");
      return new Response(null, { status: 101, webSocket: client });
    }
    if (request.method === "POST" && url.pathname === "/rooms") {
      let body: unknown;
      try {
        body = await request.json();
      } catch {
        return json({ code: "invalid_request", message: "Invalid JSON." }, 400);
      }
      if (
        typeof body !== "object" ||
        body === null ||
        (body as Record<string, unknown>).protocol !== PROTOCOL ||
        (body as Record<string, unknown>).version !== PROTOCOL_VERSION
      ) {
        return json(
          { code: "protocol_mismatch", message: "Unsupported protocol version." },
          409,
        );
      }
      const roomId = randomToken(12);
      const hostToken = randomToken(32);
      const joinToken = randomToken(32);
      const stub = env.ROOMS.getByName(roomId);
      const created = await stub.fetch("https://room.internal/create", {
        method: "POST",
        body: JSON.stringify({
          hostTokenHash: await sha256(hostToken),
          joinTokenHash: await sha256(joinToken),
        }),
      });
      if (!created.ok) return withCors(created);
      return json({ roomId, hostToken, joinToken }, 201);
    }

    const match = /^\/rooms\/([A-Za-z0-9_-]{8,64})\/connect$/.exec(
      url.pathname,
    );
    if (request.method === "GET" && match?.[1]) {
      const roomId = match[1];
      const stub = env.ROOMS.getByName(roomId);
      return stub.fetch(new Request("https://room.internal/connect", request));
    }
    return json({ code: "not_found", message: "Not found." }, 404);
  },
} satisfies ExportedHandler<Env>;

function json(
  value: unknown,
  status = 200,
  additionalHeaders: Record<string, string> = {},
): Response {
  return Response.json(value, {
    status,
    headers: {
      ...corsHeaders(),
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...additionalHeaders,
    },
  });
}

function isJoinPath(pathname: string): boolean {
  return pathname === "/join" || pathname.endsWith("/join");
}

function inviteLandingPage(url: URL): Response {
  if (url.search.length > 1024) {
    return json({ code: "invalid_invite", message: "Invalid invite." }, 400);
  }
  const keys: string[] = [];
  url.searchParams.forEach((_value, key) => keys.push(key));
  const roomValues = url.searchParams.getAll("room");
  const tokenValues = url.searchParams.getAll("token");
  if (
    keys.length !== 2 ||
    !keys.every((key) => key === "room" || key === "token") ||
    roomValues.length !== 1 ||
    tokenValues.length !== 1 ||
    !/^[A-Za-z0-9_-]{8,64}$/.test(roomValues[0] ?? "") ||
    !/^[A-Za-z0-9_-]{16,256}$/.test(tokenValues[0] ?? "")
  ) {
    return json({ code: "invalid_invite", message: "Invalid invite." }, 400);
  }

  const invite = new URL(url.origin + url.pathname);
  invite.searchParams.set("room", roomValues[0]!);
  invite.searchParams.set("token", tokenValues[0]!);
  const appLink = new URL("mirushin://watch-party/join");
  appLink.searchParams.set("invite", invite.toString());
  const safeAppLink = escapeHtml(appLink.toString());

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Join a MiruShin watch party</title>
  <style>
    :root{color-scheme:dark}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0a0011;color:#f7efff;font:16px system-ui,sans-serif}.card{width:min(32rem,calc(100% - 3rem));padding:2rem;border:1px solid #493556;border-radius:1.25rem;background:#170d1e;text-align:center;box-shadow:0 1rem 3rem #0008}h1{margin:.25rem 0 .75rem;font-size:clamp(1.5rem,6vw,2.25rem)}p{color:#cabdd2;line-height:1.55}.button{display:inline-block;margin-top:1rem;padding:.85rem 1.25rem;border-radius:999px;background:#c985ff;color:#170d1e;font-weight:700;text-decoration:none}.note{font-size:.875rem}
  </style>
</head>
<body>
  <main class="card">
    <h1>Watch together in MiruShin</h1>
    <p>This invite opens the room directly in the MiruShin app.</p>
    <a class="button" href="${safeAppLink}">Open in MiruShin</a>
    <p class="note">If nothing happens, install or update MiruShin and open this link again.</p>
  </main>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
      "Cross-Origin-Resource-Policy": "same-origin",
      "Content-Security-Policy":
        "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  };
}

function withCors(response: Response): Response {
  const result = new Response(response.body, response);
  for (const [name, value] of Object.entries(corsHeaders())) {
    result.headers.set(name, value);
  }
  return result;
}
