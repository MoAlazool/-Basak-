import { deleteAccount } from '../_shared/accounts.ts';
import { requireSuperAdmin } from '../_shared/admin-auth.ts';
import { errorMessage, errorStatus, HttpError, jsonResponse, preflight } from '../_shared/http.ts';

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const context = await requireSuperAdmin(request);
    const { serviceClient } = context;
    const { adminId } = await request.json();
    if (typeof adminId !== 'string' || !adminId) {
      return jsonResponse({ error: 'معرّف مدير الشركة غير صحيح.' }, 400);
    }
    if (adminId === context.user.id) throw new HttpError(400, 'لا يمكنك حذف حسابك الحالي.');

    const { data: target, error: lookupError } = await serviceClient
      .from('admins').select('id,role').eq('id', adminId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!target) return jsonResponse({ error: 'مدير الشركة غير موجود.' }, 404);
    // Only company admins are removable here; the platform admin is never deleted from the dashboard.
    if (target.role !== 'company_admin') throw new HttpError(403, 'يمكن حذف مديري الشركات فقط.');

    // References that would block deleting the account, cleared at once.
    // Supervisors keep their accounts and only lose the "created by"
    // attribution (no ON DELETE rule). A company admin row must name its
    // creator (ON DELETE RESTRICT): any are handed to the acting admin.
    const [{ error: supervisorsError }, { error: adminsError }] = await Promise.all([
      serviceClient.from('supervisors').update({ created_by_admin_id: null }).eq('created_by_admin_id', adminId),
      serviceClient.from('admins').update({ created_by_admin_id: context.user.id }).eq('created_by_admin_id', adminId),
    ]);
    if (supervisorsError) throw supervisorsError;
    if (adminsError) throw adminsError;

    // Every other reference to the account is ON DELETE SET NULL.
    await deleteAccount(serviceClient, adminId, 'admins');
    return jsonResponse({ deleted: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر حذف مدير الشركة.') }, errorStatus(error));
  }
});
