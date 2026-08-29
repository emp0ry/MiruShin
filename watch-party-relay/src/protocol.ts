import type { Env, RelayLimits, RelayMessage } from "./types";

export const SERVICE = "mirushin-watch-party-relay";
export const PROTOCOL = "mirushin-watch-party";
export const PROTOCOL_VERSION = 1;

export const HOST_EVENT_TYPES = new Set([
  "play",
  "pause",
  "seek",
  "speed",
  "sourceChanged",
  "episodeChanged",
  "positionSync",
  "stateSnapshot",
  "permissionsChanged",
]);

export const GUEST_EVENT_TYPES = new Set([
  "play",
  "pause",
  "seek",
  "speed",
  "streamChangeRequested",
  "helloRequest",
]);

export function limits(env: Env): RelayLimits {
  return {
    maxParticipants: bounded(env.MAX_PARTICIPANTS_PER_ROOM, 50, 2, 500),
    maxMessageBytes: bounded(env.MAX_MESSAGE_BYTES, 65_536, 1_024, 1_048_576),
    maxMessagesPerMinute: bounded(
      env.MAX_MESSAGES_PER_MINUTE,
      180,
      30,
      10_000,
    ),
    roomIdleTimeoutMs:
      bounded(env.ROOM_IDLE_TIMEOUT_SECONDS, 21_600, 60, 604_800) * 1_000,
    hostReconnectTimeoutMs:
      bounded(env.HOST_RECONNECT_TIMEOUT_SECONDS, 60, 5, 3_600) * 1_000,
  };
}

export function parseMessage(raw: string): RelayMessage | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!isRecord(value) || !Number.isInteger(value.v) || typeof value.type !== "string") {
    return null;
  }
  return {
    v: value.v as number,
    type: value.type,
    data: isRecord(value.data) ? value.data : {},
  };
}

export function validWatchPartyEvent(value: unknown): value is Record<string, unknown> {
  if (!isRecord(value) || typeof value.type !== "string") return false;
  if (!Number.isFinite(value.sentAt) || !Number.isFinite(value.positionMs)) return false;
  if (!Number.isFinite(value.speed) || value.speed as number < 0.25 || value.speed as number > 4) return false;
  return typeof value.isPlaying === "boolean";
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function errorMessage(
  code: string,
  message: string,
  fatal = false,
): string {
  return JSON.stringify({
    v: PROTOCOL_VERSION,
    type: "error",
    data: { code, message, fatal },
  });
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return bytesToBase64Url(new Uint8Array(digest));
}

export function randomToken(bytes: number): string {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return bytesToBase64Url(value);
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function bounded(
  raw: string | undefined,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number.parseInt(raw ?? "", 10);
  return Number.isFinite(parsed)
    ? Math.max(minimum, Math.min(maximum, parsed))
    : fallback;
}
