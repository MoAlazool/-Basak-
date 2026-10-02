import { corsHeaders, jsonResponse, requireSuperAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { user, serviceClient } = await requireSuperAdmin(request);
    const body = await request.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.fullName ?? '').trim();
    const companyId = String(body.companyId ?? '').trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !fullName || !companyId) {
      return jsonResponse({ error: 'أدخل الاسم والبريد الإلكتروني والشركة.' }, 400);
    }

    const { data: company, error: companyError } = await serviceClient
      .from('companies').select('id').eq('id', companyId).eq('is_active', true).maybeSingle();
    if (companyError) throw companyError;
    if (!company) return jsonResponse({ error: 'الشركة غير موجودة أو غير مفعّلة.' }, 404);

    const { data: existingAdmin, error: existingError } = await serviceClient
      .from('admins').select('id').eq('email', email).maybeSingle();
    if (existingError) throw existingError;
    if (existingAdmin) return jsonResponse({ error: 'هذا البريد مسجل بالفعل كمسؤول.' }, 409);

    const { data: invited, error: inviteError } = await serviceClient.auth.admin.inviteUserByEmail(email, {
      data: { role: 'company_admin', company_id: companyId, full_name: fullName },
    });
    if (inviteError || !invited.user) throw inviteError ?? new Error('تعذر إرسال دعوة مدير الشركة.');

    const { error: adminError } = await serviceClient.from('admins').insert({
      id: invited.user.id,
      email,
      full_name: fullName,
      role: 'company_admin',
      company_id: companyId,
      created_by_admin_id: user.id,
    });
    if (adminError) {
      await serviceClient.auth.admin.deleteUser(invited.user.id);
      throw adminError;
    }
    return jsonResponse({ id: invited.user.id, invited: true });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر إنشاء مدير الشركة.' }, 400);
  }
});
