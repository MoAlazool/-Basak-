// Pure parts of the push dispatcher: what is sent to FCM for one outbox row,
// and what FCM's answer means for that row. No network, no environment.

/** One row of claim_push_outbox. */
export interface PushOutboxRow {
  id: string | number;
  notification_id: string;
  token: string;
  platform?: string | null;
  locale?: string | null;
  title: string;
  body: string;
  title_en?: string | null;
  body_en?: string | null;
  data?: Record<string, unknown> | null;
  type?: string | null;
  category: string;
  priority?: string | null;
  badge?: number | null;
  attempts?: number | null;
}

/** One entry of complete_push_outbox(p_results). */
export interface PushOutboxResult {
  id: string | number;
  status: 'accepted' | 'failed' | 'retry' | 'invalid_token';
  message_id?: string;
  error?: string;
}

/** What came back from one send: an HTTP answer, or no answer at all. */
export type SendOutcome =
  | { kind: 'response'; status: number; body: string }
  | { kind: 'network'; timeout: boolean };

export interface MappedOutcome {
  status: PushOutboxResult['status'];
  message_id?: string;
  /** Short machine code, safe to log. */
  code?: string;
  /** Code plus FCM's own message, at most 200 characters, never the token. */
  error?: string;
  /** Our credentials were refused: nothing else can be sent in this invocation. */
  authFailure?: boolean;
}

/** The only keys of a row's `data` that reach the device: ids and the route, never personal data. */
export const DATA_KEYS = ['subscription_id', 'line_id', 'trip_id', 'ride_date', 'route'] as const;

const ERROR_LIMIT = 200;

function text(value: unknown): string | null {
  if (typeof value === 'string') return value.trim() ? value : null;
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  if (typeof value === 'boolean') return String(value);
  return null;
}

/** Arabic unless the device is English and the notification has a complete English version. */
export function localizedText(row: PushOutboxRow): { title: string; body: string } {
  const english = /^en([-_]|$)/i.test((row.locale ?? '').trim());
  const title = text(row.title_en);
  const body = text(row.body_en);
  if (english && title && body) return { title, body };
  return { title: row.title, body: row.body };
}

/** FCM data: every value a string; ids and the route only. */
export function buildData(row: PushOutboxRow): Record<string, string> {
  const source = row.data && typeof row.data === 'object' && !Array.isArray(row.data) ? row.data : {};
  const data: Record<string, string> = {
    notification_id: String(row.notification_id),
    type: text(row.type) ?? text(source.type) ?? row.category,
    category: row.category,
    route: 'notifications',
  };
  for (const key of DATA_KEYS) {
    const value = text(source[key]);
    if (value !== null) data[key] = value;
  }
  return data;
}

/** The body of FCM HTTP v1 `messages:send` for one device. */
export function buildMessage(row: PushOutboxRow) {
  const high = row.priority === 'high';
  const id = String(row.notification_id);
  const aps: Record<string, unknown> = { sound: 'default', 'thread-id': row.category };
  if (typeof row.badge === 'number' && Number.isFinite(row.badge) && row.badge >= 0) aps.badge = Math.trunc(row.badge);
  return {
    message: {
      token: row.token,
      notification: localizedText(row),
      data: buildData(row),
      android: {
        priority: high ? 'HIGH' : 'NORMAL',
        notification: { channel_id: `basak_${row.category}`, tag: id },
      },
      apns: {
        headers: { 'apns-priority': high ? '10' : '5', 'apns-collapse-id': id },
        payload: { aps },
      },
    },
  };
}

function parseJson(body: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(body);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function describe(code: string, message: unknown, token?: string): string {
  let out = typeof message === 'string' && message.trim() ? `${code}: ${message.trim()}` : code;
  if (token) out = out.split(token).join('[token]');
  return out.slice(0, ERROR_LIMIT);
}

/** INVALID_ARGUMENT is about the token (dead device) or about our payload (our bug). */
function refersToToken(error: Record<string, unknown>): boolean {
  if (typeof error.message === 'string' && /registration token|message\.token/i.test(error.message)) return true;
  const details = Array.isArray(error.details) ? error.details : [];
  return details.some((detail) =>
    Array.isArray(detail?.fieldViolations) &&
    detail.fieldViolations.some((violation: { field?: unknown }) =>
      typeof violation?.field === 'string' && /(^|\.)token$/i.test(violation.field)
    )
  );
}

/** Turns FCM's answer into the status the outbox understands. */
export function mapSendOutcome(outcome: SendOutcome, token?: string): MappedOutcome {
  if (outcome.kind === 'network') {
    const code = outcome.timeout ? 'timeout' : 'network_error';
    return { status: 'retry', code, error: code };
  }
  const { status } = outcome;
  const parsed = parseJson(outcome.body);
  if (status >= 200 && status < 300) {
    return { status: 'accepted', message_id: typeof parsed?.name === 'string' ? parsed.name : undefined };
  }

  const error = (parsed?.error && typeof parsed.error === 'object' ? parsed.error : {}) as Record<string, unknown>;
  const details = Array.isArray(error.details) ? error.details : [];
  const fcmCode = details.map((detail) => detail?.errorCode).find((code) => typeof code === 'string') as string | undefined;
  const googleStatus = typeof error.status === 'string' ? error.status : undefined;
  const code = fcmCode ?? googleStatus ?? `HTTP_${status}`;
  const result = (mapped: MappedOutcome['status'], authFailure = false): MappedOutcome => ({
    status: mapped, code, error: describe(code, error.message, token), ...(authFailure ? { authFailure } : {}),
  });

  if (code === 'UNREGISTERED' || code === 'SENDER_ID_MISMATCH') return result('invalid_token');
  // A 404 that FCM itself answered (not a proxy's page) is a token that no longer exists.
  if (status === 404 && googleStatus === 'NOT_FOUND') return result('invalid_token');
  if (code === 'INVALID_ARGUMENT') return result(refersToToken(error) ? 'invalid_token' : 'failed');
  // The APNs key in Firebase is missing or wrong: iOS only, Android still goes out.
  if (code === 'THIRD_PARTY_AUTH_ERROR') return result('retry');
  if (status === 401 || status === 403 || code === 'UNAUTHENTICATED' || code === 'PERMISSION_DENIED') {
    return result('retry', true);
  }
  if (status === 429 || status >= 500 || code === 'UNAVAILABLE' || code === 'INTERNAL' || code === 'QUOTA_EXCEEDED') {
    return result('retry');
  }
  return result('failed');
}

/** Compares without stopping at the first different byte, so timing says nothing about the secret. */
export function secretMatches(expected: string | null | undefined, given: string | null | undefined): boolean {
  if (!expected || !given) return false;
  const encoder = new TextEncoder();
  const a = encoder.encode(expected);
  const b = encoder.encode(given);
  let diff = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}
