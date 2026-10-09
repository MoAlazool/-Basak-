import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { createLogin, finishOrRemoveLogin } from './accounts.ts';
import { HttpError } from './http.ts';

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

/** Refuses (409) an e-mail that already belongs to an admin. Checked before anything is created. */
export async function assertAdminEmailFree(service: SupabaseClient, email: string): Promise<void> {
  const { data: existing, error } = await service.from('admins').select('id').eq('email', email).maybeSingle();
  if (error) throw error;
  if (existing) throw new HttpError(409, 'هذا البريد مسجل بالفعل كمسؤول.');
}

/**
 * Creates the sign-in account and the admins row together; leaves nothing
 * half-made. The caller has already run assertAdminEmailFree.
 */
export async function createCompanyAdmin(service: SupabaseClient, input: NewCompanyAdmin) {
  const { email, fullName, companyId, password, createdBy } = input;
  const metadata = { role: 'company_admin', company_id: companyId, full_name: fullName };
  let authUserId: string;
  let invited = false;

  if (password) {
    // Direct creation: works without a custom SMTP server.
    authUserId = await createLogin(service, {
      email, password, metadata,
      takenMessage: 'هذا البريد مستخدم بالفعل لحساب آخر.',
      failedMessage: 'تعذر إنشاء حساب مدير الشركة.',
    });
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

  await finishOrRemoveLogin(service, authUserId, 'create-company-admin', async () => {
    const { error } = await service.from('admins').insert({
      id: authUserId, email, full_name: fullName, role: 'company_admin',
      company_id: companyId, created_by_admin_id: createdBy,
    });
    if (error) throw error;
  });
  return { id: authUserId, invited };
}
