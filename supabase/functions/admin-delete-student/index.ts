import { corsHeaders, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';
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
    const { admin, serviceClient } = await requireAdmin(request);
    const { studentId } = await request.json();
    if (typeof studentId !== 'string' || !studentId) {
      return jsonResponse({ error: 'معرّف الطالب غير صحيح.' }, 400);
    }

    const { data: profile, error: lookupError } = await serviceClient
      .from('students').select('id').eq('id', studentId).maybeSingle();
    if (lookupError) throw lookupError;
    if (!profile) return jsonResponse({ error: 'الطالب غير موجود.' }, 404);

    if (admin.role === 'company_admin') {
      const { data: ownedLines, error: linesError } = await serviceClient.from('lines')
        .select('id').eq('company_id', admin.company_id);
      if (linesError) throw linesError;
      const companyLineIds = (ownedLines || []).map((line) => line.id);
      const { data: otherCompanySubs, error: subscriptionsError } = await serviceClient.from('subscriptions')
        .select('line_id,lines!inner(company_id)').eq('student_id', studentId)
        .neq('lines.company_id', admin.company_id || '');
      if (subscriptionsError) throw subscriptionsError;
      if ((otherCompanySubs || []).length > 0 || companyLineIds.length === 0) {
        return jsonResponse({ error: 'لا يمكن حذف حساب طالب مرتبط بخطوط شركة أخرى. استخدم إدارة حالة اشتراك شركتك.' }, 403);
      }
      const { count, error: ownershipError } = await serviceClient.from('subscriptions')
        .select('id', { count: 'exact', head: true }).eq('student_id', studentId).in('line_id', companyLineIds);
      if (ownershipError) throw ownershipError;
      if (!count) return jsonResponse({ error: 'الطالب ليس مشتركاً في خطوط شركتك.' }, 403);
    }

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
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر حذف الطالب.' }, 400);
  }
});
