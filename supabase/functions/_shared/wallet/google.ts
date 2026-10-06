// Google Wallet API client: service-account auth, class/object writes and the
// signed "Add to Google Wallet" link.

export interface GoogleConfig {
  issuerId: string;
  serviceAccountEmail: string;
  privateKeyPem: string;
  /** https://walletobjects.googleapis.com/walletobjects/v1 in production. */
  apiBase: string;
  /** https://oauth2.googleapis.com/token in production. */
  tokenUrl: string;
}

const encoder = new TextEncoder();

function base64Url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

const keyCache = new Map<string, CryptoKey>();

async function importKey(pem: string): Promise<CryptoKey> {
  const cached = keyCache.get(pem);
  if (cached) return cached;
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  keyCache.set(pem, key);
  return key;
}

export async function signJwt(claims: Record<string, unknown>, privateKeyPem: string): Promise<string> {
  const unsigned = `${base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${base64Url(JSON.stringify(claims))}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', await importKey(privateKeyPem), encoder.encode(unsigned));
  return `${unsigned}.${base64Url(new Uint8Array(signature))}`;
}

let accessToken: { key: string; token: string; expiresAt: number } | null = null;

async function getAccessToken(config: GoogleConfig): Promise<string> {
  const cacheKey = `${config.serviceAccountEmail}\n${config.tokenUrl}`;
  if (accessToken?.key === cacheKey && accessToken.expiresAt > Date.now() + 60_000) return accessToken.token;
  const now = Math.floor(Date.now() / 1000);
  const assertion = await signJwt({
    iss: config.serviceAccountEmail,
    scope: 'https://www.googleapis.com/auth/wallet_object.issuer',
    aud: config.tokenUrl,
    iat: now,
    exp: now + 3600,
  }, config.privateKeyPem);
  const response = await fetch(config.tokenUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload.access_token) {
    throw new Error(`Google sign-in failed (${response.status}): ${payload.error_description ?? payload.error ?? ''}`);
  }
  accessToken = {
    key: cacheKey,
    token: payload.access_token,
    expiresAt: Date.now() + Number(payload.expires_in ?? 3600) * 1000,
  };
  return accessToken.token;
}

async function call(config: GoogleConfig, method: string, path: string, body?: unknown) {
  const response = await fetch(`${config.apiBase}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${await getAccessToken(config)}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, ok: response.ok, text };
}

function fail(action: string, result: { status: number; text: string }): never {
  let message = result.text.slice(0, 300);
  try { message = JSON.parse(result.text).error?.message ?? message; } catch { /* keep the raw text */ }
  throw new Error(`Google Wallet ${action} failed (${result.status}): ${message}`);
}

/** Creates the resource, or replaces it when it already exists (same id either way). */
async function upsert(config: GoogleConfig, kind: 'genericClass' | 'genericObject', resource: { id: string }) {
  const inserted = await call(config, 'POST', `/${kind}`, resource);
  if (inserted.ok) return;
  if (inserted.status !== 409) fail(`${kind} insert`, inserted);
  const updated = await call(config, 'PUT', `/${kind}/${encodeURIComponent(resource.id)}`, resource);
  if (!updated.ok) fail(`${kind} update`, updated);
}

export const upsertClass = (config: GoogleConfig, resource: { id: string }) => upsert(config, 'genericClass', resource);
export const upsertObject = (config: GoogleConfig, resource: { id: string }) => upsert(config, 'genericObject', resource);

/** Applies the global theme fields to one existing object. Returns false when the object no longer exists. */
export async function patchObject(config: GoogleConfig, objectId: string, fields: Record<string, unknown>): Promise<boolean> {
  const result = await call(config, 'PATCH', `/genericObject/${encodeURIComponent(objectId)}`, fields);
  if (result.status === 404) return false;
  if (!result.ok) fail('object patch', result);
  return true;
}

/** The link the app opens; Google Wallet then offers to save the (already created) object. */
export async function buildSaveUrl(config: GoogleConfig, objectId: string): Promise<string> {
  const jwt = await signJwt({
    iss: config.serviceAccountEmail,
    aud: 'google',
    typ: 'savetowallet',
    iat: Math.floor(Date.now() / 1000),
    origins: [],
    payload: { genericObjects: [{ id: objectId }] },
  }, config.privateKeyPem);
  return `https://pay.google.com/gp/v/save/${jwt}`;
}
