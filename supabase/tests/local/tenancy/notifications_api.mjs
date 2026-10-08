// The notification system through the real API of a LOCAL stack, with real
// sign-ins: an admin, and two students each on more than one device.
//   set -a; . <local logins file>; set +a
//   SUPABASE_URL=... ANON_KEY=... node supabase/tests/local/tenancy/notifications_api.mjs
// Needs ADMIN_EMAIL/ADMIN_PW (a company admin) and STUDENT1/STUDENT2 _PHONE/_PW,
// student 1 having an open subscription in that admin's company. Everything it
// sends or registers is removed at the end.
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../../../admin_web/package.json'));
const { createClient } = require('@supabase/supabase-js');

const URL_ = process.env.SUPABASE_URL;
if (!/127\.0\.0\.1|localhost/.test(URL_ ?? '')) throw new Error('This test only runs against a local stack.');
const env = (name) => process.env[name] ?? (() => { throw new Error(`${name} is not set`); })();

const results = [];
const ok = (step, pass, detail = '') => results.push({ step, pass: !!pass, detail: pass ? '' : JSON.stringify(detail) });
const must = (value, label) => { if (value?.error) throw new Error(`${label}: ${value.error.message}`); return value.data; };
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const run = crypto.randomBytes(4).toString('hex');
const token = (name) => `${name}-${run}-${'x'.repeat(40)}`;

/** A signed-in client: one device of one account. */
async function device(email, password) {
  const client = createClient(URL_, env('ANON_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
  const session = must(await client.auth.signInWithPassword({ email, password }), `sign in`);
  await client.realtime.setAuth(session.session.access_token);
  return Object.assign(client, { userId: session.user.id });
}

/** Joins a private topic and collects what is announced on it. */
async function listen(client, topic) {
  const events = [];
  const joined = await new Promise((resolve) => {
    client.channel(topic, { config: { private: true } })
      .on('broadcast', { event: 'change' }, (message) => events.push(message.payload))
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') resolve(true);
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') resolve(false);
      });
  });
  return { joined, events };
}

const until = async (test, ms = 6000) => {
  for (const end = Date.now() + ms; Date.now() < end; await sleep(150)) if (test()) return true;
  return false;
};

const admin = await device(env('ADMIN_EMAIL'), env('ADMIN_PW'));
const s1Phone = await device(`${env('STUDENT1_PHONE')}@busak.app`, env('STUDENT1_PW'));
const s1Tablet = await device(`${env('STUDENT1_PHONE')}@busak.app`, env('STUDENT1_PW'));
const s2Phone = await device(`${env('STUDENT2_PHONE')}@busak.app`, env('STUDENT2_PW'));
const sent = [];

try {
  const companyId = must(await admin.from('admins').select('company_id').eq('id', admin.userId).single(), 'admin').company_id;

  // Devices: two for student 1, one for student 2.
  must(await s1Phone.rpc('register_push_device', { p_installation_id: `phone-${run}`, p_platform: 'ios', p_token: token('s1phone'), p_locale: 'ar', p_app_version: '1.0.6' }), 'register');
  must(await s1Tablet.rpc('register_push_device', { p_installation_id: `tablet-${run}`, p_platform: 'android', p_token: token('s1tablet'), p_locale: 'ar', p_app_version: '1.0.6' }), 'register');
  must(await s2Phone.rpc('register_push_device', { p_installation_id: `s2phone-${run}`, p_platform: 'android', p_token: token('s2phone'), p_locale: 'ar', p_app_version: '1.0.6' }), 'register');
  ok('tables are closed to the app', (await s1Phone.from('push_devices').select('id')).error
    && (await s1Phone.from('notifications').select('id')).error && (await s1Phone.from('push_outbox').select('id')).error);
  ok('the dispatcher is closed to the app', (await s1Phone.rpc('claim_push_outbox')).error
    && (await admin.rpc('claim_push_outbox')).error && (await admin.rpc('notifications_tick')).error);

  // Realtime: own topic only.
  const own = await listen(s1Tablet, `user:${s1Tablet.userId}`);
  const spy = await listen(s2Phone, `user:${s1Phone.userId}`);
  ok('a user joins their own topic', own.joined);
  ok('and cannot join another user\'s', !spy.joined);

  // The admin previews and sends to the company.
  const before = must(await s1Phone.rpc('get_my_unread_count'), 'unread');
  const preview = must(await admin.rpc('preview_notification_audience', { p_company_id: companyId, p_audience: { kind: 'company' } }), 'preview');
  ok('the preview counts students and devices on the server', preview.students >= 1 && preview.devices >= 2, preview);
  const key = `api-${run}`;
  const first = must(await admin.rpc('compose_notification', { p_company_id: companyId, p_title: `اختبار ${run}`, p_body: 'نص الاختبار.', p_audience: { kind: 'company' }, p_idempotency_key: key }), 'compose');
  const again = must(await admin.rpc('compose_notification', { p_company_id: companyId, p_title: `اختبار ${run}`, p_body: 'نص الاختبار.', p_audience: { kind: 'company' }, p_idempotency_key: key }), 'compose again');
  sent.push(first.id);
  ok('sent once; the retry with the same key is the same notification', first.status === 'sent' && again.duplicate === true && again.id === first.id, [first, again]);
  ok('students cannot compose, preview or read the history',
    (await s1Phone.rpc('compose_notification', { p_company_id: companyId, p_title: 'x', p_body: 'y', p_audience: { kind: 'company' } })).error
    && (await s1Phone.rpc('preview_notification_audience', { p_company_id: companyId, p_audience: { kind: 'company' } })).error
    && (await s1Phone.rpc('get_company_notifications_page', { p_company_id: companyId })).error);

  // Both devices of student 1 see it, unread.
  const pagePhone = must(await s1Phone.rpc('get_my_notifications_page', { p_limit: 5 }), 'page');
  const pageTablet = must(await s1Tablet.rpc('get_my_notifications_page', { p_limit: 5, p_unread_only: true }), 'page');
  ok('it is in the inbox on both devices, unread, newest first', pagePhone.items[0]?.id === first.id && pagePhone.items[0].read === false
    && pageTablet.items[0]?.id === first.id && pagePhone.unread === before + 1, pagePhone.items[0]);
  ok('the item says what it is and where to go', pagePhone.items[0]?.type === 'announcement.admin'
    && pagePhone.items[0].category === 'announcement' && pagePhone.items[0].data.route === 'notifications');

  // Read on the phone: the tablet is told, and its count follows.
  must(await s1Phone.rpc('mark_notifications_read', { p_ids: [first.id] }), 'read');
  ok('reading on one device is announced to the other', await until(() => own.events.some((e) => e.op === 'READ')), own.events);
  ok('and the other device\'s count follows', must(await s1Tablet.rpc('get_my_unread_count'), 'unread') === before);

  // History with true counts.
  const history = must(await admin.rpc('get_company_notifications_page', { p_company_id: companyId, p_limit: 5 }), 'history');
  const row = history.items.find((item) => item.id === first.id);
  ok('the history shows received, read and each push as it stands', row && row.students === preview.students && row.read >= 1
    && row.push.devices >= 2 && row.push.queued + row.push.skipped + row.push.accepted + row.push.failed === row.push.devices, row);

  // Scheduled: stored, not in the inbox, editable, cancellable.
  const at = new Date(Date.now() + 3600_000).toISOString();
  const later = must(await admin.rpc('compose_notification', { p_company_id: companyId, p_title: `مؤجل ${run}`, p_body: 'نص.', p_audience: { kind: 'company' }, p_scheduled_at: at }), 'schedule');
  sent.push(later.id);
  const inbox = must(await s1Phone.rpc('get_my_notifications_page', { p_limit: 50 }), 'page');
  ok('a scheduled notification is not in anyone\'s inbox', later.status === 'scheduled' && !inbox.items.some((item) => item.id === later.id));
  must(await admin.rpc('update_scheduled_notification', { p_id: later.id, p_title: `مؤجل معدّل ${run}`, p_body: 'نص.', p_audience: { kind: 'company' }, p_scheduled_at: new Date(Date.now() + 7200_000).toISOString() }), 'update');
  must(await admin.rpc('cancel_scheduled_notification', { p_id: later.id }), 'cancel');
  const cancelled = must(await admin.rpc('get_company_notifications_page', { p_company_id: companyId, p_status: 'cancelled', p_limit: 50 }), 'history');
  ok('it can be changed, then cancelled', cancelled.items.some((item) => item.id === later.id && item.title === `مؤجل معدّل ${run}`));

  // Preferences belong to the account.
  const prefs = must(await s1Phone.rpc('set_notification_preferences', { p_push_enabled: false, p_categories: { transport: false } }), 'prefs');
  const prefsTablet = must(await s1Tablet.rpc('get_notification_preferences'), 'prefs');
  const prefsOther = must(await s2Phone.rpc('get_notification_preferences'), 'prefs');
  ok('preferences follow the account, not another one', prefs.push_enabled === false && prefsTablet.categories.transport === false
    && prefsOther.push_enabled === true && prefsOther.categories.transport === true, [prefsTablet, prefsOther]);
  must(await s1Phone.rpc('set_notification_preferences', { p_push_enabled: true, p_categories: { transport: true } }), 'prefs back');

  // The phone changes hands: student 2 signs in on student 1's phone.
  must(await s1Phone.rpc('unregister_push_device', { p_installation_id: `phone-${run}` }), 'unregister');
  must(await s2Phone.rpc('register_push_device', { p_installation_id: `phone-${run}`, p_platform: 'ios', p_token: token('s1phone'), p_locale: 'ar', p_app_version: '1.0.6' }), 'register on the same phone');
  const after = must(await admin.rpc('preview_notification_audience', { p_company_id: companyId, p_audience: { kind: 'company' } }), 'preview');
  ok('after sign-out the phone no longer counts for the first account', after.devices <= preview.devices, [preview.devices, after.devices]);
  ok('a student cannot open or read a notification that is not theirs',
    !(await s2Phone.rpc('notification_opened', { p_id: first.id })).error
    && must(await admin.rpc('get_company_notifications_page', { p_company_id: companyId, p_limit: 50 }), 'history')
         .items.find((item) => item.id === first.id).opened === 0);
} finally {
  for (const id of sent) await admin.rpc('delete_notification', { p_id: id });
  await s1Phone.rpc('unregister_push_device', { p_installation_id: `phone-${run}` });
  await s1Tablet.rpc('unregister_push_device', { p_installation_id: `tablet-${run}` });
  await s2Phone.rpc('unregister_push_device', { p_installation_id: `s2phone-${run}` });
  await s2Phone.rpc('unregister_push_device', { p_installation_id: `phone-${run}` });
  for (const client of [admin, s1Phone, s1Tablet, s2Phone]) await client.removeAllChannels();
}

for (const r of results) console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.step}${r.pass ? '' : '  ' + r.detail}`);
const failed = results.filter((r) => !r.pass).length;
console.log(`\nnotifications api: ${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
