// deno test supabase/functions/_shared/
import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { deleteAccount, removeStudentFiles } from './accounts.ts';
import { assertAdminEmailFree, createCompanyAdmin } from './company-admin.ts';
import { HttpError } from './http.ts';
import { fakeSupabase } from './testing/fake_supabase.ts';

const USER = 'dddddddd-0000-4000-8000-000000000001';
const admin = { email: 'admin@company.test', fullName: 'مدير', companyId: 'c1', createdBy: 'creator' };

Deno.test('deleting an account removes the sign-in account, then the legacy profile row', async () => {
  const fake = fakeSupabase();
  await deleteAccount(fake.client, USER, 'supervisors');
  assertEquals(fake.log, ['auth.admin.deleteUser', 'delete supervisors']);
  assertEquals(fake.db[0].filters, { id: USER });
});

Deno.test('a profile without a sign-in account is still deleted; any other Auth error stops before the row', async () => {
  const legacy = fakeSupabase({ authAdmin: () => ({ error: { message: 'User not found' } }) });
  await deleteAccount(legacy.client, USER, 'students');
  assertEquals(legacy.count('delete students'), 1);

  const down = fakeSupabase({ authAdmin: () => ({ error: { message: 'service unavailable' } }) });
  await assertRejects(() => deleteAccount(down.client, USER, 'students'));
  assertEquals(down.count('delete students'), 0);
});

Deno.test("a student's files: both buckets at once, page after page until empty", async () => {
  const left: Record<string, number> = { 'student-avatars': 1, receipts: 2300 };
  const removed: Record<string, number> = { 'student-avatars': 0, receipts: 0 };
  const fake = fakeSupabase({
    storage: (bucket, method, args) => {
      if (method === 'list') {
        assertEquals(args[0], USER);
        return { data: Array.from({ length: Math.min(1000, left[bucket]) }, (_, index) => ({ name: `f${index}.jpg` })) };
      }
      const paths = args[0] as string[];
      assertEquals(paths.every((path) => path.startsWith(`${USER}/`)), true);
      left[bucket] -= paths.length;
      removed[bucket] += paths.length;
      return { data: [] };
    },
  });
  await removeStudentFiles(fake.client, USER);
  assertEquals(removed, { 'student-avatars': 1, receipts: 2300 });
  assertEquals(fake.timeline.slice(0, 2), ['start storage student-avatars.list', 'start storage receipts.list']);
});

Deno.test('a storage error while removing files is reported, not swallowed', async () => {
  const fake = fakeSupabase({ storage: (bucket) => bucket === 'receipts' ? { error: { message: 'storage down' } } : { data: [] } });
  await assertRejects(() => removeStudentFiles(fake.client, USER));
});

Deno.test('an e-mail that already belongs to an admin is refused before anything is created', async () => {
  const fake = fakeSupabase({ db: () => ({ data: { id: 'someone' } }) });
  const error = await assertRejects(() => assertAdminEmailFree(fake.client, admin.email), HttpError);
  assertEquals(error.status, 409);
  await assertAdminEmailFree(fakeSupabase().client, admin.email);
});

Deno.test('a company admin: account then admins row; a failed row removes the account', async () => {
  const good = fakeSupabase({ authAdmin: () => ({ data: { user: { id: USER } } }) });
  assertEquals(await createCompanyAdmin(good.client, { ...admin, password: 'Secret-123' }), { id: USER, invited: false });
  assertEquals(good.log, ['auth.admin.createUser', 'insert admins']);

  const bad = fakeSupabase({
    authAdmin: (method) => method === 'createUser' ? { data: { user: { id: USER } } } : {},
    db: () => ({ error: { message: 'check violation' } }),
  });
  await assertRejects(() => createCompanyAdmin(bad.client, { ...admin, password: 'Secret-123' }));
  assertEquals(bad.log, ['auth.admin.createUser', 'insert admins', 'auth.admin.deleteUser']);
});

Deno.test('without a password the admin is invited by e-mail, and a failed row removes that account too', async () => {
  const invited = fakeSupabase({ authAdmin: () => ({ data: { user: { id: USER } } }) });
  assertEquals(await createCompanyAdmin(invited.client, { ...admin, password: '' }), { id: USER, invited: true });
  assertEquals(invited.log, ['auth.admin.inviteUserByEmail', 'insert admins']);

  const bad = fakeSupabase({
    authAdmin: (method) => method === 'inviteUserByEmail' ? { data: { user: { id: USER } } } : {},
    db: () => ({ error: { message: 'check violation' } }),
  });
  await assertRejects(() => createCompanyAdmin(bad.client, { ...admin, password: '' }));
  assertEquals(bad.count('auth.admin.deleteUser'), 1);
});
