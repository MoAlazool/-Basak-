// The receipt image rules through the real Storage API of a LOCAL stack: a
// student may send the same image again over itself (a retry) and take back an
// image no receipt uses; nobody else may touch it.
//   set -a; . <local logins file>; set +a
//   SUPABASE_URL=... ANON_KEY=... node supabase/tests/local/tenancy/receipt_image_api.mjs
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

async function student(n) {
  const client = createClient(URL_, env('ANON_KEY'), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await client.auth.signInWithPassword({ email: `${env(`STUDENT${n}_PHONE`)}@busak.app`, password: env(`STUDENT${n}_PW`) });
  if (error) throw error;
  return Object.assign(client, { userId: data.user.id });
}
// The smallest valid JPEG is enough: the bucket checks the type, not the picture.
const jpeg = (fill) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(600, fill), Buffer.from([0xff, 0xd9])]);
const opts = { contentType: 'image/jpeg', upsert: true };

const one = await student(1);
const two = await student(2);
const bucket = (client) => client.storage.from('receipts');
const file = `${one.userId}/${crypto.randomUUID()}_${crypto.randomBytes(4).toString('hex')}.jpg`;
try {
  ok('the student uploads the image', !(await bucket(one).upload(file, jpeg(1), opts)).error);
  const again = await bucket(one).upload(file, jpeg(2), opts);
  ok('a retry sends it again over itself', !again.error, again.error?.message);
  const listed = await bucket(one).list(one.userId);
  ok('and it is still one file', listed.data?.filter((o) => file.endsWith(o.name)).length === 1, listed.data?.length);
  const foreign = await bucket(two).upload(file, jpeg(3), opts);
  ok('another student cannot overwrite it', !!foreign.error);
  const foreignRemove = await bucket(two).remove([file]);
  ok('nor remove it', (foreignRemove.data?.length ?? 0) === 0);
  ok('nor read it', !!(await bucket(two).download(file)).error);
  const removed = await bucket(one).remove([file]);
  ok('the student takes it back', removed.data?.length === 1, removed.error?.message);
  ok('and it is gone', !!(await bucket(one).download(file)).error);
} finally {
  await bucket(one).remove([file]);
}
for (const r of results) console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.step}${r.pass ? '' : '  ' + r.detail}`);
const failed = results.filter((r) => !r.pass).length;
console.log(`\nreceipt image api: ${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
