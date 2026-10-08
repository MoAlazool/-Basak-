// deno test supabase/functions/_shared/push/
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { handleDispatchRequest, type HandlerDeps, runDispatch } from './dispatch.ts';
import { resetAccessToken } from './fcm.ts';
import type { PushOutboxResult, PushOutboxRow } from './message.ts';
import { fakeGoogle, fakeServiceAccountJson, fcmError } from './testing.ts';

const serviceAccountJson = await fakeServiceAccountJson();

function outboxRow(n: number, overrides: Partial<PushOutboxRow> = {}): PushOutboxRow {
  return {
    id: `row-${n}`, notification_id: `notif-${n}`, token: `token-${n}`, platform: n % 2 ? 'android' : 'ios', locale: 'ar',
    title: 'عنوان سري', body: 'نص سري', title_en: null, body_en: null,
    data: { route: 'home' }, type: 'transport.delay', category: 'transport', priority: 'high', badge: 1, attempts: 0,
    ...overrides,
  };
}

/** The three dispatcher RPCs over an in-memory queue of batches. */
function fakeDatabase(batches: PushOutboxRow[][], fail: { claim?: boolean; complete?: number } = {}) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const completed: PushOutboxResult[][] = [];
  const configured: boolean[] = [];
  let completeFailures = fail.complete ?? 0;
  // deno-lint-ignore require-await
  const rpc = async (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    if (name === 'set_push_configured') {
      configured.push(params.p_configured as boolean);
      return { data: null, error: null };
    }
    if (name === 'claim_push_outbox') {
      if (fail.claim) return { data: null, error: { code: '57014', message: 'statement timeout' } };
      return { data: batches.shift() ?? [], error: null };
    }
    if (name === 'complete_push_outbox') {
      if (completeFailures-- > 0) return { data: null, error: { code: '40001' } };
      completed.push(params.p_results as PushOutboxResult[]);
      return { data: null, error: null };
    }
    throw new Error(`unexpected rpc ${name}`);
  };
  const names = () => calls.map((call) => call.name);
  return { rpc, calls, completed, configured, names };
}

/** Captures console output so a test can prove nothing sensitive is logged. */
async function captureLogs<T>(run: () => Promise<T>): Promise<{ result: T; logs: string }> {
  const original = { log: console.log, warn: console.warn, error: console.error };
  const lines: string[] = [];
  const record = (...parts: unknown[]) => lines.push(parts.map((part) => (typeof part === 'string' ? part : JSON.stringify(part))).join(' '));
  console.log = record; console.warn = record; console.error = record;
  try {
    return { result: await run(), logs: lines.join('\n') };
  } finally {
    Object.assign(console, original);
  }
}

const request = (headers: Record<string, string> = {}, method = 'POST') =>
  new Request('http://localhost/functions/v1/push-dispatch', { method, headers });

Deno.test('not configured: the database is told, nothing is claimed, nothing is sent', async () => {
  for (const json of [undefined, '', '{broken']) {
    const database = fakeDatabase([[outboxRow(1)]]);
    const google = fakeGoogle(() => Response.json({ name: 'x' }));
    const summary = await runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson: json });
    assertEquals(summary, { configured: false, claimed: 0, accepted: 0, failed: 0, retried: 0, invalid: 0, batches: 0 });
    assertEquals(database.calls, [{ name: 'set_push_configured', params: { p_configured: false } }]);
    assertEquals(google.tokenCalls.length + google.sendCalls.length, 0);
  }
});

Deno.test('a mixed batch: each row gets its own truthful status, in one complete call', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1), outboxRow(2), outboxRow(3), outboxRow(4), outboxRow(5)]]);
  const google = fakeGoogle((message) => {
    switch (message.token) {
      case 'token-1': return Response.json({ name: 'projects/basak-test/messages/m1' });
      case 'token-2': return fcmError(503, 'UNAVAILABLE', 'UNAVAILABLE');
      case 'token-3': return fcmError(404, 'NOT_FOUND', 'UNREGISTERED');
      case 'token-4': return fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', 'Invalid value at message.data');
      default: throw new TypeError('connection reset');
    }
  });
  const { result: summary, logs } = await captureLogs(() => runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson }));

  assertEquals(summary, { configured: true, claimed: 5, accepted: 1, failed: 1, retried: 2, invalid: 1, batches: 1 });
  assertEquals(database.configured, [true]);
  assertEquals(database.names(), ['set_push_configured', 'claim_push_outbox', 'complete_push_outbox', 'claim_push_outbox']);
  assertEquals(database.calls[1].params, { p_limit: 200 });
  assertEquals(database.completed, [[
    { id: 'row-1', status: 'accepted', message_id: 'projects/basak-test/messages/m1' },
    { id: 'row-2', status: 'retry', error: 'UNAVAILABLE: refused' },
    { id: 'row-3', status: 'invalid_token', error: 'UNREGISTERED: refused' },
    { id: 'row-4', status: 'failed', error: 'INVALID_ARGUMENT: Invalid value at message.data' },
    { id: 'row-5', status: 'retry', error: 'network_error' },
  ]]);
  // One sign-in for the whole invocation; the message is the contract's shape.
  assertEquals(google.tokenCalls.length, 1);
  assertEquals(google.sendCalls.length, 5);
  assertEquals(google.sendCalls[0].headers.authorization, 'Bearer access-1');
  const sent = JSON.parse(google.sendCalls[0].body).message;
  assertEquals(sent.data, { notification_id: 'notif-1', type: 'transport.delay', category: 'transport', route: 'home' });
  assertEquals(sent.android.notification.channel_id, 'basak_transport');
  // Counts and codes only: no token, title or body in the logs.
  assert(logs.includes('UNREGISTERED'));
  for (const secret of ['token-1', 'token-3', 'عنوان سري', 'نص سري', 'access-1']) assertFalse(logs.includes(secret));
});

Deno.test('the loop keeps claiming until a claim comes back empty', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1), outboxRow(2)], [outboxRow(3)], [], [outboxRow(99)]]);
  const google = fakeGoogle((message) => Response.json({ name: `m-${message.token}` }));
  const summary = await runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson, batchSize: 2 });

  assertEquals(summary, { configured: true, claimed: 3, accepted: 3, failed: 0, retried: 0, invalid: 0, batches: 2 });
  assertEquals(database.names(), [
    'set_push_configured', 'claim_push_outbox', 'complete_push_outbox', 'claim_push_outbox', 'complete_push_outbox', 'claim_push_outbox',
  ]);
  assertEquals(database.configured, [true]);
  assertEquals(google.tokenCalls.length, 1);
  assertEquals(google.sendCalls.length, 3);
});

Deno.test('refused credentials while sending: the batch is handed back as retry and the loop stops', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1), outboxRow(2), outboxRow(3)], [outboxRow(4)]]);
  const google = fakeGoogle(() => fcmError(401, 'UNAUTHENTICATED', undefined, 'Request had invalid authentication credentials.'));
  const { result: summary } = await captureLogs(() =>
    runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson, concurrency: 1 })
  );

  assertEquals(summary, {
    configured: true, claimed: 3, accepted: 0, failed: 0, retried: 3, invalid: 0, batches: 1,
    stopped: 'auth_failed', auth_error: 'UNAUTHENTICATED',
  });
  // The first refusal is enough: the other rows are not sent at all.
  assertEquals(google.sendCalls.length, 1);
  assertEquals(database.completed[0].map((result) => result.status), ['retry', 'retry', 'retry']);
  assertEquals(database.completed[0][1].error, 'auth: UNAUTHENTICATED');
  assertEquals(database.names().filter((name) => name === 'claim_push_outbox').length, 1);
});

Deno.test('a sign-in that fails: nothing is sent, the batch is retried later, the loop stops', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1), outboxRow(2)], [outboxRow(3)]]);
  const google = fakeGoogle(() => Response.json({ name: 'x' }), () => Response.json({ error: 'invalid_grant' }, { status: 400 }));
  const { result: summary } = await captureLogs(() => runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson }));

  assertEquals(summary.stopped, 'auth_failed');
  assertEquals(summary.auth_error, 'token_invalid_grant');
  assertEquals([summary.claimed, summary.retried, summary.batches], [2, 2, 1]);
  assertEquals(google.sendCalls.length, 0);
  assertEquals(database.completed, [[
    { id: 'row-1', status: 'retry', error: 'auth: token_invalid_grant' },
    { id: 'row-2', status: 'retry', error: 'auth: token_invalid_grant' },
  ]]);
});

Deno.test('a broken APNs key fails iOS only and does not stop the loop', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1), outboxRow(2)], [outboxRow(3)]]);
  const google = fakeGoogle((message) =>
    message.token === 'token-2' ? fcmError(401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR') : Response.json({ name: 'ok' })
  );
  const { result: summary } = await captureLogs(() => runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson }));
  assertEquals(summary, { configured: true, claimed: 3, accepted: 2, failed: 0, retried: 1, invalid: 0, batches: 2 });
});

Deno.test('the time budget ends the loop between batches', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1)], [outboxRow(2)], [outboxRow(3)]]);
  let clock = 1_800_000_000_000;
  const google = fakeGoogle(() => {
    clock += 12_000;
    return Response.json({ name: 'ok' });
  });
  const summary = await runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson, now: () => clock });
  assertEquals(summary, { configured: true, claimed: 2, accepted: 2, failed: 0, retried: 0, invalid: 0, batches: 2, stopped: 'time_budget' });
});

Deno.test('a request that hangs is cut off and retried; rows past the hard stop go back unsent', async () => {
  resetAccessToken();
  const database = fakeDatabase([[outboxRow(1), outboxRow(2), outboxRow(3)]]);
  let clock = 1_800_000_000_000;
  const google = fakeGoogle((message) => {
    if (message.token === 'token-1') return 'hang';
    return Response.json({ name: 'ok' });
  });
  const { result: summary } = await captureLogs(() =>
    runDispatch({
      rpc: database.rpc, fetch: (url, init) => {
        const answer = google.fetch(url, init);
        // The hung request "costs" a minute of wall time once it is aborted.
        if (String(init?.body ?? '').includes('token-1')) return answer.finally(() => { clock += 60_000; });
        return answer;
      },
      serviceAccountJson, now: () => clock, concurrency: 1, timeoutMs: 30,
    })
  );
  assertEquals(database.completed, [[
    { id: 'row-1', status: 'retry', error: 'timeout' },
    { id: 'row-2', status: 'retry', error: 'not_sent: time_budget' },
    { id: 'row-3', status: 'retry', error: 'not_sent: time_budget' },
  ]]);
  assertEquals(summary.retried, 3);
  assertEquals(summary.stopped, 'time_budget');
  assertEquals(google.sendCalls.length, 1);
});

Deno.test('database trouble never throws: a failed claim stops; a failed complete is retried once, then reported', async () => {
  resetAccessToken();
  const google = fakeGoogle(() => Response.json({ name: 'ok' }));

  const noClaim = fakeDatabase([[outboxRow(1)]], { claim: true });
  const first = await captureLogs(() => runDispatch({ rpc: noClaim.rpc, fetch: google.fetch, serviceAccountJson }));
  assertEquals(first.result, { configured: true, claimed: 0, accepted: 0, failed: 0, retried: 0, invalid: 0, batches: 0, stopped: 'claim_failed' });

  const flaky = fakeDatabase([[outboxRow(1)]], { complete: 1 });
  const second = await captureLogs(() => runDispatch({ rpc: flaky.rpc, fetch: google.fetch, serviceAccountJson }));
  assertEquals(second.result.stopped, undefined);
  assertEquals(flaky.completed.length, 1);

  const broken = fakeDatabase([[outboxRow(1), outboxRow(2)], [outboxRow(3)]], { complete: 5 });
  const third = await captureLogs(() => runDispatch({ rpc: broken.rpc, fetch: google.fetch, serviceAccountJson }));
  assertEquals(third.result.stopped, 'complete_failed');
  assertEquals(third.result.unrecorded, 2);
  assertEquals(third.result.batches, 1);

  const throwing = await captureLogs(() =>
    runDispatch({ rpc: () => Promise.reject(new Error('socket closed')), fetch: google.fetch, serviceAccountJson })
  );
  assertEquals(throwing.result.stopped, 'claim_failed');
});

Deno.test('concurrency is bounded', async () => {
  resetAccessToken();
  const database = fakeDatabase([Array.from({ length: 30 }, (_, index) => outboxRow(index + 1))]);
  let inFlight = 0;
  let peak = 0;
  const google = fakeGoogle(async () => {
    peak = Math.max(peak, ++inFlight);
    await new Promise((resolve) => setTimeout(resolve, 2));
    inFlight--;
    return Response.json({ name: 'ok' });
  });
  const summary = await runDispatch({ rpc: database.rpc, fetch: google.fetch, serviceAccountJson, concurrency: 4 });
  assertEquals(summary.accepted, 30);
  assertEquals(peak, 4);
  assertEquals(database.completed[0].map((result) => result.id), Array.from({ length: 30 }, (_, index) => `row-${index + 1}`));
});

Deno.test('the handler accepts only the shared secret, and only POST', async () => {
  resetAccessToken();
  const google = fakeGoogle(() => Response.json({ name: 'ok' }));
  const deps = (secret: string | undefined, database = fakeDatabase([[outboxRow(1)]])): HandlerDeps & { database: ReturnType<typeof fakeDatabase> } =>
    ({ secret, rpc: database.rpc, fetch: google.fetch, serviceAccountJson, database });

  for (const [secret, headers] of [
    ['right', {}],
    ['right', { 'x-dispatch-secret': 'wrong' }],
    ['right', { authorization: 'Bearer right' }],
    [undefined, { 'x-dispatch-secret': '' }],
    ['', { 'x-dispatch-secret': '' }],
  ] as [string | undefined, Record<string, string>][]) {
    const current = deps(secret);
    const response = await handleDispatchRequest(request(headers), current);
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { error: 'unauthorized' });
    assertEquals(current.database.calls.length, 0);
    assertEquals(response.headers.get('access-control-allow-origin'), null);
  }

  const get = deps('right');
  assertEquals((await handleDispatchRequest(request({ 'x-dispatch-secret': 'right' }, 'GET'), get)).status, 405);
  assertEquals(get.database.calls.length, 0);
  // The secret is checked before the method: a stranger learns nothing.
  assertEquals((await handleDispatchRequest(request({}, 'OPTIONS'), deps('right'))).status, 401);

  const { result: ok } = await captureLogs(() => handleDispatchRequest(request({ 'x-dispatch-secret': 'right' }), deps('right')));
  assertEquals(ok.status, 200);
  assertEquals(await ok.json(), { configured: true, claimed: 1, accepted: 1, failed: 0, retried: 0, invalid: 0, batches: 1 });

  const unset = deps('right');
  const { result: off } = await captureLogs(() =>
    handleDispatchRequest(request({ 'x-dispatch-secret': 'right' }), { ...unset, serviceAccountJson: undefined })
  );
  assertEquals(off.status, 200);
  assertEquals((await off.json()).configured, false);
  assertEquals(unset.database.names(), ['set_push_configured']);
});
