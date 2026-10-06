// Creates a company that is usable from the first minute: the company itself,
// its own copy of the semester dates, its wallet card design, its first admin
// and (optionally) a first payment method. If any step fails nothing is left behind.
import { corsHeaders, errorMessage, errorStatus, HttpError, jsonResponse, requireSuperAdmin } from '../_shared/admin-auth.ts';
import { createCompanyAdmin, validateCompanyAdmin } from '../_shared/company-admin.ts';

const text = (value: unknown) => String(value ?? '').trim();

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { user, serviceClient } = await requireSuperAdmin(request);
    const body = await request.json();
    const name = text(body.name);
    const contactPhone = text(body.contactPhone).replace(/[^0-9+]/g, '') || null;
    const contactLabel = text(body.contactLabel) || null;
    const admin = body.admin ?? {};
    const adminEmail = text(admin.email).toLowerCase();
    const adminName = text(admin.fullName);
    const adminPassword = String(admin.password ?? '');
    const method = body.paymentMethod ?? null;

    if (name.length < 2) throw new HttpError(400, 'أدخل اسم الشركة.');
    validateCompanyAdmin(adminEmail, adminName, adminPassword);
    if (method && !['instapay', 'vodafone_cash', 'bank'].includes(text(method.methodType))) {
      throw new HttpError(400, 'نوع وسيلة الدفع غير صحيح.');
    }

    // The database copies the default terms into the new company.
    const { data: company, error: companyError } = await serviceClient.from('companies')
      .insert({ name, contact_phone: contactPhone, contact_label: contactLabel })
      .select('id, name').single();
    if (companyError) {
      if (companyError.code === '23505') throw new HttpError(409, 'توجد شركة بهذا الاسم بالفعل.');
      throw companyError;
    }

    let adminId: string | null = null;
    try {
      const { error: walletError } = await serviceClient.from('wallet_card_settings')
        .upsert({ company_id: company.id }, { onConflict: 'company_id', ignoreDuplicates: true });
      if (walletError) throw walletError;

      const created = await createCompanyAdmin(serviceClient, {
        email: adminEmail, fullName: adminName, companyId: company.id, password: adminPassword,
        createdBy: user.id, redirectTo: request.headers.get('origin') ?? undefined,
      });
      adminId = created.id;

      if (method) {
        const { error: methodError } = await serviceClient.from('company_payment_methods').insert({
          company_id: company.id,
          method_type: text(method.methodType),
          display_name: text(method.displayName),
          account_holder: text(method.accountHolder) || null,
          instapay_address: text(method.instapayAddress) || null,
          wallet_phone: text(method.walletPhone) || null,
          bank_name: text(method.bankName) || null,
          bank_account_number: text(method.bankAccountNumber) || null,
          iban: text(method.iban) || null,
        });
        if (methodError) {
          throw new HttpError(400, 'بيانات وسيلة الدفع غير مكتملة أو غير صحيحة.');
        }
      }
      return jsonResponse({ id: company.id, name: company.name, adminId, invited: created.invited });
    } catch (stepError) {
      // Undo in reverse: the admin's sign-in account (which removes the admins row), then the company.
      if (adminId) await serviceClient.auth.admin.deleteUser(adminId);
      await serviceClient.from('companies').delete().eq('id', company.id);
      throw stepError;
    }
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء الشركة.') }, errorStatus(error));
  }
});
