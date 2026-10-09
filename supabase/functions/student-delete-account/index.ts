import { removeStudentFiles } from '../_shared/accounts.ts';
import { requireUser, serviceClient } from '../_shared/clients.ts';
import { errorMessage, errorStatus, jsonResponse, preflight } from '../_shared/http.ts';

// A signed-in student deletes their own account. The account is the one the
// session token belongs to: nothing in the request can name another.
Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const invalid = 'جلسة الدخول غير صالحة.';
    const user = await requireUser(request, { missing: invalid, invalid });

    const service = serviceClient();
    const [student, supervisor, admin] = await Promise.all([
      service.from('students').select('id').eq('id', user.id).maybeSingle(),
      service.from('supervisors').select('id').eq('id', user.id).maybeSingle(),
      service.from('admins').select('id').eq('id', user.id).maybeSingle(),
    ]);
    // An unanswered question is never read as "not a supervisor / not an admin".
    const failed = student.error ?? supervisor.error ?? admin.error;
    if (failed) throw failed;
    if (!student.data && (supervisor.data || admin.data || user.user_metadata?.role !== 'student')) {
      return jsonResponse({ error: 'حذف الحساب متاح للطلاب فقط.' }, 403);
    }

    // Files first: if deleting the account then fails, the student can simply
    // try again, and no personal file outlives the account.
    await removeStudentFiles(service, user.id);
    const { error: deleteError } = await service.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;

    // Deleting the Auth user cascades its student data. The database trigger
    // archives active subscription amounts without retaining student identity.
    return jsonResponse({ deleted: true, revenuePreserved: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر حذف الحساب.') }, errorStatus(error));
  }
});
