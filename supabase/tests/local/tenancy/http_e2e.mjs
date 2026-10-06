// End-to-end test of the company workspace model through the real API: Auth,
// PostgREST, Storage, Realtime and the admin Edge Functions of a LOCAL Supabase
// stack. Never point this at a real project: it creates companies and accounts.
//   SUPABASE_URL=... ANON_KEY=... SERVICE_KEY=... node supabase/tests/local/tenancy/http_e2e.mjs
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../../../admin_web/package.json'));
const { createClient } = require('@supabase/supabase-js');

const URL_ = process.env.SUPABASE_URL;
const ANON = process.env.ANON_KEY;
const SERVICE = process.env.SERVICE_KEY;
if (!/127\.0\.0\.1|localhost/.test(URL_ ?? '')) throw new Error('This test only runs against a local stack.');
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL_, SERVICE, opts);

const results = [];
const ok = (step, pass, detail = '') => { results.push({ step, pass: !!pass, detail: pass ? '' : String(detail ?? '') }); };
const must = (value, label) => { if (value?.error) throw new Error(`${label}: ${value.error.message}`); return value; };
const run = crypto.randomBytes(3).toString('hex');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const PASSWORD = `Pw-${crypto.randomBytes(9).toString('base64url')}`;
const digits = (n) => Array.from(crypto.randomBytes(n), (b) => b % 10).join('');

async function signedIn(email) {
  const client = createClient(URL_, ANON, opts);
  must(await client.auth.signInWithPassword({ email, password: PASSWORD }), `sign-in ${email}`);
  return client;
}

async function invoke(client, name, body) {
  const { data, error } = await client.functions.invoke(name, { body });
  if (!error) return { data, status: 200 };
  let payload = {};
  try { payload = await error.context.json(); } catch { /* not json */ }
  return { error: payload.error ?? error.message, status: error.context?.status };
}

/** Collects the live receipt changes one signed-in client receives for one company. */
async function watchReceipts(client, companyId) {
  const events = [];
  const { data: { session } } = await client.auth.getSession();
  await client.realtime.setAuth(session.access_token);
  const channel = client.channel(`receipts-${companyId}-${crypto.randomUUID()}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'receipts', filter: `company_id=eq.${companyId}` },
      (payload) => events.push(payload));
  // SUBSCRIBED only means the socket joined; the change feed is live once the
  // server confirms it with a system message.
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('realtime subscribe timed out')), 20000);
    channel.on('system', {}, (message) => {
      if (message.extension === 'postgres_changes' && message.status === 'ok') { clearTimeout(timer); resolve(); }
    }).subscribe();
  });
  return { events, close: () => client.removeChannel(channel) };
}

/** Joins a private broadcast topic. `joined` is false when the database refuses the listener. */
async function listen(client, topic) {
  const events = [];
  const { data: { session } } = await client.auth.getSession();
  await client.realtime.setAuth(session.access_token);
  const channel = client.channel(topic, { config: { private: true } })
    .on('broadcast', { event: 'change' }, (message) => events.push(message.payload));
  const joined = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), 8000);
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') { clearTimeout(timer); resolve(true); }
      if (status === 'CHANNEL_ERROR' || status === 'CLOSED' || status === 'TIMED_OUT') { clearTimeout(timer); resolve(false); }
    });
  });
  return { events, joined, close: () => client.removeChannel(channel) };
}

const created = { users: [], companies: [] };

async function main() {
  // ---------------------------------------------------------- platform admin
  const superEmail = `super-${run}@local.test`;
  const superUser = must(await service.auth.admin.createUser({ email: superEmail, password: PASSWORD, email_confirm: true }), 'super user').data.user;
  created.users.push(superUser.id);
  must(await service.from('admins').insert({ id: superUser.id, email: superEmail, full_name: 'Tenancy Super', role: 'super_admin' }), 'super row');
  const platform = await signedIn(superEmail);
  const university = must(await service.from('universities').insert({ name: `جامعة ${run}` }).select('id, name').single(), 'university').data;

  // ---------------------------------------------------------- create company
  const adminEmail = (c) => `admin-${c}-${run}@local.test`;
  const newCompany = (c, extra = {}) => invoke(platform, 'admin-create-company', {
    name: `شركة ${c} ${run}`, contactPhone: '01000000000', contactLabel: 'خدمة العملاء',
    admin: { fullName: `مدير ${c}`, email: adminEmail(c), password: PASSWORD },
    paymentMethod: { methodType: 'vodafone_cash', displayName: `محفظة ${c}`, walletPhone: '01012345678' }, ...extra,
  });
  const a = await newCompany('A');
  ok('create company: succeeds', a.status === 200 && a.data?.id, a.error);
  const A = a.data.id;
  created.companies.push(A); created.users.push(a.data.adminId);
  const [terms, wallet, admins, methods] = await Promise.all([
    service.from('company_terms').select('code').eq('company_id', A),
    service.from('wallet_card_settings').select('company_id').eq('company_id', A),
    service.from('admins').select('id, role').eq('company_id', A),
    service.from('company_payment_methods').select('id').eq('company_id', A),
  ]);
  ok('create company: its own terms, card design, first admin and payment method exist',
    terms.data?.length === 3 && wallet.data?.length === 1 && admins.data?.length === 1 && methods.data?.length === 1,
    JSON.stringify([terms.data?.length, wallet.data?.length, admins.data?.length, methods.data?.length]));

  const duplicate = await newCompany('A', { admin: { fullName: 'x y', email: `dup-${run}@local.test`, password: PASSWORD } });
  ok('create company: a second company with the same name is refused', duplicate.status === 409, `${duplicate.status} ${duplicate.error}`);
  const before = (await service.from('companies').select('id', { count: 'exact', head: true })).count;
  const clash = await invoke(platform, 'admin-create-company', {
    name: `شركة مرتجعة ${run}`, admin: { fullName: 'مدير مكرر', email: adminEmail('A'), password: PASSWORD },
  });
  const after = (await service.from('companies').select('id', { count: 'exact', head: true })).count;
  ok('create company: if the admin cannot be created, no company is left behind', clash.status === 409 && after === before, `${clash.status} ${before}->${after}`);
  const badMethod = await invoke(platform, 'admin-create-company', {
    name: `شركة دفع ${run}`, admin: { fullName: 'مدير دفع', email: `pay-${run}@local.test`, password: PASSWORD },
    paymentMethod: { methodType: 'vodafone_cash', displayName: 'x', walletPhone: '123' },
  });
  const afterBad = (await service.from('companies').select('id', { count: 'exact', head: true })).count;
  const orphan = (await service.from('admins').select('id').eq('email', `pay-${run}@local.test`)).data;
  ok('create company: a bad payment method rolls back the company and its admin', badMethod.status === 400 && afterBad === before && orphan.length === 0,
    `${badMethod.status} ${afterBad} ${orphan.length}`);

  const b = await newCompany('B');
  ok('create company: a second company', b.status === 200, b.error);
  const B = b.data.id;
  created.companies.push(B); created.users.push(b.data.adminId);

  const adminA = await signedIn(adminEmail('A'));
  const adminB = await signedIn(adminEmail('B'));
  ok('company admin cannot create companies', (await invoke(adminA, 'admin-create-company', { name: 'x', admin: {} })).status === 403);
  ok('company admin cannot create admins', (await invoke(adminA, 'admin-create-company-admin', {
    email: `x-${run}@local.test`, fullName: 'x', password: PASSWORD, companyId: B })).status === 403);

  // ------------------------------------------------- each company builds itself
  const line = (c) => ({
    name: `خط ${c} ${run}`, origin_name: 'البداية', destination_university_id: university.id,
    price_termly: 1000, price_yearly: 1800, price_daily: 50,
    stations: [{ name: 'محطة 1' }],
    trips: [{ direction: 'departure', start_time: '07:00', stops: [{ station_index: 0, time: '07:10' }] }],
  });
  const lineA = must(await adminA.rpc('save_line', { p_line: line('A') }), 'line A').data;
  const lineB = must(await adminB.rpc('save_line', { p_line: line('B') }), 'line B').data;
  const stationOf = async (id) => must(await service.from('stations').select('id, company_id').eq('line_id', id).single(), 'station').data;
  const [stationA, stationB] = [await stationOf(lineA), await stationOf(lineB)];
  ok('a line and its stations carry their company', stationA.company_id === A && stationB.company_id === B);
  const forced = await adminA.rpc('save_line', { p_line: { ...line('X'), company_id: B } });
  const strays = (await service.from('lines').select('id').eq('company_id', B)).data.length;
  ok('a company admin naming another company still only creates in their own', strays === 1, `${forced.error?.message} lines of B: ${strays}`);

  const supPhone = `010${digits(8)}`;
  const sup = await invoke(adminA, 'admin-create-supervisor', { fullName: 'مشرف A', phone: supPhone, password: PASSWORD, companyId: B, lineIds: [lineA] });
  ok('create supervisor: a company admin is pinned to their own company', sup.status === 200, sup.error);
  if (sup.data?.id) created.users.push(sup.data.id);
  ok('create supervisor: saved under the admin\'s company, not the one sent',
    (await service.from('supervisors').select('company_id').eq('id', sup.data.id).single()).data.company_id === A);
  ok('create supervisor: lines of another company are refused',
    (await invoke(adminA, 'admin-create-supervisor', { fullName: 'مشرف', phone: `011${digits(8)}`, password: PASSWORD, lineIds: [lineB] })).status === 400);

  const student = (phone, lineId, stationId) => ({
    fullName: 'طالب تجربة العزل الكامل', phone, university: university.name, password: PASSWORD,
    lineId, stationId, subscriptionType: 'termly', departureTime: '07:10',
  });
  const phone = `012${digits(8)}`;
  ok('create student: on another company\'s line is refused',
    (await invoke(adminA, 'admin-create-student', student(phone, lineB, stationB.id))).status === 403);
  const stu = await invoke(adminA, 'admin-create-student', student(phone, lineA, stationA.id));
  ok('create student: on the admin\'s own line', stu.status === 200, stu.error);
  const S = stu.data.id;
  created.users.push(S);
  ok('create student: the student is now a member of that company',
    (await service.from('company_students').select('company_id, status').eq('student_id', S)).data
      .every((m) => m.company_id === A && m.status === 'active'));
  ok('the student is visible to company A and not to company B',
    (await adminA.from('students').select('id').eq('id', S)).data.length === 1
    && (await adminB.from('students').select('id').eq('id', S)).data.length === 0);
  // An existing account is invited, never attached: company B learns nothing until the student accepts.
  const tripB = must(await service.from('line_trips').select('id').eq('line_id', lineB).single(), 'trip B').data.id;
  const invitation = await invoke(adminB, 'admin-create-student', { ...student(phone, lineB, stationB.id), departureTripId: tripB });
  ok('existing phone: the company gets an invitation, not a member',
    invitation.status === 200 && invitation.data?.invited === true
    && (await service.from('company_students').select('company_id').eq('student_id', S)).data.length === 1
    && (await adminB.from('students').select('id').eq('id', S)).data.length === 0, `${invitation.status} ${invitation.error}`);
  ok('existing phone: a second invitation while one is open is refused',
    (await invoke(adminB, 'admin-create-student', student(phone, lineB, stationB.id))).status === 409);
  ok('existing phone: the company sees its invitation, the other company does not',
    (await adminB.from('company_invites').select('id, phone, status')).data.length === 1
    && (await adminA.from('company_invites').select('id')).data.length === 0);

  // ---------------------------------------------- receipt, live, in one company
  const [watchA, watchB] = [await watchReceipts(adminA, A), await watchReceipts(adminB, B)];
  const watchBonA = await watchReceipts(adminB, A);  // B asking for A's feed must get nothing
  const studentClient = await signedIn(`${phone}@busak.app`);
  // Private topics: the database decides who may listen.
  // Refused joins are probed from separate connections so they cannot disturb the real listeners.
  const probe = async (email, topic) => listen(await signedIn(email), topic);
  const topics = {
    aOwn: await listen(adminA, `company:${A}`),
    bOwn: await listen(adminB, `company:${B}`),
    student: await listen(studentClient, `student:${S}`),
    studentLine: await listen(studentClient, `line:${lineA}`),
    platform: await listen(platform, 'platform'),
    bOnA: await probe(adminEmail('B'), `company:${A}`),
    studentOnCompany: await probe(`${phone}@busak.app`, `company:${A}`),
    studentOnPlatform: await probe(`${phone}@busak.app`, 'platform'),
    studentOtherLine: await probe(`${phone}@busak.app`, `line:${lineB}`),
    adminOnStudent: await probe(adminEmail('A'), `student:${S}`),
    aOnPlatform: await probe(adminEmail('A'), 'platform'),
  };
  ok('topics: each party joins its own (company, student, subscribed line, platform)',
    topics.aOwn.joined && topics.bOwn.joined && topics.student.joined && topics.studentLine.joined && topics.platform.joined,
    JSON.stringify(Object.fromEntries(Object.entries(topics).map(([k, t]) => [k, t.joined]))));
  ok('topics: nobody joins a topic that is not theirs',
    !topics.bOnA.joined && !topics.studentOnCompany.joined && !topics.studentOnPlatform.joined
    && !topics.studentOtherLine.joined && !topics.adminOnStudent.joined && !topics.aOnPlatform.joined,
    JSON.stringify(Object.fromEntries(Object.entries(topics).map(([k, t]) => [k, t.joined]))));
  const sub = must(await studentClient.from('subscriptions').select('id, company_id, status').single(), 'student subscription').data;
  const receiptPath = `${S}/${sub.id}_${Date.now()}.jpg`;
  must(await studentClient.storage.from('receipts').upload(receiptPath, Buffer.from('not really a jpeg'), { contentType: 'image/jpeg' }), 'receipt upload');
  const receipt = must(await studentClient.from('receipts').insert({ subscription_id: sub.id, image_url: receiptPath }).select('id, company_id').single(), 'receipt').data;
  ok('a receipt carries the company of its subscription', receipt.company_id === A && sub.company_id === A);
  await sleep(3000);
  ok('live: company A is told about its new receipt', watchA.events.some((e) => e.new?.id === receipt.id), `${watchA.events.length} event(s)`);
  ok('live: company B is told nothing, even when it asks for A\'s feed',
    watchB.events.length === 0 && watchBonA.events.length === 0, `${watchB.events.length}/${watchBonA.events.length}`);
  await Promise.all([watchA.close(), watchB.close(), watchBonA.close()]);

  ok('company B cannot read the receipt or its image',
    (await adminB.from('receipts').select('id').eq('id', receipt.id)).data.length === 0
    && !!(await adminB.storage.from('receipts').createSignedUrl(receiptPath, 60)).error);
  ok('company A can open the receipt image', !(await adminA.storage.from('receipts').createSignedUrl(receiptPath, 60)).error);
  ok('company B cannot approve company A\'s receipt',
    (await adminB.from('receipts').update({ status: 'approved' }).eq('id', receipt.id).select('id')).data.length === 0);
  ok('company A approves its receipt',
    (await adminA.from('receipts').update({ status: 'approved' }).eq('id', receipt.id).select('id')).data?.length === 1);
  ok('the subscription is now active', (await studentClient.from('subscriptions').select('status').single()).data.status === 'active');
  await sleep(2500);
  const seen = (t, table, op) => t.events.some((e) => e.table === table && e.op === op);
  ok('topics: the company is told about the new receipt and its approval',
    seen(topics.aOwn, 'receipts', 'INSERT') && seen(topics.aOwn, 'receipts', 'UPDATE') && seen(topics.aOwn, 'subscriptions', 'UPDATE'),
    JSON.stringify(topics.aOwn.events.map((e) => `${e.table}:${e.op}`)));
  ok('topics: the student is told their receipt was decided and their subscription changed',
    seen(topics.student, 'receipts', 'UPDATE') && seen(topics.student, 'subscriptions', 'UPDATE'),
    JSON.stringify(topics.student.events.map((e) => `${e.table}:${e.op}`)));
  ok('topics: the platform admin hears it too; company B hears nothing',
    seen(topics.platform, 'receipts', 'UPDATE') && topics.bOwn.events.length === 0 && topics.bOnA.events.length === 0,
    `${topics.platform.events.length}/${topics.bOwn.events.length}/${topics.bOnA.events.length}`);
  const allEvents = Object.values(topics).flatMap((t) => t.events);
  ok('topics: messages carry ids only, never personal data',
    allEvents.length > 0 && allEvents.every((e) => Object.keys(e).every((k) => ['table', 'op', 'id', 'company_id'].includes(k))),
    JSON.stringify(allEvents[0]));
  must(await adminA.from('stations').update({ name: 'محطة 1 (معدلة)' }).eq('id', stationA.id).select('id').single(), 'rename station');
  await sleep(2000);
  ok('topics: a route change reaches the students subscribed to that line', seen(topics.studentLine, 'stations', 'UPDATE'),
    JSON.stringify(topics.studentLine.events.map((e) => `${e.table}:${e.op}`)));
  await Promise.all(Object.values(topics).map((t) => t.close()));

  // Nested reads, as the dashboard and the mobile app make them, must still resolve
  // (one relationship per pair of tables).
  const nested = await Promise.all([
    adminA.from('lines').select('id, stations(id), line_trips(id, line_trip_stops(station_id)), line_universities(university_id)').eq('company_id', A),
    adminA.from('subscriptions').select('id, lines(name), stations(name), receipts(id)').eq('company_id', A),
    adminA.from('students').select('id, company_students!inner(company_id), subscriptions(id, lines(name))').eq('company_students.company_id', A),
    adminA.from('supervisors').select('id, supervisor_lines(line_id)').eq('company_id', A),
    studentClient.from('subscriptions').select('id, lines(name, companies(name)), stations(name), receipts(id, status)'),
  ]);
  ok('nested reads across parent and child tables still resolve', nested.every((r) => !r.error && r.data.length > 0),
    nested.map((r) => r.error?.message ?? r.data.length).join(' | '));

  // The queries the released mobile app makes, unchanged, as the student.
  const app = {
    lines: await studentClient.from('lines').select('*, companies(name), destination:destination_university_id(name)').eq('is_active', true).order('name'),
    lineOptions: await studentClient.rpc('get_student_line_options'),
    catalog: await studentClient.rpc('get_student_catalog'),
    trips: await studentClient.from('line_trips').select('id, direction, label, start_time, arrival_time, universities(name), line_trip_stops(station_id, stop_time)').eq('line_id', lineA).eq('is_active', true).order('start_time'),
    stations: await studentClient.from('stations').select().eq('line_id', lineA),
    periods: await studentClient.rpc('get_purchasable_periods', { p_line_id: lineA }),
    methods: await studentClient.from('company_payment_methods').select().eq('company_id', A),
    me: await studentClient.from('students').select().eq('id', S).single(),
    subs: await studentClient.from('subscriptions').select('*, period_label, period_phase, lines(name, companies(name)), stations(name)'),
    complaint: await studentClient.from('complaints').insert({ student_id: S, title: 'تجربة', message: 'رسالة' }).select('company_id').single(),
  };
  const broken = Object.entries(app).filter(([, r]) => r.error).map(([k, r]) => `${k}: ${r.error.message}`);
  ok('mobile app: every query of the released app still works', broken.length === 0, broken.join(' | '));
  ok('mobile app: the student finds both companies\' lines, their trips, periods and how to pay',
    app.catalog.data?.length >= 2 && app.trips.data?.length === 1 && app.stations.data?.length === 1
    && app.periods.data?.length >= 1 && app.methods.data?.length === 1 && !!app.subs.data?.[0]?.period_label,
    JSON.stringify([app.catalog.data?.length, app.trips.data?.length, app.periods.data?.length, app.methods.data?.length]));
  ok('mobile app: a complaint sent without a company reaches the student\'s company', app.complaint.data?.company_id === A);
  ok('the complaint is visible to company A and not to company B',
    (await adminA.from('complaints').select('id').eq('student_id', S)).data.length === 1
    && (await adminB.from('complaints').select('id').eq('student_id', S)).data.length === 0);

  // --------------------------------------------------------------- overviews
  const overA = await adminA.rpc('company_overview', { p_company_id: A });
  ok('overview: company A counts its member, subscription and revenue',
    overA.data?.members === 1 && overA.data?.active_subscriptions === 1 && Number(overA.data?.revenue) === 1000, JSON.stringify(overA.data ?? overA.error));
  ok('overview: company A cannot read company B\'s', !!(await adminA.rpc('company_overview', { p_company_id: B })).error);
  ok('overview: company A cannot read the platform\'s', !!(await adminA.rpc('platform_overview')).error);
  const over = must(await platform.rpc('platform_overview'), 'platform overview').data;
  const rowOf = (id) => over.per_company.find((r) => r.company.id === id);
  ok('overview: the platform sees every company, each with its own numbers',
    Number(rowOf(A)?.revenue) === 1000 && Number(rowOf(B)?.revenue) === 0 && rowOf(B)?.members === 0, JSON.stringify([rowOf(A), rowOf(B)]));

  // ------------------------------------------- removing a member, not a person
  ok('a company admin cannot delete a student\'s account', (await invoke(adminA, 'admin-delete-student', { studentId: S })).status === 403);
  ok('company B cannot remove company A\'s member', !!(await adminB.rpc('company_remove_student', { p_company_id: A, p_student_id: S })).error);
  const removed = await adminA.rpc('company_remove_student', { p_company_id: A, p_student_id: S });
  ok('company A removes the student from the company', removed.data?.removed === true, removed.error?.message);
  ok('after removal the company no longer sees the person', (await adminA.from('students').select('id').eq('id', S)).data.length === 0);
  ok('after removal the company keeps its own financial record', Number((await adminA.rpc('company_overview', { p_company_id: A })).data?.revenue) === 1000);
  const again = await signedIn(`${phone}@busak.app`);
  ok('the removed student still has their account, and their subscription has ended',
    (await again.from('students').select('id').single()).data?.id === S
    && (await again.from('subscriptions').select('status').single()).data.status === 'expired');

  // --------------------------------------------------------- suspended company
  must(await platform.from('companies').update({ status: 'suspended' }).eq('id', A).select('id').single(), 'suspend');
  ok('suspended: the admin reads no lines', (await adminA.from('lines').select('id')).data.length === 0);
  const blocked = await invoke(adminA, 'admin-create-supervisor', { fullName: 'مشرف', phone: `015${digits(8)}`, password: PASSWORD, lineIds: [lineA] });
  ok('suspended: the admin functions refuse the admin', blocked.status === 403, `${blocked.status} ${blocked.error}`);
  const supClient = await signedIn(`${supPhone}@busak.app`);
  const dash = (await supClient.rpc('get_supervisor_dashboard')).data;
  ok('suspended: the supervisor app is told the company is off and gets no lines',
    dash?.profile?.company_active === false && dash?.profile?.assignment === 'none', JSON.stringify(dash?.profile));
  ok('suspended: the supervisor cannot check anyone in',
    !!(await supClient.rpc('supervisor_check_in_student', { p_qr_code: crypto.randomUUID() })).error);
  ok('suspended: students no longer find the company', (await again.from('companies').select('id').eq('id', A)).data.length === 0);
  ok('suspended: company B is unaffected', (await adminB.from('lines').select('id')).data.length === 1);
  must(await platform.from('companies').update({ status: 'active' }).eq('id', A).select('id').single(), 'reactivate');
  ok('reactivated: the admin is back', (await adminA.from('lines').select('id')).data.length >= 1);

  // ------------------------------------------------------ invitation accepted
  const invites = (await again.rpc('get_my_invites')).data;
  ok('invitation: the student sees who invites them and to what', invites?.length === 1 && invites[0].company_id === B && !!invites[0].line_name, JSON.stringify(invites));
  ok('invitation: nobody else can answer it', !!(await adminA.rpc('respond_company_invite', { p_invite_id: invites[0].id, p_accept: true })).error);
  const accepted = await again.rpc('respond_company_invite', { p_invite_id: invites[0].id, p_accept: true });
  ok('invitation: accepting makes the student a member and opens the offered subscription',
    accepted.data?.accepted === true && !!accepted.data?.subscription_id, JSON.stringify(accepted.data ?? accepted.error));
  ok('invitation: company B now sees the student; company A (which removed them) still does not',
    (await adminB.from('students').select('id').eq('id', S)).data.length === 1
    && (await adminA.from('students').select('id').eq('id', S)).data.length === 0);

  // ------------------------------------------------------ identity corrections
  ok('correction: a company cannot edit a member\'s name directly',
    (await adminB.from('students').update({ full_name: 'اسم مغير بلا إذن أبدا' }).eq('id', S).select('id')).data.length === 0);
  ok('correction: a company that is not the student\'s cannot ask for one',
    !!(await adminA.rpc('request_student_correction', { p_company_id: A, p_student_id: S, p_field: 'full_name', p_new_value: 'طالب بعد التصحيح الكامل هنا' })).error);
  const correction = await adminB.rpc('request_student_correction', { p_company_id: B, p_student_id: S, p_field: 'full_name', p_new_value: 'طالب بعد التصحيح الكامل هنا' });
  ok('correction: the student\'s company can ask', !!correction.data, correction.error?.message);
  ok('correction: the company cannot approve its own request',
    !!(await adminB.rpc('decide_student_correction', { p_request_id: correction.data, p_approve: true })).error);
  ok('correction: the platform admin approves and the name changes',
    !(await platform.rpc('decide_student_correction', { p_request_id: correction.data, p_approve: true })).error
    && (await again.from('students').select('full_name').single()).data.full_name === 'طالب بعد التصحيح الكامل هنا');

  // ------------------------------------------------------------- all students
  const everyone = await platform.rpc('platform_students', { p_search: phone });
  const found = everyone.data?.rows?.[0];
  ok('all students: the platform admin finds the student with both memberships',
    everyone.data?.total === 1 && found?.memberships?.length === 2
    && found.memberships.some((m) => m.company_id === A && m.status === 'removed')
    && found.memberships.some((m) => m.company_id === B && m.status === 'active'), JSON.stringify(everyone.data ?? everyone.error));
  ok('all students: a company admin cannot use the platform list', !!(await adminB.rpc('platform_students', {})).error);

  // ------------------------------------------------ platform deletes an account
  ok('the platform admin can delete an account', (await invoke(platform, 'admin-delete-student', { studentId: S })).status === 200);
  ok('the company\'s revenue survives the deletion',
    Number((await adminA.rpc('company_overview', { p_company_id: A })).data?.revenue) === 1000);
}

async function cleanup() {
  for (const id of created.companies) {
    await service.from('deleted_student_revenue').delete().eq('company_id', id);
    await service.from('subscriptions').delete().eq('company_id', id);
    await service.from('lines').delete().eq('company_id', id);
  }
  for (const id of created.users.reverse()) await service.auth.admin.deleteUser(id).catch(() => {});
  for (const id of created.companies) await service.from('companies').delete().eq('id', id);
  await service.from('universities').delete().like('name', `%${run}`);
}

let failed = false;
try { await main(); } catch (error) { failed = true; console.error('ABORTED:', error.message); }
await cleanup().catch((error) => console.error('cleanup:', error.message));
for (const r of results) if (!r.pass) console.log(`FAIL ${r.step}  [${r.detail}]`);
const passed = results.filter((r) => r.pass).length;
console.log(`tenancy http: ${passed}/${results.length} passed`);
process.exit(failed || passed !== results.length ? 1 : 0);
