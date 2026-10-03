import { corsHeaders, errorMessage, jsonResponse, requireSuperAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { user, serviceClient } = await requireSuperAdmin(request);
    const body = await request.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.fullName ?? '').trim();
    const companyId = String(body.companyId ?? '').trim();
    const password = String(body.password ?? '');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !fullName || !companyId) {
      return jsonResponse({ error: 'أدخل الاسم والبريد الإلكتروني والشركة.' }, 400);
    }
    if (password && password.length < 8) {
      return jsonResponse({ error: 'كلمة المرور يجب ألا تقل عن 8 أحرف.' }, 400);
    }

    const { data: company, error: companyError } = await serviceClient
      .from('companies').select('id').eq('id', companyId).eq('is_active', true).maybeSingle();
    if (companyError) throw companyError;
    if (!company) return jsonResponse({ error: 'الشركة غير موجودة أو غير مفعّلة.' }, 404);

    const { data: existingAdmin, error: existingError } = await serviceClient
      .from('admins').select('id').eq('email', email).maybeSingle();
    if (existingError) throw existingError;
    if (existingAdmin) return jsonResponse({ error: 'هذا البريد مسجل بالفعل كمسؤول.' }, 409);

    const metadata = { role: 'company_admin', company_id: companyId, full_name: fullName };
    let authUserId: string;
    let invited = false;

    if (password) {
      // Direct creation: works without a custom SMTP server.
      const { data, error } = await serviceClient.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: metadata,
      });
      if (error || !data.user) {
        if (error && /already|registered|exists/i.test(error.message)) {
          return jsonResponse({ error: 'هذا البريد مستخدم بالفعل لحساب آخر.' }, 409);
        }
        throw error ?? new Error('تعذر إنشاء حساب مدير الشركة.');
      }
      authUserId = data.user.id;
    } else {
      // Invitation e-mail: requires custom SMTP (Supabase default SMTP only mails project members).
      const { data, error } = await serviceClient.auth.admin.inviteUserByEmail(email, {
        data: metadata,
        redirectTo: request.headers.get('origin') ?? undefined,
      });
      if (error || !data.user) {
        throw new Error(
          `تعذر إرسال الدعوة بالبريد (${error?.message ?? 'خطأ غير معروف'}). ` +
          'اكتب كلمة مرور لإنشاء الحساب مباشرة، أو فعّل SMTP مخصص في إعدادات Supabase.',
        );
      }
      authUserId = data.user.id;
      invited = true;
    }

    const { error: adminError } = await serviceClient.from('admins').insert({
      id: authUserId,
      email,
      full_name: fullName,
      role: 'company_admin',
      company_id: companyId,
      created_by_admin_id: user.id,
    });
    if (adminError) {
      await serviceClient.auth.admin.deleteUser(authUserId);
      throw adminError;
    }
    return jsonResponse({ id: authUserId, invited });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء مدير الشركة.') }, 400);
  }
});
