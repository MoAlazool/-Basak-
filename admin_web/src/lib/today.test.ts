import { describe, expect, it } from 'vitest';
import {
  cannotSubscribeText, companyAttention, forgotTitle, hiddenText, isFirstRun, nOf, oldestText, onSaleText, overBy, ridersTitle, setupSteps,
  SUBSCRIBER, tripText, type CompanyToday, type TodayLine,
} from './today';
import { companiesHint, createdText, isPilingUp, platformAttention, type PlatformCompanyRow, type PlatformToday } from './platformToday';
import { lineCounts } from './todayLegacy';

const NOW = new Date('2026-10-10T09:00:00Z');
const hoursAgo = (h: number) => new Date(NOW.getTime() - h * 3_600_000).toISOString();

const line = (o: Partial<TodayLine> = {}): TodayLine => ({
  id: 'l1', name: 'شربين', is_active: true, bus_capacity: 45, subscribers: 100, going: 80, returning: 70,
  top_trip: { id: 't1', time: '06:45', riders: 31 }, over: [], supervisors: [{ id: 's1', name: 'هاني' }],
  visible: true, hidden: null, unserved_university: null, ...o,
});
const company = (o: Partial<CompanyToday> = {}): CompanyToday => ({
  company: { id: 'c1', name: 'النورس', status: 'active', created_at: hoursAgo(1000) },
  today: '2026-10-10', ride_date: '2026-10-11', vote_opens_at: '16:00', vote_closes_at: '06:00', vote_open: true,
  members: 10, subscribers: 10, confirmed: 5, going: 5, returning: 4,
  receipts: { waiting: 0, oldest_at: null, last_attempt: 0 }, password_requests: 0, lines: [line()],
  setup: { lines: 1, first_line: null, payment_methods: 1, supervisors: 1, on_sale: [], vote_custom: false, wallet_custom: false, receipt_info: false },
  ...o,
});

describe('lineCounts', () => {
  it('adds stations up per trip and finds the busiest one and those over the bus', () => {
    const c = lineCounts([
      { schedule_id: 'a', departure_time: '07:15:00', riding_count: 20, returning_count: 18 },
      { schedule_id: 'a', departure_time: '07:05:00', riding_count: 27, returning_count: 25 },
      { schedule_id: 'b', departure_time: '08:00:00', riding_count: 10, returning_count: 9 },
      { schedule_id: 'c', departure_time: '09:00:00', riding_count: 0, returning_count: 0 },
    ], 45);
    expect(c.going).toBe(57);
    expect(c.returning).toBe(52);
    expect(c.top_trip).toMatchObject({ id: 'a', time: '07:05', riders: 47 });
    expect(c.over.map((t) => t.id)).toEqual(['a']);
  });
  it('has no busiest trip when nobody rides and no over list without a capacity', () => {
    expect(lineCounts([], 45).top_trip).toBeNull();
    expect(lineCounts([{ schedule_id: 'a', departure_time: '07:00', riding_count: 90, returning_count: 0 }], null).over).toEqual([]);
  });
});

describe('words', () => {
  it('oldest receipt', () => {
    expect(oldestText(hoursAgo(3), NOW)).toBe('أقدمها منذ 3 ساعات');
    expect(oldestText(hoursAgo(30), NOW)).toBe('أقدمها من أمس');
    expect(oldestText(null, NOW)).toBe('');
  });
  it('why a line is hidden', () => {
    expect(hiddenText({ hidden: 'unserved_university', unserved_university: 'جامعة دمياط' })).toBe('تنقصه رحلة ذهاب إلى جامعة دمياط');
    expect(hiddenText({ hidden: 'company_not_selling', unserved_university: null })).toBe('لا يُعرض أي فصل للبيع الآن');
    expect(hiddenText({ hidden: null, unserved_university: null })).toBe('');
  });
  it('counts with digits', () => {
    expect(nOf(718, SUBSCRIBER)).toBe('718 مشتركاً');
    expect(nOf(1, SUBSCRIBER)).toBe('1 مشترك');
    expect(nOf(2, SUBSCRIBER)).toBe('2 مشتركين');
    expect(nOf(0, SUBSCRIBER)).toBe('0 مشتركين');
  });
  it('trips, terms, titles', () => {
    expect(tripText({ id: 't', time: '07:30', riders: 44 })).toBe('7:30 ص · 44 راكباً');
    expect(onSaleText(['الفصل الدراسي الأول', 'الفصل الدراسي الثاني'])).toBe('الفصل الأول والثاني معروضان للبيع الآن');
    expect(onSaleText(['الفصل الدراسي الأول'])).toBe('الفصل الأول معروض للبيع الآن');
    expect(onSaleText([])).toBe('لا يُعرض أي فصل للبيع الآن');
    expect(ridersTitle('2026-10-10', '2026-10-11')).toBe('ركاب الغد');
    expect(ridersTitle('2026-10-10', '2026-10-10')).toBe('ركاب اليوم');
    expect(forgotTitle(1)).toBe('طالب نسي كلمة المرور');
    expect(forgotTitle(2)).toBe('طالبان نسيا كلمة المرور');
    expect(forgotTitle(4)).toBe('4 طلاب نسوا كلمة المرور');
    expect(overBy({ bus_capacity: 45, over: [{ id: 't', time: '07:15', riders: 47 }] })).toBe(2);
    expect(overBy({ bus_capacity: null, over: [] })).toBe(0);
    expect(createdText(hoursAgo(6 * 24), NOW)).toBe('أُنشئت منذ 6 أيام');
  });
});

describe('companyAttention', () => {
  const base = '/c/c1';
  it('lists what the board lists, in its order, with its words', () => {
    const d = company({
      receipts: { waiting: 7, oldest_at: hoursAgo(3), last_attempt: 1 },
      lines: [
        line({ id: 'a', name: 'دمياط الجديدة' }),
        line({ id: 'b', name: 'شربين', supervisors: [] }),
        line({ id: 'c', name: 'كفر البطيخ', visible: false, hidden: 'unserved_university', unserved_university: 'جامعة دمياط' }),
        line({ id: 'd', name: 'فارسكور', over: [{ id: 't', time: '07:15', riders: 47, direction: 'departure' }] }),
      ],
    });
    const items = companyAttention(d, { base, now: NOW });
    expect(items.map((a) => [a.title, a.sub, a.action])).toEqual([
      ['7 إيصالات تنتظر مراجعتك', 'أقدمها منذ 3 ساعات · واحد منها في آخر محاولة', 'راجع الإيصالات'],
      ['خط شربين بلا مشرف', 'لا أحد يسجّل ركابه عند الصعود', 'عيّن مشرفاً'],
      ['خط كفر البطيخ لا يظهر للطلاب', 'تنقصه رحلة ذهاب إلى جامعة دمياط', 'أكمل الخط'],
      ['رحلة فارسكور 7:15 ص أكبر من الباص', '47 راكباً أكّدوا والباص 45 مقعداً', 'اعرض الرحلة'],
    ]);
    expect(items[2].to).toBe('/c/c1/lines/c');
    expect(items.some((a) => a.key === 'passwords')).toBe(false);
  });
  it('is empty when nothing waits; a stopped line is not a problem', () => {
    expect(companyAttention(company({ lines: [line({ is_active: false, visible: false, hidden: 'line_inactive', supervisors: [] })] }), { base })).toEqual([]);
  });
  it('groups several lines into one row and puts a missing payment method first', () => {
    const d = company({
      setup: { ...company().setup, payment_methods: 0 },
      lines: [line({ id: 'a', name: 'أ', supervisors: [] }), line({ id: 'b', name: 'ب', supervisors: [] }), line({ id: 'c', name: 'ج', supervisors: [] })],
    });
    const items = companyAttention(d, { base });
    expect(items[0].key).toBe('pay');
    expect(items[1]).toMatchObject({ title: '3 خطوط بلا مشرف', sub: 'أ · ب · ج', to: '/c/c1/supervisors' });
  });
  it('one receipt reads in the singular', () => {
    const [r] = companyAttention(company({ receipts: { waiting: 1, oldest_at: hoursAgo(2), last_attempt: 1 } }), { base, now: NOW });
    expect([r.title, r.sub]).toEqual(['إيصال ينتظر مراجعتك', 'منذ ساعتين · في آخر محاولة']);
  });
});

describe('first run', () => {
  const blank = company({ members: 0, subscribers: 0, lines: [], setup: { ...company().setup, lines: 0, payment_methods: 0, supervisors: 0 } });
  it('shows the setup while a step is missing and nobody subscribed', () => {
    expect(isFirstRun(blank)).toBe(true);
    expect(isFirstRun({ ...blank, setup: { ...blank.setup, lines: 1, payment_methods: 1, supervisors: 1 } })).toBe(false);
    expect(isFirstRun({ ...blank, members: 3 })).toBe(false);
  });
  it('the first step not done is the current one', () => {
    expect(setupSteps(blank)).toEqual({ line: 'current', pay: 'todo', sup: 'todo', done: 0 });
    expect(setupSteps({ ...blank, setup: { ...blank.setup, lines: 1 } })).toEqual({ line: 'done', pay: 'current', sup: 'todo', done: 1 });
  });
  it('says why students cannot subscribe yet', () => {
    expect(cannotSubscribeText(blank)).toBe('لا يوجد خط يشتركون فيه بعد.');
    const one = { ...blank, lines: [line()], setup: { ...blank.setup, lines: 1 } };
    expect(cannotSubscribeText(one)).toBe('خطك يظهر لهم في التطبيق، لكن لا توجد وسيلة يدفعون بها.');
    expect(cannotSubscribeText({ ...one, setup: { ...one.setup, payment_methods: 1 } })).toBe('');
    expect(cannotSubscribeText({ ...one, lines: [line({ visible: false, hidden: 'no_price' })] })).toBe('خطك لا يظهر لهم في التطبيق بعد: لم تكتب سعر الفصل المعروض للبيع.');
  });
});

describe('platform', () => {
  const row = (name: string, o: Partial<PlatformCompanyRow> = {}): PlatformCompanyRow => ({
    company: { id: name, name, status: 'active', created_at: hoursAgo(24 * 300) } as PlatformCompanyRow['company'],
    members: 10, active_subscriptions: 5, pending_receipts: 0, revenue: 0, riders_today: 0, next_ride_date: '2026-10-11', riders_next: 0,
    lines: 2, active_lines: 1, supervisors: 1, admins: 1, oldest_receipt_at: null, payment_methods: 1, selling: true, ...o,
  });
  const platform = (per: PlatformCompanyRow[], o: Partial<PlatformToday> = {}): PlatformToday => ({
    today: '2026-10-10', companies: { total: per.length, active: per.length, suspended: 0, archived: 0 }, universities: 3, students: 0,
    active_subscriptions: 0, pending_receipts: 0, receipt_companies: 0, next_ride_date: '2026-10-11', riders_next: 0, vote_closes_at: '06:00', revenue: 0,
    corrections: { waiting: 3, oldest_at: hoursAgo(48), companies: ['النورس للنقل', 'الفيروز لنقل الطلاب'] },
    password_requests: { waiting: 2, without_company: 1 }, push_failed_24h: 14, app_versions: [], per_company: per, ...o,
  });
  it('lists the board rows', () => {
    const d = platform([
      row('الياسمين باص', { lines: 0, active_lines: 0, payment_methods: 0, company: { id: 'y', name: 'الياسمين باص', status: 'active', created_at: hoursAgo(6 * 24) } as PlatformCompanyRow['company'] }),
      row('الصفوة للرحلات', { payment_methods: 0 }), row('النخبة للنقل الجماعي', { payment_methods: 0 }),
      row('المدينة للرحلات الجامعية', { selling: false }), row('سليمة'),
    ]);
    const items = platformAttention(d, { corrections: 3, passwordRequests: 2, now: NOW });
    expect(items.map((a) => [a.title, a.sub])).toEqual([
      ['3 طلبات تصحيح بيانات تنتظر قرارك', 'أقدمها منذ يومين · من النورس للنقل والفيروز لنقل الطلاب'],
      ['طالبان نسيا كلمة المرور', 'أحدهما بلا شركة، ولا يستطيع أحد غيرك أن يعطيه رمزاً'],
      ['الياسمين باص بلا أي خط', 'أُنشئت منذ 6 أيام ولا يراها الطلاب في التطبيق'],
      ['3 شركات بلا وسيلة دفع', 'الياسمين باص · الصفوة للرحلات · النخبة للنقل الجماعي — لا يستطيع طلابها أن يدفعوا'],
      ['المدينة للرحلات الجامعية لا تعرض أي اشتراك للبيع', 'لها خطوط ووسيلة دفع، لكن كل الفصول موقوفة عن البيع'],
      ['14 تنبيهاً لم تصل إلى الهواتف في آخر 24 ساعة', 'الإشعارات نفسها ظهرت داخل التطبيق'],
    ]);
  });
  it('a suspended company is not asked about; nothing waits gives no rows', () => {
    const d = platform([row('موقوفة', { lines: 0, payment_methods: 0, company: { id: 's', name: 'موقوفة', status: 'suspended', created_at: hoursAgo(1) } as PlatformCompanyRow['company'] })], { push_failed_24h: 0 });
    expect(platformAttention(d, { corrections: 0, passwordRequests: 0 })).toEqual([]);
  });
  it('receipts pile up after a day; company counts', () => {
    expect(isPilingUp({ pending_receipts: 3, oldest_receipt_at: hoursAgo(30) }, NOW)).toBe(true);
    expect(isPilingUp({ pending_receipts: 3, oldest_receipt_at: hoursAgo(3) }, NOW)).toBe(false);
    expect(companiesHint({ total: 28, active: 26, suspended: 2, archived: 0 })).toBe('26 تعمل · 2 موقوفتان');
    expect(companiesHint({ total: 5, active: 5, suspended: 0, archived: 0 })).toBe('كلها تعمل');
  });
});
