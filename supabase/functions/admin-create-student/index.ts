import { corsHeaders, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return jsonResponse({ error: 'طريقة الطلب غير مدعومة.' }, 405);

  try {
    const { admin, serviceClient } = await requireAdmin(request);
    const body = await request.json();
    const fullName = String(body.fullName ?? '').trim();
    const phone = String(body.phone ?? '').replace(/\D/g, '');
    const university = String(body.university ?? '').trim();
    const college = String(body.college ?? 'غير محدد').trim() || 'غير محدد';
    const password = String(body.password ?? '');
    const lineId = String(body.lineId ?? '');
    const stationId = String(body.stationId ?? '');
    const subscriptionType = String(body.subscriptionType ?? 'termly');
    if (fullName.split(/\s+/).length < 4 || phone.length < 10 || !university || password.length < 6 || !lineId || !stationId || !['termly', 'yearly', 'daily'].includes(subscriptionType)) {
      return jsonResponse({ error: 'أدخل الاسم الرباعي ورقم الهاتف والجامعة والخط والمحطة وكلمة مرور صحيحة.' }, 400);
    }

    const { data: line, error: lineError } = await serviceClient.from('lines')
      .select('id,company_id,price_termly,price_yearly,price_daily,is_active')
      .eq('id', lineId).eq('is_active', true).maybeSingle();
    if (lineError) throw lineError;
    if (!line || (admin.role === 'company_admin' && line.company_id !== admin.company_id)) {
      return jsonResponse({ error: 'الخط غير تابع للشركة المخصصة لحسابك أو غير نشط.' }, 403);
    }
    const { data: station, error: stationError } = await serviceClient.from('stations')
      .select('id').eq('id', stationId).eq('line_id', lineId).eq('is_active', true).maybeSingle();
    if (stationError) throw stationError;
    if (!station) return jsonResponse({ error: 'المحطة غير تابعة للخط أو غير نشطة.' }, 400);

    const priceColumn = { termly: 'price_termly', yearly: 'price_yearly', daily: 'price_daily' }[subscriptionType] as 'price_termly' | 'price_yearly' | 'price_daily';

    const email = `${phone}@busak.app`;
    const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { role: 'student', phone, full_name: fullName },
    });
    if (createError || !created.user) throw createError ?? new Error('تعذر إنشاء حساب الطالب.');

    const { error: profileError } = await serviceClient.from('students').insert({
      id: created.user.id,
      phone,
      full_name: fullName,
      university,
      college,
    });
    if (profileError) {
      await serviceClient.auth.admin.deleteUser(created.user.id);
      throw profileError;
    }
    const { error: subscriptionError } = await serviceClient.from('subscriptions').insert({
      student_id: created.user.id,
      line_id: line.id,
      station_id: station.id,
      type: subscriptionType,
      status: 'pending_payment',
      price: Number(line[priceColumn]),
    });
    if (subscriptionError) {
      await serviceClient.auth.admin.deleteUser(created.user.id);
      throw subscriptionError;
    }
    return jsonResponse({ id: created.user.id });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : 'تعذر إضافة الطالب.' }, 400);
  }
});
