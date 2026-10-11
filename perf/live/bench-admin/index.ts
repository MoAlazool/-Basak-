// Temporary Edge Function for the live capacity benchmark (docs/audit/2026-10-CAPACITY.md).
// Deployed as `bench-admin`, removed when the benchmark is over.
//
// It does what perf/live/auth_users.mjs does, but from inside the project, so the
// benchmark needs nothing on anyone's machine: benchmark sign-in accounts are made
// and removed ONLY through the Auth Admin API, and test files are removed ONLY
// through the Storage API. Accounts are recognisable by their e-mail
// (@bench.busak.app); the platform admin and every other account are never touched.
//
// Caller: the database (pg_net), with the same x-dispatch-secret as push-dispatch
// and storage-cleanup (PUSH_DISPATCH_SECRET). A Supabase JWT is neither needed nor accepted.
//
// POST {action: "create", role: "student"|"supervisor"|"company_admin", from: 1, to: 250}
// POST {action: "delete", limit: 300}         -> removes up to `limit` benchmark accounts
// POST {action: "count"}
// POST {action: "storage_remove", bucket, paths: [...]}
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const DOMAIN = 'bench.busak.app';
const PLATFORM_ADMIN = 'c5ca34e1-0285-45ef-9ee6-8c7e656ca5f6';
const BUCKETS = new Set(['receipts', 'student-avatars', 'supervisor-avatars', 'wallet-assets', 'offer-assets']);
const CONCURRENCY = 8;

const FIRST = ['محمد', 'أحمد', 'محمود', 'علي', 'عمر', 'يوسف', 'إبراهيم', 'مصطفى', 'خالد', 'حسن', 'كريم', 'عبد الرحمن',
  'فاطمة', 'مريم', 'نور', 'سارة', 'آية', 'هبة', 'منة', 'ياسمين', 'ندى', 'رنا', 'دينا', 'سلمى'];
const REST = ['عادل', 'فؤاد', 'السيد', 'حسين', 'عبد الله', 'سعيد', 'جمال', 'رضا', 'شريف', 'طارق', 'ماهر', 'نبيل',
  'الشناوي', 'البنا', 'النجار', 'الصاوي', 'الجمال', 'غنيم', 'سالم', 'عوض', 'بدوي'];
const nameOf = (n: number) => `${FIRST[n % FIRST.length]} ${REST[(n * 7) % REST.length]} ${REST[(n * 13 + 5) % REST.length]}`;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

function secretMatches(expected: string | undefined, given: string | null): boolean {
  if (!expected || !given) return false;
  const a = new TextEncoder().encode(expected), b = new TextEncoder().encode(given);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

function account(role: string, n: number) {
  if (role === 'student') {
    const phone = `0125${String(n).padStart(7, '0')}`;
    return { email: `${phone}@${DOMAIN}`, meta: { role, phone, full_name: nameOf(n) } };
  }
  if (role === 'supervisor') {
    const phone = `0105${String(n).padStart(7, '0')}`;
    return { email: `${phone}@${DOMAIN}`, meta: { role, phone, full_name: `مشرف ${nameOf(n + 500)}` } };
  }
  if (role === 'company_admin') return { email: `admin-${n}@${DOMAIN}`, meta: { role, full_name: `مدير ${nameOf(n + 900)}` } };
  throw new Error('unknown role');
}

async function pool<T>(items: T[], fn: (item: T) => Promise<void>) {
  let i = 0, ok = 0, failed = 0;
  const ms: number[] = [];
  const errors: string[] = [];
  await Promise.all(Array.from({ length: CONCURRENCY }, async () => {
    while (i < items.length) {
      const item = items[i++];
      const t0 = performance.now();
      try { await fn(item); ok++; ms.push(performance.now() - t0); } catch (e) {
        failed++; if (errors.length < 5) errors.push(String((e as Error).message ?? e).slice(0, 160));
      }
    }
  }));
  ms.sort((a, b) => a - b);
  const q = (p: number) => (ms.length ? Math.round(ms[Math.min(ms.length - 1, Math.floor(p * ms.length))]) : null);
  return { ok, failed, median_ms: q(0.5), p95_ms: q(0.95), errors };
}

async function benchUsers(service: ReturnType<typeof createClient>, limit = Infinity) {
  const out: { id: string; email: string }[] = [];
  for (let page = 1; out.length < limit; page++) {
    const { data, error } = await service.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    for (const u of data.users) {
      if (u.id !== PLATFORM_ADMIN && u.email?.endsWith(`@${DOMAIN}`)) out.push({ id: u.id, email: u.email });
    }
    if (data.users.length < 1000) break;
  }
  return out.slice(0, limit);
}

Deno.serve(async (request: Request) => {
  if (!secretMatches(Deno.env.get('PUSH_DISPATCH_SECRET'), request.headers.get('x-dispatch-secret'))) {
    return json({ error: 'unauthorized' }, 401);
  }
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL'), key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json({ error: 'not_configured' }, 500);
  const service = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const body = await request.json().catch(() => ({}));
  const started = performance.now();

  try {
    if (body.action === 'create') {
      const from = Number(body.from), to = Number(body.to);
      if (!(from >= 1 && to >= from && to - from < 1000)) return json({ error: 'bad range' }, 400);
      const items = Array.from({ length: to - from + 1 }, (_, k) => account(body.role, from + k));
      const r = await pool(items, async (a) => {
        const { error } = await service.auth.admin.createUser({
          email: a.email, password: crypto.randomUUID() + crypto.randomUUID(), email_confirm: true, user_metadata: a.meta,
        });
        if (error && !/already been registered|already exists/i.test(error.message)) throw error;
      });
      return json({ action: 'create', role: body.role, from, to, ...r, seconds: (performance.now() - started) / 1000 });
    }
    if (body.action === 'delete') {
      const users = await benchUsers(service, Math.min(Number(body.limit) || 300, 1000));
      if (users.some((u) => u.id === PLATFORM_ADMIN || !u.email.endsWith(`@${DOMAIN}`))) throw new Error('refusing');
      const r = await pool(users, async (u) => {
        const { error } = await service.auth.admin.deleteUser(u.id);
        if (error) throw error;
      });
      return json({ action: 'delete', ...r, seconds: (performance.now() - started) / 1000 });
    }
    if (body.action === 'count') {
      return json({ action: 'count', bench_accounts: (await benchUsers(service)).length });
    }
    if (body.action === 'storage_remove') {
      if (!BUCKETS.has(body.bucket) || !Array.isArray(body.paths) || body.paths.length > 1000) {
        return json({ error: 'bad request' }, 400);
      }
      const { data, error } = await service.storage.from(body.bucket).remove(body.paths);
      if (error) throw error;
      return json({ action: 'storage_remove', bucket: body.bucket, asked: body.paths.length, removed: data?.length ?? 0 });
    }
    return json({ error: 'unknown action' }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message ?? e).slice(0, 300) }, 500);
  }
});
