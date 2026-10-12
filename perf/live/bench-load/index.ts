// Temporary Edge Function: load generator for the live concurrency benchmark
// (docs/audit/2026-10-CAPACITY.md). Deployed as `bench-load`, removed afterwards.
//
// One invocation runs a group of virtual users (VUs) against this project's own
// API gateway (/rest/v1), each with a real signed-in user's token: PostgREST runs
// as `authenticated` and every row goes through RLS. No service key is used for
// the measured traffic. Calls and select strings are the app's own (see
// subscription_gateway.dart, daily_ride_repository.dart, supervisor_repository.dart
// and admin_web/src/lib/*.ts).
//
// Caller: the database (pg_net) with the push dispatch secret. Many invocations
// run in parallel for one stage; each returns counters and latency histograms,
// which the database merges.
//
// Modes: rush (each app open as the app made it before 20261125000001: seven
// requests), bundle (the same open as the new app makes it: get_student_home,
// one request), mixed (rush plus writes), scan (supervisors scanning), burst.
//
// POST {mode: 'rush'|'bundle'|'mixed'|'scan'|'burst', t0: epoch ms, ramp_s, hold_s, down_s,
//       think: [min_s, max_s], today, week_from, week_to, from30, timeout_ms,
//       vus: [{role, id, token, ctx}]}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

function secretMatches(expected: string | undefined, given: string | null): boolean {
  if (!expected || !given) return false;
  const a = new TextEncoder().encode(expected), b = new TextEncoder().encode(given);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

const SUB_SELECT = 'id,student_id,line_id,company_id,station_id,type,status,start_date,end_date,price,created_at,' +
  'departure_time,return_time,period_code,academic_year,period_label,period_phase,' +
  'lines(name,companies(id,name,logo_path,emblem_path),supervisors(full_name,phone,profile_image_url),' +
  'line_trips(direction,is_active,start_time)),student:students(university),' +
  'stations(name,departure_times,return_times,line_trip_stops(stop_time,line_trips(direction,is_active,start_time))),' +
  'departure_trip:departure_trip_id(label,start_time,universities(name)),return_trip:return_trip_id(start_time)';
const RECEIPT_SELECT = 'subscription_id,receipt_code,company_name,student_name,student_phone,university_name,line_name,' +
  'station_name,period_label,start_date,end_date,amount,payment_method,approved_at,company_phone,company_address,' +
  'company_commercial_register,company_tax_number,company_logo_path';

// Latency histogram: bucket k holds [1.1^k, 1.1^(k+1)) ms.
const bucket = (ms: number) => Math.max(0, Math.min(140, Math.floor(Math.log(Math.max(ms, 1)) / Math.log(1.1))));

interface Stat { n: number; ok: number; c4: number; c429: number; c5: number; to: number; conn: number; bytes: number; h: Record<number, number> }
const newStat = (): Stat => ({ n: 0, ok: 0, c4: 0, c429: 0, c5: 0, to: 0, conn: 0, bytes: 0, h: {} });

Deno.serve(async (request: Request) => {
  if (!secretMatches(Deno.env.get('PUSH_DISPATCH_SECRET'), request.headers.get('x-dispatch-secret'))) {
    return json({ error: 'unauthorized' }, 401);
  }
  const base = Deno.env.get('SUPABASE_URL'), anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!base || !anon) return json({ error: 'not_configured' }, 500);
  const p = await request.json();
  const startedAt = Date.now();
  const t0: number = p.t0, rampEnd = t0 + p.ramp_s * 1000, holdEnd = rampEnd + p.hold_s * 1000;
  const endAll = holdEnd + (p.down_s ?? 0) * 1000;
  const timeoutMs: number = p.timeout_ms ?? 10000;
  const [thinkMin, thinkMax]: [number, number] = p.think ?? [3, 8];

  const all: Record<string, Stat> = {}, hold: Record<string, Stat> = {};
  const timeline: Record<number, [number, number]> = {}; // second from t0 -> [requests, errors]
  const scanResults: Record<string, number> = {};
  let maxActive = 0, active = 0;

  const sleep = (ms: number) => new Promise((r) => setTimeout(r, Math.max(0, ms)));
  const rnd = (a: number, b: number) => a + Math.random() * (b - a);

  async function call(name: string, token: string, path: string, init: RequestInit = {}, parse = false): Promise<unknown> {
    const t = performance.now();
    const at = Date.now();
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), timeoutMs);
    let status = 0, bytes = 0, kind: 'ok' | 'to' | 'conn' | 'http' = 'ok', body: unknown = undefined;
    try {
      const res = await fetch(`${base}${path}`, {
        ...init, signal: ctl.signal,
        headers: { apikey: anon!, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
      });
      status = res.status;
      if (parse && res.ok) {
        const text = await res.text();
        bytes = text.length;
        try { body = JSON.parse(text); } catch { body = undefined; }
      } else {
        bytes = (await res.arrayBuffer()).byteLength;
      }
      if (!res.ok) kind = 'http';
    } catch (e) {
      kind = (e as Error).name === 'AbortError' ? 'to' : 'conn';
    } finally {
      clearTimeout(timer);
    }
    const ms = performance.now() - t;
    const inHold = at >= rampEnd && at < holdEnd;
    for (const set of inHold ? [all, hold] : [all]) {
      const s = set[name] ??= newStat();
      s.n++; s.bytes += bytes;
      if (kind === 'ok') s.ok++;
      else if (kind === 'to') s.to++;
      else if (kind === 'conn') s.conn++;
      else if (status === 429) s.c429++;
      else if (status >= 500) s.c5++;
      else s.c4++;
      const b = bucket(ms);
      s.h[b] = (s.h[b] ?? 0) + 1;
    }
    const sec = Math.floor((at - t0) / 1000);
    const tl = timeline[sec] ??= [0, 0];
    tl[0]++; if (kind !== 'ok') tl[1]++;
    return body;
  }

  const rpc = (name: string, token: string, args: Record<string, unknown>, parse = false) =>
    call(name, token, `/rest/v1/rpc/${name}`, { method: 'POST', body: JSON.stringify(args) }, parse);

  async function openApp(vu: any, mixed: boolean) {
    const c = vu.ctx ?? {};
    if (vu.role === 'student' && p.mode === 'bundle') {
      // StudentHomeBundle: everything the seven reads below return, in one.
      await rpc('get_student_home', vu.token, { p_today: p.today, p_ride_from: p.week_from, p_ride_to: p.week_to });
    } else if (vu.role === 'student') {
      await call('subscriptions.current', vu.token,
        `/rest/v1/subscriptions?select=${encodeURIComponent(SUB_SELECT)}&student_id=eq.${vu.id}` +
        `&status=in.(pending_payment,pending_review,active,rejected)&or=(end_date.is.null,end_date.gte.${p.today})` +
        `&order=start_date.asc,created_at.desc&limit=1`);
      await call('students.me', vu.token, `/rest/v1/students?select=*&id=eq.${vu.id}`);
      await call('daily_ride_status.week', vu.token,
        `/rest/v1/daily_ride_status?select=ride_date,is_riding,departure_time,return_time,is_returning` +
        `&student_id=eq.${vu.id}&ride_date=gte.${p.week_from}&ride_date=lte.${p.week_to}`);
      await rpc('get_vote_settings', vu.token, { p_company_id: c.company });
      const inbox = await rpc('get_my_notifications_page', vu.token, { p_before: null, p_limit: 30, p_unread_only: false }, mixed) as any;
      await rpc('get_my_line_supervisors', vu.token, {});
      await call('subscription_receipts.card', vu.token,
        `/rest/v1/subscription_receipts?select=${encodeURIComponent(RECEIPT_SELECT)}&subscription_id=eq.${c.sub}`);
      if (mixed) {
        const items = Array.isArray(inbox?.items) ? inbox.items : [];
        const unread = items.filter((n: any) => !n.read_at).slice(0, 5).map((n: any) => n.id);
        if (unread.length) await rpc('mark_notifications_read', vu.token, { p_ids: unread });
        if (Math.random() < 0.3 && c.dep) {
          await rpc('toggle_student_daily_ride', vu.token, {
            p_ride_date: p.today, p_is_riding: true, p_departure_time: c.dep, p_return_time: c.ret ?? null,
            p_is_returning: !!c.ret,
          });
        }
      }
    } else if (vu.role === 'supervisor') {
      await rpc('get_supervisor_dashboard', vu.token, {});
      await rpc('get_supervisor_trip_manifest', vu.token, { p_line_id: c.line, p_direction: 'departure', p_trip_id: null, p_date: null });
      const qrs: string[] = c.qrs ?? [];
      if (qrs.length) await rpc('lookup_student_by_qr', vu.token, { p_qr_code: qrs[Math.floor(Math.random() * qrs.length)] });
      if (mixed && qrs.length) {
        for (let k = 0; k < 3; k++) await scan(vu);
      }
    } else {
      await rpc('company_overview', vu.token, { p_company_id: c.company });
      await rpc('get_company_students_page_v2', vu.token, {
        p_company_id: c.company, p_search: null, p_status: null, p_line_id: null, p_university_id: null,
        p_sort: 'newest', p_limit: 25, p_offset: 0, p_student_id: null,
      });
      await rpc('get_company_students_page_v2', vu.token, {
        p_company_id: c.company, p_search: 'محمد', p_status: null, p_line_id: null, p_university_id: null,
        p_sort: 'newest', p_limit: 25, p_offset: 0, p_student_id: null,
      });
      await rpc('company_today', vu.token, { p_company_id: c.company });
      await rpc('admin_subscription_report', vu.token, { p_filters: { company_id: c.company, academic_year: 2026, limit: 25, offset: 0 } });
      if (Math.random() < 0.2) await rpc('company_analytics', vu.token, { p_company_id: c.company, p_from: p.from30, p_to: null });
    }
  }

  let lastQr: Record<string, string> = {};
  async function scan(vu: any) {
    const c = vu.ctx ?? {};
    const qrs: string[] = c.qrs ?? [];
    // About 2% are a second scan of the student just scanned (a double tap).
    const qr = lastQr[vu.id] && Math.random() < 0.02 ? lastQr[vu.id] : qrs[Math.floor(Math.random() * qrs.length)];
    lastQr[vu.id] = qr;
    const r = await rpc('supervisor_check_in_student', vu.token, { p_qr_code: qr, p_direction: 'departure', p_trip_id: c.dep_trip }, true) as any;
    const key = r?.result ?? 'error';
    scanResults[key] = (scanResults[key] ?? 0) + 1;
  }

  async function runVu(vu: any, i: number, n: number) {
    if (p.mode === 'burst') {
      await sleep(t0 + Math.random() * p.ramp_s * 1000 - Date.now());
      active++; maxActive = Math.max(maxActive, active);
      await openApp(vu, false);
      active--;
      return;
    }
    const start = t0 + (n > 1 ? (i / n) * p.ramp_s * 1000 : 0);
    const stop = holdEnd + (n > 1 ? (i / n) * (p.down_s ?? 0) * 1000 : 0);
    await sleep(start - Date.now());
    active++; maxActive = Math.max(maxActive, active);
    while (Date.now() < stop) {
      if (p.mode === 'scan') {
        // Scanners scan; readers (also supervisors) keep today's riders list open.
        if (!vu.reader) await scan(vu);
        else await rpc('get_supervisor_trip_manifest', vu.token, { p_line_id: vu.ctx.line, p_direction: 'departure', p_trip_id: null, p_date: null });
      } else {
        await openApp(vu, p.mode === 'mixed');
      }
      await sleep(rnd(thinkMin, thinkMax) * 1000);
    }
    active--;
  }

  const vus: any[] = Array.isArray(p.vus) ? p.vus : [];
  // Stop well inside the Edge wall-clock limit whatever the schedule says.
  const hardStop = startedAt + 140_000;
  await Promise.race([
    Promise.all(vus.map((vu, i) => runVu(vu, i, vus.length))),
    sleep(Math.min(endAll + 15_000, hardStop) - Date.now()),
  ]);
  const finishedAt = Date.now();
  return json({
    inv: p.inv, mode: p.mode, vus: vus.length, max_active: maxActive, started_at: startedAt, finished_at: finishedAt,
    cut: finishedAt >= hardStop, all, hold, timeline, scan_results: scanResults,
  });
});
