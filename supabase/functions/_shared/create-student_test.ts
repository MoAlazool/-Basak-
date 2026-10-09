// deno test supabase/functions/_shared/
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import type { AdminContext } from './admin-auth.ts';
import { createStudent } from './create-student.ts';
import { HttpError } from './http.ts';
import { type DbCall, fakeSupabase, type Handlers, type Reply } from './testing/fake_supabase.ts';

const ADMIN = 'aaaaaaaa-0000-4000-8000-000000000001';
const COMPANY = 'cccccccc-0000-4000-8000-000000000001';
const OTHER_COMPANY = 'cccccccc-0000-4000-8000-000000000002';
const LINE = '11111111-0000-4000-8000-000000000001';
const STATION = '22222222-0000-4000-8000-000000000001';
const TRIP = '33333333-0000-4000-8000-000000000001';
const NEW_USER = 'dddddddd-0000-4000-8000-000000000001';
const EXISTING = 'eeeeeeee-0000-4000-8000-000000000001';

const body = (extra: Record<string, unknown> = {}) => ({
  fullName: 'سارة أحمد علي', phone: '01012345678', university: 'جامعة القاهرة', password: 'Secret-123',
  lineId: LINE, stationId: STATION, subscriptionType: 'termly', periodCode: 'first', academicYear: 2026,
  departureTripId: TRIP, ...extra,
});

interface World {
  line?: Reply;
  station?: Reply;
  student?: Reply;
  periodPrice?: Reply;
  insert?: (call: DbCall) => Reply;
  authAdmin?: Handlers['authAdmin'];
}

/** A company with one active line (termly 900, period "first" 750), one station, and no student on this phone. */
function world(overrides: World = {}, role: 'company_admin' | 'super_admin' = 'company_admin') {
  const fake = fakeSupabase({
    db: (call) => {
      if (call.op !== 'select') return overrides.insert?.(call) ?? {};
      switch (call.table) {
        case 'lines':
          return overrides.line ?? { data: { id: LINE, company_id: COMPANY, price_termly: 900, price_yearly: 1700, price_daily: 40 } };
        case 'stations': return overrides.station ?? { data: { id: STATION } };
        case 'students': return overrides.student ?? { data: null };
        case 'line_period_prices': return overrides.periodPrice ?? { data: { price: 750 } };
        default: return {};
      }
    },
    authAdmin: overrides.authAdmin ?? ((method) => method === 'createUser' ? { data: { user: { id: NEW_USER } } } : {}),
  });
  const context = {
    user: { id: ADMIN },
    admin: { id: ADMIN, role, company_id: role === 'company_admin' ? COMPANY : null },
    serviceClient: fake.client,
  } as unknown as AdminContext;
  return { fake, context };
}

const READS = ['select lines', 'select stations', 'select students', 'select line_period_prices'];
const writes = (log: string[]) => log.filter((entry) => !entry.startsWith('select '));

Deno.test('a new student: the four reads run together, then account, profile, subscription in order', async () => {
  const { fake, context } = world();
  const response = await createStudent(context, body());
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { id: NEW_USER });

  // All four questions were in flight before the first answer arrived.
  assertEquals(fake.timeline.slice(0, 4), READS.map((read) => `start ${read}`));
  assertEquals(fake.log, [...READS, 'auth.admin.createUser', 'insert students', 'insert subscriptions']);
  // Only the columns that are used.
  assertEquals(fake.db[0].columns, 'id,company_id,price_termly,price_yearly,price_daily');
  assertEquals(fake.db[0].filters, { id: LINE, is_active: true });
  assertEquals(fake.db[1].filters, { id: STATION, line_id: LINE, is_active: true });

  const subscription = fake.db.find((call) => call.table === 'subscriptions')!.values as Record<string, unknown>;
  assertEquals(subscription.student_id, NEW_USER);
  assertEquals(subscription.price, 750);
  assertEquals(subscription.status, 'pending_payment');
  assertEquals([subscription.period_code, subscription.academic_year], ['first', 2026]);
  assertEquals([subscription.departure_trip_id, subscription.departure_time], [TRIP, null]);
  const profile = fake.db.find((call) => call.op === 'insert' && call.table === 'students')!.values as Record<string, unknown>;
  assertEquals(profile, { id: NEW_USER, phone: '01012345678', full_name: 'سارة أحمد علي', university: 'جامعة القاهرة', college: 'غير محدد' });
});

Deno.test('the price is the period price when the line has one, else the line price', async () => {
  const priceOf = async (extra: Record<string, unknown>, overrides: World = {}) => {
    const { fake, context } = world(overrides);
    await createStudent(context, body(extra));
    return [
      (fake.db.find((call) => call.table === 'subscriptions')!.values as { price: number }).price,
      fake.db.find((call) => call.table === 'line_period_prices')?.filters.option ?? null,
    ];
  };
  assertEquals(await priceOf({}), [750, 'first']);
  assertEquals(await priceOf({}, { periodPrice: { data: null } }), [900, 'first']);
  assertEquals(await priceOf({}, { periodPrice: { data: { price: 0 } } }), [900, 'first']);
  assertEquals(await priceOf({ subscriptionType: 'yearly' }), [750, 'both']);
  assertEquals(await priceOf({ periodCode: 'annual' }), [750, 'both']);
  // No period named: the line price, and the period table is not asked at all.
  assertEquals(await priceOf({ periodCode: undefined }), [900, null]);
  assertEquals(await priceOf({ subscriptionType: 'daily' }), [40, null]);
});

Deno.test('the phone is normalised before it is looked up or used as the sign-in address', async () => {
  let email = '';
  const { fake, context } = world({
    authAdmin: (method, args) => {
      if (method === 'createUser') email = (args[0] as { email: string }).email;
      return { data: { user: { id: NEW_USER } } };
    },
  });
  assertEquals((await createStudent(context, body({ phone: '+20 101 234 5678' }))).status, 200);
  assertEquals(email, '01012345678@busak.app');
  assertEquals(fake.db.find((call) => call.table === 'students')!.filters, { phone: '01012345678' });
});

Deno.test('incomplete input is refused before anything is read or created', async () => {
  for (const wrong of [{ phone: '12345' }, { fullName: 'سارة أحمد' }, { password: 'short' }, { lineId: '' }, { subscriptionType: 'weekly' }, { university: '' }]) {
    const { fake, context } = world();
    assertEquals((await createStudent(context, body(wrong))).status, 400, JSON.stringify(wrong));
    assertEquals(fake.log, []);
  }
});

Deno.test("a company admin cannot register a student on another company's line: nothing is written", async () => {
  const { fake, context } = world({ line: { data: { id: LINE, company_id: OTHER_COMPANY, price_termly: 900 } } });
  const error = await assertRejects(() => createStudent(context, body()), HttpError);
  assertEquals(error.status, 403);
  assertEquals(writes(fake.log), []);
});

Deno.test('the platform admin may register a student on any company\'s line', async () => {
  const { context } = world({ line: { data: { id: LINE, company_id: OTHER_COMPANY, price_termly: 900 } } }, 'super_admin');
  assertEquals((await createStudent(context, body())).status, 200);
});

Deno.test('an unknown line, a foreign station or a missing trip is refused with nothing written', async () => {
  const cases: [World, Record<string, unknown>, number][] = [
    [{ line: { data: null } }, {}, 404],
    [{ station: { data: null } }, {}, 400],
    [{}, { departureTripId: null }, 400],
  ];
  for (const [overrides, extra, expected] of cases) {
    const { fake, context } = world(overrides);
    assertEquals((await createStudent(context, body(extra))).status, expected);
    assertEquals(writes(fake.log), []);
  }
});

Deno.test('a failed read is an error, never treated as "no such student"', async () => {
  const { fake, context } = world({ student: { error: { message: 'timeout' } } });
  await assertRejects(() => createStudent(context, body()));
  assertEquals(writes(fake.log), []);
});

Deno.test('if the profile row fails, the new account is removed again', async () => {
  const { fake, context } = world({
    insert: (call) => call.table === 'students' ? { error: { message: 'duplicate phone', code: '23505' } } : {},
  });
  const error = await assertRejects(() => createStudent(context, body()));
  assertEquals((error as { message: string }).message, 'duplicate phone');
  assertEquals(writes(fake.log), ['auth.admin.createUser', 'insert students', 'auth.admin.deleteUser']);
});

Deno.test('if the subscription fails, the new account (and with it the profile) is removed again', async () => {
  const deleted: unknown[] = [];
  const { fake, context } = world({
    insert: (call) => call.table === 'subscriptions' ? { error: { message: 'هذه الفترة غير متاحة للاشتراك على هذا الخط.', code: '23514' } } : {},
    authAdmin: (method, args) => {
      if (method === 'deleteUser') deleted.push(args[0]);
      return method === 'createUser' ? { data: { user: { id: NEW_USER } } } : {};
    },
  });
  const error = await assertRejects(() => createStudent(context, body()));
  assertEquals((error as { message: string }).message, 'هذه الفترة غير متاحة للاشتراك على هذا الخط.');
  assertEquals(writes(fake.log), ['auth.admin.createUser', 'insert students', 'insert subscriptions', 'auth.admin.deleteUser']);
  assertEquals(deleted, [NEW_USER]);
});

Deno.test('a step that throws (not just reports an error) also removes the account', async () => {
  const { fake, context } = world({ insert: () => { throw new TypeError('network down'); } });
  await assertRejects(() => createStudent(context, body()), TypeError);
  assertEquals(fake.count('auth.admin.deleteUser'), 1);
});

Deno.test('a removal that fails is tried again, logged by id only, and the first error is still the one reported', async () => {
  const logged: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => { logged.push(args); };
  try {
    const { fake, context } = world({
      insert: (call) => call.table === 'students' ? { error: { message: 'profile failed' } } : {},
      authAdmin: (method) => method === 'createUser' ? { data: { user: { id: NEW_USER } } } : { error: { message: 'auth is down' } },
    });
    const error = await assertRejects(() => createStudent(context, body()));
    assertEquals((error as { message: string }).message, 'profile failed');
    assertEquals(fake.count('auth.admin.deleteUser'), 2);
  } finally {
    console.error = original;
  }
  assertEquals(logged.length, 1);
  const line = logged[0].join(' ');
  assert(line.includes(NEW_USER));
  assert(!line.includes('01012345678') && !line.includes('Secret-123'));
});

Deno.test('a phone that already has a sign-in account is refused and nothing is inserted', async () => {
  const { fake, context } = world({
    authAdmin: () => ({ error: { message: 'A user with this email address has already been registered' } }),
  });
  const error = await assertRejects(() => createStudent(context, body()), HttpError);
  assertEquals(error.status, 409);
  assertEquals(writes(fake.log), ['auth.admin.createUser']);
});

Deno.test('an existing student is invited, never attached or re-created', async () => {
  const { fake, context } = world({
    student: { data: { id: EXISTING, memberships: [{ company_id: OTHER_COMPANY, status: 'active' }, { company_id: COMPANY, status: 'removed' }] } },
  });
  const response = await createStudent(context, body());
  assertEquals(await response.json(), { invited: true });
  assertEquals(writes(fake.log), ['insert company_invites']);
  const invite = fake.db.find((call) => call.table === 'company_invites')!.values as Record<string, unknown>;
  assertEquals([invite.company_id, invite.student_id, invite.invited_by, invite.line_id], [COMPANY, EXISTING, ADMIN, LINE]);
  // The membership came with the student row: no separate query for it.
  assertEquals(fake.count('select company_students'), 0);
});

Deno.test('a student who is already an active member, or already invited, gets a clear refusal', async () => {
  const member = world({ student: { data: { id: EXISTING, memberships: [{ company_id: COMPANY, status: 'active' }] } } });
  assertEquals((await createStudent(member.context, body())).status, 409);
  assertEquals(writes(member.fake.log), []);

  const invited = world({
    student: { data: { id: EXISTING, memberships: [] } },
    insert: () => ({ error: { message: 'duplicate', code: '23505' } }),
  });
  assertEquals((await createStudent(invited.context, body())).status, 409);
});
