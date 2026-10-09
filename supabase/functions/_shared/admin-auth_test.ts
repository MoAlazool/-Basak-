// deno test supabase/functions/_shared/
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { assertCompanyAccess, requireAdmin, requireSuperAdmin, resolveCompany } from './admin-auth.ts';
import { HttpError } from './http.ts';
import { fakeSupabase, type Handlers, post, type Reply } from './testing/fake_supabase.ts';

const USER = 'aaaaaaaa-0000-4000-8000-000000000001';
const COMPANY = 'cccccccc-0000-4000-8000-000000000001';
const OTHER = 'cccccccc-0000-4000-8000-000000000002';

/** A fake project where the session token belongs to USER and the admins table answers `adminRow`. */
function project(adminRow: Reply, extra: Handlers = {}) {
  const fake = fakeSupabase({
    getUser: (token) => token === 'session-token' ? { data: { id: USER } } : { error: { message: 'invalid JWT' } },
    db: (call) => call.table === 'admins' ? adminRow : extra.db?.(call) ?? {},
  });
  return { fake, clients: { anon: fake.client, service: fake.client } };
}

async function status(run: Promise<unknown>): Promise<number> {
  const error = await assertRejects(() => run, HttpError);
  return error.status;
}

const superRow = { data: { id: USER, role: 'super_admin', company_id: null, company: null } };
const companyRow = (companyStatus: string | null) => ({
  data: { id: USER, role: 'company_admin', company_id: COMPANY, company: companyStatus ? { status: companyStatus } : null },
});

Deno.test('a request without a token is refused before anything is asked', async () => {
  const { fake, clients } = project(superRow);
  assertEquals(await status(requireAdmin(post({}, null), clients)), 401);
  assertEquals(fake.log, []);
});

Deno.test('a token Auth does not accept is refused, and the admins table is never read', async () => {
  const { fake, clients } = project(superRow);
  assertEquals(await status(requireAdmin(post({}, 'stolen-or-expired'), clients)), 401);
  assertEquals(fake.log, ['auth.getUser']);
});

Deno.test('a signed-in user who is not an admin is refused', async () => {
  const { clients } = project({ data: null });
  assertEquals(await status(requireAdmin(post({}), clients)), 403);
});

Deno.test('when the admins table cannot be read the caller is refused, not waved through', async () => {
  const { clients } = project({ error: { message: 'connection reset' } });
  assertEquals(await status(requireAdmin(post({}), clients)), 403);
});

Deno.test('the platform admin is accepted with one Auth call and one query', async () => {
  const { fake, clients } = project(superRow);
  const context = await requireAdmin(post({ adminId: 'someone-else' }), clients);
  assertEquals(context.admin, { id: USER, role: 'super_admin', company_id: null });
  assertEquals(context.user.id, USER);
  assertEquals(fake.log, ['auth.getUser', 'select admins']);
  // Looked up by the id Auth vouched for; the company arrives in the same query.
  assertEquals(fake.db[0].filters, { id: USER });
  assertEquals(fake.db[0].columns, 'id,role,company_id,company:companies(status)');
});

Deno.test('a company admin of an active company is accepted and scoped to it, without a second query', async () => {
  const { fake, clients } = project(companyRow('active'));
  const context = await requireAdmin(post({}), clients);
  assertEquals(context.admin, { id: USER, role: 'company_admin', company_id: COMPANY });
  assertEquals(fake.log, ['auth.getUser', 'select admins']);
});

Deno.test('a company admin is refused while the company is suspended, archived or missing', async () => {
  for (const companyStatus of ['suspended', 'archived', null]) {
    const { clients } = project(companyRow(companyStatus));
    assertEquals(await status(requireAdmin(post({}), clients)), 403, String(companyStatus));
  }
});

Deno.test('a role this code does not know is refused', async () => {
  const { clients } = project({ data: { id: USER, role: 'owner', company_id: null, company: null } });
  assertEquals(await status(requireAdmin(post({}), clients)), 403);
});

Deno.test('platform-only actions refuse a company admin', async () => {
  assertEquals(await status(requireSuperAdmin(post({}), project(companyRow('active')).clients)), 403);
  assertEquals((await requireSuperAdmin(post({}), project(superRow).clients)).admin.role, 'super_admin');
});

Deno.test('a company admin may act on their own company only; the platform admin on any', async () => {
  const company = await requireAdmin(post({}), project(companyRow('active')).clients);
  assertCompanyAccess(company, COMPANY);
  for (const foreign of [OTHER, null, undefined]) {
    let refused = 0;
    try { assertCompanyAccess(company, foreign); } catch (error) { refused = (error as HttpError).status; }
    assertEquals(refused, 403);
  }
  assertCompanyAccess(await requireAdmin(post({}), project(superRow).clients), OTHER);
});

Deno.test('a company admin is pinned to their company whatever the request names', async () => {
  const { fake, clients } = project(companyRow('active'));
  const context = await requireAdmin(post({}), clients);
  assertEquals(await resolveCompany(context, OTHER), COMPANY);
  assertEquals(fake.count('select companies'), 0);
});

Deno.test('the platform admin must name a company that exists', async () => {
  const { clients } = project(superRow, {
    db: (call) => ({ data: call.filters.id === COMPANY ? { id: COMPANY } : null }),
  });
  const context = await requireAdmin(post({}), clients);
  assertEquals(await resolveCompany(context, COMPANY), COMPANY);
  assertEquals(await status(resolveCompany(context, OTHER)), 404);
  assertEquals(await status(resolveCompany(context, 'not-a-uuid')), 400);
  assertEquals(await status(resolveCompany(context, undefined)), 400);
});
