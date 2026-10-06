import { corsHeaders, errorMessage, errorStatus, jsonResponse, requireSuperAdmin } from '../_shared/admin-auth.ts';

// Admin-assisted password reset (Super Admin only). Changes the student's real
// Supabase Auth password with the service role and flags the account so the app
// forces a new password at the next sign-in. The temporary password is never
// stored or logged: it is returned once, only to the Super Admin who asked.

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';

function generatePassword(length = 10): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  let out = '';
  for (const b of bytes) out += ALPHABET[b % ALPHABET.length];
  // Guarantee at least one digit and one letter.
  return /\d/.test(out) && /[A-Za-z]/.test(out) ? out : generatePassword(length);
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { user, serviceClient } = await requireSuperAdmin(request);
    const body = await request.json();
    const studentId = String(body.studentId ?? '').trim();
    const requested = typeof body.password === 'string' ? body.password : '';
    if (!/^[0-9a-f-]{36}$/i.test(studentId)) return jsonResponse({ error: 'اختر الطالب أولاً.' }, 400);
    if (requested && requested.length < 8) {
      return jsonResponse({ error: 'كلمة المرور المؤقتة يجب ألا تقل عن 8 أحرف.' }, 400);
    }

    const { data: student, error: studentError } = await serviceClient
      .from('students').select('id, full_name, phone').eq('id', studentId).maybeSingle();
    if (studentError) throw studentError;
    if (!student) return jsonResponse({ error: 'الطالب غير موجود.' }, 404);

    // The student's Auth account is the profile id (phone@busak.app); never create a new one.
    const { data: authUser, error: authLookupError } = await serviceClient.auth.admin.getUserById(student.id);
    if (authLookupError || !authUser?.user) {
      return jsonResponse({ error: 'لا يوجد حساب دخول لهذا الطالب. احذفه وأعد إضافته من صفحة الطلاب.' }, 409);
    }

    const generated = !requested;
    const temporaryPassword = requested || generatePassword();
    const { error: updateError } = await serviceClient.auth.admin.updateUserById(student.id, {
      password: temporaryPassword,
    });
    if (updateError) throw updateError;

    const { error: flagError } = await serviceClient
      .from('students').update({ must_change_password: true }).eq('id', student.id);
    if (flagError) throw flagError;

    // Audit without the password.
    const companyId = /^[0-9a-f-]{36}$/i.test(String(body.companyId ?? '')) ? String(body.companyId) : null;
    await serviceClient.from('password_admin_resets').insert({
      student_id: student.id, reset_by: user.id, generated, company_id: companyId,
    });

    return jsonResponse({
      ok: true,
      student: { id: student.id, full_name: student.full_name, phone: student.phone },
      // Only returned when the server generated it; a typed password is already known to the admin.
      temporaryPassword: generated ? temporaryPassword : undefined,
    });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إعادة تعيين كلمة المرور.') }, errorStatus(error));
  }
});
