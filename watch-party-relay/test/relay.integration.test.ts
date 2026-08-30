import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

interface Room {
  roomId: string;
  hostToken: string;
  joinToken: string;
}

interface RelayMessage {
  v: number;
  type: string;
  data: Record<string, unknown>;
}

class Peer {
  readonly messages: RelayMessage[] = [];
  private readonly waiters: Array<{
    type: string;
    resolve: (message: RelayMessage) => void;
  }> = [];
  private closeEvent?: CloseEvent;
  private readonly closeWaiters: Array<(event: CloseEvent) => void> = [];

  constructor(readonly socket: WebSocket) {
    socket.accept();
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data)) as RelayMessage;
      const index = this.waiters.findIndex((waiter) => waiter.type === message.type);
      if (index >= 0) {
        this.waiters.splice(index, 1)[0]!.resolve(message);
      } else {
        this.messages.push(message);
      }
    });
    socket.addEventListener("close", (event) => {
      this.closeEvent = event;
      for (const resolve of this.closeWaiters.splice(0)) resolve(event);
    });
  }

  send(type: string, data: Record<string, unknown>, version = 1): void {
    this.socket.send(JSON.stringify({ v: version, type, data }));
  }

  sendEvent(event: Record<string, unknown>): void {
    this.send("event", { event });
  }

  async next(type: string): Promise<RelayMessage> {
    const index = this.messages.findIndex((message) => message.type === type);
    if (index >= 0) return this.messages.splice(index, 1)[0]!;
    return new Promise<RelayMessage>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Timed out waiting for ${type}`)), 4_000);
      this.waiters.push({
        type,
        resolve: (message) => {
          clearTimeout(timer);
          resolve(message);
        },
      });
    });
  }

  close(): void {
    this.socket.close(1000, "test close");
  }

  closed(): Promise<CloseEvent> {
    if (this.closeEvent) return Promise.resolve(this.closeEvent);
    return new Promise((resolve) => this.closeWaiters.push(resolve));
  }
}

function event(
  type: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    type,
    sentAt: Date.now(),
    positionMs: 12_000,
    speed: 1,
    isPlaying: true,
    temporarySpeedActive: false,
    ...extra,
  };
}

async function createRoom(): Promise<Room> {
  const response = await SELF.fetch("https://relay.test/rooms", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ protocol: "mirushin-watch-party", version: 1 }),
  });
  expect(response.status).toBe(201);
  return response.json<Room>();
}

async function connect(
  room: Room,
  role: "host" | "guest",
  sessionId: string,
): Promise<{ peer: Peer; welcome: RelayMessage }> {
  const response = await SELF.fetch(
    `https://relay.test/rooms/${room.roomId}/connect`,
    { headers: { Upgrade: "websocket" } },
  );
  expect(response.status).toBe(101);
  const peer = new Peer(response.webSocket!);
  peer.send("authenticate", {
    role,
    token: role === "host" ? room.hostToken : room.joinToken,
    sessionId,
  });
  return { peer, welcome: await peer.next("welcome") };
}

describe("reference relay", () => {
  it("serves a self-contained, non-cacheable invite landing page", async () => {
    const invite =
      "https://relay.test/join?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890";
    const response = await SELF.fetch(invite);
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("text/html");
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.headers.get("Referrer-Policy")).toBe("no-referrer");
    expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(response.headers.get("Content-Security-Policy")).toContain(
      "default-src 'none'",
    );
    const body = await response.text();
    expect(body).toContain("Open in MiruShin");
    expect(body).toContain("mirushin://watch-party/join?invite=");
    expect(body).toContain(
      encodeURIComponent(invite).replaceAll("%20", "+"),
    );
    expect(body).not.toContain("hostToken");
    expect(body).not.toMatch(/<script|https:\/\/[^&\"]+\.(js|css)/i);
  });

  it("keeps a relay base path in the app bridge", async () => {
    const response = await SELF.fetch(
      "https://relay.test/base/relay/join?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890",
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toContain(
      encodeURIComponent(
        "https://relay.test/base/relay/join?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890",
      ),
    );
  });

  it("rejects malformed invite pages and non-GET methods", async () => {
    for (const url of [
      "https://relay.test/join",
      "https://relay.test/join?room=short&token=guest_join_token_1234567890",
      "https://relay.test/join?room=AbCdEfGhIjKlMnOp&token=short",
      "https://relay.test/join?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890&hostToken=secret",
      "https://relay.test/join?room=AbCdEfGhIjKlMnOp&room=OtherRoom123&token=guest_join_token_1234567890",
    ]) {
      const response = await SELF.fetch(url);
      expect(response.status, url).toBe(400);
      expect(response.headers.get("Cache-Control")).toBe("no-store");
    }
    const post = await SELF.fetch(
      "https://relay.test/join?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890",
      { method: "POST" },
    );
    expect(post.status).toBe(405);
    expect(post.headers.get("Allow")).toBe("GET");
  });

  it("reports compatible health and creates unpredictable tokenized rooms", async () => {
    const health = await SELF.fetch("https://relay.test/health");
    expect(await health.json()).toMatchObject({
      service: "mirushin-watch-party-relay",
      protocolVersion: 1,
      status: "ok",
    });
    const room = await createRoom();
    expect(room.roomId.length).toBeGreaterThanOrEqual(16);
    expect(room.hostToken.length).toBeGreaterThan(32);
    expect(room.joinToken.length).toBeGreaterThan(32);
    expect(room.hostToken).not.toBe(room.joinToken);
    const probeResponse = await SELF.fetch("https://relay.test/probe", {
      headers: { Upgrade: "websocket" },
    });
    expect(probeResponse.status).toBe(101);
    const probe = new Peer(probeResponse.webSocket!);
    await expect(probe.next("probeOk")).resolves.toMatchObject({ v: 1 });
  });

  it("fans one host event out to four simultaneous guests", async () => {
    const room = await createRoom();
    const host = (await connect(room, "host", "host-session-0001")).peer;
    const guests = await Promise.all(
      [1, 2, 3, 4].map(async (number) =>
        (await connect(room, "guest", `guest-session-000${number}`)).peer,
      ),
    );
    host.sendEvent(event("play"));
    const deliveries = await Promise.all(guests.map((guest) => guest.next("event")));
    expect(deliveries.map((message) => (message.data.event as Record<string, unknown>).type))
      .toEqual(["play", "play", "play", "play"]);
    host.sendEvent(event("sourceChanged", {
      source: {
        serverId: "server-b",
        qualityId: "1080p",
        soraEpisodeHref: "episode-2",
      },
    }));
    const streamDeliveries = await Promise.all(
      guests.map((guest) => guest.next("event")),
    );
    for (const delivery of streamDeliveries) {
      expect(delivery.data.event).toMatchObject({
        type: "sourceChanged",
        source: { serverId: "server-b", qualityId: "1080p" },
      });
    }
  });

  it("immediately gives a late guest the cached authoritative state", async () => {
    const room = await createRoom();
    const host = (await connect(room, "host", "host-session-0002")).peer;
    host.sendEvent(event("stateSnapshot", {
      positionMs: 91_000,
      source: { serverId: "server-a", qualityId: "1080p", soraEpisodeHref: "ep-5" },
      permissions: { canSeek: false, canChangeStream: false },
    }));
    const guest = (await connect(room, "guest", "late-guest-session")).peer;
    const snapshot = await guest.next("event");
    expect(snapshot.data.event).toMatchObject({
      type: "stateSnapshot",
      positionMs: 91_000,
      source: { serverId: "server-a", qualityId: "1080p" },
    });
  });

  it("removes one guest without affecting others and reconnects without duplicates", async () => {
    const room = await createRoom();
    await connect(room, "host", "host-session-0003");
    const first = await connect(room, "guest", "stable-guest-session");
    const observer = (await connect(room, "guest", "observer-session-01")).peer;
    const participantId = first.welcome.data.participantId;
    first.peer.close();
    const left = await observer.next("participantLeft");
    expect((left.data.participant as Record<string, unknown>).participantId).toBe(participantId);
    const reconnected = await connect(room, "guest", "stable-guest-session");
    expect(reconnected.welcome.data.participantId).toBe(participantId);
    await expect(observer.next("participantUpdated")).resolves.toBeTruthy();
    const participants = reconnected.welcome.data.participants as unknown[];
    expect(participants).toHaveLength(3);
  });

  it("keeps guests waiting during host loss and resumes the same host session", async () => {
    const room = await createRoom();
    const host = await connect(room, "host", "stable-host-session");
    const guest = (await connect(room, "guest", "host-watch-session")).peer;
    host.peer.close();
    await expect(guest.next("hostDisconnected")).resolves.toBeTruthy();
    await connect(room, "host", "stable-host-session");
    await expect(guest.next("hostReconnected")).resolves.toBeTruthy();
  });

  it("ends a room after the host reconnect timeout", async () => {
    const room = await createRoom();
    const host = await connect(room, "host", "timeout-host-session");
    const guest = (await connect(room, "guest", "timeout-guest-session")).peer;
    host.peer.close();
    await guest.next("hostDisconnected");
    await new Promise((resolve) => setTimeout(resolve, 5_300));
    await expect(guest.next("roomClosed")).resolves.toMatchObject({
      data: { code: "host_timeout" },
    });
  });

  it("rejects unauthorized guest controls and routes authorized seek and stream requests to the host", async () => {
    const room = await createRoom();
    const host = (await connect(room, "host", "permission-host-session")).peer;
    const guest = (await connect(room, "guest", "permission-guest-session")).peer;
    guest.sendEvent(event("seek"));
    await expect(guest.next("error")).resolves.toMatchObject({
      data: { code: "permission_denied" },
    });

    host.sendEvent(event("permissionsChanged", {
      permissions: {
        canControlPlayback: false,
        canSeek: true,
        canChangeSpeed: false,
        canChangeStream: true,
      },
    }));
    await guest.next("event");
    guest.sendEvent(event("seek", { positionMs: 44_000 }));
    expect((await host.next("event")).data.event).toMatchObject({
      type: "seek",
      positionMs: 44_000,
    });
    guest.sendEvent(event("streamChangeRequested", {
      source: { serverId: "server-b", qualityId: "720p", soraEpisodeHref: "ep-1" },
    }));
    expect((await host.next("event")).data.event).toMatchObject({
      type: "streamChangeRequested",
      source: { serverId: "server-b", qualityId: "720p" },
    });
    host.sendEvent(event("sourceChanged", {
      source: {
        serverId: "server-b",
        qualityId: "720p",
        soraEpisodeHref: "ep-1",
      },
    }));
    expect((await guest.next("event")).data.event).toMatchObject({
      type: "sourceChanged",
      source: { serverId: "server-b", qualityId: "720p" },
    });
  });

  it("isolates rooms and rejects malformed, oversized, and mismatched messages", async () => {
    const roomA = await createRoom();
    const roomB = await createRoom();
    const hostA = (await connect(roomA, "host", "isolation-host-a")).peer;
    const guestA = (await connect(roomA, "guest", "isolation-guest-a")).peer;
    const guestB = (await connect(roomB, "guest", "isolation-guest-b")).peer;
    hostA.sendEvent(event("pause"));
    expect((await guestA.next("event")).data.event).toMatchObject({ type: "pause" });
    expect(guestB.messages.some((message) => message.type === "event")).toBe(false);

    const mismatchResponse = await SELF.fetch(
      `https://relay.test/rooms/${roomA.roomId}/connect`,
      { headers: { Upgrade: "websocket" } },
    );
    const mismatch = new Peer(mismatchResponse.webSocket!);
    mismatch.send("authenticate", {}, 99);
    await expect(mismatch.next("error")).resolves.toMatchObject({
      data: { code: "protocol_mismatch" },
    });

    const malformed = await connect(roomB, "guest", "malformed-session-1");
    malformed.peer.socket.send("not-json");
    await expect(malformed.peer.closed()).resolves.toMatchObject({ code: 1008 });
    const oversized = await connect(roomB, "guest", "oversized-session-1");
    oversized.peer.socket.send("x".repeat(70_000));
    await expect(oversized.peer.closed()).resolves.toMatchObject({ code: 1009 });
  });
});
