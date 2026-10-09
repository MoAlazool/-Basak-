// Who is calling a dashboard function, and what they may act on.
import type { SupabaseClient, User } from 'https://esm.sh/@supabase/supabase-js@2';
import { type Clients, requireUser, serviceClient } from './clients.ts';
import { HttpError } from './http.ts';

export interface AdminRow {
  id: string;
  role: 'super_admin' | 'company_admin';
  company_id: string | null;
}

export interface AdminContext {
  user: User;
  admin: AdminRow;
  /** Full access: use it only for what the checks above allow this admin to do. */
  serviceClient: SupabaseClient;
}

/**
 * The caller must be a signed-in admin: the platform admin, or the admin of a
 * company that is active. `clients` is only passed by tests.
 */
export async function requireAdmin(request: Request, clients?: Clients): Promise<AdminContext> {
  const user = await requireUser(request, {
    missing: 'يلزم تسجيل الدخول كمسؤول.',
    invalid: 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى.',
  }, clients?.anon);

  // The row is looked up by the id Auth just vouched for, never by anything the
  // request says. Its company comes back in the same query.
  const service = clients?.service ?? serviceClient();
  const { data: admin, error: adminError } = await service
    .from('admins').select('id,role,company_id,company:companies(status)').eq('id', user.id).maybeSingle();
  if (adminError || !admin) throw new HttpError(403, 'هذا الإجراء متاح للمسؤولين فقط.');

  if (admin.role === 'company_admin') {
    // A company's admins lose access while the company is suspended or archived.
    const company = admin.company as { status?: string } | null;
    if (!admin.company_id || company?.status !== 'active') {
      throw new HttpError(403, 'حساب شركتك موقوف حالياً. تواصل مع إدارة المنصة.');
    }
  } else if (admin.role !== 'super_admin') {
    throw new HttpError(403, 'هذا الإجراء متاح للمسؤولين فقط.');
  }

  return {
    user,
    admin: { id: admin.id, role: admin.role, company_id: admin.company_id },
    serviceClient: service,
  };
}

export async function requireSuperAdmin(request: Request, clients?: Clients): Promise<AdminContext> {
  const context = await requireAdmin(request, clients);
  if (context.admin.role !== 'super_admin') {
    throw new HttpError(403, 'هذا الإجراء متاح لمدير النظام فقط. (الحساب المسجل حالياً ليس مدير النظام)');
  }
  return context;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Refuses a company admin acting on any company but their own. */
export function assertCompanyAccess(context: AdminContext, companyId: string | null | undefined) {
  if (context.admin.role === 'company_admin' && companyId !== context.admin.company_id) {
    throw new HttpError(403, 'هذا الإجراء خارج صلاحيات شركتك.');
  }
}

/**
 * The company a request acts on: a company admin is pinned to their own
 * whatever the client sends; the platform admin must name an existing one.
 */
export async function resolveCompany(context: AdminContext, requested: unknown): Promise<string> {
  if (context.admin.role === 'company_admin') return context.admin.company_id as string;
  const companyId = String(requested ?? '').trim();
  if (!UUID.test(companyId)) throw new HttpError(400, 'اختر الشركة أولاً.');
  const { data: company, error } = await context.serviceClient
    .from('companies').select('id').eq('id', companyId).maybeSingle();
  if (error) throw error;
  if (!company) throw new HttpError(404, 'الشركة غير موجودة.');
  return companyId;
}
