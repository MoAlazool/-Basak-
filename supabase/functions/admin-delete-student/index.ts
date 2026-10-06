import { corsHeaders, errorMessage, errorStatus, jsonResponse, requireSuperAdmin } from '../_shared/admin-auth.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

async function removeStudentFiles(service: SupabaseClient, studentId: string) {
  for (const bucket of ['student-avatars', 'receipts']) {
    let offset = 0;
    while (true) {
      const { data: files, error } = await service.storage
        .from(bucket)
        .list(studentId, { limit: 1000, offset });
      if (error) throw error;
      if (!files?.length) break;
      const { error: removeError } = await service.storage.from(bucket).remove(
        files.map((file) => `${studentId}/${file.name}`),
      );
      if (removeError) throw removeError;
      if (files.length < 1000) break;
      offset += files.length;
    }
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

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

    await removeStudentFiles(serviceClient, profile.id);

    // Auth deletion cascades subscriptions and student records. A trigger
    // records active subscription prices in an identity-free revenue ledger.
    const { error: deleteAuthError } = await serviceClient.auth.admin.deleteUser(studentId);
    if (deleteAuthError && !/not found|does not exist/i.test(deleteAuthError.message)) {
      throw deleteAuthError;
    }

    // Legacy admin-created rows can exist without a matching Auth user.
    const { error: deleteProfileError } = await serviceClient
      .from('students').delete().eq('id', studentId);
    if (deleteProfileError) throw deleteProfileError;
    return jsonResponse({ deleted: true, revenuePreserved: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر حذف الطالب.') }, errorStatus(error));
  }
});
