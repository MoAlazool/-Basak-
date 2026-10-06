import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/** An error with an HTTP status: 401 = not signed in / invalid session, 403 = not allowed. */
export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function errorStatus(error: unknown): number {
  return error instanceof HttpError ? error.status : 400;
}

export async function requireAdmin(request: Request) {
  const authorization = request.headers.get('Authorization');
  const token = authorization?.replace(/^Bearer\s+/i, '');
  if (!token) throw new HttpError(401, 'يلزم تسجيل الدخول كمسؤول.');

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) throw new Error('إعدادات وظيفة الإدارة غير مكتملة.');

  const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);
  if (authError || !user) throw new HttpError(401, 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى.');

  const serviceClient = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: admin, error: adminError } = await serviceClient
    .from('admins').select('id,role,company_id').eq('id', user.id).maybeSingle();
  if (adminError || !admin) throw new HttpError(403, 'هذا الإجراء متاح للمسؤولين فقط.');

  // A company's admins lose access while the company is suspended or archived.
  if (admin.role === 'company_admin') {
    const { data: company, error: companyError } = await serviceClient
      .from('companies').select('status').eq('id', admin.company_id).maybeSingle();
    if (companyError || company?.status !== 'active') {
      throw new HttpError(403, 'حساب شركتك موقوف حالياً. تواصل مع إدارة المنصة.');
    }
  }

  return { user, admin, serviceClient };
}

export type AdminContext = Awaited<ReturnType<typeof requireAdmin>>;

export async function requireSuperAdmin(request: Request) {
  const context = await requireAdmin(request);
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

export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Readable message for thrown Errors and for PostgREST / Auth error objects. */
export function errorMessage(error: unknown, fallback: string): string {
  if (error && typeof error === 'object' && 'message' in error) {
    const message = String((error as { message?: unknown }).message ?? '').trim();
    if (message) return message;
  }
  return fallback;
}
