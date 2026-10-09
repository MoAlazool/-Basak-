// deno test supabase/functions/_shared/wallet/
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { fakeSupabase, type Handlers } from '../testing/fake_supabase.ts';
import type { PushResult } from './apple.ts';
import { type AppleConfig, deliverGoogle, loadAppleDevices, markDelivered, pushAppleDevices } from './runtime.ts';
import { fakeGoogleWallet, fakeImaging, STUDENT, testCard, testGoogleConfig } from './testing.ts';

const avatar: Handlers['storage'] = (_bucket, method) => method === 'download' ? { data: new Blob(['photo-a']) } : {};
const photoLink = /^https:\/\/project\.test\/functions\/v1\/wallet-photo\/([0-9a-f]{64})\.jpg$/;
// deno-lint-ignore no-explicit-any
const photoOf = (object: any): string | undefined => object.imageModulesData[0]?.mainImage.sourceUri.uri;

Deno.test('an installed card with the same photo: no download, no database write, one request to Google', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet({ existing: [`${config.issuerId}.basak_student_card`, `${config.issuerId}.student_${STUDENT}`] });
  const fake = fakeSupabase();
  try {
    const card = testCard({ photo: { path: `${STUDENT}/a.jpg`, version: 'v1' } });
    await deliverGoogle(fake.client, config, card, { photo_token: 'a'.repeat(64), photo_version: 'v1', content_hash: 'old', dirty_at: 't' });
    assertEquals(fake.log, []);
    assertEquals(google.requests(), ['PATCH genericClass', 'PUT genericObject']);
    // The link Google already has keeps working.
    assertEquals(photoOf(google.calls[1].body), `https://project.test/functions/v1/wallet-photo/${'a'.repeat(64)}.jpg`);
  } finally { google.restore(); }
});

Deno.test('a first card: the row is created with its photo token before Google is told the link', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet();
  const pictures = fakeImaging();
  const fake = fakeSupabase({ storage: avatar });
  try {
    const card = testCard({ photo: { path: `${STUDENT}/first.png`, version: 'v1' } });
    await deliverGoogle(fake.client, config, card, null);
    assertEquals(fake.log, ['storage student-avatars.download', 'upsert wallet_passes']);
    const row = fake.db[0].values as Record<string, string>;
    assertEquals([row.student_id, row.platform, row.photo_version], [STUDENT, 'google', 'v1']);
    assertEquals(fake.db[0].options, { onConflict: 'student_id,platform' });
    // First time ever: the class and the object are both created.
    assertEquals(google.requests(), ['PATCH genericClass', 'POST genericClass', 'POST genericObject']);
    const object = google.calls[2].body!;
    assertEquals(photoOf(object)?.match(photoLink)?.[1], row.photo_token);
    assertEquals(object.id, `${config.issuerId}.student_${STUDENT}`);
    // Saved first, sent second: the link works by the time Google fetches it.
    assertEquals(fake.timeline.indexOf('end upsert wallet_passes') >= 0 && google.calls[2].method === 'POST', true);
  } finally { google.restore(); pictures.restore(); }
});

Deno.test('a replaced photo gets a new token (the old link dies); a removed photo loses its token', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet();
  const state = { photo_token: 'a'.repeat(64), photo_version: 'v1', content_hash: 'old', dirty_at: null };
  const pictures = fakeImaging();
  try {
    const replaced = fakeSupabase({ storage: avatar });
    await deliverGoogle(replaced.client, config, testCard({ photo: { path: `${STUDENT}/second.png`, version: 'v2' } }), state);
    assertEquals(replaced.log, ['storage student-avatars.download', 'update wallet_passes']);
    const saved = replaced.db[0].values as { photo_token: string; photo_version: string };
    assert(/^[0-9a-f]{64}$/.test(saved.photo_token) && saved.photo_token !== state.photo_token);
    assertEquals(saved.photo_version, 'v2');
    assertEquals(replaced.db[0].filters, { student_id: STUDENT, platform: 'google' });

    const removed = fakeSupabase();
    await deliverGoogle(removed.client, config, testCard(), state);
    assertEquals(removed.log, ['update wallet_passes']);
    assertEquals(removed.db[0].values, { photo_token: null, photo_version: null });
    assertEquals(photoOf(google.calls.at(-1)!.body), undefined);
  } finally { google.restore(); pictures.restore(); }
});

Deno.test('a photo that cannot be shown gives a card without one', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet();
  const fake = fakeSupabase({ storage: () => ({ data: new Blob(['not an image']) }) });
  const pictures = fakeImaging();
  const quiet = console.warn;
  console.warn = () => {};
  try {
    await deliverGoogle(fake.client, config, testCard({ photo: { path: `${STUDENT}/broken.png`, version: 'v1' } }), null);
    assertEquals((fake.db[0].values as Record<string, unknown>).photo_token, null);
    assertEquals(photoOf(google.calls.at(-1)!.body), undefined);
  } finally { console.warn = quiet; google.restore(); pictures.restore(); }
});

Deno.test('a batch delivered at once writes the shared class once and signs in once', async () => {
  const config = await testGoogleConfig();
  const google = fakeGoogleWallet({ existing: [`${config.issuerId}.basak_student_card`] });
  const fake = fakeSupabase();
  try {
    const ids = Array.from({ length: 6 }, (_, index) => `5f0c2f6e-3f0a-4c58-9d55-0d2b7f1f0a2${index}`);
    await Promise.all(ids.map((id) => {
      const card = testCard();
      card.content.student = { ...card.content.student, id, qr_code_value: id };
      return deliverGoogle(fake.client, config, card, { photo_token: null, photo_version: null, content_hash: 'old', dirty_at: 't' });
    }));
    assertEquals(google.requests().filter((request) => request.endsWith('genericClass')), ['PATCH genericClass']);
    assertEquals(google.requests().filter((request) => request === 'PUT genericObject').length, 6);
    assertEquals(google.tokenRequests(), 1);
  } finally { google.restore(); }
});

Deno.test('when Google refuses the class nothing is remembered: the next delivery writes it again', async () => {
  const config = await testGoogleConfig();
  let refusals = 1;
  const google = fakeGoogleWallet({
    refuse: (call) => call.kind === 'genericClass' && refusals-- > 0 ? Response.json({ error: { message: 'down' } }, { status: 503 }) : null,
  });
  try {
    await assertRejects(() => deliverGoogle(fakeSupabase().client, config, testCard(), null));
    await deliverGoogle(fakeSupabase().client, config, testCard(), null);
    assert(google.stored.has(`${config.issuerId}.basak_student_card`));
  } finally { google.restore(); }
});

Deno.test('a delivered card leaves the queue in the same write', async () => {
  const fake = fakeSupabase({ db: () => ({ data: [{ student_id: STUDENT }] }) });
  await markDelivered(fake.client, STUDENT, 'google', testCard(), '2026-10-09T10:00:00+00:00');
  assertEquals(fake.log, ['update wallet_passes']);
  const values = fake.db[0].values as Record<string, unknown>;
  assertEquals([values.content_hash, values.dirty_at, values.claimed_at, values.last_error], ['hash-now', null, null, null]);
  assertEquals(fake.db[0].filters, { student_id: STUDENT, platform: 'google', dirty_at: '2026-10-09T10:00:00+00:00' });
});

Deno.test('a card that changed again during delivery is recorded but stays queued', async () => {
  const fake = fakeSupabase({ db: () => ({ data: [] }) });
  await markDelivered(fake.client, STUDENT, 'apple', testCard(), '2026-10-09T10:00:00+00:00');
  assertEquals(fake.log, ['update wallet_passes', 'update wallet_passes']);
  assertEquals('dirty_at' in (fake.db[1].values as Record<string, unknown>), false);
  assertEquals(fake.db[1].filters, { student_id: STUDENT, platform: 'apple' });
});

Deno.test('a card that was not queued is recorded with one write that never touches the queue', async () => {
  const fake = fakeSupabase();
  await markDelivered(fake.client, STUDENT, 'google', testCard(), null);
  assertEquals(fake.log, ['update wallet_passes']);
  assertEquals('dirty_at' in (fake.db[0].values as Record<string, unknown>), false);
});

Deno.test('a failed write is an error, so the card stays claimed and is retried', async () => {
  const fake = fakeSupabase({ db: () => ({ error: { message: 'timeout' } }) });
  await assertRejects(() => markDelivered(fake.client, STUDENT, 'google', testCard(), 't'));
});

Deno.test("the devices of a batch's Apple passes come from one query", async () => {
  const fake = fakeSupabase({
    db: () => ({
      data: [
        { student_id: 's1', device_library_id: 'd1', wallet_apple_devices: { push_token: 'p1' } },
        { student_id: 's1', device_library_id: 'd2', wallet_apple_devices: { push_token: 'p2' } },
        { student_id: 's2', device_library_id: 'd3', wallet_apple_devices: null },
      ],
    }),
  });
  const devices = await loadAppleDevices(fake.client, ['s1', 's2', 's3']);
  assertEquals(fake.log, ['select wallet_apple_registrations']);
  assertEquals(fake.db[0].filters, { 'in:student_id': ['s1', 's2', 's3'] });
  assertEquals(devices.get('s1')?.map((device) => device.push_token), ['p1', 'p2']);
  assertEquals([devices.get('s2'), devices.get('s3')], [undefined, undefined]);
  // No Apple pass in the batch: nothing is asked.
  assertEquals((await loadAppleDevices(fake.client, [])).size, 0);
  assertEquals(fake.log.length, 1);
});

Deno.test('devices are pushed at once; dead ones are forgotten in one delete; failures are counted', async () => {
  const fake = fakeSupabase();
  const events: string[] = [];
  const send = async (pushToken: string): Promise<PushResult> => {
    events.push(`start ${pushToken}`);
    await new Promise((resolve) => setTimeout(resolve, 1));
    events.push(`end ${pushToken}`);
    if (pushToken.startsWith('dead')) return { ok: false, invalidToken: true, status: 410, reason: 'Unregistered' };
    if (pushToken.startsWith('busy')) return { ok: false, invalidToken: false, status: 503, reason: 'ServiceUnavailable' };
    return { ok: true, invalidToken: false, status: 200, reason: '' };
  };
  const quiet = console.warn;
  console.warn = () => {};
  try {
    const failures = await pushAppleDevices(fake.client, { push: {} } as AppleConfig, [
      { device_library_id: 'd1', push_token: 'good-1' },
      { device_library_id: 'd2', push_token: 'dead-2' },
      { device_library_id: 'd3', push_token: 'busy-3' },
      { device_library_id: 'd4', push_token: 'dead-4' },
    ], send);
    assertEquals(failures, 1);
    assertEquals(events.slice(0, 4), ['start good-1', 'start dead-2', 'start busy-3', 'start dead-4']);
    assertEquals(fake.log, ['delete wallet_apple_devices']);
    assertEquals(fake.db[0].filters, { 'in:device_library_id': ['d2', 'd4'] });
  } finally { console.warn = quiet; }

  const none = fakeSupabase();
  assertEquals(await pushAppleDevices(none.client, { push: {} } as AppleConfig, [], send), 0);
  assertEquals(none.log, []);
});
