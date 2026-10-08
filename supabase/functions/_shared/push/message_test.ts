// deno test supabase/functions/_shared/push/
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { buildData, buildMessage, localizedText, mapSendOutcome, type PushOutboxRow, secretMatches } from './message.ts';

const TOKEN = 'fcm-token-AAAA:bbbb_cccc';
const row: PushOutboxRow = {
  id: 'o0000000-0000-0000-0000-000000000001',
  notification_id: 'n0000000-0000-0000-0000-000000000001',
  token: TOKEN, platform: 'android', locale: 'ar',
  title: 'تأخير الرحلة', body: 'الأتوبيس متأخر 10 دقائق',
  title_en: 'Trip delayed', body_en: 'The bus is 10 minutes late',
  type: 'transport.delay', category: 'transport', priority: 'high', badge: 3, attempts: 0,
  data: { route: 'home', line_id: 'l0000000-0000-0000-0000-000000000001', ride_date: '2026-11-02' },
};
const response = (status: number, body: unknown) =>
  ({ kind: 'response' as const, status, body: typeof body === 'string' ? body : JSON.stringify(body) });
const fcm = (status: number, googleStatus: string, errorCode?: string, message = 'refused', details: unknown[] = []) =>
  response(status, {
    error: {
      code: status, message, status: googleStatus,
      details: [...(errorCode ? [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode }] : []), ...details],
    },
  });

Deno.test('Arabic is the default; English only for an English device with a complete English version', () => {
  assertEquals(localizedText(row), { title: row.title, body: row.body });
  assertEquals(localizedText({ ...row, locale: null }), { title: row.title, body: row.body });
  assertEquals(localizedText({ ...row, locale: 'en' }), { title: 'Trip delayed', body: 'The bus is 10 minutes late' });
  assertEquals(localizedText({ ...row, locale: 'en_US' }).title, 'Trip delayed');
  assertEquals(localizedText({ ...row, locale: 'EN-gb' }).title, 'Trip delayed');
  assertEquals(localizedText({ ...row, locale: 'en', body_en: null }), { title: row.title, body: row.body });
  assertEquals(localizedText({ ...row, locale: 'en', title_en: '  ' }), { title: row.title, body: row.body });
  // Not every locale that starts with "en" letters is English.
  assertEquals(localizedText({ ...row, locale: 'enm' }).title, row.title);
  assertEquals(buildMessage({ ...row, locale: 'en-US' }).message.notification, { title: 'Trip delayed', body: 'The bus is 10 minutes late' });
});

Deno.test('data carries the fixed keys plus whitelisted ids, all as strings, and nothing else', () => {
  const data = buildData({
    ...row,
    data: {
      route: 'subscription', subscription_id: 's1', line_id: 'l1', trip_id: 42, ride_date: '2026-11-02',
      student_name: 'سارة أحمد', phone: '01001234567', token: 'x', nested: { a: 1 }, notification_id: 'spoofed', category: 'spoofed',
    },
  });
  assertEquals(data, {
    notification_id: row.notification_id, type: 'transport.delay', category: 'transport',
    route: 'subscription', subscription_id: 's1', line_id: 'l1', trip_id: '42', ride_date: '2026-11-02',
  });
  for (const value of Object.values(data)) assertEquals(typeof value, 'string');
});

Deno.test('missing, null and non-scalar data values are dropped; route falls back to the Notification Center', () => {
  assertEquals(buildData({ ...row, data: null }), {
    notification_id: row.notification_id, type: 'transport.delay', category: 'transport', route: 'notifications',
  });
  const data = buildData({ ...row, data: { route: null, line_id: '', trip_id: { id: 1 }, subscription_id: ['a'], ride_date: undefined } });
  assertEquals(Object.keys(data).sort(), ['category', 'notification_id', 'route', 'type']);
  assertEquals(data.route, 'notifications');
});

Deno.test('type comes from the row, then from data.type, then from the category', () => {
  assertEquals(buildData(row).type, 'transport.delay');
  assertEquals(buildData({ ...row, type: undefined, data: { type: 'transport.arrived' } }).type, 'transport.arrived');
  assertEquals(buildData({ ...row, type: null, data: {} }).type, 'transport');
});

Deno.test('priority, channel, collapse and thread follow the row', () => {
  const high = buildMessage(row).message;
  assertEquals(high.token, TOKEN);
  assertEquals(high.android, {
    priority: 'HIGH',
    notification: { channel_id: 'basak_transport', tag: row.notification_id },
  });
  assertEquals(high.apns.headers, { 'apns-priority': '10', 'apns-collapse-id': row.notification_id });
  assertEquals(high.apns.payload, { aps: { sound: 'default', 'thread-id': 'transport', badge: 3 } });

  const normal = buildMessage({ ...row, priority: 'normal', category: 'announcement' }).message;
  assertEquals(normal.android.priority, 'NORMAL');
  assertEquals(normal.android.notification.channel_id, 'basak_announcement');
  assertEquals(normal.apns.headers['apns-priority'], '5');
  assertEquals(normal.apns.payload.aps['thread-id'], 'announcement');
  assertEquals(buildMessage({ ...row, priority: null }).message.android.priority, 'NORMAL');
});

Deno.test('the badge is the unread count, zero included, and is left out when unknown', () => {
  assertEquals(buildMessage({ ...row, badge: 0 }).message.apns.payload.aps.badge, 0);
  assertEquals(buildMessage({ ...row, badge: 7.9 }).message.apns.payload.aps.badge, 7);
  assertFalse('badge' in buildMessage({ ...row, badge: null }).message.apns.payload.aps);
  assertFalse('badge' in buildMessage({ ...row, badge: -1 }).message.apns.payload.aps);
});

Deno.test('2xx is accepted with the provider message id', () => {
  assertEquals(mapSendOutcome(response(200, { name: 'projects/basak-test/messages/0:123' })), {
    status: 'accepted', message_id: 'projects/basak-test/messages/0:123',
  });
  assertEquals(mapSendOutcome(response(200, 'not json')).status, 'accepted');
});

Deno.test('dead tokens are invalid_token', () => {
  assertEquals(mapSendOutcome(fcm(404, 'NOT_FOUND', 'UNREGISTERED')).status, 'invalid_token');
  assertEquals(mapSendOutcome(fcm(404, 'NOT_FOUND')).status, 'invalid_token');
  assertEquals(mapSendOutcome(fcm(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH')).status, 'invalid_token');
  assertFalse(mapSendOutcome(fcm(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH')).authFailure ?? false);
  assertEquals(
    mapSendOutcome(fcm(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'The registration token is not a valid FCM registration token')).status,
    'invalid_token',
  );
  assertEquals(
    mapSendOutcome(fcm(400, 'INVALID_ARGUMENT', undefined, 'Request contains an invalid argument.', [
      { '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.token', description: 'Invalid registration token' }] },
    ])).status,
    'invalid_token',
  );
});

Deno.test('an INVALID_ARGUMENT about our payload is failed, not a dead token', () => {
  const mapped = mapSendOutcome(fcm(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'Invalid value at message.android.priority', [
    { '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.android.priority' }] },
  ]));
  assertEquals(mapped.status, 'failed');
  assertEquals(mapped.code, 'INVALID_ARGUMENT');
});

Deno.test('temporary provider trouble and no answer at all are retry', () => {
  assertEquals(mapSendOutcome(fcm(429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED')).status, 'retry');
  assertEquals(mapSendOutcome(fcm(503, 'UNAVAILABLE', 'UNAVAILABLE')).status, 'retry');
  assertEquals(mapSendOutcome(fcm(500, 'INTERNAL', 'INTERNAL')).status, 'retry');
  assertEquals(mapSendOutcome(response(429, '')).status, 'retry');
  assertEquals(mapSendOutcome(response(500, '<html>')).status, 'retry');
  assertEquals(mapSendOutcome(response(503, '')).status, 'retry');
  assertEquals(mapSendOutcome({ kind: 'network', timeout: false }), { status: 'retry', code: 'network_error', error: 'network_error' });
  assertEquals(mapSendOutcome({ kind: 'network', timeout: true }), { status: 'retry', code: 'timeout', error: 'timeout' });
  for (const outcome of [fcm(503, 'UNAVAILABLE', 'UNAVAILABLE'), fcm(429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED')]) {
    assertFalse(mapSendOutcome(outcome).authFailure ?? false);
  }
});

Deno.test('refused credentials are retry and flag the invocation to stop', () => {
  for (const outcome of [fcm(401, 'UNAUTHENTICATED'), fcm(403, 'PERMISSION_DENIED'), response(401, ''), response(403, 'Forbidden')]) {
    const mapped = mapSendOutcome(outcome);
    assertEquals(mapped.status, 'retry');
    assertEquals(mapped.authFailure, true);
  }
  // A broken APNs key in Firebase concerns iOS only: retry, but keep sending.
  const apns = mapSendOutcome(fcm(401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR'));
  assertEquals(apns.status, 'retry');
  assertFalse(apns.authFailure ?? false);
});

Deno.test('anything else is failed', () => {
  assertEquals(mapSendOutcome(response(400, '')).status, 'failed');
  assertEquals(mapSendOutcome(response(404, '<html>Not Found</html>')).status, 'failed');
  assertEquals(mapSendOutcome(response(413, '')).code, 'HTTP_413');
  assertEquals(mapSendOutcome(fcm(400, 'FAILED_PRECONDITION')).status, 'failed');
});

Deno.test('the error is short and never contains the token', () => {
  const mapped = mapSendOutcome(fcm(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', `Bad registration token ${TOKEN} ${'x'.repeat(500)}`), TOKEN);
  assertEquals(mapped.status, 'invalid_token');
  assert(mapped.error!.length <= 200);
  assertFalse(mapped.error!.includes(TOKEN));
  assert(mapped.error!.startsWith('INVALID_ARGUMENT: Bad registration token [token]'));
});

Deno.test('the dispatch secret must match exactly', () => {
  assert(secretMatches('s3cret-value', 's3cret-value'));
  assertFalse(secretMatches('s3cret-value', 's3cret-valuE'));
  assertFalse(secretMatches('s3cret-value', 's3cret-valu'));
  assertFalse(secretMatches('s3cret-value', 's3cret-value-and-more'));
  assertFalse(secretMatches('s3cret-value', ''));
  assertFalse(secretMatches('s3cret-value', null));
  // A function without its secret accepts nobody, not everybody.
  assertFalse(secretMatches('', ''));
  assertFalse(secretMatches(undefined, undefined));
  assertFalse(secretMatches(null, 'anything'));
});
