export interface Env {
  ROOMS: DurableObjectNamespace;
  MAX_PARTICIPANTS_PER_ROOM?: string;
  MAX_MESSAGE_BYTES?: string;
  MAX_MESSAGES_PER_MINUTE?: string;
  ROOM_IDLE_TIMEOUT_SECONDS?: string;
  HOST_RECONNECT_TIMEOUT_SECONDS?: string;
}

export type ParticipantRole = "host" | "guest";

export interface RoomRecord {
  hostTokenHash: string;
  joinTokenHash: string;
  createdAt: number;
  lastActivityAt: number;
  hostReconnectDeadline?: number;
  closed?: boolean;
}

export interface SocketAttachment {
  authenticated: boolean;
  acceptedAt?: number;
  role?: ParticipantRole;
  participantId?: string;
  sessionId?: string;
  connectedAt?: number;
  rateWindowStartedAt: number;
  rateWindowMessages: number;
}

export interface PublicParticipant {
  participantId: string;
  role: ParticipantRole;
  connected: boolean;
  connectedAt: string;
}

export interface RelayLimits {
  maxParticipants: number;
  maxMessageBytes: number;
  maxMessagesPerMinute: number;
  roomIdleTimeoutMs: number;
  hostReconnectTimeoutMs: number;
}

export interface RelayMessage {
  v: number;
  type: string;
  data: Record<string, unknown>;
}
