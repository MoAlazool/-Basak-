// HTTP end-to-end test against a running Supabase-compatible stack
// (GoTrue + PostgREST + the Edge Functions), using @supabase/supabase-js exactly
// like the dashboard and the app do. See tests/local/README.md.
//   SUPABASE_URL=... ANON_KEY=... SERVICE_KEY=... node supabase/tests/local/http_e2e.mjs
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../../admin_web/package.json'));
const { createClient } = require('@supabase/supabase-js');

const URL = process.env.SUPABASE_URL;
const ANON = process.env.ANON_KEY;
const SERVICE = process.env.SERVICE_KEY;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL, SERVICE, opts);
const LINE_A = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const LINE_B = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const LINE_C = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const COMPANY_1 = '11111111-1111-1111-1111-111111111111';
const COMPANY_2 = '22222222-2222-2222-2222-222222222222';

const results = [];
const ok = (step, pass, detail = '') => { results.push({ step, pass: !!pass, detail }); };
const must = (value, label) => { if (value?.error) throw new Error(`${label}: ${value.error.message}`); return value; };

async function signedIn(email, password) {
  const client = createClient(URL, ANON, opts);
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`sign-in ${email}: ${error.message}`);
  return client;
}

/** Same error unwrapping as admin_web/src/lib/edgeFunctions.ts */
async function invoke(client, name, body) {
  const { data, error } = await client.functions.invoke(name, { body });
  if (!error) return { data, status: 200 };
  let message = error.message;
  try { message = (await error.context.json()).error ?? message; } catch { /* not json */ }
  return { error: message, status: error.context?.status };
}

async function main() {
  // ---- Super admin (bootstrap with the service role, as done once in production)
  const superEmail = 'super@basak.test';
  const { data: su } = must(await service.auth.admin.createUser({ email: superEmail, password: 'Super-pass-1', email_confirm: true }), 'create super');
  must(await service.from('admins').insert({ id: su.user.id, email: superEmail, full_name: 'Super', role: 'super_admin' }), 'super row');
  const superAdmin = await signedIn(superEmail, 'Super-pass-1');

  for (const [email, company] of [['admin1@basak.test', COMPANY_1], ['admin2@basak.test', COMPANY_2]]) {
    const r = await invoke(superAdmin, 'admin-create-company-admin', { email, fullName: email, companyId: company, password: 'Admin-pass-1' });
    ok(`company admin created (${email})`, r.status === 200, r.error);
  }
  const admin1 = await signedIn('admin1@basak.test', 'Admin-pass-1');
  const admin2 = await signedIn('admin2@basak.test', 'Admin-pass-1');

  // ---- 1. The 400 the deployed (old) dashboard bundle produced
  const legacy = await superAdmin.from('supervisors').insert({
    full_name: 'Old Build', phone: '01011111111', company_id: COMPANY_1, password: '123456', is_active: true,
  });
  ok('old bundle payload -> HTTP 400 (password column no longer exists)', legacy.status === 400,
    `${legacy.status} ${legacy.error?.code} ${legacy.error?.message}`);

  // ---- 1+2. Supervisor creation with lines (super admin and company admin)
  let r = await invoke(superAdmin, 'admin-create-supervisor', { fullName: 'No Lines', phone: '01022222222', password: 'secret1', companyId: COMPANY_1, lineIds: [] });
  ok('create supervisor without a line is refused with a clear message', r.status === 400 && /خط/.test(r.error), r.error);
  r = await invoke(superAdmin, 'admin-create-supervisor', { fullName: 'Wrong Line', phone: '01022222223', password: 'secret1', companyId: COMPANY_1, lineIds: [LINE_C] });
  ok('create supervisor with another company\'s line is refused', r.status === 400, r.error);
  const noAuthLeft = await service.auth.admin.listUsers();
  ok('refused creations leave no Auth user behind',
    !noAuthLeft.data.users.some((u) => ['01022222222@busak.app', '01022222223@busak.app'].includes(u.email)));

  r = await invoke(superAdmin, 'admin-create-supervisor', { fullName: 'Sup Super', phone: '01033333333', password: 'secret1', companyId: COMPANY_1, lineIds: [LINE_A] });
  ok('super admin creates supervisor with line A', r.status === 200, r.error);
  const supA = r.data?.id;
  r = await invoke(admin1, 'admin-create-supervisor', { fullName: 'Sup Company', phone: '01044444444', password: 'secret1', companyId: COMPANY_2, lineIds: [LINE_A, LINE_B] });
  ok('company admin creates supervisor with lines A+B (company pinned to own)', r.status === 200, r.error);
  const supAB = r.data?.id;
  r = await invoke(admin1, 'admin-create-supervisor', { fullName: 'Sneaky', phone: '01055555555', password: 'secret1', lineIds: [LINE_C] });
  ok('company admin cannot assign another company\'s line', r.status === 400, r.error);

  const { data: rows } = must(await service.from('supervisor_lines').select('supervisor_id,line_id'), 'assignments');
  ok('assignments stored in the database',
    rows.filter((x) => x.supervisor_id === supA).map((x) => x.line_id).join() === LINE_A
    && rows.filter((x) => x.supervisor_id === supAB).length === 2);
  const { data: supRow } = await service.from('supervisors').select('company_id').eq('id', supAB).single();
  ok('company admin\'s supervisor belongs to the admin\'s company', supRow?.company_id === COMPANY_1);
  const listed = await admin1.from('supervisors').select('id, phone, full_name, company_id, is_active, created_at, companies(name)');
  ok('dashboard supervisors list query works (no 400)', !listed.error && listed.data.length === 2, listed.error?.message);
  const listed2 = await admin2.from('supervisor_lines').select('supervisor_id');
  ok('other company admin sees none of these assignments', !listed2.error && listed2.data.length === 0);

  // dashboard edits lines
  const edit = await admin1.rpc('set_supervisor_lines', { p_supervisor_id: supAB, p_line_ids: [LINE_B] });
  ok('company admin edits lines via RPC', !edit.error, edit.error?.message);

  // ---- Supervisor app
  const supervisor = await signedIn('01044444444@busak.app', 'secret1');
  const dash = await supervisor.rpc('get_supervisor_dashboard');
  ok('supervisor dashboard shows only assigned line B, no receipt counter',
    !dash.error && dash.data.lines.length === 1 && dash.data.lines[0].id === LINE_B && !('pending_receipts' in dash.data.totals),
    dash.error?.message);

  // ---- Student registers (same calls as the app) and subscribes
  const student = createClient(URL, ANON, opts);
  must(await student.auth.signUp({ email: '01066666666@busak.app', password: 'Student-pass-1', options: { data: { role: 'student' } } }), 'student signup');
  const { data: me } = await student.auth.getUser();
  must(await student.from('students').insert({ id: me.user.id, phone: '01066666666', full_name: 'طالب تجربة واحد اثنين', university: 'جامعة المنصورة', college: 'غير محدد' }), 'student row');
  const periods = must(await student.rpc('get_purchasable_periods', { p_line_id: LINE_B }), 'periods').data;
  ok('student sees current + upcoming (+ annual) periods',
    periods.some((p) => p.phase === 'current') && periods.some((p) => p.phase === 'upcoming'),
    periods.map((p) => `${p.period_code}:${p.phase}`).join(','));
  const { data: station } = await student.from('stations').select('id,departure_times,return_times').eq('line_id', LINE_B).order('order_index').limit(1).single();
  const subFor = (p) => ({ student_id: me.user.id, line_id: LINE_B, station_id: station.id, type: p.subscription_type,
    price: 1, departure_time: station.departure_times[0], return_time: station.return_times[0],
    period_code: p.period_code, academic_year: p.academic_year });
  const select = '*, period_label, period_phase';
  const current = periods.find((p) => p.phase === 'current' && p.subscription_type === 'termly');
  const next = periods.find((p) => p.phase === 'upcoming' && p.subscription_type === 'termly');
  const s1 = await student.from('subscriptions').insert(subFor(current)).select(select).single();
  const s2 = await student.from('subscriptions').insert(subFor(next)).select(select).single();
  ok('student subscribes to the current period', !s1.error && s1.data.period_phase === 'current', s1.error?.message ?? s1.data.period_label);
  ok('student pays the next semester in advance', !s2.error && s2.data.period_phase === 'upcoming', s2.error?.message ?? s2.data.period_label);
  const dup = await student.from('subscriptions').insert(subFor(current)).select('id').single();
  ok('duplicate period refused with readable message', !!dup.error && /يغطي/.test(dup.error.message), dup.error?.message);

  // ---- Receipt (row; the image object is covered by the SQL test's storage policies)
  const imagePath = `${me.user.id}/${s1.data.id}_${Date.now()}.jpg`;
  const rec = await student.from('receipts').insert({ subscription_id: s1.data.id, image_url: imagePath, status: 'pending' }).select().single();
  ok('student uploads receipt (attempt 1, amount recorded)', !rec.error && rec.data.attempt_number === 1 && Number(rec.data.amount) > 0, rec.error?.message);
  const supRead = await supervisor.from('receipts').select('id');
  ok('supervisor cannot read receipts', !supRead.error && supRead.data.length === 0);
  const supUpd = await supervisor.from('receipts').update({ status: 'approved' }).eq('id', rec.data.id).select('id');
  ok('supervisor cannot approve receipts', (supUpd.data ?? []).length === 0);
  const a2 = await admin2.from('receipts').select('id');
  ok('other company admin cannot see the receipt', !a2.error && a2.data.length === 0);
  const queue = await admin1.from('subscriptions').select('id, type, price, start_date, end_date, period_label, period_phase').eq('id', s1.data.id).single();
  ok('dashboard receipt query returns period + dates', !queue.error && !!queue.data.period_label && !!queue.data.start_date, queue.error?.message);
  const approve = await admin1.from('receipts').update({ status: 'approved' }).eq('id', rec.data.id).select('id').single();
  ok('company admin approves', !approve.error, approve.error?.message);
  const after = await student.from('subscriptions').select('status, start_date, end_date, paid_at').eq('id', s1.data.id).single();
  ok('subscription active for its period, paid_at set',
    after.data.status === 'active' && after.data.start_date === s1.data.start_date && !!after.data.paid_at);

  // ---- QR: once per day
  const { data: qr } = await student.from('students').select('qr_code_value').eq('id', me.user.id).single();
  const c1 = await supervisor.rpc('supervisor_check_in_student', { p_qr_code: qr.qr_code_value, p_direction: 'departure' });
  const c2 = await supervisor.rpc('supervisor_check_in_student', { p_qr_code: qr.qr_code_value, p_direction: 'return' });
  ok('first scan checks in', c1.data?.result === 'checked_in', c1.error?.message ?? c1.data?.result);
  ok('second scan same day rejected: "already been checked in today"',
    c2.data?.result === 'already_checked_in' && /already been checked in today/.test(c2.data?.message), c2.data?.message);

  // ---- Annual switch
  must(await admin1.rpc('set_annual_subscription', { p_enabled: false, p_company_id: COMPANY_1 }), 'annual off');
  const noAnnual = must(await student.rpc('get_purchasable_periods', { p_line_id: LINE_B }), 'periods').data;
  ok('annual hidden when company disables it', !noAnnual.some((p) => p.subscription_type === 'yearly'));
  const glob = await admin1.rpc('set_annual_subscription', { p_enabled: false });
  ok('company admin cannot change the global switch', !!glob.error);
  must(await admin1.rpc('set_annual_subscription', { p_enabled: true, p_company_id: COMPANY_1 }), 'annual on');

  // ---- Forgot password
  const anon = createClient(URL, ANON, opts);
  const req = await anon.rpc('request_student_password_reset', { p_phone: '01066666666' });
  ok('student requests a reset before sign-in', !req.error && req.data.status === 'requested', req.error?.message);
  const list = must(await admin1.rpc('admin_list_password_reset_requests'), 'list').data;
  const open = list.find((x) => x.student_phone === '01066666666');
  ok('company admin sees the request', !!open);
  const otherList = must(await admin2.rpc('admin_list_password_reset_requests'), 'list2').data;
  ok('other company admin does not', !otherList.some((x) => x.student_phone === '01066666666'));
  const code = must(await admin1.rpc('admin_issue_password_reset_code', { p_request_id: open.id }), 'issue').data.code;
  const wrong = await invoke(anon, 'student-reset-password', { phone: '01066666666', code: code === '000000' ? '111111' : '000000', newPassword: 'New-pass-123' });
  ok('wrong code refused with remaining attempts', wrong.status === 400 && /المتبقية/.test(wrong.error), wrong.error);
  const short = await invoke(anon, 'student-reset-password', { phone: '01066666666', code, newPassword: 'short' });
  ok('weak password refused', short.status === 400, short.error);
  const good = await invoke(anon, 'student-reset-password', { phone: '+20 106 666 6666', code, newPassword: 'New-pass-123' });
  ok('right code sets the new password', good.status === 200 && good.data.reset === true, good.error);
  const relogin = createClient(URL, ANON, opts);
  const newLogin = await relogin.auth.signInWithPassword({ email: '01066666666@busak.app', password: 'New-pass-123' });
  const oldLogin = await createClient(URL, ANON, opts).auth.signInWithPassword({ email: '01066666666@busak.app', password: 'Student-pass-1' });
  ok('student logs in with the new password; the old one fails', !newLogin.error && !!oldLogin.error);
  const reuse = await invoke(anon, 'student-reset-password', { phone: '01066666666', code, newPassword: 'Another-pass-1' });
  ok('code cannot be reused', reuse.status === 400, reuse.error);

  // ---- Delete supervisor
  r = await invoke(admin1, 'admin-delete-supervisor', { supervisorId: supAB });
  const gone = await service.from('supervisor_lines').select('line_id').eq('supervisor_id', supAB);
  ok('deleting a supervisor removes account and assignments', r.status === 200 && gone.data.length === 0, r.error);
}

try {
  await main();
} catch (error) {
  ok('unexpected error', false, error.message);
}
for (const [i, x] of results.entries()) console.log(`${String(i + 1).padStart(2)} ${x.pass ? 'PASS' : 'FAIL'}  ${x.step}${x.detail ? `  — ${x.detail}` : ''}`);
const failed = results.filter((x) => !x.pass).length;
console.log(failed ? `\n${failed} FAILED` : `\nall ${results.length} passed`);
process.exit(failed ? 1 : 0);
