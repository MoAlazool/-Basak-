// get_student_home (20261125000001) against the requests it stands for.
//
// For every student of a local database it makes the app's separate launch
// requests through PostgREST, exactly as the app builds them (select strings,
// filters and order copied from mobile_app/lib), then asks get_student_home,
// and compares each part: same values, same keys in the same order. Only the
// lists PostgREST itself leaves unordered (a line's trips, a station's stops,
// the week's votes, the recap releases) are compared as sets.
//
// Needs PostgREST (the version the project runs) on a local database with the
// migrations (README.md, section 2), and students to look at (any fixture;
// perf/live/bench.sql makes realistic ones). Never point it at a real project:
// it signs its own tokens with the local secret.
//
//   PGRST_URL=http://localhost:3009 JWT_SECRET=... node student_home_parity.mjs [YYYY-MM-DD ...]
//
// Each date is used as the phone's "today" (default: 2026-10-12, 2026-03-01,
// 2027-02-15); the votes asked for are that date's Saturday-to-Friday week.
import { createRequire } from 'node:module';
import crypto from 'node:crypto';

const require = createRequire(new URL('../../../admin_web/package.json', import.meta.url));
const { PostgrestClient } = require('@supabase/postgrest-js');

const url = process.env.PGRST_URL ?? 'http://localhost:3009';
const secret = process.env.JWT_SECRET;
if (!secret) throw new Error('JWT_SECRET is required');
const days = process.argv.slice(2).length ? process.argv.slice(2) : ['2026-10-12', '2026-03-01', '2027-02-15'];

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
function token(claims) {
  const head = b64({ alg: 'HS256', typ: 'JWT' });
  const body = b64({ aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600, ...claims });
  return `${head}.${body}.${crypto.createHmac('sha256', secret).update(`${head}.${body}`).digest('base64url')}`;
}
const client = (claims) => new PostgrestClient(url, { headers: { Authorization: `Bearer ${token(claims)}` } });
const must = ({ data, error }) => {
  if (error) throw new Error(JSON.stringify(error));
  return data;
};

// SupabaseSubscriptionGateway._select
const SUB = `
          id, student_id, line_id, company_id, station_id, type, status, start_date, end_date, price, created_at,
          departure_time, return_time, period_code, academic_year, period_label, period_phase,
          lines(name, companies(id, name, logo_path, emblem_path), supervisors(full_name, phone, profile_image_url),
            line_trips(direction, is_active, start_time)),
          student:students(university),
          stations(name, departure_times, return_times,
            line_trip_stops(stop_time, line_trips(direction, is_active, start_time))),
          departure_trip:departure_trip_id(label, start_time, universities(name)),
          return_trip:return_trip_id(start_time)
        `;
// receiptColumns
const RECEIPT =
  'id, subscription_id, image_url, status, rejection_reason, attempt_number, reviewed_by, created_at, reviewed_at, payment_method_id';

async function separately(db, userId, today, from, to) {
  const out = {};
  out.profile = must(await db.from('students').select().eq('id', userId).maybeSingle());
  out.subscriptions = must(await db.from('subscriptions').select(SUB).eq('student_id', userId)
    .order('start_date', { ascending: false, nullsFirst: false }).order('created_at', { ascending: false }));
  out.current = must(await db.from('subscriptions').select(SUB).eq('student_id', userId)
    .in('status', ['pending_payment', 'pending_review', 'active', 'rejected'])
    .or(`end_date.is.null,end_date.gte.${today}`)
    .order('start_date', { ascending: true }).order('created_at', { ascending: false }).limit(1).maybeSingle());
  out.vote_settings = must(await db.rpc('get_vote_settings', { p_company_id: out.current?.company_id ?? null }));
  out.ride_days = must(await db.from('daily_ride_status').select('ride_date, is_riding, departure_time, return_time, is_returning')
    .eq('student_id', userId).gte('ride_date', from).lte('ride_date', to));
  out.receipts = out.current
    ? must(await db.from('receipts').select(RECEIPT).eq('subscription_id', out.current.id).order('attempt_number', { ascending: false }))
    : [];
  out.inbox = must(await db.rpc('get_my_notifications_page', { p_before: null, p_limit: 30, p_unread_only: false }));
  out.invites = must(await db.rpc('get_my_invites'));
  out.offers = must(await db.rpc('get_my_offers'));
  out.line_supervisors = must(await db.rpc('get_my_line_supervisors'));
  out.recap_releases = must(await db.from('term_recap_releases').select('academic_year, period_code, published_at, unpublished_at'));
  out.boarded_rides = must(await db.rpc('get_my_boarded_rides_count'));
  return out;
}

// Lists PostgREST leaves in no particular order, by the key that holds them.
const UNORDERED = new Set(['line_trips', 'line_trip_stops', 'ride_days', 'recap_releases']);
// A canonical form that keeps each object's key order.
function canon(value, key = '') {
  if (Array.isArray(value)) {
    const items = value.map((v) => canon(v));
    return UNORDERED.has(key) ? items.map((i) => JSON.stringify(i)).sort().map((s) => JSON.parse(s)) : items;
  }
  if (value && typeof value === 'object') return Object.entries(value).map(([k, v]) => [k, canon(v, k)]);
  return value;
}
const same = (a, b, key) => JSON.stringify(canon(a, key)) === JSON.stringify(canon(b, key));

function week(today) {
  const d = new Date(`${today}T00:00:00Z`);
  const back = (d.getUTCDay() + 1) % 7; // to Saturday
  const from = new Date(d.getTime() - back * 86400000);
  const to = new Date(from.getTime() + 6 * 86400000);
  return [from.toISOString().slice(0, 10), to.toISOString().slice(0, 10)];
}

const service = client({ role: 'service_role' });
const students = must(await service.from('students').select('id').order('id'));
let cases = 0;
const failures = [];
const seen = new Map();
for (const { id } of students) {
  const db = client({ sub: id, role: 'authenticated' });
  for (const today of days) {
    const [from, to] = week(today);
    const old = await separately(db, id, today, from, to);
    const bundle = must(await db.rpc('get_student_home', { p_today: today, p_ride_from: from, p_ride_to: to }));
    cases++;
    for (const part of Object.keys(old)) {
      if (!same(old[part], bundle[part], part)) failures.push(`${id} ${today} ${part}`);
    }
    if (bundle.vote_company !== (old.current?.company_id ?? null)) failures.push(`${id} ${today} vote_company`);
    if (bundle.receipts_of !== (old.current?.id ?? null)) failures.push(`${id} ${today} receipts_of`);
    const tally = (k, yes) => seen.set(k, (seen.get(k) ?? 0) + (yes ? 1 : 0));
    tally(`current ${old.current?.status ?? 'none'}`, true);
    tally('several subscriptions', old.subscriptions.length > 1);
    tally('votes in the week', old.ride_days.length > 0);
    tally('receipts', old.receipts.length > 0);
    tally('invites', old.invites.length > 0);
    tally('inbox items', old.inbox.items.length > 0);
    tally('two or more supervisors', old.line_supervisors.length > 1);
    tally('company vote settings', old.vote_settings.custom === true);
  }
}
console.log(`${cases} cases (${students.length} students x ${days.length} days)`);
for (const [k, n] of [...seen].sort()) console.log(`  ${k}: ${n}`);
if (failures.length) {
  console.log(`DIFFERENT (${failures.length}):`);
  for (const f of failures.slice(0, 50)) console.log(`  ${f}`);
  process.exit(1);
}
console.log('every part identical');
