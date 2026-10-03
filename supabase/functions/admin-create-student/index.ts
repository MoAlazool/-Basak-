import { corsHeaders, errorMessage, jsonResponse, requireAdmin } from '../_shared/admin-auth.ts';

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
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
    const requestedDeparture = String(body.departureTime ?? '').trim();
    const requestedReturn = String(body.returnTime ?? '').trim();
    // Optional period (see get_purchasable_periods); the DB picks the current one if omitted.
    const periodCode = String(body.periodCode ?? '').trim() || null;
    const academicYear = Number.isInteger(Number(body.academicYear)) && body.academicYear !== null && body.academicYear !== undefined
      ? Number(body.academicYear) : null;
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

    // Trips are chosen by id (dashboard) or matched by stop time (older clients).
    // The subscription trigger checks the trip stops at the station and serves
    // the student's university, and sets the stop times as the subscription times.
    const tripId = (value: unknown) => {
      const id = String(value ?? '').trim();
      return /^[0-9a-f-]{36}$/i.test(id) ? id : null;
    };
    const departureTripId = tripId(body.departureTripId);
    const returnTripId = tripId(body.returnTripId);
    if (!departureTripId && !requestedDeparture) {
      return jsonResponse({ error: 'اختر رحلة الذهاب للطالب.' }, 400);
    }

    const priceColumn = { termly: 'price_termly', yearly: 'price_yearly', daily: 'price_daily' }[subscriptionType] as 'price_termly' | 'price_yearly' | 'price_daily';

    const email = `${phone}@busak.app`;
    const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { role: 'student', phone, full_name: fullName },
    });
    if (createError || !created.user) {
      if (createError && /already|registered|exists/i.test(createError.message)) {
        return jsonResponse({ error: 'رقم الهاتف مسجل بالفعل لحساب آخر.' }, 409);
      }
      throw createError ?? new Error('تعذر إنشاء حساب الطالب.');
    }

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
      period_code: subscriptionType === 'daily' ? null : periodCode,
      academic_year: subscriptionType === 'daily' ? null : academicYear,
      departure_trip_id: departureTripId,
      return_trip_id: returnTripId,
      departure_time: departureTripId ? null : requestedDeparture || null,
      return_time: returnTripId ? null : requestedReturn || null,
      status: 'pending_payment',
      price: Number(line[priceColumn]),
    });
    if (subscriptionError) {
      await serviceClient.auth.admin.deleteUser(created.user.id);
      throw subscriptionError;
    }
    return jsonResponse({ id: created.user.id });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error, 'تعذر إضافة الطالب.') }, 400);
  }
});
