// Test helpers only (imported by *_test.ts): a fake Google Wallet in place of
// the real one, and a throwaway configuration that points at it.
import { fakeServiceAccountJson } from '../push/testing.ts';
import type { GoogleConfig } from './google.ts';
import type { CardContent } from './pass_data.ts';
import { imaging } from './photo.ts';

let privateKey: Promise<string> | undefined;
let issuers = 0;

/** A configuration with its own issuer and service account, so no test sees another's cached token or class. */
export async function testGoogleConfig(): Promise<GoogleConfig> {
  privateKey ??= fakeServiceAccountJson().then((json) => JSON.parse(json).private_key as string);
  const n = ++issuers;
  return {
    issuerId: `issuer${n}`,
    serviceAccountEmail: `wallet${n}@basak-test.iam.gserviceaccount.com`,
    privateKeyPem: await privateKey,
    apiBase: 'https://wallet.test/v1',
    tokenUrl: 'https://oauth2.test/token',
    publicBaseUrl: 'https://project.test',
  };
}

export interface WalletCall { method: string; kind: string; id: string; body: Record<string, unknown> | null }

/**
 * Replaces the global fetch with a Google that keeps classes and objects in
 * memory and answers as the real API does: POST of an existing id is 409, PUT
 * of a missing one is 404. Always call restore() (try/finally).
 */
export function fakeGoogleWallet(options: { existing?: string[]; token?: () => Response; refuse?: (call: WalletCall) => Response | null } = {}) {
  const stored = new Set(options.existing ?? []);
  const calls: WalletCall[] = [];
  let tokenRequests = 0;
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    await new Promise((resolve) => setTimeout(resolve, 0));
    const url = String(input);
    if (url.endsWith('/token')) {
      tokenRequests += 1;
      return options.token?.() ?? Response.json({ access_token: 'access-1', expires_in: 3600 });
    }
    const [, kind, rawId] = url.match(/\/v1\/(genericClass|genericObject)(?:\/(.+))?$/) ?? [];
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    const id = rawId ? decodeURIComponent(rawId) : String(body?.id);
    const call = { method: String(init?.method), kind, id, body };
    calls.push(call);
    if (new Headers(init?.headers).get('authorization') !== 'Bearer access-1') {
      return Response.json({ error: { message: 'unauthenticated' } }, { status: 401 });
    }
    const refused = options.refuse?.(call);
    if (refused) return refused;
    if (call.method === 'POST') {
      if (stored.has(id)) return Response.json({ error: { message: 'already exists' } }, { status: 409 });
      stored.add(id);
      return Response.json(body);
    }
    if (!stored.has(id)) return Response.json({ error: { message: 'not found' } }, { status: 404 });
    return Response.json(body);
  }) as typeof fetch;
  return {
    calls,
    stored,
    /** "PUT genericObject", ... in order. */
    requests: () => calls.map((call) => `${call.method} ${call.kind}`),
    tokenRequests: () => tokenRequests,
    restore: () => { globalThis.fetch = realFetch; },
  };
}

export const STUDENT = '5f0c2f6e-3f0a-4c58-9d55-0d2b7f1f0a11';

export function testCard(overrides: Partial<CardContent> = {}) {
  const content: CardContent = {
    student: { id: STUDENT, full_name: 'سارة أحمد علي', qr_code_value: STUDENT, university: 'جامعة القاهرة', college: null },
    photo: null,
    company: { id: 'cccccccc-0000-4000-8000-000000000001', name: 'شركة النقل', logo_path: null, contact_phone: null, contact_label: null },
    theme: { background_color: '#00658D', foreground_color: '#FFFFFF', label_color: '#D6EEF9', card_title: null, banner_path: null, revision: 1 },
    route: null,
    ...overrides,
  };
  return { content, hash: 'hash-now' };
}

/**
 * Replaces the picture work with one that needs no decoder: any bytes starting
 * with "photo" are a picture, anything else is not. The fake PNG and JPEG say
 * what was asked for, e.g. "png 90 of photo-a". Always call restore().
 */
export function fakeImaging() {
  const real = imaging.square;
  const text = new TextEncoder();
  let decoded = 0;
  imaging.square = (original: Uint8Array) => {
    decoded += 1;
    const name = new TextDecoder().decode(original);
    if (!name.startsWith('photo')) return Promise.reject(new Error('not a still image'));
    return Promise.resolve({
      png: (side: number) => Promise.resolve(text.encode(`png ${side} of ${name}`)),
      jpeg: () => Promise.resolve(text.encode(`jpeg of ${name}`)),
    });
  };
  return { decoded: () => decoded, restore: () => { imaging.square = real; } };
}
