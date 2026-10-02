import { corsHeaders, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { admin, serviceClient } = await requireAdmin(request);
    const { supervisorId } = await request.json();
    if (typeof supervisorId !== 'string' || !supervisorId) {
      return jsonResponse({ error: 'معرّف المشرف غير صحيح.' }, 400);
    }

    const { data: supervisor, error: lookupError } = await serviceClient
      .from('supervisors').select('id,company_id').eq('id', supervisorId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!supervisor) return jsonResponse({ error: 'المشرف غير موجود.' }, 404);
    if (admin.role === 'company_admin' && supervisor.company_id !== admin.company_id) {
      return jsonResponse({ error: 'هذا المشرف غير تابع لشركتك.' }, 403);
    }

    // Unassign lines first so no line keeps pointing at a deleted account.
    const { error: unassignError } = await serviceClient
      .from('lines').update({ supervisor_id: null }).eq('supervisor_id', supervisorId);
    if (unassignError) throw unassignError;

    // Deleting the Auth user cascades the supervisors row (FK ON DELETE CASCADE).
    const { error: deleteAuthError } = await serviceClient.auth.admin.deleteUser(supervisorId);
    if (deleteAuthError && !/not found|does not exist/i.test(deleteAuthError.message)) {
      throw deleteAuthError;
    }
    // Legacy rows can exist without a matching Auth user.
    const { error: deleteRowError } = await serviceClient.from('supervisors').delete().eq('id', supervisorId);
    if (deleteRowError) throw deleteRowError;
    return jsonResponse({ deleted: true });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر حذف المشرف.' }, 400);
  }
});
