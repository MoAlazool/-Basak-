import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export async function requireAdmin(request: Request) {
  const authorization = request.headers.get('Authorization');
  const token = authorization?.replace(/^Bearer\s+/i, '');
  if (!token) throw new Error('يلزم تسجيل الدخول كمسؤول.');

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) throw new Error('إعدادات وظيفة الإدارة غير مكتملة.');

  const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
  const { data: { user }, error: authError } = await authClient.auth.getUser(token);
  if (authError || !user) throw new Error('جلسة الدخول غير صالحة.');

  const serviceClient = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: admin, error: adminError } = await serviceClient
    .from('admins').select('id,role,company_id').eq('id', user.id).maybeSingle();
  if (adminError || !admin) throw new Error('هذا الإجراء متاح للمسؤولين فقط.');

  return { user, admin, serviceClient };
}

export async function requireSuperAdmin(request: Request) {
  const context = await requireAdmin(request);
  if (context.admin.role !== 'super_admin') throw new Error('هذا الإجراء متاح لمدير النظام فقط.');
  return context;
}

export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
