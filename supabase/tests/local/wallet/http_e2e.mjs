// End-to-end test of the Wallet card against a LOCAL Supabase stack with the
// wallet functions served and fakes.mjs standing in for Apple's push service
// and Google's Wallet API. Never point this at a real project: it creates
// companies, lines, users and subscriptions. See ../README.md.
//   SUPABASE_URL=... ANON_KEY=... SERVICE_KEY=... DB_URL=postgresql://... CA_PEM=.../ca.pem PHOTO=.../photo.jpg node http_e2e.mjs
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../../../admin_web/package.json'));
const { createClient } = require('@supabase/supabase-js');

const URL_ = process.env.SUPABASE_URL;
const ANON = process.env.ANON_KEY;
const SERVICE = process.env.SERVICE_KEY;
const DB_URL = process.env.DB_URL;
const CA_PEM = process.env.CA_PEM;
const PHOTO = fs.readFileSync(process.env.PHOTO);
const FAKES = process.env.FAKES_URL ?? 'http://127.0.0.1:8444';
const PASS_TYPE = process.env.APPLE_PASS_TYPE_ID ?? 'pass.test.basak';
const ISSUER = process.env.GOOGLE_WALLET_ISSUER_ID ?? '3388000000099999999';
const WEB = `${URL_}/functions/v1/wallet-apple-web/v1`;
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(URL_, SERVICE, opts);

const results = [];
const ok = (step, pass, detail = '') => { results.push({ step, pass: !!pass, detail: pass ? '' : String(detail ?? '') }); };
const must = (value, label) => { if (value?.error) throw new Error(`${label}: ${value.error.message}`); return value; };
const run = crypto.randomBytes(3).toString('hex');
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
/** Plain SQL as the database owner: for what no API user can do (e.g. simulating time passing). */
const sql = (statement) => execFileSync('psql', [DB_URL, '-v', 'ON_ERROR_STOP=1', '-qAt', '-c', statement], { encoding: 'utf8' }).trim();

async function signedIn(email, password) {
  const client = createClient(URL_, ANON, opts);
  must(await client.auth.signInWithPassword({ email, password }), `sign-in ${email}`);
  return client;
}

async function invoke(client, name, body) {
  const { data, error } = await client.functions.invoke(name, { body });
  if (!error) return { data, status: 200 };
  let payload = {};
  try { payload = await error.context.json(); } catch { /* not json */ }
  return { error: payload.error ?? error.message, reason: payload.reason, status: error.context?.status };
}

const fakeState = async () => (await fetch(`${FAKES}/__state`)).json();
const fakeReset = () => fetch(`${FAKES}/__reset`, { method: 'POST' });

/** Unpacks a .pkpass, checks every hash in the manifest and the signature over it. */
function openPass(bytes) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pkpass-'));
  const file = path.join(dir, 'card.pkpass');
  fs.writeFileSync(file, bytes);
  execFileSync('unzip', ['-o', '-q', file, '-d', path.join(dir, 'x')]);
  const read = (name) => fs.readFileSync(path.join(dir, 'x', name));
  const manifest = JSON.parse(read('manifest.json'));
  const hashesMatch = Object.entries(manifest).every(
    ([name, sha1]) => crypto.createHash('sha1').update(read(name)).digest('hex') === sha1);
  let signatureValid = true;
  try {
    execFileSync('openssl', ['smime', '-verify', '-binary', '-inform', 'DER', '-in', path.join(dir, 'x', 'signature'),
      '-content', path.join(dir, 'x', 'manifest.json'), '-CAfile', CA_PEM, '-purpose', 'any', '-out', '/dev/null'], { stdio: 'pipe' });
  } catch { signatureValid = false; }
  const pass = JSON.parse(read('pass.json'));
  const pngSize = (name) => (manifest[name] ? [read(name).readUInt32BE(16), read(name).readUInt32BE(20)] : null);
  const out = {
    pass, files: Object.keys(manifest).sort(), hashesMatch, signatureValid, manifest,
    thumbnails: ['thumbnail.png', 'thumbnail@2x.png', 'thumbnail@3x.png'].map(pngSize),
  };
  fs.rmSync(dir, { recursive: true, force: true });
  return out;
}

// Empty spacer fields only position their neighbour; they carry no information.
const fields = (pass, group) => Object.fromEntries((pass.eventTicket?.[group] ?? [])
  .filter((f) => !f.key.endsWith('-spacer')).map((f) => [f.key, f.value]));
const front = (pass) => ({ ...fields(pass, 'primaryFields'), ...fields(pass, 'secondaryFields'), ...fields(pass, 'auxiliaryFields') });

const applePass = (token) => ({ Authorization: `ApplePass ${token}` });
const web = (pathname, init = {}) => fetch(`${WEB}${pathname}`, init);
const register = (device, serial, token, pushToken) => web(`/devices/${device}/registrations/${PASS_TYPE}/${serial}`, {
  method: 'POST', headers: { ...applePass(token), 'content-type': 'application/json' }, body: JSON.stringify({ pushToken }),
});
const unregister = (device, serial, token) => web(`/devices/${device}/registrations/${PASS_TYPE}/${serial}`, {
  method: 'DELETE', headers: applePass(token),
});
const updatedSince = (device, tag) => web(`/devices/${device}/registrations/${PASS_TYPE}${tag ? `?passesUpdatedSince=${tag}` : ''}`);
const fetchPass = async (student, token) => {
  const r = await web(`/passes/${PASS_TYPE}/${student.id}`, { headers: applePass(token ?? student.token) });
  return r.status === 200 ? openPass(Buffer.from(await r.arrayBuffer())) : { status: r.status };
};

const passRows = async (ids) => must(await service.from('wallet_passes')
  .select('student_id, platform, company_id, dirty_at, content_updated_at, last_error').in('student_id', ids), 'pass rows').data;
const dirtyCount = async (ids) => (await passRows(ids)).filter((p) => p.dirty_at).length;
/** Waits for the database-triggered delivery (trigger -> pg_net -> wallet-sync). */
async function settled(ids, timeoutMs = 20000) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    if ((await dirtyCount(ids)) === 0) return true;
    await sleep(400);
  }
  return false;
}

/** The dashboard's rollout loop for one company. */
async function publish(admin, companyId) {
  const total = { updated: 0, failed: 0, calls: 0, remaining: 0 };
  for (;;) {
    const r = await invoke(admin, 'wallet-sync', { companyId });
    if (r.error) throw new Error(`publish: ${r.error}`);
    total.updated += r.data.updated; total.failed += r.data.failed; total.calls += 1; total.remaining = r.data.remaining;
    if (r.data.done) return total;
  }
}

const PNG = (seed) => Buffer.concat([Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64'), Buffer.from(seed)]);

async function main() {
  // ---- World: a super admin, two companies each with an admin and a line, four students
  const mk = async (email, password) =>
    must(await service.auth.admin.createUser({ email, password, email_confirm: true }), `create ${email}`).data.user.id;
  const superId = await mk(`super-${run}@basak.test`, 'Super-pass-1');
  must(await service.from('admins').insert({ id: superId, email: `super-${run}@basak.test`, full_name: 'مدير النظام', role: 'super_admin' }), 'super row');
  const superAdmin = await signedIn(`super-${run}@basak.test`, 'Super-pass-1');
  const university = must(await service.from('universities').insert({ name: `جامعة ${run}` }).select('id, name').single(), 'university').data;

  const world = {};
  for (const key of ['A', 'B']) {
    const company = must(await service.from('companies').insert({ name: `شركة ${key} ${run}` }).select('id, name').single(), 'company').data;
    const adminId = await mk(`admin-${key}-${run}@basak.test`, 'Admin-pass-1');
    must(await service.from('admins').insert({
      id: adminId, email: `admin-${key}-${run}@basak.test`, full_name: `مدير ${key}`, role: 'company_admin',
      company_id: company.id, created_by_admin_id: superId,
    }), 'company admin row');
    const lineId = must(await superAdmin.rpc('save_line', { p_line: {
      company_id: company.id, name: `خط ${key} ${run}`, origin_name: `بداية ${key}`, destination_university_id: university.id,
      university_ids: [university.id], price_termly: 100, price_yearly: 180, price_daily: 5,
      stations: [{ name: `محطة ${key}1` }, { name: `محطة ${key}2` }],
      trips: [
        { direction: 'departure', start_time: '07:00', stops: [{ station_index: 0, time: '07:10' }, { station_index: 1, time: '07:20' }] },
        { direction: 'return', start_time: '14:00', stops: [{ station_index: 1, time: '14:10' }, { station_index: 0, time: '14:20' }] },
      ],
    } }), `line ${key}`).data;
    const stations = must(await service.from('stations').select('id, name, departure_times, return_times').eq('line_id', lineId).order('order_index'), 'stations').data;
    world[key] = { company, lineId, lineName: `خط ${key} ${run}`, stations, admin: await signedIn(`admin-${key}-${run}@basak.test`, 'Admin-pass-1') };
  }
  const { A, B } = world;

  const students = {};
  for (const [i, key, name, college, withPhoto] of [[1, 'sara', 'سارة أحمد', 'الهندسة', true], [2, 'omar', 'عمر خالد', 'غير محدد', false],
    [3, 'mona', 'منى سعيد', 'العلوم', true], [4, 'zaki', 'زكي بلا اشتراك', 'غير محدد', false]]) {
    const phone = `010${String(parseInt(run, 16) % 1000000).padStart(6, '0')}${i}0`.slice(0, 11);
    const id = await mk(`${phone}@busak.app`, 'Student-pass-1');
    if (withPhoto) must(await service.storage.from('student-avatars').upload(`${id}/avatar.jpg`, PHOTO, { contentType: 'image/jpeg' }), 'photo');
    const row = must(await service.from('students').insert({
      id, phone, full_name: name, university: university.name, college, profile_image_url: withPhoto ? `${id}/avatar.jpg` : null,
    }).select('id, qr_code_value').single(), `student ${key}`).data;
    students[key] = { ...row, name, client: await signedIn(`${phone}@busak.app`, 'Student-pass-1') };
  }
  const { sara, omar, mona, zaki } = students;
  const ids = Object.values(students).map((s) => s.id);

  const subscribe = async (student, target, stationIndex = 0, phase = 'current') => {
    const periods = must(await student.client.rpc('get_purchasable_periods', { p_line_id: target.lineId }), 'periods').data;
    const period = periods.find((p) => p.phase === phase && p.subscription_type === 'termly');
    if (!period) throw new Error(`no ${phase} termly period`);
    const station = target.stations[stationIndex];
    return must(await student.client.from('subscriptions').insert({
      student_id: student.id, line_id: target.lineId, station_id: station.id, type: 'termly', price: 100,
      departure_time: station.departure_times[0], return_time: station.return_times[0],
      period_code: period.period_code, academic_year: period.academic_year,
    }).select('id, status, company_id').single(), 'subscribe').data;
  };
  const approve = async (subscription) => must(await superAdmin.from('subscriptions')
    .update({ status: 'active' }).eq('id', subscription.id).select('id').single(), 'approve');
  const issueApple = async (student) => {
    const r = await invoke(student.client, 'student-wallet-pass', { platform: 'apple' });
    if (r.error) throw new Error(`apple pass: ${r.error}`);
    const opened = openPass(Buffer.from(r.data.pkpass, 'base64'));
    student.token = opened.pass.authenticationToken;
    return opened;
  };
  const issueGoogle = async (student) => {
    const r = await invoke(student.client, 'student-wallet-pass', { platform: 'google' });
    if (r.error) throw new Error(`google pass: ${r.error}`);
    return r.data.saveUrl;
  };
  const googleObject = async (student) => (await fakeState()).objects[`${ISSUER}.student_${student.id}`];
  await fakeReset();

  // ---- P. Permissions: a company admin for their own company, the super admin for any
  const design = (background, extra = {}) => ({
    p_background_color: background, p_foreground_color: '#FFFFFF', p_label_color: '#E3F2FD', ...extra });
  ok('P1 company admin reads their own design (no id needed)',
    must(await A.admin.rpc('get_wallet_card_settings'), 'own').data.company_id === A.company.id);
  ok('P2 company admin cannot read another company', (await A.admin.rpc('get_wallet_card_settings', { p_company_id: B.company.id })).error?.code === '42501');
  ok('P3 company admin cannot change another company',
    (await A.admin.rpc('set_wallet_card_settings', { p_company_id: B.company.id, ...design('#000000') })).error?.code === '42501');
  ok('P4 a student can neither read nor change any design',
    (await sara.client.rpc('get_wallet_card_settings', { p_company_id: A.company.id })).error?.code === '42501'
    && (await sara.client.rpc('set_wallet_card_settings', { p_company_id: A.company.id, ...design('#000000') })).error?.code === '42501');
  ok('P5 the super admin must name a company', !!(await superAdmin.rpc('get_wallet_card_settings')).error);
  ok('P6 nobody reads the tables directly',
    !!(await A.admin.from('wallet_card_settings').select('company_id')).error && !!(await sara.client.from('wallet_passes').select('student_id')).error
    && !!(await superAdmin.from('wallet_runtime').select('sync_secret')).error);
  ok('P7 bad colour, phone or foreign artwork path are refused',
    !!(await A.admin.rpc('set_wallet_card_settings', { p_company_id: A.company.id, ...design('blue') })).error
    && !!(await A.admin.rpc('set_wallet_card_settings', { p_company_id: A.company.id, ...design('#1565C0', { p_contact_phone: 'call me' }) })).error
    && !!(await A.admin.rpc('set_wallet_card_settings', { p_company_id: A.company.id, ...design('#1565C0', { p_logo_path: `${B.company.id}/logo/x` }) })).error);

  for (const file of ['icon.png', 'icon@2x.png', 'icon@3x.png', 'logo.png', 'logo@2x.png', 'logo@3x.png', 'google.png']) {
    must(await A.admin.storage.from('wallet-assets').upload(`${A.company.id}/logo/s1/${file}`, PNG(`A/${file}`), { contentType: 'image/png' }), `logo ${file}`);
  }
  ok('P8 artwork: only inside the admin\'s own company folder',
    !!(await A.admin.storage.from('wallet-assets').upload(`${B.company.id}/logo/x/logo.png`, PNG('x'), { contentType: 'image/png' })).error
    && !!(await sara.client.storage.from('wallet-assets').upload(`${A.company.id}/logo/y/logo.png`, PNG('y'), { contentType: 'image/png' })).error
    && !(await superAdmin.storage.from('wallet-assets').upload(`${B.company.id}/logo/s1/google.png`, PNG('B'), { contentType: 'image/png' })).error);

  const savedA = must(await A.admin.rpc('set_wallet_card_settings', { p_company_id: A.company.id,
    ...design('#1565c0', { p_logo_path: `${A.company.id}/logo/s1`, p_contact_phone: '0100 123 4567', p_contact_label: 'مكتب النقل' }) }), 'save A').data;
  ok('P9 company admin saves design, logo and contact; who and when are recorded',
    savedA.background_color === '#1565C0' && savedA.revision === 1 && savedA.updated_by_name === 'مدير A'
    && savedA.contact_phone === '0100 123 4567' && savedA.logo_path === `${A.company.id}/logo/s1`, JSON.stringify(savedA));
  must(await superAdmin.rpc('set_wallet_card_settings', { p_company_id: B.company.id, ...design('#EF6C00') }), 'save B');
  ok('P10 the super admin can set any company\'s design',
    must(await B.admin.rpc('get_wallet_card_settings'), 'B').data.background_color === '#EF6C00');
  ok('P11 wallet-sync: company admin is pinned to own company, a student is refused, no caller no service',
    (await invoke(sara.client, 'wallet-sync', { companyId: A.company.id })).status === 403
    && (await invoke(superAdmin, 'wallet-sync', {})).status === 400
    && (await fetch(`${URL_}/functions/v1/wallet-sync`, { method: 'POST', headers: { 'x-wallet-sync-secret': 'wrong' }, body: '{}' })).status === 401);

  // ---- R. Route visibility: only an approved subscription puts line and station on the card
  const zakiPass = await issueApple(zaki);
  ok('R0 never subscribed: neutral platform card, identity only',
    zakiPass.pass.logoText === 'باصك' && zakiPass.files.includes('logo.png')
    && JSON.stringify(front(zakiPass.pass)) === JSON.stringify({ name: 'زكي بلا اشتراك', university: university.name }),
    JSON.stringify(front(zakiPass.pass)));

  const saraSub = await subscribe(sara, A, 0);
  const pending = await issueApple(sara);
  ok('R1 pending subscription: no line, no station, no company yet',
    saraSub.status !== 'active' && !('line' in front(pending.pass)) && !('station' in front(pending.pass)) && pending.pass.logoText === 'باصك',
    JSON.stringify(front(pending.pass)));
  ok('R2 the pass is intact, signed, ID-style, updatable, with no expiry',
    pending.hashesMatch && pending.signatureValid && !!pending.pass.eventTicket && !pending.pass.storeCard
    && pending.pass.webServiceURL === `${URL_}/functions/v1/wallet-apple-web/` && pending.pass.authenticationToken.length >= 16
    && !('expirationDate' in pending.pass) && pending.pass.sharingProhibited === true);
  ok('R3 serial = student id, barcode = the bare permanent QR',
    pending.pass.serialNumber === sara.id && pending.pass.barcodes.length === 1 && pending.pass.barcodes[0].message === sara.qr_code_value);

  ok('R4 register a device for the card', (await register(`phone-${run}`, sara.id, sara.token, `tok-phone-${run}`)).status === 201);
  await fakeReset();
  await approve(saraSub);
  ok('R5 approval is delivered by itself (trigger -> wallet-sync), no publish pressed', await settled([sara.id]));
  const approved = await fetchPass(sara);
  ok('R6 after approval the same card shows the company, the line and the pickup station',
    approved.pass?.logoText === A.company.name && front(approved.pass).line === A.lineName && front(approved.pass).station === 'محطة A1'
    && approved.pass.serialNumber === sara.id && approved.pass.authenticationToken === sara.token
    && approved.pass.barcodes[0].message === sara.qr_code_value, JSON.stringify(approved.pass ? front(approved.pass) : approved));
  ok('R7 ...in the company\'s colours, with its logo, contact on the back and the platform as attribution only',
    approved.pass.backgroundColor === 'rgb(21, 101, 192)'
    && approved.manifest['logo.png'] === crypto.createHash('sha1').update(PNG('A/logo.png')).digest('hex')
    && fields(approved.pass, 'backFields').contact === '0100 123 4567'
    && approved.pass.eventTicket.backFields.find((f) => f.key === 'contact').label === 'مكتب النقل'
    && !JSON.stringify(front(approved.pass)).includes('باصك') && fields(approved.pass, 'backFields').platform.includes('Powered by Basak'));
  ok('R6b ...and the term of that subscription, with its year on the line below; a pending one showed none',
    /^.+\n\d{4}\/\d{4}$/.test(front(approved.pass).term ?? '') && !('term' in front(pending.pass)), JSON.stringify(front(approved.pass).term));
  ok('R8 the device was pushed for it', (await fakeState()).pushes.some((p) => p.token === `tok-phone-${run}` && p.body === '{}' && p.topic === PASS_TYPE));

  // ---- A/B. Same company -> same design; different companies -> independent designs
  const omarSub = await subscribe(omar, A, 1); await approve(omarSub);
  const monaSub = await subscribe(mona, B, 0); await approve(monaSub);
  const omarPass = await issueApple(omar);
  const monaPass = await issueApple(mona);
  ok('A1 two students of company A: same logo, colours and title; different name, QR, station',
    omarPass.pass.backgroundColor === approved.pass.backgroundColor && omarPass.pass.logoText === approved.pass.logoText
    && omarPass.manifest['logo.png'] === approved.manifest['logo.png']
    && front(omarPass.pass).name === 'عمر خالد' && front(omarPass.pass).station === 'محطة A2'
    && omarPass.pass.barcodes[0].message === omar.qr_code_value && omarPass.pass.serialNumber !== approved.pass.serialNumber);
  ok('B1 company B student: B\'s colour and name; no logo uploaded for Apple -> name as text only',
    monaPass.pass.backgroundColor === 'rgb(239, 108, 0)' && monaPass.pass.logoText === B.company.name
    && !monaPass.files.includes('logo.png') && monaPass.files.includes('icon.png') && front(monaPass.pass).line === B.lineName);

  // ---- F. Missing data never shows a placeholder
  ok('F1 college "غير محدد" and a missing contact are simply absent',
    !('college' in front(omarPass.pass)) && !('college' in front(approved.pass))
    && !('contact' in fields(monaPass.pass, 'backFields'))
    && ![JSON.stringify(omarPass.pass), JSON.stringify(monaPass.pass), JSON.stringify(zakiPass.pass)].some((t) => /غير محدد|N\/A|null|undefined/.test(t)));

  // ---- I. Photo
  ok('I1 Apple: square portrait at three scales for a student with a photo, none without',
    JSON.stringify(approved.thumbnails) === JSON.stringify([[90, 90], [180, 180], [270, 270]])
    && omarPass.thumbnails.every((t) => t === null) && !omarPass.files.some((f) => f.startsWith('thumbnail')), JSON.stringify(approved.thumbnails));

  const saraSave = await issueGoogle(sara);
  await issueGoogle(omar); await issueGoogle(mona);
  const [gSara, gOmar, gMona] = [await googleObject(sara), await googleObject(omar), await googleObject(mona)];
  const claims = JSON.parse(Buffer.from(saraSave.split('/').pop().split('.')[1], 'base64url').toString());
  ok('G1 Google: signed save link for the student\'s own object, one shared class',
    saraSave.startsWith('https://pay.google.com/gp/v/save/') && claims.payload.genericObjects[0].id === `${ISSUER}.student_${sara.id}`
    && gSara.classId === `${ISSUER}.basak_student_card` && gSara.classId === gMona.classId && gOmar.classId === gSara.classId);
  ok('G2 Google: company title and colour per company; bare QR; route rows; no placeholders',
    gSara.cardTitle.defaultValue.value === A.company.name && gSara.hexBackgroundColor === '#1565c0' && gOmar.hexBackgroundColor === '#1565c0'
    && gMona.hexBackgroundColor === '#ef6c00' && gMona.cardTitle.defaultValue.value === B.company.name
    && gSara.barcode.value === sara.qr_code_value && gSara.header.defaultValue.value === 'سارة أحمد'
    && gSara.textModulesData.map((m) => m.id).join() === 'station,line,university,term'
    && gOmar.textModulesData.map((m) => m.id).join() === 'station,line,university,term'
    && gSara.logo.sourceUri.uri.endsWith(`${A.company.id}/logo/s1/google.png`) && gOmar.logo.sourceUri.uri === gSara.logo.sourceUri.uri && !('logo' in gMona)
    && gSara.linksModuleData.uris[0].uri === 'tel:01001234567' && gMona.linksModuleData.uris.length === 0, JSON.stringify(gSara.textModulesData));
  const photoUrl = gSara.imageModulesData[0]?.mainImage.sourceUri.uri ?? '';
  const photo = await fetch(photoUrl);
  const photoBytes = Buffer.from(await photo.arrayBuffer());
  ok('I2 Google: the photo is served only through an unguessable link, as a small JPEG, never the original',
    /\/functions\/v1\/wallet-photo\/[0-9a-f]{64}\.jpg$/.test(photoUrl) && photo.status === 200 && photo.headers.get('content-type') === 'image/jpeg'
    && photoBytes[0] === 0xff && photoBytes[1] === 0xd8 && photoBytes.length < PHOTO.length && !photoUrl.includes(sara.id)
    && !JSON.stringify(gSara).includes('avatar') && gOmar.imageModulesData.length === 0, `${photo.status} ${photoBytes.length}`);
  ok('I3 a wrong token gets nothing',
    (await fetch(photoUrl.replace(/[0-9a-f]{64}/, 'f'.repeat(64)))).status === 404
    && (await fetch(`${URL_}/functions/v1/wallet-photo/${sara.id}.jpg`)).status === 404);
  must(await service.storage.from('student-avatars').update(`${sara.id}/avatar.jpg`, Buffer.concat([PHOTO, Buffer.from('new')]), { contentType: 'image/jpeg', upsert: true }), 'replace photo');
  must(await sara.client.rpc('wallet_refresh_my_card'), 'refresh');
  await settled([sara.id]);
  const rotated = (await googleObject(sara)).imageModulesData[0].mainImage.sourceUri.uri;
  ok('I4 a replaced photo gets a new link and the old one dies',
    rotated !== photoUrl && (await fetch(rotated)).status === 200 && (await fetch(photoUrl)).status === 404);

  // ---- J. Apple: many devices, many passes
  ok('J1 one pass on a second device; one device holding two students\' passes',
    (await register(`watch-${run}`, sara.id, sara.token, `tok-watch-${run}`)).status === 201
    && (await register(`shared-${run}`, sara.id, sara.token, `tok-shared-old-${run}`)).status === 201
    && (await register(`shared-${run}`, omar.id, omar.token, `tok-shared-${run}`)).status === 201
    && (await register(`shared-${run}`, omar.id, omar.token, `tok-shared-${run}`)).status === 200
    && (await register(`phone-${run}`, sara.id, omar.token, 'x')).status === 401);
  await register(`gone-${run}`, omar.id, omar.token, `dead-${run}`);
  await register(`b-phone-${run}`, mona.id, mona.token, `tok-b-${run}`);
  const tag = (await (await updatedSince(`shared-${run}`)).json()).lastUpdated;
  ok('J2 nothing changed since the device\'s tag -> 204', (await updatedSince(`shared-${run}`, tag)).status === 204);

  // ---- C. Company admin changes A blue -> green: only A's cards, all of A's cards
  await settled(ids);
  await fakeReset();
  const beforeB = (await passRows([mona.id])).map((p) => p.content_updated_at).join();
  const greenA = must(await A.admin.rpc('set_wallet_card_settings', { p_company_id: A.company.id,
    ...design('#00897B', { p_logo_path: `${A.company.id}/logo/s1`, p_contact_phone: '0100 123 4567', p_contact_label: 'مكتب النقل', p_card_title: 'شركة A - الفصل الثاني' }) }), 'green').data;
  const rolloutA = await publish(A.admin, A.company.id);
  await settled([sara.id, omar.id]);
  const afterA = must(await A.admin.rpc('get_wallet_card_settings'), 'A').data;
  ok('C1 the rollout finishes with nothing pending for A', greenA.revision === 2 && rolloutA.failed === 0 && afterA.pending_cards === 0
    && afterA.apple_cards === 2 && afterA.google_cards === 2, JSON.stringify({ rolloutA, afterA }));
  let state = await fakeState();
  const pushed = state.pushes.map((p) => p.token);
  ok('C2 Apple: every device holding an A card is pushed once per card, with the pass certificate, over HTTP/2',
    [`tok-phone-${run}`, `tok-watch-${run}`, `tok-shared-${run}`, `dead-${run}`].every((t) => pushed.includes(t)) && !pushed.includes(`tok-shared-old-${run}`)
    && state.pushes.every((p) => p.body === '{}' && p.topic === PASS_TYPE && p.httpVersion === '2.0' && String(p.certificate).includes(PASS_TYPE)));
  ok('C3 company B is untouched: no push, no Google write, no row change',
    !pushed.includes(`tok-b-${run}`) && !state.calls.some((c) => c.id === `${ISSUER}.student_${mona.id}`)
    && (await passRows([mona.id])).map((p) => p.content_updated_at).join() === beforeB);
  ok('C4 a device with a dead push token is forgotten',
    must(await service.from('wallet_apple_devices').select('device_library_id').eq('device_library_id', `gone-${run}`), 'dead').data.length === 0);
  const changed = await updatedSince(`shared-${run}`, tag);
  const changedBody = changed.status === 200 ? await changed.json() : {};
  ok('C5 the shared device hears that both its passes changed, then nothing more',
    changedBody.serialNumbers?.length === 2 && (await updatedSince(`shared-${run}`, changedBody.lastUpdated)).status === 204, JSON.stringify(changedBody));
  const greenSara = await fetchPass(sara);
  ok('C6 Apple: the device downloads the green card - same serial, token and QR',
    greenSara.pass.backgroundColor === 'rgb(0, 137, 123)' && greenSara.pass.logoText === 'شركة A - الفصل الثاني'
    && greenSara.pass.serialNumber === sara.id && greenSara.pass.authenticationToken === sara.token
    && greenSara.pass.barcodes[0].message === sara.qr_code_value && greenSara.signatureValid);
  ok('C7 Google: A\'s objects carry the same new values under the same ids',
    (await googleObject(sara)).hexBackgroundColor === '#00897b' && (await googleObject(omar)).hexBackgroundColor === '#00897b'
    && (await googleObject(omar)).cardTitle.defaultValue.value === 'شركة A - الفصل الثاني'
    && (await googleObject(sara)).id === `${ISSUER}.student_${sara.id}` && (await googleObject(sara)).barcode.value === sara.qr_code_value);
  ok('C8 publishing again does nothing', (await publish(A.admin, A.company.id)).updated === 0);

  // ---- D. Super admin changes B: only B
  await fakeReset();
  must(await superAdmin.rpc('set_wallet_card_settings', { p_company_id: B.company.id, ...design('#6A1B9A') }), 'purple B');
  await publish(superAdmin, B.company.id);
  await settled([mona.id]);
  state = await fakeState();
  ok('D1 only company B updates', state.pushes.map((p) => p.token).join() === `tok-b-${run}`
    && (await googleObject(mona)).hexBackgroundColor === '#6a1b9a' && !state.calls.some((c) => c.id.includes(sara.id) || c.id.includes(omar.id))
    && (await fetchPass(mona)).pass.backgroundColor === 'rgb(106, 27, 154)');
  ok('D2 a company admin cannot roll out another company',
    (await invoke(A.admin, 'wallet-sync', { companyId: B.company.id })).data?.remaining === 0
    && (await dirtyCount([mona.id])) === 0);

  // ---- E. One student's data changes: only that student's card
  await fakeReset();
  const others = (await passRows([omar.id, mona.id, zaki.id])).map((p) => p.content_updated_at).join();
  must(await service.from('students').update({ full_name: 'سارة أحمد علي' }).eq('id', sara.id), 'rename student');
  ok('E1 a corrected name reaches that student\'s card by itself', await settled([sara.id])
    && front((await fetchPass(sara)).pass).name === 'سارة أحمد علي' && (await googleObject(sara)).header.defaultValue.value === 'سارة أحمد علي');
  ok('E2 ...and nobody else\'s', (await passRows([omar.id, mona.id, zaki.id])).map((p) => p.content_updated_at).join() === others
    && !(await fakeState()).pushes.some((p) => p.token === `tok-b-${run}`));
  must(await A.admin.rpc('save_line', { p_line: {
    id: A.lineId, company_id: A.company.id, name: `خط A الجديد ${run}`, origin_name: 'بداية A', destination_university_id: university.id,
    university_ids: [university.id], price_termly: 100, price_yearly: 180, price_daily: 5,
    stations: [{ id: A.stations[0].id, name: 'المحطة الأولى' }, { id: A.stations[1].id, name: 'محطة A2' }],
    trips: [
      { direction: 'departure', start_time: '07:00', stops: [{ station_index: 0, time: '07:10' }, { station_index: 1, time: '07:20' }] },
      { direction: 'return', start_time: '14:00', stops: [{ station_index: 1, time: '14:10' }, { station_index: 0, time: '14:20' }] },
    ],
  } }), 'rename line');
  await settled([sara.id, omar.id]);
  const renamed = [front((await fetchPass(sara)).pass), front((await fetchPass(omar)).pass)];
  ok('E3 renaming a line and a station through the dashboard updates the riders\' cards',
    renamed[0].line === `خط A الجديد ${run}` && renamed[0].station === 'المحطة الأولى' && renamed[1].line === `خط A الجديد ${run}` && renamed[1].station === 'محطة A2',
    JSON.stringify(renamed));

  // ---- H / E2. A pending subscription elsewhere changes nothing; an approved move changes company
  sql(`UPDATE public.subscriptions SET status = 'expired', end_date = public.cairo_today() - 1, start_date = public.cairo_today() - 90 WHERE id = '${omarSub.id}'`);
  await settled([omar.id]);
  const ended = (await fetchPass(omar)).pass;
  ok('H1 subscription ended: the route disappears, the last company\'s branding stays',
    !('line' in front(ended)) && !('station' in front(ended)) && ended.logoText === 'شركة A - الفصل الثاني' && ended.backgroundColor === 'rgb(0, 137, 123)',
    JSON.stringify(front(ended)));
  const omarToB = await subscribe(omar, B, 1);
  await settled([omar.id]);
  const stillA = (await fetchPass(omar)).pass;
  ok('H2 a pending subscription with company B changes nothing', stillA.logoText === 'شركة A - الفصل الثاني' && !('line' in front(stillA)));
  await fakeReset();
  await approve(omarToB);
  await settled([omar.id]);
  const moved = (await fetchPass(omar)).pass;
  ok('H3 approved: the SAME card becomes company B\'s, with B\'s line and station',
    moved.logoText === B.company.name && moved.backgroundColor === 'rgb(106, 27, 154)' && front(moved).line === B.lineName && front(moved).station === 'محطة B2'
    && moved.serialNumber === omar.id && moved.authenticationToken === omar.token && moved.barcodes[0].message === omar.qr_code_value
    && (await googleObject(omar)).cardTitle.defaultValue.value === B.company.name && (await googleObject(omar)).id === `${ISSUER}.student_${omar.id}`,
    JSON.stringify(front(moved)));
  const scope = Object.fromEntries((await passRows([omar.id])).map((p) => [p.platform, p.company_id]));
  ok('H4 from now on the card belongs to B\'s rollouts, not A\'s',
    scope.apple === B.company.id && scope.google === B.company.id
    && must(await A.admin.rpc('get_wallet_card_settings'), 'A').data.apple_cards === 1
    && must(await B.admin.rpc('get_wallet_card_settings'), 'B').data.apple_cards === 2);

  // ---- K. Time passing without any write: caught the first time the card is used
  const supervisorId = await mk(`0109${String(parseInt(run, 16) % 10000000).padStart(7, '0')}@busak.app`, 'Supervisor-1');
  must(await service.from('supervisors').insert({ id: supervisorId, full_name: 'مشرف', phone: `0109${String(parseInt(run, 16) % 10000000).padStart(7, '0')}`, company_id: B.company.id }), 'supervisor');
  await settled(ids);
  sql(`ALTER TABLE public.subscriptions DISABLE TRIGGER trg_wallet_subscription_change;
       UPDATE public.subscriptions SET end_date = public.cairo_today() - 1, start_date = public.cairo_today() - 90 WHERE id = '${monaSub.id}';
       ALTER TABLE public.subscriptions ENABLE TRIGGER trg_wallet_subscription_change;`);
  const beforeScan = (await passRows([mona.id])).map((p) => p.content_updated_at).join();
  await sleep(1500);
  ok('K1 a subscription that ends by date alone leaves the card as it was (nothing ran)',
    (await dirtyCount([mona.id])) === 0 && (await passRows([mona.id])).map((p) => p.content_updated_at).join() === beforeScan);
  sql(`INSERT INTO public.supervisor_scan_events (supervisor_id, student_id, ride_date, direction, result)
       SELECT s.id, '${mona.id}', public.cairo_today(), 'departure', 'no_active_subscription' FROM public.supervisors s LIMIT 1`);
  const scanned = sql('SELECT count(*) FROM public.supervisors') !== '0';
  if (!scanned) must(await mona.client.rpc('wallet_refresh_my_card'), 'refresh');
  await settled([mona.id]);
  ok(`K2 the next ${scanned ? 'scan' : 'app refresh'} corrects it: the route is gone, the brand stays`,
    (await passRows([mona.id])).every((p) => !beforeScan.includes(p.content_updated_at))
    && !(await googleObject(mona)).textModulesData.some((m) => m.id === 'line') && !('line' in front((await fetchPass(mona)).pass))
    && (await fetchPass(mona)).pass.logoText === B.company.name);
  const unchanged = (await passRows([zaki.id])).map((p) => p.content_updated_at).join();
  must(await zaki.client.rpc('wallet_refresh_my_card'), 'refresh');
  ok('K3 a refresh with nothing to change is a no-op', (await dirtyCount([zaki.id])) === 0
    && (await passRows([zaki.id])).map((p) => p.content_updated_at).join() === unchanged);

  // ---- G. The card is never the authority
  const scan = await superAdmin.rpc('lookup_student_by_qr', { p_qr_code: mona.qr_code_value });
  ok('G3 the QR on the card is still just the student\'s id: the server answers from live data',
    !scan.error && scan.data?.id === mona.id, scan.error?.message);

  // ---- L. A wallet failure must never break the business
  sql('ALTER TABLE public.wallet_passes RENAME TO wallet_passes_broken');
  let businessOk = true;
  try {
    const sub = await subscribe(zaki, A, 0);
    await approve(sub);
    must(await service.from('students').update({ college: 'الطب' }).eq('id', zaki.id), 'student update');
    must(await superAdmin.from('companies').update({ name: `${B.company.name} ` }).eq('id', B.company.id), 'company update');
  } catch (error) { businessOk = String(error.message); }
  sql("ALTER TABLE public.wallet_passes_broken RENAME TO wallet_passes; NOTIFY pgrst, 'reload schema'");
  await sleep(2500);
  ok('L1 with the wallet tables broken, subscribing, approving and editing still work', businessOk === true, businessOk);
  must(await zaki.client.rpc('wallet_refresh_my_card'), 'refresh');
  await settled([zaki.id]);
  ok('L2 ...and the card catches up afterwards', front((await fetchPass(zaki)).pass).line === `خط A الجديد ${run}`
    && !('college' in front((await fetchPass(zaki)).pass)));

  // ---- X. Removing cards and accounts
  ok('X1 unregistering one of two passes keeps the device; the last one forgets it',
    (await unregister(`shared-${run}`, sara.id, sara.token)).status === 200
    && must(await service.from('wallet_apple_devices').select('device_library_id').eq('device_library_id', `shared-${run}`), 'd').data.length === 1
    && (await unregister(`shared-${run}`, omar.id, omar.token)).status === 200
    && must(await service.from('wallet_apple_devices').select('device_library_id').eq('device_library_id', `shared-${run}`), 'd').data.length === 0);
  const lastToken = must(await service.from('wallet_passes').select('photo_token').eq('student_id', sara.id).eq('platform', 'google').single(), 'token').data.photo_token;
  const lastPhoto = `${URL_}/functions/v1/wallet-photo/${lastToken}.jpg`;
  const photoWorked = (await fetch(lastPhoto)).status === 200;
  must(await service.auth.admin.deleteUser(sara.id), 'delete student');
  ok('X2 deleting a student removes cards, registrations, orphaned devices, and kills the token and photo link',
    (await passRows([sara.id])).length === 0
    && must(await service.from('wallet_apple_devices').select('device_library_id').in('device_library_id', [`phone-${run}`, `watch-${run}`]), 'devices').data.length === 0
    && (await fetchPass(sara)).status === 401 && photoWorked && (await fetch(lastPhoto)).status === 404);
}

main().catch((error) => { ok('test run completed', false, error.stack ?? error.message); }).finally(() => {
  for (const r of results) console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.step}${r.detail ? `\n      ${r.detail}` : ''}`);
  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
});
