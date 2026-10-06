import { corsHeaders, errorMessage, errorStatus, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';

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
    const lineIds: string[] = Array.isArray(body.lineIds)
      ? [...new Set(body.lineIds.map((id: unknown) => String(id ?? '').trim()).filter(Boolean))] as string[]
      : [];

    if (!fullName || !/^01[0125][0-9]{8}$/.test(phone) || !companyId) {
      return jsonResponse({ error: 'أدخل اسم المشرف ورقم هاتف مصري صحيح والشركة.' }, 400);
    }
    if (password.length < 8) {
      return jsonResponse({ error: 'كلمة المرور يجب ألا تقل عن 8 أحرف.' }, 400);
    }
    if (lineIds.length === 0) {
      return jsonResponse({ error: 'اختر خطاً واحداً على الأقل يكون المشرف مسؤولاً عنه.' }, 400);
    }

    const { data: company, error: companyError } = await serviceClient
      .from('companies').select('id').eq('id', companyId).eq('is_active', true).maybeSingle();
    if (companyError) throw companyError;
    if (!company) return jsonResponse({ error: 'الشركة غير موجودة أو غير مفعّلة.' }, 404);

    const { data: lines, error: linesError } = await serviceClient
      .from('lines').select('id').eq('company_id', companyId).in('id', lineIds);
    if (linesError) throw linesError;
    if ((lines ?? []).length !== lineIds.length) {
      return jsonResponse({ error: 'بعض الخطوط المختارة لا تتبع شركة المشرف.' }, 400);
    }

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

    // Company -> Line -> Supervisor. Stored in supervisor_lines (validated in the DB).
    const { error: assignError } = await serviceClient.rpc('set_supervisor_lines', {
      p_supervisor_id: created.user.id,
      p_line_ids: lineIds,
    });
    if (assignError) {
      // Deleting the Auth user cascades the supervisors row: nothing half-created remains.
      await serviceClient.auth.admin.deleteUser(created.user.id);
      throw assignError;
    }
    return jsonResponse({ id: created.user.id, lineIds });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إضافة المشرف.') }, errorStatus(error));
  }
});
