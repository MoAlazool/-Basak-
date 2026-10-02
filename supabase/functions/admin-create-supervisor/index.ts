import { corsHeaders, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { user, admin, serviceClient } = await requireAdmin(request);
    const body = await request.json();
    const fullName = String(body.fullName ?? '').trim();
    let phone = String(body.phone ?? '').replace(/\D/g, '');
    if (phone.startsWith('20') && phone.length >= 12) phone = phone.substring(2);
    if (phone.length === 10 && phone.startsWith('1')) phone = `0${phone}`;
    const password = String(body.password ?? '');
    // Company admins are always pinned to their own company, whatever the client sends.
    const companyId = admin.role === 'company_admin' ? admin.company_id : String(body.companyId ?? '').trim();

    if (!fullName || !/^01[0125][0-9]{8}$/.test(phone) || !companyId) {
      return jsonResponse({ error: 'أدخل اسم المشرف ورقم هاتف مصري صحيح والشركة.' }, 400);
    }
    if (password.length < 6) {
      return jsonResponse({ error: 'كلمة المرور يجب ألا تقل عن 6 أحرف.' }, 400);
    }

    const { data: company, error: companyError } = await serviceClient
      .from('companies').select('id').eq('id', companyId).eq('is_active', true).maybeSingle();
    if (companyError) throw companyError;
    if (!company) return jsonResponse({ error: 'الشركة غير موجودة أو غير مفعّلة.' }, 404);

    const { data: existing, error: existingError } = await serviceClient
      .from('supervisors').select('id').eq('phone', phone).maybeSingle();
    if (existingError) throw existingError;
    if (existing) return jsonResponse({ error: 'رقم الهاتف مسجل بالفعل لمشرف آخر.' }, 409);

    const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
      email: `${phone}@busak.app`,
      password,
      email_confirm: true,
      user_metadata: { role: 'supervisor', phone, full_name: fullName },
    });
    if (createError || !created.user) {
      if (createError && /already|registered|exists/i.test(createError.message)) {
        return jsonResponse({ error: 'رقم الهاتف مستخدم بالفعل لحساب آخر (طالب أو مشرف).' }, 409);
      }
      throw createError ?? new Error('تعذر إنشاء حساب المشرف.');
    }

    const { error: insertError } = await serviceClient.from('supervisors').insert({
      id: created.user.id,
      full_name: fullName,
      phone,
      company_id: companyId,
      created_by_admin_id: user.id,
      is_active: true,
    });
    if (insertError) {
      await serviceClient.auth.admin.deleteUser(created.user.id);
      throw insertError;
    }
    return jsonResponse({ id: created.user.id });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر إضافة المشرف.' }, 400);
  }
});
