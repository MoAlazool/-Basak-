import { requireSuperAdmin, resolveCompany } from '../_shared/admin-auth.ts';
import { assertAdminEmailFree, createCompanyAdmin, validateCompanyAdmin } from '../_shared/company-admin.ts';
import { errorMessage, errorStatus, jsonResponse, preflight, together } from '../_shared/http.ts';

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

  try {
    const context = await requireSuperAdmin(request);
    const body = await request.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.fullName ?? '').trim();
    const password = String(body.password ?? '');
    validateCompanyAdmin(email, fullName, password);
    const [companyId] = await together([
      resolveCompany(context, body.companyId),
      assertAdminEmailFree(context.serviceClient, email),
    ]);

    const created = await createCompanyAdmin(context.serviceClient, {
      email, fullName, companyId, password, createdBy: context.user.id,
      redirectTo: request.headers.get('origin') ?? undefined,
    });
    return jsonResponse(created);
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء مدير الشركة.') }, errorStatus(error));
  }
});
