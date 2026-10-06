import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { HttpError } from './admin-auth.ts';

export interface NewCompanyAdmin {
  email: string;
  fullName: string;
  companyId: string;
  /** Empty = send an invitation e-mail instead (needs custom SMTP). */
  password: string;
  createdBy: string;
  redirectTo?: string;
}

export function validateCompanyAdmin(email: string, fullName: string, password: string) {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !fullName) {
    throw new HttpError(400, 'أدخل اسم مدير الشركة وبريده الإلكتروني.');
  }
  if (password && password.length < 8) {
    throw new HttpError(400, 'كلمة المرور يجب ألا تقل عن 8 أحرف.');
  }
}

/** Creates the sign-in account and the admins row together; leaves nothing half-made. */
export async function createCompanyAdmin(service: SupabaseClient, input: NewCompanyAdmin) {
  const { email, fullName, companyId, password, createdBy } = input;
  const { data: existingAdmin, error: existingError } = await service
    .from('admins').select('id').eq('email', email).maybeSingle();
  if (existingError) throw existingError;
  if (existingAdmin) throw new HttpError(409, 'هذا البريد مسجل بالفعل كمسؤول.');

  const metadata = { role: 'company_admin', company_id: companyId, full_name: fullName };
  let authUserId: string;
  let invited = false;

  if (password) {
    // Direct creation: works without a custom SMTP server.
    const { data, error } = await service.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: metadata,
    });
    if (error || !data.user) {
      if (error && /already|registered|exists/i.test(error.message)) {
        throw new HttpError(409, 'هذا البريد مستخدم بالفعل لحساب آخر.');
      }
      throw error ?? new Error('تعذر إنشاء حساب مدير الشركة.');
    }
    authUserId = data.user.id;
  } else {
    // Invitation e-mail: requires custom SMTP (Supabase default SMTP only mails project members).
    const { data, error } = await service.auth.admin.inviteUserByEmail(email, {
      data: metadata, redirectTo: input.redirectTo,
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

  const { error: adminError } = await service.from('admins').insert({
    id: authUserId, email, full_name: fullName, role: 'company_admin',
    company_id: companyId, created_by_admin_id: createdBy,
  });
  if (adminError) {
    await service.auth.admin.deleteUser(authUserId);
    throw adminError;
  }
  return { id: authUserId, invited };
}
