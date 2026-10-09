// A company (or the platform admin) registers a student on one of its lines.
// Kept apart from the HTTP entry so it runs under `deno test`.
import { createLogin, finishOrRemoveLogin } from './accounts.ts';
import { type AdminContext, assertCompanyAccess } from './admin-auth.ts';
import { jsonResponse } from './http.ts';
import { isEgyptianMobile, loginEmail, normalizeEgyptianPhone } from './phone.ts';

const PRICE_COLUMN = { termly: 'price_termly', yearly: 'price_yearly', daily: 'price_daily' } as const;
type SubscriptionType = keyof typeof PRICE_COLUMN;

const text = (value: unknown) => String(value ?? '').trim();

// Trips are chosen by id (dashboard) or matched by stop time (older clients).
// The subscription trigger checks the trip stops at the station and serves the
// student's university, and sets the stop times as the subscription times.
function tripId(value: unknown): string | null {
  const id = text(value);
  return /^[0-9a-f-]{36}$/i.test(id) ? id : null;
}

/**
 * `context` is an admin already checked by requireAdmin. Answers
 * { id } for a new student, { invited: true } when the phone already has an
 * account (that person decides in the app), or { error } with a status.
 */
export async function createStudent(context: AdminContext, body: Record<string, unknown>): Promise<Response> {
  const service = context.serviceClient;
  const fullName = text(body.fullName);
  const phone = normalizeEgyptianPhone(body.phone);
  const university = text(body.university);
  const college = text(body.college ?? 'غير محدد') || 'غير محدد';
  const password = String(body.password ?? '');
  const lineId = String(body.lineId ?? '');
  const stationId = String(body.stationId ?? '');
  const subscriptionType = String(body.subscriptionType ?? 'termly') as SubscriptionType;
  const requestedDeparture = text(body.departureTime);
  const requestedReturn = text(body.returnTime);
  // Optional period (see get_purchasable_periods); the DB picks the current one if omitted.
  const periodCode = text(body.periodCode) || null;
  const academicYear = Number.isInteger(Number(body.academicYear)) && body.academicYear !== null && body.academicYear !== undefined
    ? Number(body.academicYear) : null;
  if (
    fullName.split(/\s+/).length < 3 || !isEgyptianMobile(phone) || !university || password.length < 8
    || !lineId || !stationId || !Object.hasOwn(PRICE_COLUMN, subscriptionType)
  ) {
    return jsonResponse({ error: 'أدخل الاسم ثلاثياً على الأقل ورقم الهاتف والجامعة والخط والمحطة وكلمة مرور من 8 أحرف على الأقل.' }, 400);
  }
  const daily = subscriptionType === 'daily';
  // A period has its own price on the line; the line columns are the fallback
  // (daily, or a period left for the database to pick).
  const option = daily ? null : subscriptionType === 'yearly' || periodCode === 'annual' ? 'both' : periodCode;

  // Four questions that do not depend on each other, asked at once. Nothing
  // is answered or written from them until the company check below has passed.
  const [lineRead, stationRead, existingRead, priceRead] = await Promise.all([
    service.from('lines').select('id,company_id,price_termly,price_yearly,price_daily')
      .eq('id', lineId).eq('is_active', true).maybeSingle(),
    service.from('stations').select('id')
      .eq('id', stationId).eq('line_id', lineId).eq('is_active', true).maybeSingle(),
    // The phone may already belong to someone, in this company or another.
    service.from('students').select('id, memberships:company_students(company_id,status)')
      .eq('phone', phone).maybeSingle(),
    option
      ? service.from('line_period_prices').select('price').eq('line_id', lineId).eq('option', option).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);

  const line = lineRead.data;
  if (lineRead.error) throw lineRead.error;
  if (!line) return jsonResponse({ error: 'الخط غير موجود أو غير نشط.' }, 404);
  // The line decides the company; the student becomes its member by subscribing.
  assertCompanyAccess(context, line.company_id);
  const station = stationRead.data;
  if (stationRead.error) throw stationRead.error;
  if (!station) return jsonResponse({ error: 'المحطة غير تابعة للخط أو غير نشطة.' }, 400);

  const departureTripId = tripId(body.departureTripId);
  const returnTripId = tripId(body.returnTripId);
  if (!departureTripId && !requestedDeparture) {
    return jsonResponse({ error: 'اختر رحلة الذهاب للطالب.' }, 400);
  }
  const period = { period_code: daily ? null : periodCode, academic_year: daily ? null : academicYear };

  // An existing student is never attached to the company directly: they get an
  // invitation and decide in the app.
  const existing = existingRead.data;
  if (existingRead.error) throw existingRead.error;
  if (existing) {
    const memberships = (existing.memberships ?? []) as { company_id: string; status: string }[];
    if (memberships.some((m) => m.company_id === line.company_id && m.status === 'active')) {
      return jsonResponse({ error: 'هذا الطالب مسجل في شركتك بالفعل. أضف له اشتراكاً من قائمة الطلاب.' }, 409);
    }
    const { error: inviteError } = await service.from('company_invites').insert({
      company_id: line.company_id, student_id: existing.id, phone,
      line_id: line.id, station_id: station.id, subscription_type: subscriptionType, ...period,
      departure_trip_id: departureTripId, return_trip_id: returnTripId,
      invited_by: context.user.id,
    });
    if (inviteError) {
      if (inviteError.code === '23505') {
        return jsonResponse({ error: 'توجد دعوة معلقة لهذا الرقم بالفعل. تظهر للطالب في التطبيق.' }, 409);
      }
      throw inviteError;
    }
    return jsonResponse({ invited: true });
  }

  if (priceRead.error) throw priceRead.error;
  const optionPrice = Number((priceRead.data as { price?: unknown } | null)?.price);
  const price = optionPrice > 0 ? optionPrice : Number(line[PRICE_COLUMN[subscriptionType]]);

  const studentId = await createLogin(service, {
    email: loginEmail(phone), password, metadata: { role: 'student', phone, full_name: fullName },
    takenMessage: 'رقم الهاتف مسجل بالفعل لحساب آخر.',
    failedMessage: 'تعذر إنشاء حساب الطالب.',
  });
  // The account exists now; the profile and the subscription must follow, or the account goes.
  await finishOrRemoveLogin(service, studentId, 'admin-create-student', async () => {
    const { error: profileError } = await service.from('students').insert({
      id: studentId, phone, full_name: fullName, university, college,
    });
    if (profileError) throw profileError;
    const { error: subscriptionError } = await service.from('subscriptions').insert({
      student_id: studentId,
      line_id: line.id,
      station_id: station.id,
      type: subscriptionType,
      ...period,
      departure_trip_id: departureTripId,
      return_trip_id: returnTripId,
      departure_time: departureTripId ? null : requestedDeparture || null,
      return_time: returnTripId ? null : requestedReturn || null,
      status: 'pending_payment',
      price,
    });
    if (subscriptionError) throw subscriptionError;
  });
  return jsonResponse({ id: studentId });
}
