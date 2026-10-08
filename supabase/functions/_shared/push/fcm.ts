// FCM HTTP v1 client: service-account sign-in and sending one message.
// iOS goes through FCM too (the APNs key lives in Firebase), so there is no
// APNs secret here.
import { signJwt } from '../wallet/google.ts';
import type { SendOutcome } from './message.ts';

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface FcmCredentials {
  projectId: string;
  clientEmail: string;
  privateKeyPem: string;
  /** https://oauth2.googleapis.com/token in production. */
  tokenUrl: string;
  /** https://fcm.googleapis.com in production. */
  apiBase: string;
}

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const DEFAULT_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const DEFAULT_API_BASE = 'https://fcm.googleapis.com';

/** Google refused our credentials, or could not be asked. `code` is safe to log. */
export class FcmAuthError extends Error {
  constructor(public code: string) {
    super(code);
  }
}

/**
 * Reads the Firebase service-account key file (pasted whole into a secret).
 * null when it is missing, not JSON, incomplete, or its private key is unusable.
 */
export async function loadCredentials(raw: string | null | undefined, apiBase?: string | null): Promise<FcmCredentials | null> {
  const value = raw?.trim();
  if (!value) return null;
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(value);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== 'object') return null;
  const field = (name: string) => (typeof parsed[name] === 'string' ? (parsed[name] as string).trim() : '');
  const projectId = field('project_id');
  const clientEmail = field('client_email');
  // Some shells store the key's line breaks as a literal "\n".
  const privateKeyPem = field('private_key').replace(/\\n/g, '\n');
  if (!projectId || !clientEmail || !privateKeyPem) return null;
  try {
    await signJwt({ probe: true }, privateKeyPem);
  } catch {
    return null;
  }
  return {
    projectId, clientEmail, privateKeyPem,
    tokenUrl: field('token_uri') || DEFAULT_TOKEN_URL,
    apiBase: (apiBase?.trim() || DEFAULT_API_BASE).replace(/\/+$/, ''),
  };
}

type FetchResult = { failed: false; status: number; ok: boolean; body: string } | { failed: true; timeout: boolean };

async function fetchWithTimeout(fetchFn: FetchLike, url: string, init: RequestInit, timeoutMs: number): Promise<FetchResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchFn(url, { ...init, signal: controller.signal });
    // The body is read under the same timer.
    return { failed: false, status: response.status, ok: response.ok, body: await response.text() };
  } catch {
    return { failed: true, timeout: controller.signal.aborted };
  } finally {
    clearTimeout(timer);
  }
}

let cached: { key: string; token: string; expiresAt: number } | null = null;

/** Forgets the cached access token (it was refused, or a test starts clean). */
export function resetAccessToken() {
  cached = null;
}

/** An OAuth access token for FCM, kept in the module until a minute before it expires. */
export async function getAccessToken(
  credentials: FcmCredentials, fetchFn: FetchLike, now: () => number = Date.now, timeoutMs = 10_000,
): Promise<string> {
  const key = `${credentials.clientEmail}\n${credentials.tokenUrl}`;
  if (cached?.key === key && cached.expiresAt > now() + 60_000) return cached.token;
  const issued = Math.floor(now() / 1000);
  const assertion = await signJwt({
    iss: credentials.clientEmail, scope: SCOPE, aud: credentials.tokenUrl, iat: issued, exp: issued + 3600,
  }, credentials.privateKeyPem);
  const result = await fetchWithTimeout(fetchFn, credentials.tokenUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
  }, timeoutMs);
  if (result.failed) throw new FcmAuthError(result.timeout ? 'token_timeout' : 'token_network_error');
  let payload: Record<string, unknown> = {};
  try { payload = JSON.parse(result.body) ?? {}; } catch { /* not JSON: reported by status */ }
  if (!result.ok || typeof payload.access_token !== 'string' || !payload.access_token) {
    const reason = typeof payload.error === 'string' ? payload.error : `http_${result.status}`;
    throw new FcmAuthError(`token_${reason}`.slice(0, 80));
  }
  cached = { key, token: payload.access_token, expiresAt: now() + Number(payload.expires_in ?? 3600) * 1000 };
  return cached.token;
}

/** Sends one message. Never throws: no answer is an outcome too. */
export async function sendMessage(
  credentials: FcmCredentials, accessToken: string, payload: unknown, fetchFn: FetchLike, timeoutMs = 10_000,
): Promise<SendOutcome> {
  const url = `${credentials.apiBase}/v1/projects/${encodeURIComponent(credentials.projectId)}/messages:send`;
  const result = await fetchWithTimeout(fetchFn, url, {
    method: 'POST',
    headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  }, timeoutMs);
  if (result.failed) return { kind: 'network', timeout: result.timeout };
  return { kind: 'response', status: result.status, body: result.body };
}
