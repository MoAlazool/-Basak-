import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

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
    const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!token) return jsonResponse({ error: 'جلسة الدخول غير صالحة.' }, 401);

    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) throw new Error('إعدادات حذف الحساب غير مكتملة.');

    const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) return jsonResponse({ error: 'جلسة الدخول غير صالحة.' }, 401);

    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const [{ data: student }, { data: supervisor }, { data: admin }] = await Promise.all([
      service.from('students').select('id').eq('id', user.id).maybeSingle(),
      service.from('supervisors').select('id').eq('id', user.id).maybeSingle(),
      service.from('admins').select('id').eq('id', user.id).maybeSingle(),
    ]);
    if (!student && (supervisor || admin || user.user_metadata?.role !== 'student')) {
      return jsonResponse({ error: 'حذف الحساب متاح للطلاب فقط.' }, 403);
    }

    await removeStudentFiles(service, student?.id ?? user.id);
    const { error: deleteError } = await service.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;

    // Deleting the Auth user cascades its student data. The database trigger
    // archives active subscription amounts without retaining student identity.
    return jsonResponse({ deleted: true, revenuePreserved: true });
  } catch (error) {
    return jsonResponse({
      error: error instanceof Error ? error.message : 'تعذر حذف الحساب.',
    }, 400);
  }
});
