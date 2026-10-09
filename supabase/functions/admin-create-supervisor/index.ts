import { createLogin, finishOrRemoveLogin } from '../_shared/accounts.ts';
import { requireAdmin, resolveCompany } from '../_shared/admin-auth.ts';
import { errorMessage, errorStatus, jsonResponse, preflight, together } from '../_shared/http.ts';
import { isEgyptianMobile, loginEmail, normalizeEgyptianPhone } from '../_shared/phone.ts';

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const context = await requireAdmin(request);
    const { user, serviceClient } = context;
    const body = await request.json();
    const fullName = String(body.fullName ?? '').trim();
    const phone = normalizeEgyptianPhone(body.phone);
    const password = String(body.password ?? '');
    const lineIds: string[] = Array.isArray(body.lineIds)
      ? [...new Set(body.lineIds.map((id: unknown) => String(id ?? '').trim()).filter(Boolean))] as string[]
      : [];

    if (!fullName || !isEgyptianMobile(phone)) {
      return jsonResponse({ error: 'أدخل اسم المشرف ورقم هاتف مصري صحيح.' }, 400);
    }
    if (password.length < 8) {
      return jsonResponse({ error: 'كلمة المرور يجب ألا تقل عن 8 أحرف.' }, 400);
    }
    if (lineIds.length === 0) {
      return jsonResponse({ error: 'اختر خطاً واحداً على الأقل يكون المشرف مسؤولاً عنه.' }, 400);
    }

    // The company and its lines on one side, the phone on the other: asked at once.
    const [scope, taken] = await together([
      (async () => {
        const companyId = await resolveCompany(context, body.companyId);
        const { data: lines, error } = await serviceClient
          .from('lines').select('id').eq('company_id', companyId).in('id', lineIds);
        if (error) throw error;
        return { companyId, lines: lines ?? [] };
      })(),
      serviceClient.from('supervisors').select('id').eq('phone', phone).maybeSingle(),
    ]);
    if (scope.lines.length !== lineIds.length) {
      return jsonResponse({ error: 'بعض الخطوط المختارة لا تتبع شركة المشرف.' }, 400);
    }
    if (taken.error) throw taken.error;
    if (taken.data) return jsonResponse({ error: 'رقم الهاتف مسجل بالفعل لمشرف آخر.' }, 409);

    const supervisorId = await createLogin(serviceClient, {
      email: loginEmail(phone), password, metadata: { role: 'supervisor', phone, full_name: fullName },
      takenMessage: 'رقم الهاتف مستخدم بالفعل لحساب آخر (طالب أو مشرف).',
      failedMessage: 'تعذر إنشاء حساب المشرف.',
    });
    // Deleting the Auth user cascades the supervisors row: nothing half-created remains.
    await finishOrRemoveLogin(serviceClient, supervisorId, 'admin-create-supervisor', async () => {
      const { error: insertError } = await serviceClient.from('supervisors').insert({
        id: supervisorId,
        full_name: fullName,
        phone,
        company_id: scope.companyId,
        created_by_admin_id: user.id,
        is_active: true,
      });
      if (insertError) throw insertError;
      // Company -> Line -> Supervisor. Stored in supervisor_lines (validated in the DB).
      const { error: assignError } = await serviceClient.rpc('set_supervisor_lines', {
        p_supervisor_id: supervisorId,
        p_line_ids: lineIds,
      });
      if (assignError) throw assignError;
    });
    return jsonResponse({ id: supervisorId, lineIds });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إضافة المشرف.') }, errorStatus(error));
  }
});
