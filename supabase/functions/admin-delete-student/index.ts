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

async function requireAdmin(request: Request) {
  const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) throw new Error('جلسة الدخول غير صالحة.');
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) throw new Error('إعدادات وظيفة الإدارة غير مكتملة.');

  const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);
  if (authError || !user) throw new Error('جلسة الدخول غير صالحة.');
  const serviceClient = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: admin, error: adminError } = await serviceClient
    .from('admins').select('id').eq('id', user.id).maybeSingle();
  if (adminError || !admin) throw new Error('هذا الإجراء متاح للمسؤولين فقط.');
  return serviceClient;
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
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const serviceClient = await requireAdmin(request);
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
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر حذف الطالب.' }, 400);
  }
});
