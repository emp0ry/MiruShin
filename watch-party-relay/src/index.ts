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

function json(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: {
      ...corsHeaders(),
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
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
