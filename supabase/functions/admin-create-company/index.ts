// Creates a company that is usable from the first minute: the company itself,
// its own copy of the semester dates, its wallet card design, (optionally) a
// first payment method and its first admin. If any step fails nothing is left behind.
import { requireSuperAdmin } from '../_shared/admin-auth.ts';
import { assertAdminEmailFree, createCompanyAdmin, validateCompanyAdmin } from '../_shared/company-admin.ts';
import { errorMessage, errorStatus, HttpError, jsonResponse, preflight } from '../_shared/http.ts';

const text = (value: unknown) => String(value ?? '').trim();

Deno.serve(async (request: Request) => {
  const early = preflight(request);
  if (early) return early;

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
    // Known before anything exists, so a taken e-mail never creates a company to undo.
    await assertAdminEmailFree(serviceClient, adminEmail);

    // The database copies the default terms into the new company.
    const { data: company, error: companyError } = await serviceClient.from('companies')
      .insert({ name, contact_phone: contactPhone, contact_label: contactLabel })
      .select('id, name').single();
    if (companyError) {
      if (companyError.code === '23505') throw new HttpError(409, 'توجد شركة بهذا الاسم بالفعل.');
      throw companyError;
    }

    try {
      // Rows that belong to the company alone, and go with it if it is removed.
      const [{ error: walletError }, { error: methodError }] = await Promise.all([
        serviceClient.from('wallet_card_settings')
          .upsert({ company_id: company.id }, { onConflict: 'company_id', ignoreDuplicates: true }),
        method
          ? serviceClient.from('company_payment_methods').insert({
            company_id: company.id,
            method_type: text(method.methodType),
            display_name: text(method.displayName),
            account_holder: text(method.accountHolder) || null,
            instapay_address: text(method.instapayAddress) || null,
            wallet_phone: text(method.walletPhone) || null,
            bank_name: text(method.bankName) || null,
            bank_account_number: text(method.bankAccountNumber) || null,
            iban: text(method.iban) || null,
          })
          : Promise.resolve({ error: null }),
      ]);
      if (walletError) throw walletError;
      if (methodError) throw new HttpError(400, 'بيانات وسيلة الدفع غير مكتملة أو غير صحيحة.');

      // The admin comes last: an invitation e-mail cannot be taken back, and
      // this step removes its own account again if the admins row fails.
      const created = await createCompanyAdmin(serviceClient, {
        email: adminEmail, fullName: adminName, companyId: company.id, password: adminPassword,
        createdBy: user.id, redirectTo: request.headers.get('origin') ?? undefined,
      });
      return jsonResponse({ id: company.id, name: company.name, adminId: created.id, invited: created.invited });
    } catch (stepError) {
      // No admin exists at this point, so the company and its own rows can go.
      const { error: undoError } = await serviceClient.from('companies').delete().eq('id', company.id);
      if (undoError) console.error('admin-create-company: an unfinished company could not be removed', company.id, undoError.message);
      throw stepError;
    }
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إنشاء الشركة.') }, errorStatus(error));
  }
});
