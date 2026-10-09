// Times the Storage calls the receipts review makes, on a LOCAL stack with
// dataset.sql: signing 50 receipt images in one batch as the company's admin,
// and listing a student's own folder as that student.
//   SUPABASE_URL=… ANON_KEY=… JWT_SECRET=… node supabase/tests/local/perf/sign.mjs
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
const URL_ = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
if (!/127\.0\.0\.1|localhost/.test(URL_)) throw new Error('local only');
const DB = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sql = (q) => execFileSync('psql', [DB, '-qAt', '-c', q]).toString().trim();
const b64 = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
const token = (id) => { const body = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: id, role: 'authenticated', aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })}`;
  return `${body}.${crypto.createHmac('sha256', process.env.JWT_SECRET).update(body).digest('base64url')}`; };
const company = sql(`SELECT cs.company_id FROM company_students cs JOIN companies c ON c.id = cs.company_id WHERE c.name LIKE 'PERF %' GROUP BY 1 ORDER BY count(*) DESC LIMIT 1`);
const admin = sql(`SELECT id FROM admins WHERE company_id = '${company}' LIMIT 1`);
const paths = sql(`SELECT string_agg(image_url, ',') FROM (SELECT image_url FROM receipts WHERE company_id = '${company}' AND status = 'pending' ORDER BY created_at LIMIT 50) x`).split(',');
const student = paths[0].split('/')[0];
const call = async (user, path, body) => {
  const started = performance.now();
  const response = await fetch(`${URL_}/storage/v1/${path}`, { method: 'POST', signal: AbortSignal.timeout(40000),
    headers: { apikey: process.env.ANON_KEY, Authorization: `Bearer ${token(user)}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).catch((e) => ({ status: e.name, json: async () => [] }));
  const data = await response.json().catch(() => null);
  return { ms: Math.round(performance.now() - started), status: response.status, data };
};
const signed = await call(admin, 'object/sign/receipts', { expiresIn: 600, paths });
console.log(`admin signs 50 receipt images in one call: ${signed.ms} ms, HTTP ${signed.status}, signed ${Array.isArray(signed.data) ? signed.data.filter((x) => x.signedURL).length : 0}`);
const listed = await call(student, 'object/list/receipts', { prefix: student, limit: 100 });
console.log(`a student lists their own receipt folder: ${listed.ms} ms, HTTP ${listed.status}, files ${Array.isArray(listed.data) ? listed.data.length : 0}`);
