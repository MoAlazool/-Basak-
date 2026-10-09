import { deleteAccount } from '../_shared/accounts.ts';
import { assertCompanyAccess, requireAdmin } from '../_shared/admin-auth.ts';
import { errorMessage, errorStatus, jsonResponse, preflight } from '../_shared/http.ts';

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const context = await requireAdmin(request);
    const { serviceClient } = context;
    const { supervisorId } = await request.json();
    if (typeof supervisorId !== 'string' || !supervisorId) {
      return jsonResponse({ error: 'معرّف المشرف غير صحيح.' }, 400);
    }

    const { data: supervisor, error: lookupError } = await serviceClient
      .from('supervisors').select('id,company_id').eq('id', supervisorId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!supervisor) return jsonResponse({ error: 'المشرف غير موجود.' }, 404);
    assertCompanyAccess(context, supervisor.company_id);

    // Deleting the Auth user cascades the supervisors row and its supervisor_lines;
    // each line's primary contact is then recomputed by the database.
    await deleteAccount(serviceClient, supervisor.id, 'supervisors');
    // Their photos go too. A leftover file is harmless (nobody can see it), so
    // a storage hiccup does not fail the deletion.
    const { data: photos } = await serviceClient.storage.from('supervisor-avatars').list(supervisor.id);
    if (photos?.length) {
      await serviceClient.storage.from('supervisor-avatars')
        .remove(photos.map((photo) => `${supervisor.id}/${photo.name}`));
    }
    return jsonResponse({ deleted: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر حذف المشرف.') }, errorStatus(error));
  }
});
