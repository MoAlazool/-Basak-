import { deleteAccount, removeStudentFiles } from '../_shared/accounts.ts';
import { requireSuperAdmin } from '../_shared/admin-auth.ts';
import { errorMessage, errorStatus, jsonResponse, preflight } from '../_shared/http.ts';

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    // Deleting the account is for the person themselves (in the app) or the
    // platform admin. A company removes a student from the company instead
    // (company_remove_student), which leaves the account and other companies alone.
    const { serviceClient } = await requireSuperAdmin(request);
    const { studentId } = await request.json();
    if (typeof studentId !== 'string' || !studentId) {
      return jsonResponse({ error: 'معرّف الطالب غير صحيح.' }, 400);
    }

    const { data: profile, error: lookupError } = await serviceClient
      .from('students').select('id').eq('id', studentId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!profile) return jsonResponse({ error: 'الطالب غير موجود.' }, 404);

    // Files first: if anything after this fails the request can simply be
    // repeated, and no personal file outlives its account.
    await removeStudentFiles(serviceClient, profile.id);

    // Auth deletion cascades subscriptions and student records. A trigger
    // records active subscription prices in an identity-free revenue ledger.
    await deleteAccount(serviceClient, profile.id, 'students');
    return jsonResponse({ deleted: true, revenuePreserved: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر حذف الطالب.') }, errorStatus(error));
  }
});
