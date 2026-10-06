import { corsHeaders, errorMessage, errorStatus, jsonResponse, requireSuperAdmin, resolveCompany } from '../_shared/admin-auth.ts';
import { createCompanyAdmin, validateCompanyAdmin } from '../_shared/company-admin.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const context = await requireSuperAdmin(request);
    const body = await request.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.fullName ?? '').trim();
    const password = String(body.password ?? '');
    validateCompanyAdmin(email, fullName, password);
    const companyId = await resolveCompany(context, body.companyId);

    const created = await createCompanyAdmin(context.serviceClient, {
      email, fullName, companyId, password, createdBy: context.user.id,
      redirectTo: request.headers.get('origin') ?? undefined,
    });
    return jsonResponse(created);
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء مدير الشركة.') }, errorStatus(error));
  }
});
