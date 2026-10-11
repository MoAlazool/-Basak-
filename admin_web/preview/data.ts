/**
 * Sample rows for the preview. Names, numbers and phones follow the boards
 * (docs/canvas/Adm*.dc.html); all of it is invented.
 */
type Row = Record<string, any>;

export const COMPANY_ID = '11111111-1111-4111-8111-111111111111';
export const COMPANY2_ID = '22222222-2222-4222-8222-222222222222';
export const ADMINS = {
  company: { id: 'a0000000-0000-4000-8000-000000000001', email: 'ahmed@elnawras.example', full_name: 'أحمد سعيد النورس', role: 'company_admin', company_id: COMPANY_ID },
  platform: { id: 'a0000000-0000-4000-8000-000000000002', email: 'admin@basak.example', full_name: 'محمد عادل', role: 'super_admin', company_id: null },
} as const;

const uid = (prefix: string, n: number) => {
  const h = (prefix + String(n).padStart(4, '0')).padEnd(32, '0').slice(0, 32).replace(/[^0-9a-f]/g, 'a');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};
const daysAgo = (d: number, h = 0) => new Date(Date.now() - d * 86_400_000 - h * 3_600_000).toISOString();
const today = new Date();
const iso = (d: Date) => d.toISOString().slice(0, 10);
export const TODAY = iso(today);
export const TOMORROW = iso(new Date(today.getTime() + 86_400_000));

export const UNIVERSITIES: Row[] = [
  ['جامعة دمياط', 'دمياط'], ['جامعة المنصورة', 'المنصورة'], ['جامعة الدلتا التكنولوجية', 'المنصورة'], ['الجامعة المصرية اليابانية', 'برج العرب'],
  ['جامعة المنصورة الأهلية', 'المنصورة الجديدة'], ['المعهد العالي للهندسة', 'دمياط الجديدة'], ['جامعة حورس', 'دمياط الجديدة'],
].map(([name, city], i) => ({ id: uid('dd0', i + 1), name, city, is_active: i !== 6, created_at: daysAgo(200 - i) }));

const LINE_DEFS: [string, string[], number, number, number][] = [
  // name, stations, subscribers, capacity, supervisorIndex(-1 none)
  ['دمياط الجديدة', ['المنطقة الرابعة', 'الحي الثالث', 'المركز التجاري', 'بوابة الجامعة'], 168, 50, 0],
  ['الزرقا', ['موقف الزرقا', 'كوبري السرو', 'الشعراء', 'بوابة الجامعة'], 124, 50, 1],
  ['شربين', ['ميدان شربين', 'الكوبري العلوي', 'بلقاس', 'بوابة الجامعة'], 112, 45, -1],
  ['فارسكور', ['موقف فارسكور', 'الروضة', 'السيالة', 'بوابة الجامعة'], 96, 45, 2],
  ['كفر سعد', ['ميدان كفر سعد', 'الصيانة', 'بوابة الجامعة'], 74, 30, 3],
  ['السرو', ['مدخل السرو', 'الوحدة الصحية', 'بوابة الجامعة'], 61, 30, 1],
  ['ميت أبو غالب', ['المعدية', 'الخياطة', 'بوابة الجامعة'], 45, 30, 0],
  ['كفر البطيخ', ['الميدان', 'المصنع', 'بوابة الجامعة'], 38, 30, 3],
];
export const SUPERVISORS: Row[] = [
  ['إبراهيم الدسوقي عبد الحميد', '01012345678'], ['محمود السيد عبد الغني', '01123456789'], ['هاني عبد المقصود', '01234567890'], ['سامح فتحي البنا', '01534567891'], ['كريم مصطفى الشافعي', '01098765432'],
].map(([full_name, phone], i) => ({ id: uid('5e0', i + 1), full_name, phone, company_id: COMPANY_ID, is_active: i !== 4, profile_image_url: null, created_at: daysAgo(120 - i * 9) }));

const times = ['06:30', '06:45', '07:00', '07:15', '07:30'];
export const LINES: Row[] = LINE_DEFS.map(([name, stations, , cap], li) => {
  const lineId = uid('11e', li + 1);
  const st = stations.map((s, si) => ({ id: uid(`5a${li}`, si + 1), name: s, order_index: si, is_active: true }));
  const dep = [0, 1].map((t) => ({
    id: uid(`d${li}0`, t + 1), direction: 'departure', label: t ? 'الثانية' : 'الأولى', start_time: `${times[(li + t * 2) % 5]}:00`, arrival_time: null,
    university_id: UNIVERSITIES[0].id, is_active: true,
    line_trip_stops: st.map((s, si) => ({ station_id: s.id, stop_time: `0${6 + t}:${String(30 + si * 8 + (li % 3) * 5).padStart(2, '0').slice(-2)}:00`.replace(/:(\d)$/, ':0$1') })),
  }));
  const ret = [{ id: uid(`e${li}0`, 1), direction: 'return', label: 'العودة', start_time: '14:00:00', arrival_time: null, university_id: UNIVERSITIES[0].id, is_active: true, line_trip_stops: [] }];
  return {
    id: lineId, name, company_id: COMPANY_ID, origin_name: stations[0], destination_university_id: UNIVERSITIES[0].id,
    price_termly: 3500, price_yearly: 6500, price_daily: 50, is_active: li !== 7, bus_capacity: cap, created_at: daysAgo(300 - li),
    stations: st, line_trips: [...dep, ...ret], line_universities: [{ university_id: UNIVERSITIES[0].id }],
    line_period_prices: [{ option: 'first', price: 3500, is_enabled: true }, { option: 'second', price: 3500, is_enabled: true }, { option: 'both', price: 6500, is_enabled: true }, { option: 'summer', price: 0, is_enabled: false }],
  };
});
export const LINE_SUBSCRIBERS = Object.fromEntries(LINE_DEFS.map(([, , n], i) => [LINES[i].id, n]));
export const SUPERVISOR_LINES: Row[] = LINE_DEFS.flatMap(([, , , , s], i) => (s >= 0 ? [{ supervisor_id: SUPERVISORS[s].id, line_id: LINES[i].id, company_id: COMPANY_ID }] : []));

const FIRST = ['منة الله', 'عبد الرحمن', 'يوسف', 'ملك', 'عمر', 'سلمى', 'محمد', 'نور', 'أحمد', 'رنا', 'مصطفى', 'هبة', 'كريم', 'آية', 'زياد', 'مريم', 'خالد', 'سارة', 'علي', 'فاطمة'];
const MIDDLE = ['إبراهيم', 'محمد', 'أحمد', 'حسام الدين', 'خالد', 'السيد', 'عبد الفتاح', 'مصطفى', 'حسن', 'عادل'];
const LAST = ['عبد الرازق', 'الشربيني', 'عبد الفتاح', 'مصطفى', 'البنا', 'النجار', 'الدسوقي', 'عوض', 'سليمان', 'رمضان'];
const COLLEGES = ['الهندسة', 'الطب', 'التجارة', 'الحاسبات والمعلومات', 'الصيدلة', 'العلوم', 'التربية'];
const SPECS = ['مدني', '', 'محاسبة', 'علوم الحاسب', '', 'كيمياء', 'لغة إنجليزية'];
const STATUSES = ['active', 'active', 'active', 'pending_review', 'pending_payment', 'active', 'rejected', 'active', 'expired', 'active'];

export const STUDENTS: Row[] = Array.from({ length: 64 }, (_, i) => {
  const line = LINES[i % 7];
  const status = STATUSES[i % STATUSES.length];
  const phone = `01${[0, 1, 2, 5][i % 4]}${String(23456789 + i * 7919).slice(0, 8)}`;
  return {
    id: uid('57d', i + 1), full_name: `${FIRST[i % 20]} ${MIDDLE[(i * 3) % 10]} ${LAST[(i * 7) % 10]}`, phone,
    university: UNIVERSITIES[i % 3].name, college: COLLEGES[i % 7], specialisation: SPECS[i % 7] || null, profile_image_url: null,
    created_at: daysAgo(i * 2 + 1, i % 5),
    subscriptions: [{
      id: uid('5b0', i + 1), status, type: i % 6 === 0 ? 'yearly' : i % 9 === 0 ? 'daily' : 'termly', price: i % 6 === 0 ? 6500 : 3500, created_at: daysAgo(i * 2 + 1),
      start_date: '2026-09-20', end_date: '2027-01-31', period_label: i % 6 === 0 ? 'الفصلان معاً 2026/2027' : 'الفصل الأول 2026/2027', period_phase: status === 'expired' ? 'expired' : 'current',
      departure_time: line.line_trips[0].start_time, return_time: '14:00:00', line_name: line.name, trip_label: 'الأولى', trip_university: UNIVERSITIES[0].name,
      line_id: line.id, station_name: line.stations[i % line.stations.length].name,
    }],
  };
});

export const RECEIPTS: Row[] = STUDENTS.filter((s) => s.subscriptions[0].status === 'pending_review').concat(STUDENTS.slice(40, 42)).map((s, i) => {
  const sub = s.subscriptions[0];
  return {
    id: uid('4ec', i + 1), image_url: `receipts/${s.id}/r${i}.jpg`, attempt_number: i === 0 ? 5 : (i % 3) + 1, created_at: daysAgo(0, 3 + i * 4), amount: sub.price,
    subscription_id: sub.id, student_id: s.id, student_name: s.full_name, student_phone: s.phone, university: s.university, college: s.college, specialisation: s.specialisation,
    company_id: COMPANY_ID, company_name: 'النورس للنقل', line_name: sub.line_name, station_name: sub.station_name, departure_time: sub.departure_time, return_time: sub.return_time,
    subscription_type: sub.type, period_label: sub.period_label, period_start: sub.start_date, period_end: sub.end_date, period_phase: 'current', price: sub.price,
  };
});

export const RESET_REQUESTS: Row[] = [3, 17].map((n, i) => ({
  id: uid('7e5', i + 1), student_id: STUDENTS[n].id, student_name: STUDENTS[n].full_name, student_phone: STUDENTS[n].phone, company_id: COMPANY_ID, company_name: 'النورس للنقل',
  status: 'pending', requested_at: daysAgo(0, 1 + i * 5), code_expires_at: null, code_issued_at: null, failed_attempts: 0, closed_at: null,
}));

/** Tables the client reads directly. */
export const tables: Record<string, Row[]> = {
  governorates: [
    ['alexandria', 'الإسكندرية'], ['ismailia', 'الإسماعيلية'], ['aswan', 'أسوان'], ['asyut', 'أسيوط'], ['luxor', 'الأقصر'],
    ['red_sea', 'البحر الأحمر'], ['beheira', 'البحيرة'], ['beni_suef', 'بني سويف'], ['port_said', 'بورسعيد'],
    ['south_sinai', 'جنوب سيناء'], ['giza', 'الجيزة'], ['dakahlia', 'الدقهلية'], ['damietta', 'دمياط'], ['sohag', 'سوهاج'],
    ['suez', 'السويس'], ['sharqia', 'الشرقية'], ['north_sinai', 'شمال سيناء'], ['gharbia', 'الغربية'], ['faiyum', 'الفيوم'],
    ['cairo', 'القاهرة'], ['qalyubia', 'القليوبية'], ['qena', 'قنا'], ['kafr_el_sheikh', 'كفر الشيخ'], ['matrouh', 'مطروح'],
    ['monufia', 'المنوفية'], ['minya', 'المنيا'], ['new_valley', 'الوادي الجديد'],
  ].map(([code, name], i) => ({ code, name, sort_order: i + 1 })),
  company_governorates: [{ company_id: COMPANY_ID, governorate_code: 'dakahlia' }, { company_id: COMPANY_ID, governorate_code: 'damietta' }],
  companies: [
    { id: COMPANY_ID, name: 'النورس للنقل', status: 'active', is_active: true, created_at: daysAgo(320), contact_phone: '01001234567', contact_label: 'للاستفسار', address: 'دمياط الجديدة · المنطقة المركزية', logo_path: null, emblem_path: null,
      annual_subscription_enabled: true, daily_subscription_enabled: true, advance_subscription_enabled: true, vote_opens_at: '16:00:00', vote_closes_at: '06:00:00', vote_reminder_minutes: 60, vote_reminder_off_weekdays: [5], vote_reminder_off_dates: [] },
    { id: COMPANY2_ID, name: 'الدلتا للنقل الجامعي', status: 'active', is_active: true, created_at: daysAgo(90), contact_phone: '01112223334', contact_label: null, address: 'المنصورة', logo_path: null, emblem_path: null,
      annual_subscription_enabled: true, daily_subscription_enabled: false, advance_subscription_enabled: false, vote_opens_at: null, vote_closes_at: null, vote_reminder_minutes: null, vote_reminder_off_weekdays: null, vote_reminder_off_dates: null },
  ],
  admins: [
    { ...ADMINS.company, created_at: daysAgo(320), companies: { id: COMPANY_ID, name: 'النورس للنقل', status: 'active' } },
    { id: uid('ad0', 3), email: 'sara@elnawras.example', full_name: 'سارة محمود النورس', role: 'company_admin', company_id: COMPANY_ID, created_at: daysAgo(100), companies: { id: COMPANY_ID, name: 'النورس للنقل', status: 'active' } },
    { id: uid('ad0', 4), email: 'owner@delta.example', full_name: 'حسن عبد الله', role: 'company_admin', company_id: COMPANY2_ID, created_at: daysAgo(90), companies: { id: COMPANY2_ID, name: 'الدلتا للنقل الجامعي', status: 'active' } },
    { ...ADMINS.platform, created_at: daysAgo(400), companies: null },
  ],
  universities: UNIVERSITIES,
  colleges: UNIVERSITIES.slice(0, 3).flatMap((u, ui) => COLLEGES.map((name, ci) => ({ id: uid(`c${ui}0`, ci + 1), university_id: u.id, name, is_active: true, created_at: daysAgo(150) }))),
  lines: LINES,
  supervisors: SUPERVISORS,
  supervisor_lines: SUPERVISOR_LINES,
  company_payment_methods: [
    { id: uid('9a0', 1), company_id: COMPANY_ID, type: 'instapay', display_name: 'إنستاباي', account_holder: 'شركة النورس للنقل', instapay_address: 'elnawras@instapay', wallet_number: null, bank_name: null, account_number: null, iban: null, instructions: 'اكتب اسمك ورقم هاتفك في ملاحظة التحويل.', is_active: true, sort_order: 0, created_at: daysAgo(300) },
    { id: uid('9a0', 2), company_id: COMPANY_ID, type: 'wallet', display_name: 'فودافون كاش', account_holder: 'أحمد سعيد النورس', instapay_address: null, wallet_number: '01001234567', bank_name: null, account_number: null, iban: null, instructions: null, is_active: true, sort_order: 1, created_at: daysAgo(290) },
    { id: uid('9a0', 3), company_id: COMPANY_ID, type: 'bank', display_name: 'تحويل بنكي', account_holder: 'شركة النورس للنقل', instapay_address: null, wallet_number: null, bank_name: 'البنك الأهلي المصري', account_number: '1234567890123', iban: 'EG380019000500000000263180002', instructions: null, is_active: false, sort_order: 2, created_at: daysAgo(200) },
  ],
  student_correction_requests: [0, 5, 9].map((n, i) => ({ id: uid('c0e', i + 1), student_id: STUDENTS[n].id, company_id: COMPANY_ID, field: i === 1 ? 'university' : 'full_name', old_value: i === 1 ? STUDENTS[n].university : STUDENTS[n].full_name, new_value: i === 1 ? 'جامعة المنصورة' : `${STUDENTS[n].full_name} محمد`, note: i === 0 ? 'الاسم في البطاقة رباعي' : null, status: 'pending', requested_by: ADMINS.company.id, created_at: daysAgo(i, 2), decided_by: null, decided_at: null, decision_note: null, companies: { name: 'النورس للنقل' }, students: { full_name: STUDENTS[n].full_name, phone: STUDENTS[n].phone } })),
  company_invites: [7, 12].map((n, i) => ({ id: uid('1a0', i + 1), company_id: COMPANY_ID, student_id: STUDENTS[n].id, phone: STUDENTS[n].phone, status: 'pending', created_at: daysAgo(i + 1), expires_at: daysAgo(-6), students: { full_name: STUDENTS[n].full_name } })),
  app_versions: [
    { platform: 'android', min_version: '1.0.9', latest_version: '1.0.13', whats_new: ['صورة الطالب تظهر للمشرف عند المسح', 'تحسينات في السرعة'], store_url: 'https://play.google.com/store/apps/details?id=app.basak', updated_at: daysAgo(3), updated_by: ADMINS.platform.id },
    { platform: 'ios', min_version: '1.0.9', latest_version: '1.0.13', whats_new: ['صورة الطالب تظهر للمشرف عند المسح'], store_url: 'https://apps.apple.com/app/id000000', updated_at: daysAgo(3), updated_by: ADMINS.platform.id },
  ],
  app_settings: [{ id: true, annual_subscription_enabled: true, daily_subscription_enabled: true, vote_opens_at: '16:00:00', vote_closes_at: '06:00:00', vote_reminder_minutes: 60, vote_reminder_off_weekdays: [5], vote_reminder_off_dates: [], support_whatsapp: '01001112223' }],
  password_reset_requests: RESET_REQUESTS,
  blocked_phones: [],
  notifications: [],
};

/**
 * Two lines of the second company for the line page's timetable: one with a
 * single departure trip, one with many (it scrolls sideways). Kept out of
 * LINES so the first company's pages and their per-line tables are unchanged.
 * Open as the platform admin: /c/<COMPANY2_ID>/lines/<id> with ?as=platform.
 */
const EXTRA_LINE_DEFS: [string, string[], string[], number, number][] = [
  // name, stations, departure start times, subscribers, capacity
  ['طلخا', ['موقف طلخا', 'كوبري طلخا', 'المشاية', 'بوابة الجامعة'], ['07:00'], 22, 30],
  ['ميت غمر', ['موقف ميت غمر', 'دقادوس', 'أجا', 'سندوب', 'بوابة الجامعة'], ['06:00', '06:30', '07:00', '07:30', '08:00', '09:00', '10:00'], 236, 50],
];
export const EXTRA_LINES: Row[] = EXTRA_LINE_DEFS.map(([name, stations, starts, , cap], li) => {
  const st = stations.map((s, si) => ({ id: uid(`5c${li}`, si + 1), name: s, order_index: si, is_active: true }));
  const hm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}:00`;
  const dep = starts.map((start, t) => {
    const m0 = Number(start.slice(0, 2)) * 60 + Number(start.slice(3));
    return {
      id: uid(`d9${li}`, t + 1), direction: 'departure', label: t === 0 && starts.length > 1 ? 'المبكرة' : '', start_time: `${start}:00`, arrival_time: hm(m0 + 10 * st.length + 15),
      university_id: t === 5 ? UNIVERSITIES[2].id : null, is_active: true,
      line_trip_stops: st.filter((_, si) => !(li === 1 && t === 2 && si === 2)).map((s) => ({ station_id: s.id, stop_time: hm(m0 + 10 * st.indexOf(s)) })),
    };
  });
  const ret = ['14:00', '16:30', '18:00'].slice(0, li ? 3 : 1).map((s, t) => ({ id: uid(`e9${li}`, t + 1), direction: 'return', label: '', start_time: `${s}:00`, arrival_time: null, university_id: null, is_active: true, line_trip_stops: [] }));
  return {
    id: uid('12e', li + 1), name, company_id: COMPANY2_ID, origin_name: stations[0], destination_university_id: UNIVERSITIES[1].id,
    price_termly: 3000, price_yearly: 5600, price_daily: 45, is_active: true, bus_capacity: cap, created_at: daysAgo(80 - li),
    stations: st, line_trips: [...dep, ...ret], line_universities: [{ university_id: UNIVERSITIES[1].id }, ...(li ? [{ university_id: UNIVERSITIES[2].id }] : [])],
    line_period_prices: [{ option: 'first', price: 3000, is_enabled: true }, { option: 'second', price: 3000, is_enabled: true }, { option: 'both', price: 5600, is_enabled: true }, { option: 'summer', price: 0, is_enabled: false }],
  };
});
// A new array: tables.lines is LINES itself, which the first company's pages index by position.
tables.lines = [...tables.lines, ...EXTRA_LINES];
EXTRA_LINE_DEFS.forEach(([, , , n], i) => { (LINE_SUBSCRIBERS as Record<string, number>)[EXTRA_LINES[i].id] = n; });
