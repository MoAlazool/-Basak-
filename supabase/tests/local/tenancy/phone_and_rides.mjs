// Two guarantees, checked through the real API of a LOCAL stack:
//   1. one phone number = one account, enforced by the server
//   2. "confirmed riders" is the same number in the dashboard, the supervisor app
//      and the database, after every change, and changes are announced live
//   SUPABASE_URL=... ANON_KEY=... SERVICE_KEY=... node supabase/tests/local/tenancy/phone_and_rides.mjs
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../../../admin_web/package.json'));
const { createClient } = require('@supabase/supabase-js');

const URL_ = process.env.SUPABASE_URL;
if (!/127\.0\.0\.1|localhost/.test(URL_ ?? '')) throw new Error('This test only runs against a local stack.');
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL_, process.env.SERVICE_KEY, opts);
const anon = () => createClient(URL_, process.env.ANON_KEY, opts);

const results = [];
const ok = (step, pass, detail = '') => results.push({ step, pass: !!pass, detail: pass ? '' : String(detail ?? '') });
const must = (value, label) => { if (value?.error) throw new Error(`${label}: ${value.error.message}`); return value; };
const run = crypto.randomBytes(3).toString('hex');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const PASSWORD = `Pw-${crypto.randomBytes(9).toString('base64url')}`;
const digits = (n) => Array.from(crypto.randomBytes(n), (b) => b % 10).join('');
const newPhone = () => `010${digits(8)}`;
const created = { users: [], companies: [] };

/** What the app does to register: create the login, then the student row. */
async function register(phone, { email = `${phone}@busak.app`, rowPhone = phone } = {}) {
  const client = anon();
  const signUp = await client.auth.signUp({ email, password: PASSWORD });
  if (signUp.error || !signUp.data.session) return { stage: 'login', error: signUp.error?.message ?? 'no session' };
  created.users.push(signUp.data.user.id);
  const row = await client.from('students').insert({
    id: signUp.data.user.id, phone: rowPhone, full_name: 'طالب اختبار رقم الهاتف', university: universityName,
  }).select('phone').single();
  return row.error ? { stage: 'row', error: row.error.message } : { phone: row.data.phone, id: signUp.data.user.id };
}

let universityName;

async function phones() {
  const phone = newPhone();
  const first = await register(phone);
  ok('phone: a new number registers', first.phone === phone, first.error);

  const second = await register(phone);
  ok('phone: the same number cannot register again', second.stage === 'login' && /already|registered|exists/i.test(second.error), JSON.stringify(second));
  ok('phone: still exactly one account for it',
    (await service.from('students').select('id', { count: 'exact', head: true }).eq('phone', phone)).count === 1);

  // The same number written differently is still the same number.
  for (const [label, email] of [['with country code', `2${phone}@busak.app`], ['under an e-mail login', `someone-${run}@example.com`]]) {
    const variant = await register(phone, { email, rowPhone: `+2 ${phone.slice(0, 4)} ${phone.slice(4)}` });
    ok(`phone: registering it ${label} is refused by the database`, variant.stage === 'row', JSON.stringify(variant));
  }
  const arabic = newPhone();
  const arabicDigits = arabic.replace(/\d/g, (d) => '٠١٢٣٤٥٦٧٨٩'[d]);
  const typedInArabic = await register(arabic, { rowPhone: arabicDigits });
  ok('phone: a number typed in Arabic numerals is stored in its one canonical form', typedInArabic.phone === arabic, JSON.stringify(typedInArabic));

  const unclaimed = newPhone();
  const impostor = await register(newPhone(), { rowPhone: unclaimed });
  ok('phone: an account cannot register a number it does not sign in with', impostor.stage === 'row', JSON.stringify(impostor));
  ok('phone: an invalid number is refused', (await register('01234', { email: `01234${run}@busak.app`, rowPhone: '01234' })).stage === 'row');

  // Ten people pressing "register" with the same number at the same moment.
  const raced = newPhone();
  const attempts = await Promise.all(Array.from({ length: 10 }, () => register(raced)));
  const winners = attempts.filter((a) => a.phone === raced).length;
  ok('phone: ten simultaneous registrations produce exactly one account', winners === 1
    && (await service.from('students').select('id', { count: 'exact', head: true }).eq('phone', raced)).count === 1, `${winners} winner(s)`);

  // A supervisor's number is taken too.
  const supervisorPhone = (await service.from('supervisors').select('phone').eq('company_id', created.companies[0]).single()).data.phone;
  const asStudent = await register(supervisorPhone);
  ok('phone: a supervisor\'s number cannot become a student account', !asStudent.phone, JSON.stringify(asStudent));
}

async function rides() {
  const [A, B] = created.companies;
  const today = (await service.rpc('cairo_today')).data;
  const nextRide = (await service.rpc('next_votable_ride_date')).data;
  const { adminA, supervisorA, lineA, stationA, tripA, students } = fixture;

  /** The four places the number is shown or stored, for one day. */
  const counts = async (date) => {
    const overview = must(await adminA.rpc('company_overview', { p_company_id: A }), 'overview').data;
    const dashboard = must(await supervisorA.rpc('get_supervisor_dashboard'), 'supervisor dashboard').data;
    const perStation = must(await supervisorA.rpc('get_line_rider_counts_with_returns', { p_line_id: lineA, p_ride_date: date }), 'rider counts').data;
    const truth = (await service.from('daily_ride_status').select('student_id').eq('ride_date', date).eq('is_riding', true)
      .in('student_id', students)).data.length;
    return {
      dashboard: date === today ? overview.riders_today : overview.riders_next,
      week: overview.riders_week.find((d) => d.date === date)?.riders,
      supervisorHome: date === today ? dashboard.totals.confirmed_today : undefined,
      supervisorStations: perStation.reduce((sum, row) => sum + Number(row.riding_count), 0),
      truth,
    };
  };
  const same = (c, expected) => [c.dashboard, c.supervisorStations, c.truth, ...(c.week === undefined ? [] : [c.week]),
    ...(c.supervisorHome === undefined ? [] : [c.supervisorHome])].every((n) => Number(n) === expected);
  const vote = (student, date, riding) => must(await_(service.from('daily_ride_status')
    .upsert({ student_id: student, ride_date: date, is_riding: riding, toggled_at: new Date().toISOString() }, { onConflict: 'student_id,ride_date' })), 'vote');
  const await_ = (x) => x;

  // Live feed of company A, as the dashboard and the supervisor app hold it.
  const events = [];
  const { data: { session } } = await adminA.auth.getSession();
  await adminA.realtime.setAuth(session.access_token);
  const channel = adminA.channel(`company:${A}`, { config: { private: true } })
    .on('broadcast', { event: 'change' }, (m) => events.push({ ...m.payload, at: Date.now() }));
  await new Promise((resolve) => channel.subscribe((status) => status === 'SUBSCRIBED' && resolve()));

  let c = await counts(today);
  ok('rides: nobody confirmed yet, everywhere', same(c, 0), JSON.stringify(c));

  const started = Date.now();
  await Promise.all(students.slice(0, 3).map((s) => vote(s, today, true)));
  c = await counts(today);
  ok('rides: three confirm, and every place says 3', same(c, 3), JSON.stringify(c));
  await sleep(1500);
  const rideEvents = events.filter((e) => e.table === 'daily_ride_status');
  ok('rides: each confirmation is announced live within 2 s', rideEvents.length >= 3 && rideEvents.every((e) => e.at - started < 2000),
    `${rideEvents.length} event(s), slowest ${Math.max(0, ...rideEvents.map((e) => e.at - started))} ms`);

  await vote(students[0], today, false);
  c = await counts(today);
  ok('rides: one cancels, and every place says 2', same(c, 2), JSON.stringify(c));

  // The same student tapping confirm/cancel many times at once: one row, one final answer.
  await Promise.all(Array.from({ length: 20 }, (_, i) => vote(students[1], today, i % 2 === 0)));
  const final = (await service.from('daily_ride_status').select('is_riding').eq('student_id', students[1]).eq('ride_date', today)).data;
  c = await counts(today);
  ok('rides: twenty simultaneous taps leave one row and one consistent count', final.length === 1 && same(c, final[0].is_riding ? 2 : 1), JSON.stringify([final, c]));
  await vote(students[1], today, true);

  // A subscription that ends takes its rider out of every count, without touching the vote.
  must(await service.from('subscriptions').update({ status: 'expired' }).eq('student_id', students[2]).eq('company_id', A), 'expire');
  c = await counts(today);
  ok('rides: a rider whose subscription ended is counted nowhere',
    c.dashboard === 1 && c.supervisorStations === 1 && Number(c.supervisorHome) === 1 && c.truth === 2, JSON.stringify(c));
  must(await service.from('subscriptions').update({ status: 'active' }).eq('student_id', students[2]).eq('company_id', A), 'reactivate');
  c = await counts(today);
  ok('rides: reactivated, and every place says 2 again', same(c, 2), JSON.stringify(c));

  // The evening vote is for the next ride: that day has its own count.
  if (nextRide !== today) {
    await Promise.all(students.map((s) => vote(s, nextRide, true)));
    const next = await counts(nextRide);
    ok('rides: confirmations for the next ride are counted for that day', next.dashboard === students.length && next.supervisorStations === students.length, JSON.stringify(next));
    c = await counts(today);
    ok('rides: and today\'s count did not move', same(c, 2), JSON.stringify(c));
  }

  const other = must(await fixture.adminB.rpc('company_overview', { p_company_id: B }), 'overview B').data;
  ok('rides: the other company\'s counts stayed at zero', other.riders_today === 0 && other.riders_next === 0, JSON.stringify([other.riders_today, other.riders_next]));
  const platform = must(await fixture.platform.rpc('platform_overview'), 'platform').data;
  ok('rides: the platform total is the sum of the companies',
    platform.riders_today === platform.per_company.reduce((sum, r) => sum + r.riders_today, 0), String(platform.riders_today));
  await adminA.removeChannel(channel);
}

const fixture = {};
async function setup() {
  const signedIn = async (email) => { const c = anon(); must(await c.auth.signInWithPassword({ email, password: PASSWORD }), `sign-in ${email}`); return c; };
  const invoke = async (client, name, body) => { const { data, error } = await client.functions.invoke(name, { body }); if (error) throw new Error(`${name}: ${(await error.context?.json?.().catch(() => ({})))?.error ?? error.message}`); return data; };

  const superEmail = `super-pr-${run}@local.test`;
  const superUser = must(await service.auth.admin.createUser({ email: superEmail, password: PASSWORD, email_confirm: true }), 'super').data.user;
  created.users.push(superUser.id);
  must(await service.from('admins').insert({ id: superUser.id, email: superEmail, full_name: 'PR Super', role: 'super_admin' }), 'super row');
  fixture.platform = await signedIn(superEmail);
  const university = must(await service.from('universities').insert({ name: `جامعة اختبار ${run}` }).select('id, name').single(), 'university').data;
  universityName = university.name;

  for (const c of ['A', 'B']) {
    const company = await invoke(fixture.platform, 'admin-create-company', {
      name: `شركة ركاب ${c} ${run}`, admin: { fullName: `مدير ${c}`, email: `ride-${c}-${run}@local.test`, password: PASSWORD } });
    created.companies.push(company.id); created.users.push(company.adminId);
    fixture[`admin${c}`] = await signedIn(`ride-${c}-${run}@local.test`);
  }
  const { adminA } = fixture;
  fixture.lineA = must(await adminA.rpc('save_line', { p_line: {
    name: `خط ركاب ${run}`, origin_name: 'البداية', destination_university_id: university.id,
    price_termly: 1000, price_yearly: 1800, price_daily: 50, stations: [{ name: 'محطة 1' }],
    trips: [{ direction: 'departure', start_time: '07:00', stops: [{ station_index: 0, time: '07:10' }] }] } }), 'line').data;
  fixture.stationA = must(await service.from('stations').select('id').eq('line_id', fixture.lineA).single(), 'station').data.id;
  fixture.tripA = must(await service.from('line_trips').select('id').eq('line_id', fixture.lineA).single(), 'trip').data.id;
  const supPhone = newPhone();
  const sup = await invoke(adminA, 'admin-create-supervisor', { fullName: 'مشرف الركاب', phone: supPhone, password: PASSWORD, lineIds: [fixture.lineA] });
  created.users.push(sup.id);
  fixture.supervisorA = await signedIn(`${supPhone}@busak.app`);

  const today = (await service.rpc('cairo_today')).data;
  const nextRide = (await service.rpc('next_votable_ride_date')).data;
  fixture.students = [];
  for (let i = 0; i < 4; i++) {
    const phone = newPhone();
    const user = must(await service.auth.admin.createUser({ email: `${phone}@busak.app`, password: PASSWORD, email_confirm: true }), 'student').data.user;
    created.users.push(user.id);
    must(await service.from('students').insert({ id: user.id, phone, full_name: `راكب اختبار رقم ${i + 1} هنا`, university: university.name }), 'student row');
    must(await service.from('subscriptions').insert({
      student_id: user.id, line_id: fixture.lineA, station_id: fixture.stationA, departure_trip_id: fixture.tripA,
      type: 'daily', status: 'active', start_date: today, end_date: nextRide > today ? nextRide : today, price: 50 }), 'subscription');
    fixture.students.push(user.id);
  }
}

async function cleanup() {
  for (const id of created.companies) {
    await service.from('subscriptions').delete().eq('company_id', id);
    await service.from('lines').delete().eq('company_id', id);
  }
  for (const id of [...created.users].reverse()) await service.auth.admin.deleteUser(id).catch(() => {});
  for (const id of created.companies) await service.from('companies').delete().eq('id', id);
  await service.from('universities').delete().like('name', `%${run}`);
}

let failed = false;
try { await setup(); await phones(); await rides(); } catch (error) { failed = true; console.error('ABORTED:', error.message); }
await cleanup().catch((error) => console.error('cleanup:', error.message));
for (const r of results) if (!r.pass) console.log(`FAIL ${r.step}  [${r.detail}]`);
const passed = results.filter((r) => r.pass).length;
console.log(`phone + rides: ${passed}/${results.length} passed`);
process.exit(failed || passed !== results.length ? 1 : 0);
