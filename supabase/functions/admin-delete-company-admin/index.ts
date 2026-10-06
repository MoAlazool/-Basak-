import { corsHeaders, errorMessage, errorStatus, HttpError, jsonResponse, requireSuperAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

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

    // References that would block deleting the account. Supervisors keep their
    // accounts and only lose the "created by" attribution (no ON DELETE rule).
    const { error: supervisorsError } = await serviceClient
      .from('supervisors').update({ created_by_admin_id: null }).eq('created_by_admin_id', adminId);
    if (supervisorsError) throw supervisorsError;
    // A company admin row must name its creator (ON DELETE RESTRICT): hand any to the acting admin.
    const { error: adminsError } = await serviceClient
      .from('admins').update({ created_by_admin_id: context.user.id }).eq('created_by_admin_id', adminId);
    if (adminsError) throw adminsError;

    // Deleting the Auth user signs them out everywhere and cascades the admins row;
    // every other reference to the account is ON DELETE SET NULL.
    const { error: deleteAuthError } = await serviceClient.auth.admin.deleteUser(adminId);
    if (deleteAuthError && !/not found|does not exist/i.test(deleteAuthError.message)) {
      throw deleteAuthError;
    }
    // Legacy rows can exist without a matching Auth user.
    const { error: deleteRowError } = await serviceClient.from('admins').delete().eq('id', adminId);
    if (deleteRowError) throw deleteRowError;
    return jsonResponse({ deleted: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر حذف مدير الشركة.') }, errorStatus(error));
  }
});
