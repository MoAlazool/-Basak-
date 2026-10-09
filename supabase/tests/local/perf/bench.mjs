// Benchmarks against a LOCAL stack loaded with dataset.sql, through the real API
// (PostgREST, so RLS, grants and JSON size are all included).
//
//   SUPABASE_URL=http://127.0.0.1:54321 ANON_KEY=… JWT_SECRET=… DB_URL=… \
//   node supabase/tests/local/perf/bench.mjs single          # each request alone: p50, p95, bytes
//   node supabase/tests/local/perf/bench.mjs load 10 50 100  # mixed traffic at those concurrencies
//
// Users are picked from the dataset and signed in by minting their token with the
// local JWT secret (they have no passwords). It refuses to run anywhere but locally.
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const URL_ = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
if (!/127\.0\.0\.1|localhost/.test(URL_)) throw new Error('This benchmark only runs against a local stack.');
const DB = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const env = (name) => process.env[name] ?? (() => { throw new Error(`${name} is not set`); })();
const sql = (query) => execFileSync('psql', [DB, '-qAt', '-c', query]).toString().trim();
const b64 = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
function tokenFor(userId) {
  const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: userId, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 7200 })}`;
  return `${body}.${crypto.createHmac('sha256', env('JWT_SECRET')).update(body).digest('base64url')}`;
}

// ---- Who -------------------------------------------------------------------
const company = sql(`SELECT cs.company_id FROM company_students cs JOIN companies c ON c.id = cs.company_id
                     WHERE c.name LIKE 'PERF %' GROUP BY 1 ORDER BY count(*) DESC LIMIT 1`);
const admin = sql(`SELECT id FROM admins WHERE company_id = '${company}' LIMIT 1`);
const superAdmin = sql(`SELECT id FROM admins WHERE role = 'super_admin' LIMIT 1`);
const supervisors = sql(`SELECT string_agg(id::text, ',') FROM (SELECT id FROM supervisors WHERE company_id = '${company}' ORDER BY phone LIMIT 20) x`).split(',');
const students = sql(`SELECT string_agg(student_id::text, ',') FROM (SELECT student_id FROM subscriptions
                      WHERE company_id = '${company}' AND status = 'active' AND end_date >= current_date ORDER BY id LIMIT 400) x`).split(',');
const supervisorLine = sql(`SELECT line_id FROM supervisor_lines WHERE supervisor_id = '${supervisors[0]}' ORDER BY line_id LIMIT 1`);
const someName = 'محمد عادل';
const somePhone = sql(`SELECT right(phone, 5) FROM students WHERE id = '${students[7]}'`);
const today = sql('SELECT public.cairo_today()');
const studentSub = sql(`SELECT id FROM subscriptions WHERE student_id = '${students[0]}' AND status = 'active' ORDER BY created_at DESC LIMIT 1`);
const hasFn = (name) => sql(`SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = '${name}'`) !== '0';

// ---- Requests ----------------------------------------------------------------
async function call(user, method, path, body, headers = {}) {
  const started = performance.now();
  let status = 0, bytes = 0, text = '';
  try {
    const response = await fetch(`${URL_}/rest/v1/${path}`, {
      method, signal: AbortSignal.timeout(15000),
      headers: { apikey: env('ANON_KEY'), Authorization: `Bearer ${tokenFor(user)}`, 'Content-Type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    text = await response.text();
    status = response.status; bytes = Buffer.byteLength(text);
  } catch (error) {
    status = error.name === 'TimeoutError' ? 599 : 598;
  }
  return { ms: performance.now() - started, status, bytes, text };
}
const rpc = (user, name, args = {}) => call(user, 'POST', `rpc/${name}`, args);
const get = (user, path, headers) => call(user, 'GET', path, undefined, headers);

const studentsSelect = encodeURIComponent('id,phone,full_name,university,college,profile_image_url,created_at,company_students!inner(company_id,status),subscriptions(id,status,type,price,created_at,start_date,end_date,period_label,period_phase,departure_time,return_time,lines(name),departure_trip:departure_trip_id(label,universities(name)))');
const studentsOld = (search, offset = 0) =>
  `students?select=${studentsSelect}&company_students.company_id=eq.${company}&company_students.status=eq.active&subscriptions.company_id=eq.${company}`
  + (search ? `&or=${encodeURIComponent(`(full_name.ilike.*${search}*,phone.ilike.*${search}*,university.ilike.*${search}*)`)}` : '')
  + `&order=created_at.desc&offset=${offset}&limit=26`;
const studentsCount = (search) =>
  `students?select=${encodeURIComponent('id,company_students!inner(company_id,status)')}&company_students.company_id=eq.${company}&company_students.status=eq.active`
  + (search ? `&or=${encodeURIComponent(`(full_name.ilike.*${search}*,phone.ilike.*${search}*,university.ilike.*${search}*)`)}` : '') + '&limit=1';

/** The old receipts loader: five requests in three stages. */
async function pendingReceiptsOld(user) {
  const started = performance.now();
  const first = await get(user, `receipts?select=id,image_url,attempt_number,created_at,subscription_id,amount&company_id=eq.${company}&status=eq.pending&order=created_at.asc&limit=51`);
  const receipts = JSON.parse(first.text || '[]');
  const subIds = [...new Set(receipts.map((r) => r.subscription_id))];
  const second = await get(user, `subscriptions?select=id,type,price,student_id,line_id,station_id,departure_time,return_time,start_date,end_date,period_label,period_phase&id=in.(${subIds.join(',')})`);
  const subs = JSON.parse(second.text || '[]');
  const ids = (key) => [...new Set(subs.map((s) => s[key]))].join(',');
  const third = await Promise.all([
    get(user, `students?select=id,full_name,phone,university,college&id=in.(${ids('student_id')})`),
    get(user, `lines?select=id,name,company_id,companies(name)&id=in.(${ids('line_id')})`),
    get(user, `stations?select=id,name&id=in.(${ids('station_id')})`),
  ]);
  const all = [first, second, ...third];
  return { ms: performance.now() - started, status: Math.max(...all.map((r) => r.status)), bytes: all.reduce((sum, r) => sum + r.bytes, 0), requests: 5 };
}

const single = {
  // Student
  'student: role (my_role)': () => rpc(students[0], 'my_role'),
  'student: current subscription': () => get(students[0], `subscriptions?select=id,status,type,price,start_date,end_date,line_id,station_id,lines(name),stations(name)&student_id=eq.${students[0]}&order=created_at.desc`),
  'student: subscription history': () => get(students[0], `subscriptions?select=id,status,type,price,start_date,end_date,period_code,academic_year,lines(name)&student_id=eq.${students[0]}&order=created_at.desc`),
  'student: receipts of one subscription': () => get(students[0], `receipts?select=id,status,attempt_number,created_at,rejection_reason&subscription_id=eq.${studentSub}&order=created_at.desc`),
  'student: catalog': () => rpc(students[0], 'get_subscription_catalog'),
  'student: profile': () => get(students[0], `students?select=id,full_name,phone,university,college,profile_image_url,email,birth_date&id=eq.${students[0]}`),
  'student: card (QR) data': () => get(students[0], `students?select=id,full_name,qr_code_value,profile_image_url,university&id=eq.${students[0]}`),
  "student: today's vote": () => get(students[0], `daily_ride_status?select=ride_date,is_riding,is_returning,departure_time,return_time&student_id=eq.${students[0]}&ride_date=gte.${today}`),
  'student: vote settings': () => rpc(students[0], 'get_vote_settings', { p_company_id: company }),
  'student: inbox page': () => rpc(students[0], 'get_my_notifications_page'),
  'student: unread count': () => rpc(students[0], 'get_my_unread_count'),
  // Supervisor
  'supervisor: dashboard': () => rpc(supervisors[0], 'get_supervisor_dashboard'),
  'supervisor: trip manifest': () => rpc(supervisors[0], 'get_supervisor_trip_manifest', { p_line_id: supervisorLine, p_direction: 'departure' }),
  'supervisor: rider counts (one line)': () => rpc(supervisors[0], 'get_line_rider_counts_with_returns', { p_line_id: supervisorLine, p_ride_date: today }),
  'supervisor: monthly summary': () => rpc(supervisors[0], 'get_supervisor_monthly_summary'),
  // Company admin
  'admin: company overview': () => rpc(admin, 'company_overview', { p_company_id: company }),
  'admin: students page 1 (old: nested select)': () => get(admin, studentsOld('')),
  'admin: students exact count (old)': () => get(admin, studentsCount(''), { Prefer: 'count=exact', Range: '0-0' }),
  'admin: students page 400 (old)': () => get(admin, studentsOld('', 10000)),
  'admin: students search by name (old)': () => get(admin, studentsOld(someName)),
  'admin: students search by phone (old)': () => get(admin, studentsOld(somePhone)),
  'admin: pending receipts (old: 5 requests)': () => pendingReceiptsOld(admin),
  'admin: financial report': () => rpc(admin, 'admin_subscription_report', { p_filters: {} }),
  'admin: financial report, first 100 rows': () => rpc(admin, 'admin_subscription_report', { p_filters: { limit: 100 } }),
  'admin: financial report, search': () => rpc(admin, 'admin_subscription_report', { p_filters: { search: someName } }),
  'admin: financial report, current phase': () => rpc(admin, 'admin_subscription_report', { p_filters: { phase: 'current', payment: 'paid' } }),
  'admin: notifications history': () => rpc(admin, 'get_company_notifications_page', { p_company_id: company }),
  'admin: subscription settings': () => rpc(admin, 'get_subscription_settings', { p_company_id: company }),
  // Platform
  'platform: overview': () => rpc(superAdmin, 'platform_overview'),
  'platform: all students page': () => rpc(superAdmin, 'platform_students', {}),
  'platform: all students search': () => rpc(superAdmin, 'platform_students', { p_search: someName }),
  'platform: notifications history': () => rpc(superAdmin, 'get_platform_notifications_page', {}),
  'platform: university counts': () => rpc(superAdmin, 'university_student_counts'),
};
if (hasFn('get_company_students_page')) Object.assign(single, {
  'admin: students page 1 (new RPC, with total)': () => rpc(admin, 'get_company_students_page', { p_company_id: company, p_with_total: true }),
  'admin: students page 1 (new RPC)': () => rpc(admin, 'get_company_students_page', { p_company_id: company }),
  'admin: students page 400 (new RPC)': () => rpc(admin, 'get_company_students_page', { p_company_id: company, p_offset: 10000 }),
  'admin: students search by name (new RPC, with total)': () => rpc(admin, 'get_company_students_page', { p_company_id: company, p_search: someName, p_with_total: true }),
  'admin: students search by phone (new RPC)': () => rpc(admin, 'get_company_students_page', { p_company_id: company, p_search: somePhone }),
});
if (hasFn('get_pending_receipts_page')) single['admin: pending receipts (new RPC)'] = () => rpc(admin, 'get_pending_receipts_page', { p_company_id: company });
if (hasFn('get_lines_rider_counts')) single['supervisor: rider counts (all lines, one call)'] = () =>
  rpc(supervisors[0], 'get_lines_rider_counts', { p_line_ids: sql(`SELECT string_agg(line_id::text, ',') FROM supervisor_lines WHERE supervisor_id = '${supervisors[0]}'`).split(','), p_ride_date: today });

const pct = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
const summary = (times) => { const s = [...times].sort((a, b) => a - b); return { p50: pct(s, 0.5), p95: pct(s, 0.95), p99: pct(s, 0.99), max: s[s.length - 1] }; };
const f = (n) => n.toFixed(n < 10 ? 1 : 0);

async function runSingle(filter) {
  console.log('| Request | p50 ms | p95 ms | payload |\n|---|---:|---:|---:|');
  for (const [name, fn] of Object.entries(single)) {
    if (filter && !name.includes(filter)) continue;
    await fn();                                    // warm-up
    const times = []; let last;
    for (let i = 0; i < 15; i++) { last = await fn(); times.push(last.ms); }
    const s = summary(times);
    const size = last.bytes > 2048 ? `${(last.bytes / 1024).toFixed(0)} KB` : `${last.bytes} B`;
    console.log(`| ${name}${last.status >= 400 ? ` — HTTP ${last.status}` : ''} | ${f(s.p50)} | ${f(s.p95)} | ${size} |`);
  }
}

// ---- Mixed traffic -------------------------------------------------------------
// One "user" keeps doing what their role does, with a short think time between
// actions: 80% students, 15% supervisors, 5% admins.
const pick = (list) => list[Math.floor(Math.random() * list.length)];
const journeys = {
  student: (id) => [
    // Weighted by repetition: the app reads the catalog only when the purchase
    // screen is opened (about one action in ten here), not at every start.
    ...Array.from({ length: 3 }, () => ['student: unread count', () => rpc(id, 'get_my_unread_count')]),
    ...Array.from({ length: 5 }, () => ['student: open app', () => Promise.all([rpc(id, 'my_role'),
      get(id, `subscriptions?select=id,status,type,price,start_date,end_date,line_id,station_id,lines(name),stations(name)&student_id=eq.${id}&order=created_at.desc`),
      get(id, `students?select=id,full_name,phone,university,profile_image_url,qr_code_value&id=eq.${id}`),
      rpc(id, 'get_my_notifications_page'),
      get(id, `daily_ride_status?select=ride_date,is_riding,is_returning&student_id=eq.${id}&ride_date=gte.${today}`)])]),
    ['student: catalog (purchase screen)', () => rpc(id, 'get_subscription_catalog')],
  ],
  supervisor: (id) => [
    ['supervisor: dashboard', () => rpc(id, 'get_supervisor_dashboard')],
    ['supervisor: monthly summary', () => rpc(id, 'get_supervisor_monthly_summary')],
  ],
  admin: () => [
    ['admin: overview', () => rpc(admin, 'company_overview', { p_company_id: company })],
    ['admin: students page', () => hasStudentsRpc
      ? rpc(admin, 'get_company_students_page', { p_company_id: company, p_offset: 25 * Math.floor(Math.random() * 40) })
      : get(admin, studentsOld('', 25 * Math.floor(Math.random() * 40)))],
    ['admin: pending receipts', () => hasReceiptsRpc ? rpc(admin, 'get_pending_receipts_page', { p_company_id: company }) : pendingReceiptsOld(admin)],
    ['admin: report', () => rpc(admin, 'admin_subscription_report', { p_filters: { phase: 'current' } })],
  ],
};
const hasStudentsRpc = hasFn('get_company_students_page');
const hasReceiptsRpc = hasFn('get_pending_receipts_page');

async function runLoad(users, seconds = 30) {
  const until = Date.now() + seconds * 1000;
  const samples = new Map(); let errors = 0, timeouts = 0, actions = 0;
  const record = (name, result) => {
    const list = Array.isArray(result) ? result : [result];
    const ms = Math.max(...list.map((r) => r.ms));
    for (const r of list) { if (r.status === 599) timeouts++; else if (r.status >= 400 || r.status === 598) errors++; }
    if (!samples.has(name)) samples.set(name, []);
    samples.get(name).push(ms); actions++;
  };
  await Promise.all(Array.from({ length: users }, async (_, index) => {
    const roll = index % 20;
    const steps = roll < 16 ? journeys.student(pick(students)) : roll < 19 ? journeys.supervisor(pick(supervisors)) : journeys.admin();
    while (Date.now() < until) {
      const [name, fn] = pick(steps);
      const started = performance.now();
      const result = await fn();
      record(name, Array.isArray(result) ? result.map((r) => ({ ...r, ms: performance.now() - started })) : result);
      await new Promise((resolve) => setTimeout(resolve, 200 + Math.random() * 600));   // think time
    }
  }));
  const all = [...samples.values()].flat();
  const s = summary(all);
  console.log(`\n### ${users} concurrent users, ${seconds} s — ${actions} actions (${(actions / seconds).toFixed(1)}/s), errors ${errors}, timeouts ${timeouts}`);
  console.log(`all actions: p50 ${f(s.p50)} ms, p95 ${f(s.p95)} ms, p99 ${f(s.p99)} ms, max ${f(s.max)} ms\n`);
  console.log('| Action | count | p50 ms | p95 ms | p99 ms |\n|---|---:|---:|---:|---:|');
  for (const [name, times] of [...samples.entries()].sort()) {
    const t = summary(times);
    console.log(`| ${name} | ${times.length} | ${f(t.p50)} | ${f(t.p95)} | ${f(t.p99)} |`);
  }
}

const [mode, ...rest] = process.argv.slice(2);
if (mode === 'single') await runSingle(rest[0]);
else if (mode === 'load') for (const users of (rest.length ? rest : ['10', '50', '100'])) await runLoad(Number(users));
else console.log('usage: bench.mjs single [filter] | load [users …]');
