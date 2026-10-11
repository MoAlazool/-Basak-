#!/usr/bin/env node
// Benchmark sign-in accounts for the live capacity benchmark (docs/audit/2026-10-CAPACITY.md).
//
// Runs on the owner's machine and talks ONLY to the official Supabase Auth Admin API
// of the real project. Nothing is written to auth.users directly. Every account it makes
// has an e-mail ending in @bench.busak.app, so it can always be found and removed;
// the platform admin (and anything not on that domain) is never touched.
//
// Accounts look like the ones the app makes (Edge Function admin-create-student /
// admin-create-supervisor): confirmed e-mail login "<phone>@…", user_metadata
// {role, phone, full_name}. Students get phones 0125xxxxxxx, supervisors 0105xxxxxxx.
//
// Usage (Node 18+, no packages):
//   export SUPABASE_URL=https://hnwpkkryxovhmsrokdsd.supabase.co
//   export SUPABASE_SERVICE_ROLE_KEY=...        # never commit or paste it anywhere
//   export BENCH_PASSWORD='a long random password'  # the same for every benchmark account
//   node perf/live/auth_users.mjs count
//   node perf/live/auth_users.mjs create --students 2100 --supervisors 20 --admins 8
//   node perf/live/auth_users.mjs delete            # removes every @bench.busak.app account
//
// `create` is idempotent: it creates only the accounts that are missing up to the
// given totals, so it can be run again with larger numbers for the next stage.

const DOMAIN = 'bench.busak.app';
const PLATFORM_ADMIN = 'c5ca34e1-0285-45ef-9ee6-8c7e656ca5f6';
const CONCURRENCY = 6;

const url = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
if (!url.startsWith('https://') || !key) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY first.');
  process.exit(1);
}
const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };

const FIRST = ['محمد', 'أحمد', 'محمود', 'علي', 'عمر', 'يوسف', 'إبراهيم', 'مصطفى', 'خالد', 'حسن', 'كريم', 'عبد الرحمن',
  'فاطمة', 'مريم', 'نور', 'سارة', 'آية', 'هبة', 'منة', 'ياسمين', 'ندى', 'رنا', 'دينا', 'سلمى'];
const REST = ['عادل', 'فؤاد', 'السيد', 'حسين', 'عبد الله', 'سعيد', 'جمال', 'رضا', 'شريف', 'طارق', 'ماهر', 'نبيل',
  'الشناوي', 'البنا', 'النجار', 'الصاوي', 'الجمال', 'غنيم', 'سالم', 'عوض', 'بدوي'];
const nameOf = (n) => `${FIRST[n % FIRST.length]} ${REST[(n * 7) % REST.length]} ${REST[(n * 13 + 5) % REST.length]}`;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function call(method, path, body) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(`${url}/auth/v1${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    if (res.status === 429 || res.status >= 500) {
      if (attempt >= 6) throw new Error(`${method} ${path}: HTTP ${res.status} after retries`);
      await sleep(1000 * 2 ** attempt);
      continue;
    }
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) {
      const err = new Error(`${method} ${path}: HTTP ${res.status} ${data?.msg || data?.message || data?.error_description || ''}`);
      err.status = res.status;
      throw err;
    }
    return data;
  }
}

async function listBench() {
  const out = [];
  for (let page = 1; ; page++) {
    const data = await call('GET', `/admin/users?page=${page}&per_page=1000`);
    const users = data?.users ?? [];
    for (const u of users) if (u.email?.endsWith(`@${DOMAIN}`) && u.id !== PLATFORM_ADMIN) out.push(u);
    if (users.length < 1000) break;
  }
  return out;
}

async function pool(items, fn) {
  let i = 0, done = 0, failed = 0;
  const started = Date.now();
  const timings = [];
  await Promise.all(Array.from({ length: CONCURRENCY }, async () => {
    while (i < items.length) {
      const item = items[i++];
      const t0 = performance.now();
      try { await fn(item); timings.push(performance.now() - t0); } catch (e) { failed++; console.error(String(e.message || e)); }
      if (++done % 250 === 0) console.log(`  ${done}/${items.length}`);
    }
  }));
  timings.sort((a, b) => a - b);
  const q = (p) => (timings.length ? timings[Math.min(timings.length - 1, Math.floor(p * timings.length))].toFixed(0) : '-');
  return { done, failed, seconds: ((Date.now() - started) / 1000).toFixed(1), median_ms: q(0.5), p95_ms: q(0.95) };
}

function arg(name, fallback = 0) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? Number(process.argv[i + 1]) : fallback;
}

const cmd = process.argv[2];
if (cmd === 'count') {
  const users = await listBench();
  const by = {};
  for (const u of users) by[u.user_metadata?.role ?? '?'] = (by[u.user_metadata?.role ?? '?'] ?? 0) + 1;
  console.log(JSON.stringify({ bench_accounts: users.length, by_role: by }));
} else if (cmd === 'create') {
  const password = process.env.BENCH_PASSWORD;
  if (!password || password.length < 12) { console.error('Set BENCH_PASSWORD (12+ characters).'); process.exit(1); }
  const want = { student: arg('students'), supervisor: arg('supervisors'), company_admin: arg('admins') };
  const have = new Set((await listBench()).map((u) => u.email));
  const todo = [];
  for (let n = 1; n <= want.student; n++) {
    const phone = `0125${String(n).padStart(7, '0')}`;
    todo.push({ email: `${phone}@${DOMAIN}`, meta: { role: 'student', phone, full_name: nameOf(n) } });
  }
  for (let n = 1; n <= want.supervisor; n++) {
    const phone = `0105${String(n).padStart(7, '0')}`;
    todo.push({ email: `${phone}@${DOMAIN}`, meta: { role: 'supervisor', phone, full_name: `مشرف ${nameOf(n + 500)}` } });
  }
  for (let n = 1; n <= want.company_admin; n++) {
    todo.push({ email: `admin-${n}@${DOMAIN}`, meta: { role: 'company_admin', full_name: `مدير ${nameOf(n + 900)}` } });
  }
  const missing = todo.filter((t) => !have.has(t.email));
  console.log(`creating ${missing.length} accounts (${todo.length - missing.length} already exist)`);
  const r = await pool(missing, (t) => call('POST', '/admin/users',
    { email: t.email, password, email_confirm: true, user_metadata: t.meta }));
  console.log(JSON.stringify({ created: r.done - r.failed, failed: r.failed, seconds: r.seconds,
    create_median_ms: r.median_ms, create_p95_ms: r.p95_ms }));
} else if (cmd === 'delete') {
  const users = await listBench();
  if (users.some((u) => u.id === PLATFORM_ADMIN || !u.email.endsWith(`@${DOMAIN}`))) throw new Error('refusing: unexpected account in list');
  console.log(`deleting ${users.length} benchmark accounts`);
  const r = await pool(users, (u) => call('DELETE', `/admin/users/${u.id}`));
  console.log(JSON.stringify({ deleted: r.done - r.failed, failed: r.failed, seconds: r.seconds,
    delete_median_ms: r.median_ms, delete_p95_ms: r.p95_ms }));
  const left = await listBench();
  console.log(JSON.stringify({ bench_accounts_left: left.length }));
} else {
  console.log('usage: auth_users.mjs count | create --students N --supervisors N --admins N | delete');
}
