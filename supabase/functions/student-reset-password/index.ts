import { serviceClient } from '../_shared/clients.ts';
import { errorMessage, jsonResponse, preflight } from '../_shared/http.ts';

// Steps 3 and 4 of the student "Forgot password" flow (see migration
// 20261004000003_student_password_reset.sql), called by the app before sign-in.
//   * { phone, code, verifyOnly: true }: is this the one-time code the bus
//     company issued? The app asks before it shows the new-password page. A
//     wrong code counts as one of the 5 tries; a right one is not used up.
//   * { phone, code, newPassword }: checks the code again and sets the new
//     password, which goes straight to Supabase Auth; the code is then used.
const reasons: Record<string, string> = {
  no_code: 'لا يوجد رمز استعادة فعّال لهذا الرقم. اطلب الاستعادة ثم تواصل مع إدارة شركتك للحصول على الرمز.',
  expired: 'انتهت صلاحية الرمز. اطلب رمزاً جديداً من إدارة شركتك.',
  wrong_code: 'الرمز غير صحيح.',
  locked: 'تم إيقاف الرمز بعد 5 محاولات خاطئة. اطلب استعادة جديدة.',
};

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const body = await request.json();
    const phone = String(body.phone ?? '');
    const code = String(body.code ?? '').replace(/\D/g, '');
    const newPassword = String(body.newPassword ?? '');
    const verifyOnly = body.verifyOnly === true;
    if (code.length !== 6) return jsonResponse({ error: 'أدخل الرمز المكون من 6 أرقام.' }, 400);
    if (!verifyOnly && newPassword.length < 8) {
      return jsonResponse({ error: 'كلمة المرور الجديدة يجب ألا تقل عن 8 أحرف.' }, 400);
    }

    // No session exists yet: the one-time code, checked by the database, is the credential.
    const service = serviceClient();

    const { data: check, error: checkError } = await service.rpc('check_student_password_reset_code', {
      p_phone: phone,
      p_code: code,
    });
    if (checkError) throw checkError;
    if (!check?.ok) {
      const message = reasons[check?.reason] ?? 'تعذر التحقق من الرمز.';
      const left = check?.reason === 'wrong_code' && typeof check?.attempts_left === 'number'
        ? ` المحاولات المتبقية: ${check.attempts_left}.` : '';
      return jsonResponse({ error: message + left, reason: check?.reason }, 400);
    }
    if (verifyOnly) return jsonResponse({ valid: true });

    const { error: updateError } = await service.auth.admin.updateUserById(check.student_id, {
      password: newPassword,
    });
    if (updateError) throw updateError;

    const { error: completeError } = await service.rpc('complete_student_password_reset', {
      p_request_id: check.request_id,
    });
    if (completeError) throw completeError;
    return jsonResponse({ reset: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر تغيير كلمة المرور.') }, 400);
  }
});
