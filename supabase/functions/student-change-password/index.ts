import { bearerToken, passwordCheckClient, requireUser, serviceClient } from '../_shared/clients.ts';
import { errorMessage, errorStatus, jsonResponse, preflight } from '../_shared/http.ts';

// A signed-in student sets a new password (required after an admin reset).
// The caller is identified from their own session token; the password is set
// on that same Auth user and the "must change password" flag is cleared —
// the flag can only be cleared here, never directly from the app.
Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const messages = { missing: 'سجّل الدخول أولاً.', invalid: 'جلسة الدخول غير صالحة.' };
    if (!bearerToken(request)) return jsonResponse({ error: messages.missing }, 401);
    const body = await request.json();
    const newPassword = String(body.newPassword ?? '');
    if (newPassword.length < 8) {
      return jsonResponse({ error: 'كلمة المرور الجديدة يجب ألا تقل عن 8 أحرف.' }, 400);
    }
    const user = await requireUser(request, messages);

    const service = serviceClient();
    const { data: student, error: studentError } = await service
      .from('students').select('id, must_change_password').eq('id', user.id).maybeSingle();
    if (studentError) throw studentError;
    if (!student) return jsonResponse({ error: 'تغيير كلمة المرور من هنا متاح للطلاب فقط.' }, 403);

    // Outside the forced change after an admin reset, a session alone is not
    // enough: the current password is required, so a stolen or left-open
    // session cannot lock the student out of their own account.
    if (!student.must_change_password) {
      const currentPassword = String(body.currentPassword ?? '');
      const { error: verifyError } = !currentPassword || !user.email
        ? { error: true }
        : await passwordCheckClient().auth.signInWithPassword({ email: user.email, password: currentPassword });
      if (verifyError) return jsonResponse({ error: 'كلمة المرور الحالية غير صحيحة.' }, 403);
    }

    const { error: updateError } = await service.auth.admin.updateUserById(user.id, { password: newPassword });
    if (updateError) throw updateError;
    const { error: flagError } = await service
      .from('students').update({ must_change_password: false }).eq('id', user.id);
    if (flagError) throw flagError;

    return jsonResponse({ ok: true });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر تغيير كلمة المرور.') }, errorStatus(error));
  }
});
