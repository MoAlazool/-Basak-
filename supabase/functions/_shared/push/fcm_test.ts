// deno test supabase/functions/_shared/push/
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { FcmAuthError, getAccessToken, loadCredentials, resetAccessToken, sendMessage } from './fcm.ts';
import { fakeGoogle, fakeServiceAccountJson } from './testing.ts';

function decodeJwtPart(part: string) {
  return JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/')));
}

Deno.test('credentials: missing, broken or incomplete key files mean "not configured"', async () => {
  assertEquals(await loadCredentials(undefined), null);
  assertEquals(await loadCredentials('   '), null);
  assertEquals(await loadCredentials('{not json'), null);
  assertEquals(await loadCredentials('"a string"'), null);
  assertEquals(await loadCredentials(await fakeServiceAccountJson({ project_id: '' })), null);
  assertEquals(await loadCredentials(await fakeServiceAccountJson({ client_email: undefined })), null);
  assertEquals(await loadCredentials(await fakeServiceAccountJson({ private_key: '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----' })), null);
});

Deno.test('credentials: a whole key file is read, with escaped line breaks tolerated', async () => {
  const raw = await fakeServiceAccountJson();
  const credentials = await loadCredentials(raw);
  assertEquals(credentials?.projectId, 'basak-test');
  assertEquals(credentials?.clientEmail, 'push@basak-test.iam.gserviceaccount.com');
  assertEquals(credentials?.tokenUrl, 'https://oauth2.test/token');
  assertEquals(credentials?.apiBase, 'https://fcm.googleapis.com');

  const key = JSON.parse(raw);
  const escaped = JSON.stringify({ ...key, private_key: key.private_key.replace(/\n/g, '\\n'), token_uri: undefined });
  const other = await loadCredentials(escaped, 'http://127.0.0.1:9099/');
  assertEquals(other?.tokenUrl, 'https://oauth2.googleapis.com/token');
  assertEquals(other?.apiBase, 'http://127.0.0.1:9099');
});

Deno.test('the access token is requested with the messaging scope and reused until it is about to expire', async () => {
  resetAccessToken();
  const credentials = (await loadCredentials(await fakeServiceAccountJson()))!;
  let issued = 0;
  const google = fakeGoogle(() => Response.json({}), () => Response.json({ access_token: `access-${++issued}`, expires_in: 3600 }));
  let clock = 1_800_000_000_000;
  const now = () => clock;

  assertEquals(await getAccessToken(credentials, google.fetch, now), 'access-1');
  assertEquals(await getAccessToken(credentials, google.fetch, now), 'access-1');
  assertEquals(google.tokenCalls.length, 1);

  const form = new URLSearchParams(google.tokenCalls[0].body);
  assertEquals(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  const [header, claims] = form.get('assertion')!.split('.').map((part, index) => (index < 2 ? decodeJwtPart(part) : part));
  assertEquals(header, { alg: 'RS256', typ: 'JWT' });
  assertEquals(claims.iss, credentials.clientEmail);
  assertEquals(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  assertEquals(claims.aud, 'https://oauth2.test/token');
  assertEquals(claims.exp - claims.iat, 3600);

  clock += 3_590_000; // ten seconds before expiry
  assertEquals(await getAccessToken(credentials, google.fetch, now), 'access-2');
  assertEquals(google.tokenCalls.length, 2);
  resetAccessToken();
});

Deno.test('a refused or unreachable sign-in is an FcmAuthError with a short code', async () => {
  resetAccessToken();
  const credentials = (await loadCredentials(await fakeServiceAccountJson()))!;
  const refused = fakeGoogle(() => Response.json({}), () => Response.json({ error: 'invalid_grant', error_description: 'Invalid JWT Signature.' }, { status: 400 }));
  const error = await assertRejects(() => getAccessToken(credentials, refused.fetch), FcmAuthError);
  assertEquals(error.code, 'token_invalid_grant');

  const down = fakeGoogle(() => Response.json({}), () => { throw new TypeError('connection refused'); });
  assertEquals((await assertRejects(() => getAccessToken(credentials, down.fetch), FcmAuthError)).code, 'token_network_error');

  const html = fakeGoogle(() => Response.json({}), () => new Response('<html>', { status: 502 }));
  assertEquals((await assertRejects(() => getAccessToken(credentials, html.fetch), FcmAuthError)).code, 'token_http_502');
});

Deno.test('send posts to the project endpoint with the bearer token and returns the raw answer', async () => {
  const credentials = (await loadCredentials(await fakeServiceAccountJson()))!;
  const google = fakeGoogle(() => Response.json({ name: 'projects/basak-test/messages/1' }));
  const outcome = await sendMessage(credentials, 'access-1', { message: { token: 't' } }, google.fetch);
  assertEquals(outcome, { kind: 'response', status: 200, body: '{"name":"projects/basak-test/messages/1"}' });
  assertEquals(google.sendCalls[0].url, 'https://fcm.googleapis.com/v1/projects/basak-test/messages:send');
  assertEquals(google.sendCalls[0].headers.authorization, 'Bearer access-1');
  assertEquals(google.sendCalls[0].headers['content-type'], 'application/json');
});

Deno.test('send never throws: a network error and a timeout are outcomes', async () => {
  const credentials = (await loadCredentials(await fakeServiceAccountJson()))!;
  const down = fakeGoogle(() => { throw new TypeError('connection reset'); });
  assertEquals(await sendMessage(credentials, 'a', {}, down.fetch), { kind: 'network', timeout: false });

  const slow = fakeGoogle(() => 'hang');
  const started = Date.now();
  assertEquals(await sendMessage(credentials, 'a', {}, slow.fetch, 30), { kind: 'network', timeout: true });
  assert(Date.now() - started < 2_000);
});
