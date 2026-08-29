import {
  GUEST_EVENT_TYPES,
  HOST_EVENT_TYPES,
  PROTOCOL_VERSION,
  errorMessage,
  isRecord,
  limits,
  parseMessage,
  sha256,
  validWatchPartyEvent,
} from "./protocol";
import type {
  Env,
  PublicParticipant,
  RelayLimits,
  RoomRecord,
  SocketAttachment,
} from "./types";

const ROOM_KEY = "room";
const SNAPSHOT_KEY = "latestSnapshot";
const PERMISSIONS_KEY = "permissions";
const SESSIONS_KEY = "recentGuestSessions";
const AUTHENTICATION_TIMEOUT_MS = 15_000;

export class WatchPartyRoom implements DurableObject {
  private readonly roomLimits: RelayLimits;

  constructor(
    private readonly ctx: DurableObjectState,
    private readonly env: Env,
  ) {
    this.roomLimits = limits(env);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/create") {
      if (await this.ctx.storage.get<RoomRecord>(ROOM_KEY)) {
        return Response.json({ code: "room_exists" }, { status: 409 });
      }
      const body = (await request.json()) as Partial<RoomRecord>;
      if (!body.hostTokenHash || !body.joinTokenHash) {
        return Response.json({ code: "invalid_request" }, { status: 400 });
      }
      const now = Date.now();
      await this.ctx.storage.put<RoomRecord>(ROOM_KEY, {
        hostTokenHash: body.hostTokenHash,
        joinTokenHash: body.joinTokenHash,
        createdAt: now,
        lastActivityAt: now,
      });
      await this.scheduleAlarm();
      return new Response(null, { status: 204 });
    }
    if (request.method === "GET" && url.pathname === "/connect") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return Response.json({ code: "upgrade_required" }, { status: 426 });
      }
      const room = await this.ctx.storage.get<RoomRecord>(ROOM_KEY);
      if (!room || room.closed) {
        return Response.json(
          { code: "room_not_found", message: "Room not found or expired." },
          { status: 404 },
        );
      }
      if (this.ctx.getWebSockets().length >= this.roomLimits.maxParticipants + 8) {
        return Response.json(
          { code: "room_full", message: "This watch party is full." },
          { status: 429 },
        );
      }
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
      const now = Date.now();
      server.serializeAttachment({
        authenticated: false,
        acceptedAt: now,
        rateWindowStartedAt: now,
        rateWindowMessages: 0,
      } satisfies SocketAttachment);
      this.ctx.acceptWebSocket(server);
      await this.scheduleAlarm();
      return new Response(null, { status: 101, webSocket: client });
    }
    return Response.json({ code: "not_found" }, { status: 404 });
  }

  async webSocketMessage(socket: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    if (typeof raw !== "string") {
      socket.close(1003, "binary messages are unsupported");
      return;
    }
    if (new TextEncoder().encode(raw).byteLength > this.roomLimits.maxMessageBytes) {
      socket.close(1009, "message too large");
      return;
    }
    const attachment = this.attachment(socket);
    if (!this.withinRateLimit(socket, attachment)) return;
    const message = parseMessage(raw);
    if (!message) {
      socket.close(1008, "invalid message");
      return;
    }
    if (message.v !== PROTOCOL_VERSION) {
      socket.send(
        errorMessage(
          "protocol_mismatch",
          "Unsupported Watch with Friends protocol version.",
          true,
        ),
      );
      socket.close(1008, "protocol mismatch");
      return;
    }
    if (!attachment.authenticated) {
      if (message.type !== "authenticate") {
        socket.close(1008, "authentication required");
        return;
      }
      await this.authenticate(socket, attachment, message.data);
      return;
    }
    await this.touchRoom();
    if (message.type === "closeRoom") {
      if (attachment.role !== "host") {
        socket.send(errorMessage("permission_denied", "Only the host can close the room."));
        return;
      }
      await this.closeRoom("host_closed", "The host ended the watch party.");
      return;
    }
    if (message.type !== "event") {
      socket.send(errorMessage("invalid_message", "Unknown relay message type."));
      return;
    }
    await this.routeEvent(socket, attachment, message.data);
  }

  async webSocketClose(
    socket: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean,
  ): Promise<void> {
    await this.handleSocketGone(socket);
  }

  async webSocketError(socket: WebSocket, _error: unknown): Promise<void> {
    await this.handleSocketGone(socket);
  }

  async alarm(): Promise<void> {
    const room = await this.ctx.storage.get<RoomRecord>(ROOM_KEY);
    if (!room) return;
    const now = Date.now();
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = this.attachment(socket);
      if (
        !attachment.authenticated &&
        now - (attachment.acceptedAt ?? now) >= AUTHENTICATION_TIMEOUT_MS
      ) {
        delete attachment.acceptedAt;
        socket.serializeAttachment(attachment);
        socket.close(1008, "authentication timeout");
      }
    }
    if (
      room.hostReconnectDeadline !== undefined &&
      now >= room.hostReconnectDeadline &&
      !this.findRole("host")
    ) {
      await this.closeRoom(
        "host_timeout",
        "Watch party ended because the host disconnected.",
      );
      return;
    }
    if (now - room.lastActivityAt >= this.roomLimits.roomIdleTimeoutMs) {
      await this.closeRoom("room_idle", "The inactive watch party expired.");
      return;
    }
    await this.scheduleAlarm();
  }

  private async authenticate(
    socket: WebSocket,
    attachment: SocketAttachment,
    data: Record<string, unknown>,
  ): Promise<void> {
    const role = data.role;
    const token = data.token;
    const sessionId = data.sessionId;
    if (
      (role !== "host" && role !== "guest") ||
      typeof token !== "string" ||
      token.length < 32 ||
      typeof sessionId !== "string" ||
      !/^[A-Za-z0-9_-]{16,128}$/.test(sessionId)
    ) {
      socket.send(errorMessage("authentication_failed", "Invalid room credentials.", true));
      socket.close(1008, "authentication failed");
      return;
    }
    const room = await this.ctx.storage.get<RoomRecord>(ROOM_KEY);
    if (!room || room.closed) {
      socket.send(errorMessage("room_not_found", "Room not found or expired.", true));
      socket.close(1008, "room unavailable");
      return;
    }
    const tokenHash = await sha256(token);
    const expected = role === "host" ? room.hostTokenHash : room.joinTokenHash;
    if (tokenHash !== expected) {
      socket.send(errorMessage("authentication_failed", "Invalid room credentials.", true));
      socket.close(1008, "authentication failed");
      return;
    }

    const current = this.authenticatedSockets();
    const existing = current.find(
      ({ attachment: item }) => item.role === role && item.sessionId === sessionId,
    );
    if (!existing && current.length >= this.roomLimits.maxParticipants) {
      socket.send(errorMessage("room_full", "This watch party is full.", true));
      socket.close(1008, "room full");
      return;
    }
    if (role === "host") {
      for (const entry of current.filter(({ attachment: item }) => item.role === "host")) {
        this.markReplaced(entry.socket);
      }
    } else if (existing) {
      this.markReplaced(existing.socket);
    }

    const now = Date.now();
    const sessionHash = await sha256(sessionId);
    const recentGuestSessions =
      (await this.ctx.storage.get<Record<string, number>>(SESSIONS_KEY)) ?? {};
    const knownGuestSession = role === "guest" && sessionHash in recentGuestSessions;
    const participantId = role === "host"
      ? "host"
      : `guest-${sessionHash.slice(0, 16)}`;
    const reconnected = Boolean(existing) || knownGuestSession ||
      (role === "host" && room.hostReconnectDeadline !== undefined);
    if (role === "guest") {
      recentGuestSessions[sessionHash] = now;
      const entries = Object.entries(recentGuestSessions).sort(
        ([, left], [, right]) => right - left,
      );
      const retained = Object.fromEntries(
        entries.slice(0, this.roomLimits.maxParticipants * 4),
      );
      await this.ctx.storage.put(SESSIONS_KEY, retained);
    }
    const updated: SocketAttachment = {
      ...attachment,
      authenticated: true,
      role,
      participantId,
      sessionId,
      connectedAt: now,
    };
    socket.serializeAttachment(updated);
    if (role === "host" && room.hostReconnectDeadline !== undefined) {
      delete room.hostReconnectDeadline;
      room.lastActivityAt = now;
      await this.ctx.storage.put(ROOM_KEY, room);
      this.broadcast("hostReconnected", {}, socket);
    } else {
      await this.touchRoom();
    }

    socket.send(
      this.encode("welcome", {
        participantId,
        role,
        participants: this.publicParticipants(),
      }),
    );
    const participant = this.publicParticipant(updated);
    this.broadcast(reconnected ? "participantUpdated" : "participantJoined", { participant }, socket);
    this.broadcastParticipants();

    if (role === "guest") {
      const snapshot = await this.ctx.storage.get<Record<string, unknown>>(SNAPSHOT_KEY);
      if (snapshot) {
        socket.send(
          this.encode("event", {
            senderParticipantId: "host",
            event: snapshot,
          }),
        );
      }
    }
    await this.scheduleAlarm();
  }

  private async routeEvent(
    socket: WebSocket,
    attachment: SocketAttachment,
    data: Record<string, unknown>,
  ): Promise<void> {
    const event = data.event;
    if (!validWatchPartyEvent(event)) {
      socket.send(errorMessage("invalid_message", "Invalid watch-party event."));
      return;
    }
    const type = event.type as string;
    if (attachment.role === "host") {
      if (!HOST_EVENT_TYPES.has(type)) {
        socket.send(errorMessage("permission_denied", "The host cannot send that event."));
        return;
      }
      if (type === "stateSnapshot") {
        await this.ctx.storage.put(SNAPSHOT_KEY, event);
      }
      if (
        (type === "permissionsChanged" || type === "stateSnapshot") &&
        isRecord(event.permissions)
      ) {
        await this.ctx.storage.put(PERMISSIONS_KEY, event.permissions);
      }
      const target = typeof data.targetParticipantId === "string"
        ? data.targetParticipantId
        : undefined;
      const envelope = this.encode("event", {
        senderParticipantId: attachment.participantId,
        event,
      });
      if (target) {
        const guest = this.findParticipant(target);
        if (guest?.attachment.role === "guest") guest.socket.send(envelope);
      } else {
        this.sendToGuests(envelope);
      }
      return;
    }

    if (!GUEST_EVENT_TYPES.has(type)) {
      socket.send(errorMessage("permission_denied", "Guests cannot send that event."));
      return;
    }
    if (type !== "helloRequest") {
      const permissions =
        (await this.ctx.storage.get<Record<string, unknown>>(PERMISSIONS_KEY)) ?? {};
      const allowed =
        ((type === "play" || type === "pause") && permissions.canControlPlayback === true) ||
        (type === "seek" && permissions.canSeek === true) ||
        (type === "speed" && permissions.canChangeSpeed === true) ||
        (type === "streamChangeRequested" && permissions.canChangeStream === true);
      if (!allowed) {
        socket.send(errorMessage("permission_denied", "The host has not allowed that action."));
        return;
      }
    }
    const host = this.findRole("host");
    if (!host) {
      socket.send(errorMessage("host_unavailable", "Host disconnected. Waiting for reconnection…"));
      return;
    }
    host.socket.send(
      this.encode("event", {
        senderParticipantId: attachment.participantId,
        event,
      }),
    );
  }

  private async handleSocketGone(socket: WebSocket): Promise<void> {
    const attachment = this.attachment(socket);
    if (!attachment.authenticated || !attachment.participantId) return;
    attachment.authenticated = false;
    socket.serializeAttachment(attachment);
    const participant = this.publicParticipant({ ...attachment, authenticated: true });
    if (attachment.role === "host" && !this.findRole("host")) {
      const room = await this.ctx.storage.get<RoomRecord>(ROOM_KEY);
      if (room) {
        room.hostReconnectDeadline = Date.now() + this.roomLimits.hostReconnectTimeoutMs;
        room.lastActivityAt = Date.now();
        await this.ctx.storage.put(ROOM_KEY, room);
      }
      this.broadcast("hostDisconnected", { reconnectTimeoutMs: this.roomLimits.hostReconnectTimeoutMs });
    } else {
      this.broadcast("participantLeft", { participant });
    }
    this.broadcastParticipants();
    await this.scheduleAlarm();
  }

  private withinRateLimit(socket: WebSocket, attachment: SocketAttachment): boolean {
    const now = Date.now();
    if (now - attachment.rateWindowStartedAt >= 60_000) {
      attachment.rateWindowStartedAt = now;
      attachment.rateWindowMessages = 0;
    }
    attachment.rateWindowMessages += 1;
    socket.serializeAttachment(attachment);
    if (attachment.rateWindowMessages <= this.roomLimits.maxMessagesPerMinute) return true;
    socket.send(errorMessage("rate_limited", "Too many messages.", true));
    socket.close(1008, "rate limited");
    return false;
  }

  private markReplaced(socket: WebSocket): void {
    const old = this.attachment(socket);
    old.authenticated = false;
    socket.serializeAttachment(old);
    socket.close(1000, "session reconnected");
  }

  private authenticatedSockets(): Array<{
    socket: WebSocket;
    attachment: SocketAttachment;
  }> {
    return this.ctx
      .getWebSockets()
      .map((socket) => ({ socket, attachment: this.attachment(socket) }))
      .filter(
        ({ socket, attachment }) =>
          attachment.authenticated && socket.readyState === WebSocket.OPEN,
      );
  }

  private findRole(role: "host" | "guest") {
    return this.authenticatedSockets().find(({ attachment }) => attachment.role === role);
  }

  private findParticipant(participantId: string) {
    return this.authenticatedSockets().find(
      ({ attachment }) => attachment.participantId === participantId,
    );
  }

  private attachment(socket: WebSocket): SocketAttachment {
    return socket.deserializeAttachment() as SocketAttachment;
  }

  private publicParticipants(): PublicParticipant[] {
    return this.authenticatedSockets().map(({ attachment }) =>
      this.publicParticipant(attachment),
    );
  }

  private publicParticipant(attachment: SocketAttachment): PublicParticipant {
    return {
      participantId: attachment.participantId!,
      role: attachment.role!,
      connected: true,
      connectedAt: new Date(attachment.connectedAt ?? Date.now()).toISOString(),
    };
  }

  private broadcast(type: string, data: Record<string, unknown>, except?: WebSocket): void {
    const message = this.encode(type, data);
    for (const { socket } of this.authenticatedSockets()) {
      if (socket !== except) socket.send(message);
    }
  }

  private broadcastParticipants(): void {
    this.broadcast("participants", { participants: this.publicParticipants() });
  }

  private sendToGuests(message: string): void {
    for (const { socket, attachment } of this.authenticatedSockets()) {
      if (attachment.role === "guest") socket.send(message);
    }
  }

  private encode(type: string, data: Record<string, unknown>): string {
    return JSON.stringify({ v: PROTOCOL_VERSION, type, data });
  }

  private async touchRoom(): Promise<void> {
    const room = await this.ctx.storage.get<RoomRecord>(ROOM_KEY);
    if (!room) return;
    room.lastActivityAt = Date.now();
    await this.ctx.storage.put(ROOM_KEY, room);
    await this.scheduleAlarm();
  }

  private async scheduleAlarm(): Promise<void> {
    const room = await this.ctx.storage.get<RoomRecord>(ROOM_KEY);
    if (!room) return;
    const idleDeadline = room.lastActivityAt + this.roomLimits.roomIdleTimeoutMs;
    let deadline = room.hostReconnectDeadline === undefined
      ? idleDeadline
      : Math.min(idleDeadline, room.hostReconnectDeadline);
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = this.attachment(socket);
      if (!attachment.authenticated && attachment.acceptedAt !== undefined) {
        deadline = Math.min(
          deadline,
          attachment.acceptedAt + AUTHENTICATION_TIMEOUT_MS,
        );
      }
    }
    await this.ctx.storage.setAlarm(deadline);
  }

  private async closeRoom(code: string, message: string): Promise<void> {
    const payload = this.encode("roomClosed", { code, message });
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(payload);
        socket.close(1000, "room closed");
      } catch {
        // Socket was already gone; room cleanup still continues.
      }
    }
    await this.ctx.storage.deleteAll();
  }
}
