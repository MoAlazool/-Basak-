// Test helpers only (imported by *_test.ts): a throwaway service account and a fake Google.

/** A Firebase-shaped key file with a freshly generated private key. */
export async function fakeServiceAccountJson(overrides: Record<string, unknown> = {}): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify'],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let binary = '';
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).replace(/(.{64})/g, '$1\n')}\n-----END PRIVATE KEY-----\n`;
  return JSON.stringify({
    type: 'service_account', project_id: 'basak-test', client_email: 'push@basak-test.iam.gserviceaccount.com',
    private_key: pem, token_uri: 'https://oauth2.test/token', ...overrides,
  });
}

export interface FakeCall {
  url: string;
  headers: Record<string, string>;
  body: string;
}

/**
 * A fetch that answers the token endpoint itself and asks `send` for every FCM
 * request. `send` may return a Response, throw (network error), or return
 * 'hang' (answers only when the request is aborted).
 */
export function fakeGoogle(
  // deno-lint-ignore no-explicit-any
  send: (message: any, call: FakeCall) => Response | 'hang' | Promise<Response | 'hang'>,
  token: () => Response = () => Response.json({ access_token: 'access-1', expires_in: 3600 }),
) {
  const tokenCalls: FakeCall[] = [];
  const sendCalls: FakeCall[] = [];
  const fetch = async (url: string, init?: RequestInit): Promise<Response> => {
    const call = { url, headers: Object.fromEntries(new Headers(init?.headers).entries()), body: String(init?.body ?? '') };
    if (url.endsWith('/token')) {
      tokenCalls.push(call);
      return token();
    }
    sendCalls.push(call);
    const answer = await send(JSON.parse(call.body).message, call);
    if (answer !== 'hang') return answer;
    return new Promise<Response>((_, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
    });
  };
  return { fetch, tokenCalls, sendCalls };
}

/** FCM's error body. */
export function fcmError(status: number, googleStatus: string, errorCode?: string, message = 'refused'): Response {
  return Response.json({
    error: {
      code: status, message, status: googleStatus,
      details: errorCode ? [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode }] : [],
    },
  }, { status });
}
