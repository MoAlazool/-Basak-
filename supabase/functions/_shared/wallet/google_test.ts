// deno test supabase/functions/_shared/wallet/
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { upsertClass, upsertObject } from './google.ts';
import { fakeGoogleWallet, testGoogleConfig } from './testing.ts';

Deno.test('an object believed to exist is replaced with one request', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet({ existing: ['issuer.card'] });
  try {
    await upsertObject(config, { id: 'issuer.card' }, true);
    assertEquals(google.requests(), ['PUT genericObject']);
  } finally { google.restore(); }
});

Deno.test('a new object is created with one request', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet();
  try {
    await upsertObject(config, { id: 'issuer.card' }, false);
    assertEquals(google.requests(), ['POST genericObject']);
    assert(google.stored.has('issuer.card'));
  } finally { google.restore(); }
});

Deno.test('a wrong belief either way is corrected by the other request', async () => {
  const config = await testGoogleConfig();
  const missing = fakeGoogleWallet();
  try {
    await upsertObject(config, { id: 'issuer.card' }, true);
    assertEquals(missing.requests(), ['PUT genericObject', 'POST genericObject']);
    assert(missing.stored.has('issuer.card'));
  } finally { missing.restore(); }

  const present = fakeGoogleWallet({ existing: ['issuer.card'] });
  try {
    await upsertObject(config, { id: 'issuer.card' });
    assertEquals(present.requests(), ['POST genericObject', 'PUT genericObject']);
  } finally { present.restore(); }
});

Deno.test('an object created by someone else between the two requests is still replaced', async () => {
  const config = await testGoogleConfig();
  let posts = 0;
  const google = fakeGoogleWallet({
    refuse: (call) => {
      if (call.method === 'POST' && ++posts === 1) {
        google.stored.add(call.id);
        return Response.json({ error: { message: 'already exists' } }, { status: 409 });
      }
      return null;
    },
  });
  try {
    await upsertObject(config, { id: 'issuer.card' }, true);
    assertEquals(google.requests(), ['PUT genericObject', 'POST genericObject', 'PUT genericObject']);
  } finally { google.restore(); }
});

Deno.test('who may save the card is set when the class is created and never sent again', async () => {
  const config = await testGoogleConfig();
  const resource = { id: 'issuer.class', multipleDevicesAndHoldersAllowedStatus: 'ONE_USER_ALL_DEVICES', note: 'v2' };
  const google = fakeGoogleWallet();
  try {
    await upsertClass(config, resource, true);
    await upsertClass(config, resource, true);
    assertEquals(google.requests(), ['PATCH genericClass', 'POST genericClass', 'PATCH genericClass']);
    assertEquals(google.calls[1].body?.multipleDevicesAndHoldersAllowedStatus, 'ONE_USER_ALL_DEVICES');
    // Google refuses to change it once anyone has saved a card (400 on every update).
    assertEquals(google.calls[2].body, { id: 'issuer.class', note: 'v2' });
  } finally { google.restore(); }
});

Deno.test("Google's refusal is reported with its status and message", async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet({
    existing: ['issuer.class'],
    refuse: () => Response.json({ error: { message: 'Invalid resource' } }, { status: 400 }),
  });
  try {
    const error = await assertRejects(() => upsertClass(config, { id: 'issuer.class' }, true), Error);
    assertEquals(error.message, 'Google Wallet genericClass update failed (400): Invalid resource');
    assertEquals(google.requests(), ['PATCH genericClass']);
  } finally { google.restore(); }
});

Deno.test('requests that start together share one sign-in, and the token is reused afterwards', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet();
  try {
    await Promise.all(['a', 'b', 'c', 'd'].map((id) => upsertObject(config, { id })));
    await upsertObject(config, { id: 'e' });
    assertEquals(google.tokenRequests(), 1);
    assertEquals(google.calls.length, 5);
  } finally { google.restore(); }
});

Deno.test('a failed sign-in is not remembered: the next request signs in again', async () => {
  const config = await testGoogleConfig();
  let attempts = 0;
  const google = fakeGoogleWallet({
    token: () => ++attempts === 1
      ? Response.json({ error: 'invalid_grant', error_description: 'bad key' }, { status: 400 })
      : Response.json({ access_token: 'access-1', expires_in: 3600 }),
  });
  try {
    const error = await assertRejects(() => upsertObject(config, { id: 'a' }), Error);
    assertEquals(error.message, 'Google sign-in failed (400): bad key');
    await upsertObject(config, { id: 'a' });
    assertEquals(google.tokenRequests(), 2);
  } finally { google.restore(); }
});
