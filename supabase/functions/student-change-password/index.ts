import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders, errorMessage, jsonResponse } from '../_shared/admin-auth.ts';

// A signed-in student sets a new password (required after an admin reset).
// The caller is identified from their own session token; the password is set
// on that same Auth user and the "must change password" flag is cleared —
// the flag can only be cleared here, never directly from the app.
Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!token) return jsonResponse({ error: 'سجّل الدخول أولاً.' }, 401);
    const body = await request.json();
    const newPassword = String(body.newPassword ?? '');
    if (newPassword.length < 8) {
      return jsonResponse({ error: 'كلمة المرور الجديدة يجب ألا تقل عن 8 أحرف.' }, 400);
    }

    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) throw new Error('إعدادات تغيير كلمة المرور غير مكتملة.');

    const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    if (authError || !user) return jsonResponse({ error: 'جلسة الدخول غير صالحة.' }, 401);

    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: student, error: studentError } = await service
      .from('students').select('id').eq('id', user.id).maybeSingle();
    if (studentError) throw studentError;
    if (!student) return jsonResponse({ error: 'تغيير كلمة المرور من هنا متاح للطلاب فقط.' }, 403);

    const { error: updateError } = await service.auth.admin.updateUserById(user.id, { password: newPassword });
    if (updateError) throw updateError;
    const { error: flagError } = await service
      .from('students').update({ must_change_password: false }).eq('id', user.id);
    if (flagError) throw flagError;

    return jsonResponse({ ok: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر تغيير كلمة المرور.') }, 400);
  }
});
