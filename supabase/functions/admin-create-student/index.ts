import { corsHeaders, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { serviceClient } = await requireAdmin(request);
    const body = await request.json();
    const fullName = String(body.fullName ?? '').trim();
    const phone = String(body.phone ?? '').replace(/\D/g, '');
    const university = String(body.university ?? '').trim();
    const college = String(body.college ?? 'غير محدد').trim() || 'غير محدد';
    const password = String(body.password ?? '');
    if (fullName.split(/\s+/).length < 4 || phone.length < 10 || !university || password.length < 6) {
      return jsonResponse({ error: 'أدخل الاسم الرباعي ورقم الهاتف والجامعة وكلمة مرور من 6 أحرف على الأقل.' }, 400);
    }

    const email = `${phone}@busak.app`;
    const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { role: 'student', phone, full_name: fullName },
    });
    if (createError || !created.user) throw createError ?? new Error('تعذر إنشاء حساب الطالب.');

    const { error: profileError } = await serviceClient.from('students').insert({
      id: created.user.id,
      phone,
      full_name: fullName,
      university,
      college,
    });
    if (profileError) {
      await serviceClient.auth.admin.deleteUser(created.user.id);
      throw profileError;
    }
    return jsonResponse({ id: created.user.id });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر إضافة الطالب.' }, 400);
  }
});
