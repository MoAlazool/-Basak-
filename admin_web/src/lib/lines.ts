/**
 * A line as the dashboard edits it, and every rule about it that does not need
 * the network: the draft the five steps fill, the timetable checks, the
 * "minutes between stations" helper, the one request that saves it all
 * (save_line_full), and whether students can see a line and why not.
 * Pure: no React, no Supabase (hooks live in lib/linesData.ts).
 */
import { clockLabel, hhmm } from './time';
import { SALE_OPTIONS, optionName, type SaleOption } from './saleOptions';
import { BUS_CAPACITY_MAX, capacityText, parseBusCapacity } from './lineCapacity';

export type Direction = 'departure' | 'return';

export interface StationDraft { key: string; id?: string; name: string }
export interface TripDraft {
  key: string; id?: string; direction: Direction; label: string;
  /** `HH:MM` or ''. */
  start_time: string; arrival_time: string;
  /** '' = every university of the line. */
  university_id: string; is_active: boolean;
  /** Stop time per station key (departure only). A station with no time is skipped. */
  times: Record<string, string>;
}
export interface PriceDraft { enabled: boolean; price: number | '' }
export interface LineDraft {
  id?: string; company_id: string; name: string; university_ids: string[];
  /** The bus-seats field as typed. */
  capacity: string;
  prices: Record<SaleOption, PriceDraft>;
  price_daily: number | '';
  /** Daily is sold on this line. Off saves the daily price as 0 (the line then sells no daily). */
  daily_enabled: boolean;
  is_active: boolean;
  stations: StationDraft[];
  trips: TripDraft[];
}

/** The line as read from the database (lib/reference.ts · LineRow), the parts used here. */
export interface LineLike {
  id: string; name: string; company_id: string; is_active: boolean; price_daily: number;
  price_termly?: number; price_yearly?: number;
  stations: { id: string; name: string; order_index: number; is_active: boolean }[];
  line_trips: {
    id: string; direction: Direction; label: string | null; start_time: string; arrival_time: string | null;
    university_id: string | null; is_active: boolean; line_trip_stops: { station_id: string; stop_time: string }[];
  }[];
  line_universities: { university_id: string }[];
  line_period_prices: { option: SaleOption; price: number; is_enabled: boolean }[];
  destination_university_id?: string | null;
}

let seq = 0;
export const newKey = () => `k${++seq}`;

// ── Clock arithmetic ────────────────────────────────────────────────────────
export const toMinutes = (t: string): number => { const [h, m] = t.slice(0, 5).split(':').map(Number); return h * 60 + m; };
const fromMinutes = (total: number) => `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
/** `07:30` + 15 → `07:45`; kept inside the same day (00:00–23:59). */
export function addMinutes(t: string, minutes: number): string {
  return fromMinutes(Math.min(23 * 60 + 59, Math.max(0, toMinutes(t) + minutes)));
}
/** «7:30 ص», or «—». */
export const clockOr = (t: string | null | undefined) => clockLabel(t) || '—';

/**
 * The «احسب المواعيد» helper: the time at each station of the route from the
 * trip's start, `gap` minutes apart, counted by the station's place on the route
 * (the first station is the start itself). Stations the trip does not stop at
 * keep no time, and the others keep their place in the count.
 */
export function fillStopTimes(start: string, gap: number, stations: StationDraft[], skipped: ReadonlySet<string> = new Set()): Record<string, string> {
  const step = Math.max(0, Math.round(gap) || 0);
  const times: Record<string, string> = {};
  stations.forEach((s, i) => { if (!skipped.has(s.key)) times[s.key] = addMinutes(start, step * i); });
  return times;
}

// ── Drafts ──────────────────────────────────────────────────────────────────
const blankPrices = (sold?: Partial<Record<SaleOption, boolean>>): Record<SaleOption, PriceDraft> =>
  Object.fromEntries(SALE_OPTIONS.map((o) => [o, { enabled: sold ? !!sold[o] : o !== 'summer', price: '' }])) as Record<SaleOption, PriceDraft>;

/** A new line: nothing typed, no price written for the admin, one empty station. */
export function emptyDraft(companyId: string, sold?: Partial<Record<SaleOption, boolean>>): LineDraft {
  return {
    company_id: companyId, name: '', university_ids: [], capacity: '', prices: blankPrices(sold), price_daily: '', daily_enabled: true,
    is_active: true, stations: [{ key: newKey(), name: '' }], trips: [],
  };
}

export const emptyTrip = (direction: Direction, start = ''): TripDraft => ({
  key: newKey(), direction, label: '', start_time: start, arrival_time: '', university_id: '', is_active: true, times: {},
});

/** The saved line as a draft (only what is in use: active stations and trips). */
export function draftFromLine(line: LineLike, capacity: number | null | undefined): LineDraft {
  const stations = line.stations.filter((s) => s.is_active).sort((a, b) => a.order_index - b.order_index)
    .map((s) => ({ key: s.id, id: s.id, name: s.name }));
  const unis = line.line_universities.map((u) => u.university_id);
  return {
    id: line.id, company_id: line.company_id, name: line.name,
    university_ids: unis.length ? unis : line.destination_university_id ? [line.destination_university_id] : [],
    capacity: capacityText(capacity),
    prices: Object.fromEntries(SALE_OPTIONS.map((o) => {
      const row = line.line_period_prices.find((p) => p.option === o);
      return [o, row ? { enabled: row.is_enabled, price: row.price > 0 ? Number(row.price) : '' } : { enabled: false, price: '' }];
    })) as Record<SaleOption, PriceDraft>,
    price_daily: line.price_daily > 0 ? Number(line.price_daily) : '',
    daily_enabled: line.price_daily > 0,
    is_active: line.is_active, stations,
    trips: line.line_trips.filter((t) => t.is_active)
      .sort((a, b) => a.direction.localeCompare(b.direction) || a.start_time.localeCompare(b.start_time))
      .map((t) => ({
        key: t.id, id: t.id, direction: t.direction, label: t.label ?? '', start_time: hhmm(t.start_time),
        arrival_time: hhmm(t.arrival_time), university_id: t.university_id ?? '', is_active: t.is_active,
        times: t.direction === 'return' ? {} : Object.fromEntries(t.line_trip_stops.map((s) => [s.station_id, hhmm(s.stop_time)])),
      })),
  };
}

export const tripsOf = (d: Pick<LineDraft, 'trips'>, direction: Direction) =>
  d.trips.filter((t) => t.direction === direction).sort((a, b) => (a.start_time || '99').localeCompare(b.start_time || '99'));

// ── Timetable checks ────────────────────────────────────────────────────────
export interface TripProblem { stationKey?: string; field?: 'start' | 'arrival' | 'stops'; message: string; short: string }
const stationName = (s: StationDraft) => s.name.trim() || 'بدون اسم';

/**
 * What is wrong with one trip, the way save_line would refuse it: a start time;
 * on the way there, at least one stop time, stop times in route order and not
 * before the start, and the arrival not before the last stop. Each problem names
 * the station it belongs to, so it can be shown under that field.
 */
export function tripProblems(trip: TripDraft, stations: StationDraft[]): TripProblem[] {
  const out: TripProblem[] = [];
  if (!trip.start_time) {
    out.push(trip.direction === 'return'
      ? { field: 'start', message: 'اكتب موعد تحرك الباص من الجامعة.', short: 'موعد عودة بلا وقت.' }
      : { field: 'start', message: 'اكتب موعد تحرك الرحلة من أول محطة.', short: 'رحلة بلا موعد تحرك.' });
    return out;
  }
  if (trip.direction === 'return') return out;
  const route = stations.filter((s) => trip.times[s.key]);
  if (route.length === 0) {
    out.push({ field: 'stops', message: 'الرحلة لا تمر بأي محطة. اكتب موعد مرورها على محطة واحدة على الأقل، فالطلاب يركبون منها.', short: 'لا تمر بأي محطة.' });
    return out;
  }
  let prev = trip.start_time;
  let prevName: string | null = null;
  for (const s of route) {
    const time = trip.times[s.key];
    if (time < prev) {
      out.push(prevName
        ? { stationKey: s.key, message: `موعد «${stationName(s)}» (${clockLabel(time)}) قبل محطة «${prevName}» (${clockLabel(prev)}). المواعيد يجب أن تكون بترتيب المسار.`,
            short: `موعد محطة «${stationName(s)}» قبل المحطة التي قبلها.` }
        : { stationKey: s.key, message: `موعد «${stationName(s)}» (${clockLabel(time)}) قبل موعد التحرك (${clockLabel(prev)}).`,
            short: `موعد محطة «${stationName(s)}» قبل موعد التحرك.` });
    }
    prev = time > prev ? time : prev;
    prevName = stationName(s);
  }
  if (trip.arrival_time && trip.arrival_time < prev) {
    out.push({ field: 'arrival', message: `موعد الوصول (${clockLabel(trip.arrival_time)}) قبل آخر محطة (${clockLabel(prev)}).`, short: 'موعد الوصول قبل آخر محطة.' });
  }
  return out;
}

// ── Steps ───────────────────────────────────────────────────────────────────
export type StepNo = 1 | 2 | 3 | 4 | 5;
export interface Issue { step: StepNo; message: string; tripKey?: string; stationKey?: string }
export interface SaleContext {
  /** Options the company sells (null while unknown: every option counts as sold). */
  sold: Partial<Record<SaleOption, boolean>> | null;
  /** The company sells the daily cash ride. */
  daily: boolean;
  uniName: (id: string) => string;
}
export const priceOf = (p: PriceDraft) => (p.price === '' ? 0 : Number(p.price));
/** The daily price the line sells at: 0 while daily is switched off on it. */
export const dailyPrice = (d: Pick<LineDraft, 'price_daily' | 'daily_enabled'>) => (d.daily_enabled && d.price_daily !== '' ? Number(d.price_daily) : 0);
export const isSold = (ctx: Pick<SaleContext, 'sold'>, o: SaleOption) => (ctx.sold ? !!ctx.sold[o] : true);

/** Every reason the line cannot be saved yet, by step. Nothing here is a warning: each one blocks the save. */
export function draftIssues(d: LineDraft, ctx: SaleContext): Issue[] {
  const out: Issue[] = [];
  const name = d.name.trim();
  if (name.length > 40) out.push({ step: 1, message: 'اسم الخط طويل: حتى 40 حرفاً، مثل اسم المنطقة.' });
  if (/[←→]/.test(name)) out.push({ step: 1, message: 'اكتب اسم المنطقة فقط، بلا أسهم.' });
  if (d.university_ids.length === 0) out.push({ step: 1, message: 'اختر جامعة واحدة على الأقل يوصل إليها الخط.' });
  const seats = parseBusCapacity(d.capacity);
  if (!seats.ok) out.push({ step: 1, message: seats.message });

  if (d.stations.length === 0) out.push({ step: 2, message: 'أضف محطة واحدة على الأقل.' });
  d.stations.forEach((s, i) => { if (!s.name.trim()) out.push({ step: 2, stationKey: s.key, message: `اكتب اسم المحطة رقم ${i + 1}.` }); });

  const going = tripsOf(d, 'departure');
  if (going.length === 0) out.push({ step: 3, message: 'أضف رحلة ذهاب واحدة على الأقل.' });
  d.trips.forEach((t) => {
    const p = tripProblems(t, d.stations)[0];
    if (p) out.push({ step: 3, tripKey: t.key, stationKey: p.stationKey, message: `${t.direction === 'return' ? 'موعد العودة' : 'رحلة'}${t.start_time ? ` ${clockLabel(t.start_time)}` : ''}: ${p.short}` });
  });
  const seen = new Set<string>();
  d.trips.forEach((t) => {
    if (!t.start_time) return;
    const k = `${t.direction}|${t.start_time}|${t.university_id}`;
    if (seen.has(k)) out.push({ step: 3, tripKey: t.key, message: `${t.direction === 'return' ? 'موعدا عودة' : 'رحلتان'} في ${clockLabel(t.start_time)} لنفس الجامعة. احذف إحداهما أو غيّر موعدها.` });
    seen.add(k);
  });
  if (going.length > 0) {
    uncoveredUniversities(d).forEach((u) => out.push({ step: 3, message: `لا رحلة ذهاب إلى ${ctx.uniName(u)}: اجعل رحلة «لكل جامعات الخط» أو أضف رحلة لها.` }));
  }

  SALE_OPTIONS.forEach((o) => {
    if (isSold(ctx, o) && d.prices[o].enabled && priceOf(d.prices[o]) <= 0) out.push({ step: 4, message: `${optionName[o]} مفتوح للبيع وبلا سعر.` });
  });
  if (ctx.daily && d.daily_enabled && dailyPrice(d) <= 0) out.push({ step: 4, message: 'اليومي (نقداً في الباص) مفتوح للبيع وبلا سعر.' });
  return out;
}

/** Universities of the line that no departure trip goes to (their students would never see the line). */
export function uncoveredUniversities(d: Pick<LineDraft, 'university_ids' | 'trips'>): string[] {
  return d.university_ids.filter((id) => !d.trips.some((t) => t.direction === 'departure' && t.is_active && (!t.university_id || t.university_id === id)));
}

/** A soft note under the prices (not blocking). */
export function bothPriceNote(d: LineDraft): string | null {
  const both = priceOf(d.prices.both);
  if (!d.prices.both.enabled || both <= 0) return null;
  const first = priceOf(d.prices.first); const second = priceOf(d.prices.second);
  if (both < Math.max(first, second)) return 'سعر الفصلين معاً أقل من سعر فصل واحد. راجع السعر.';
  if (first > 0 && second > 0 && both > first + second) return 'سعر الفصلين معاً أكبر من مجموع الفصلين. راجع السعر.';
  return null;
}

// ── The one request ─────────────────────────────────────────────────────────
export interface SavePayload {
  id: string | null; company_id: string; name: string; origin_name: string; destination_university_id: null;
  university_ids: string[]; price_termly: number; price_yearly: number; price_daily: number;
  /** Only for a new line: an edit never switches a line on or off (save_line keeps it as it is). */
  is_active?: boolean;
  bus_capacity: number | null;
  stations: { id: string | null; name: string }[];
  trips: { id: string | null; direction: Direction; label: string; start_time: string; arrival_time: string | null; university_id: string | null; is_active: boolean; stops: { station_index: number; time: string }[] }[];
  prices: { option: SaleOption; price: number | null; is_enabled: boolean }[];
}

/**
 * Everything save_line_full needs, from the draft. An option is sent "on sale"
 * only with a price (an option the company does not sell may be on without one:
 * it is then saved off). Return trips carry no stops. Stop times are by the
 * station's place on the route, as save_line expects.
 */
export function buildSavePayload(d: LineDraft): SavePayload {
  const index = new Map(d.stations.map((s, i) => [s.key, i]));
  const seats = parseBusCapacity(d.capacity);
  return {
    id: d.id ?? null, company_id: d.company_id, name: d.name.trim(), origin_name: '', destination_university_id: null,
    university_ids: [...d.university_ids],
    price_termly: priceOf(d.prices.first), price_yearly: priceOf(d.prices.both),
    price_daily: dailyPrice(d), ...(d.id ? {} : { is_active: d.is_active }),
    bus_capacity: seats.ok ? seats.value : null,
    stations: d.stations.map((s) => ({ id: s.id ?? null, name: s.name.trim() })),
    trips: d.trips.map((t) => ({
      id: t.id ?? null, direction: t.direction, label: t.label.trim(), start_time: t.start_time,
      arrival_time: t.direction === 'departure' ? t.arrival_time || null : null,
      university_id: t.university_id || null, is_active: t.is_active,
      stops: t.direction === 'return' ? []
        : d.stations.filter((s) => t.times[s.key]).map((s) => ({ station_index: index.get(s.key)!, time: t.times[s.key] })),
    })),
    prices: SALE_OPTIONS.map((o) => {
      const p = d.prices[o]; const price = priceOf(p);
      return { option: o, price: price > 0 ? price : null, is_enabled: p.enabled && price > 0 };
    }),
  };
}

// ── Words ───────────────────────────────────────────────────────────────────
/** The noun after a number: 1 طالب · 2 طالبان · 3–10 طلاب · 11+ طالباً (0 takes the last form). */
export function unitWord(n: number, forms: readonly [string, string, string, string]): string {
  if (n === 1) return forms[0];
  if (n === 2) return forms[1];
  if (n >= 3 && n <= 10) return forms[2];
  return forms[3];
}
/** «5 محطات», «محطة واحدة», «محطتان». */
export function countOf(n: number, forms: readonly [string, string, string, string], one?: string): string {
  if (n === 1) return one ?? `${forms[0]} ${forms[0].endsWith('ة') ? 'واحدة' : 'واحد'}`;
  if (n === 2) return forms[1];
  return `${n.toLocaleString('en-US')} ${unitWord(n, forms)}`;
}
export const W = {
  station: ['محطة', 'محطتان', 'محطات', 'محطة'],
  line: ['خط', 'خطان', 'خطوط', 'خطاً'],
  trip: ['رحلة', 'رحلتان', 'رحلات', 'رحلة'],
  time: ['موعد', 'موعدان', 'مواعيد', 'موعداً'],
  student: ['طالب', 'طالبان', 'طلاب', 'طالباً'],
  rider: ['راكب', 'راكبان', 'ركاب', 'راكباً'],
  seat: ['مقعد', 'مقعدان', 'مقاعد', 'مقعداً'],
  university: ['جامعة', 'جامعتان', 'جامعات', 'جامعة'],
  price: ['سعر', 'سعران', 'أسعار', 'سعراً'],
  subscription: ['اشتراك', 'اشتراكان', 'اشتراكات', 'اشتراكاً'],
} as const satisfies Record<string, readonly [string, string, string, string]>;

/** «أ» · «أ وب» · «أ، ب وج». */
export function joinAnd(names: string[]): string {
  if (names.length <= 1) return names[0] ?? '';
  return `${names.slice(0, -1).join('، ')} و${names[names.length - 1]}`;
}

/** The step list's second lines and the summary card, from the draft. */
export function stepSubs(d: LineDraft): Record<1 | 2 | 3 | 4, string> {
  const name = d.name.trim() || d.stations[0]?.name.trim() || 'بلا اسم';
  const seats = parseBusCapacity(d.capacity);
  const unis = d.university_ids.length;
  const uniText = unis === 1 ? 'جامعة واحدة' : unis === 2 ? 'جامعتان' : `${unis} ${unitWord(unis, W.university)}`;
  const priced = SALE_OPTIONS.filter((o) => d.prices[o].enabled && priceOf(d.prices[o]) > 0).length + (dailyPrice(d) > 0 ? 1 : 0);
  return {
    1: [name, unis ? uniText : null, seats.ok && seats.value ? `${seats.value} ${unitWord(seats.value, W.seat)}` : null].filter(Boolean).join(' · '),
    2: d.stations.length ? countOf(d.stations.length, W.station) : '',
    3: d.trips.length ? `${tripsOf(d, 'departure').length} ذهاب · ${tripsOf(d, 'return').length} عودة` : '',
    4: priced ? countOf(priced, W.price, 'سعر واحد') : '',
  };
}

/** «8 محطات: من موقف الزرقا إلى مدخل فارسكور». */
export function stationsText(d: Pick<LineDraft, 'stations'>): string {
  const names = d.stations.map((s) => s.name.trim()).filter(Boolean);
  if (!names.length) return '';
  if (names.length === 1) return `محطة واحدة: ${names[0]}`;
  return `${countOf(names.length, W.station)}: من ${names[0]} إلى ${names[names.length - 1]}`;
}
/** «5 رحلات: من 6:15 ص إلى 8:15 ص». */
export function tripsRangeText(d: Pick<LineDraft, 'trips'>, direction: Direction): string {
  const list = tripsOf(d, direction).filter((t) => t.start_time);
  if (!list.length) return '';
  const forms = direction === 'departure' ? W.trip : W.time;
  if (list.length === 1) return `${direction === 'departure' ? 'رحلة واحدة' : 'موعد واحد'}: ${clockLabel(list[0].start_time)}`;
  return `${countOf(list.length, forms)}: من ${clockLabel(list[0].start_time)} إلى ${clockLabel(list[list.length - 1].start_time)}`;
}
/** «الأول 3,200 ج.م · الفصلان معاً 6,000 ج.م · اليومي 45 ج.م». */
export function pricesText(d: LineDraft, long = false): string {
  const short: Record<SaleOption, string> = { first: long ? 'الفصل الأول' : 'الأول', second: 'الثاني', both: 'الفصلان معاً', summer: 'الصيفي' };
  const parts = SALE_OPTIONS.filter((o) => d.prices[o].enabled && priceOf(d.prices[o]) > 0).map((o) => `${short[o]} ${priceOf(d.prices[o]).toLocaleString('en-US')} ج.م`);
  if (dailyPrice(d) > 0) parts.push(`اليومي ${dailyPrice(d).toLocaleString('en-US')} ج.م`);
  return parts.join(' · ');
}

// ── Can students see it? ────────────────────────────────────────────────────
export type Visibility =
  | { state: 'on' }
  | { state: 'off' }
  | { state: 'hidden'; reason: string; fix: string; step: StepNo };

/** Whether the app shows a saved line to students, and when not, what is missing and which step fixes it. */
export function lineVisibility(line: LineLike, o: { daily: boolean; uniName: (id: string) => string }): Visibility {
  if (!line.is_active) return { state: 'off' };
  const unis = line.line_universities.map((u) => u.university_id);
  if (unis.length === 0) return { state: 'hidden', reason: 'لم تُحدد له جامعة', fix: 'اختر الجامعات', step: 1 };
  const going = line.line_trips.filter((t) => t.direction === 'departure' && t.is_active);
  const missing = unis.filter((u) => !going.some((t) => !t.university_id || t.university_id === u));
  if (missing.length) return { state: 'hidden', reason: `تنقصه رحلة ذهاب إلى ${joinAnd(missing.map(o.uniName))}`, fix: 'أضف رحلة', step: 3 };
  const priced = line.line_period_prices.some((p) => p.is_enabled && Number(p.price) > 0) || (o.daily && Number(line.price_daily) > 0);
  if (!priced) return { state: 'hidden', reason: 'لم يُكتب سعر لأي اشتراك', fix: 'اكتب الأسعار', step: 4 };
  return { state: 'on' };
}

export { BUS_CAPACITY_MAX };

// ── Typing a time ───────────────────────────────────────────────────────────
/**
 * What the admin typed in a time field, as `HH:MM`: «7:30 ص», «7:30 م», «19:30»,
 * «7.30», «730», «7:30pm», Arabic digits too. With no ص/م and an hour from 1 to
 * 12, `assume` decides; without it 7–11 are morning and 12, 1–6 afternoon (a
 * bus's day). '' for an empty field, null when it is not a time.
 */
export function parseClock(text: string, assume?: 'am' | 'pm'): string | null {
  const s = text.trim().replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d))).toLowerCase();
  if (!s) return '';
  const m = /^(\d{1,2})(?:\s*[:.٫]\s*(\d{1,2})|(\d{2}))?\s*(ص|م|am|pm|a\.m\.|p\.m\.)?$/.exec(s.replace(/\s+/g, ' '));
  if (!m) return null;
  let h = Number(m[1]);
  const min = Number(m[2] ?? m[3] ?? 0);
  if (min > 59) return null;
  const suffix = m[4] ? (/^(ص|am|a\.m\.)$/.test(m[4]) ? 'am' : 'pm') : null;
  if (suffix) {
    if (h < 1 || h > 12) return null;
    h = suffix === 'am' ? h % 12 : (h % 12) + 12;
  } else if (h > 23) {
    return null;
  } else if (h >= 1 && h <= 12 && !(m[1].length === 2 && m[1].startsWith('0'))) {
    const pm = assume ? assume === 'pm' : h === 12 || h <= 6;
    h = pm ? (h % 12) + 12 : h % 12;
  }
  return `${String(h).padStart(2, '0')}:${String(min).padStart(2, '0')}`;
}

// ── Editing a line in use ───────────────────────────────────────────────────
/** Same trip, comparing stop times only on the stations that remain (a removed station is counted once, on its own). */
const sameTrip = (a: TripDraft, b: TripDraft, keep: Set<string>) => {
  const times = (t: TripDraft) => JSON.stringify(Object.entries(t.times).filter(([k, v]) => v && keep.has(k)).sort());
  return a.start_time === b.start_time && a.arrival_time === b.arrival_time && a.label.trim() === b.label.trim()
    && a.university_id === b.university_id && times(a) === times(b);
};

/** How many things the draft changes compared with the saved line (for «تعديلان لم يُحفظا»). */
export function changeCount(saved: LineDraft, d: LineDraft): number {
  let n = 0;
  if (saved.name.trim() !== d.name.trim()) n += 1;
  if ([...saved.university_ids].sort().join() !== [...d.university_ids].sort().join()) n += 1;
  if (saved.capacity.trim() !== d.capacity.trim()) n += 1;
  const oldSt = new Map(saved.stations.map((s) => [s.key, s]));
  d.stations.forEach((s) => { const o = oldSt.get(s.key); if (!o || o.name.trim() !== s.name.trim()) n += 1; });
  saved.stations.forEach((s) => { if (!d.stations.some((x) => x.key === s.key)) n += 1; });
  const kept = d.stations.filter((s) => oldSt.has(s.key)).map((s) => s.key).join();
  if (kept !== saved.stations.filter((s) => d.stations.some((x) => x.key === s.key)).map((s) => s.key).join()) n += 1;
  const oldTr = new Map(saved.trips.map((t) => [t.key, t]));
  const keep = new Set(d.stations.map((s) => s.key));
  d.trips.forEach((t) => { const o = oldTr.get(t.key); if (!o || !sameTrip(o, t, keep)) n += 1; });
  saved.trips.forEach((t) => { if (!d.trips.some((x) => x.key === t.key)) n += 1; });
  SALE_OPTIONS.forEach((o) => { if (saved.prices[o].enabled !== d.prices[o].enabled || priceOf(saved.prices[o]) !== priceOf(d.prices[o])) n += 1; });
  if (dailyPrice(saved) !== dailyPrice(d)) n += 1;
  return n;
}
/** «تعديل واحد لم يُحفظ», «تعديلان لم يُحفظا», «3 تعديلات لم تُحفظ». */
export function unsavedText(n: number): string {
  if (n === 1) return 'تعديل واحد لم يُحفظ';
  if (n === 2) return 'تعديلان لم يُحفظا';
  return `${n} ${n <= 10 ? 'تعديلات' : 'تعديلاً'} لم تُحفظ`;
}

export type Effect =
  | { kind: 'times'; trip: string; stations: number; students: number }
  | { kind: 'station'; name: string; students: number }
  | { kind: 'trip'; trip: string; direction: Direction; students: number };

/**
 * What saving an edit does to students: a trip whose stop times changed moves
 * its subscribers' boarding time; a removed station or trip that students use
 * is retired, not deleted. Only effects with students are listed.
 */
export function editEffects(saved: LineDraft, d: LineDraft, onStation: Record<string, number>, onTrip: Record<string, number>): Effect[] {
  const out: Effect[] = [];
  d.trips.forEach((t) => {
    const o = saved.trips.find((x) => x.key === t.key);
    if (!o || !t.id || t.direction !== 'departure') return;
    const changed = d.stations.filter((s) => s.id && (o.times[s.key] ?? '') !== (t.times[s.key] ?? '') && (o.times[s.key] || t.times[s.key])).length;
    const students = onTrip[t.id] ?? 0;
    if (changed && students) out.push({ kind: 'times', trip: t.start_time, stations: changed, students });
  });
  saved.stations.forEach((s) => {
    if (s.id && !d.stations.some((x) => x.key === s.key) && (onStation[s.id] ?? 0) > 0) out.push({ kind: 'station', name: s.name, students: onStation[s.id] });
  });
  saved.trips.forEach((t) => {
    if (t.id && !d.trips.some((x) => x.key === t.key) && (onTrip[t.id] ?? 0) > 0) out.push({ kind: 'trip', trip: t.start_time, direction: t.direction, students: onTrip[t.id] });
  });
  return out;
}

/** What a new line's draft already holds, for «كتبت الاسم، 8 محطات و10 رحلات». */
export function typedSummary(d: LineDraft): string {
  const parts: string[] = [];
  if (d.name.trim()) parts.push('الاسم');
  else if (d.university_ids.length) parts.push('الجامعات');
  const st = d.stations.filter((s) => s.name.trim()).length;
  if (st) parts.push(countOf(st, W.station));
  if (d.trips.length) parts.push(countOf(d.trips.length, W.trip));
  const pr = SALE_OPTIONS.filter((o) => priceOf(d.prices[o]) > 0).length + (Number(d.price_daily) > 0 ? 1 : 0);
  if (pr) parts.push(countOf(pr, W.price, 'سعراً واحداً'));
  if (parts.length <= 1) return parts[0] ?? '';
  return `${parts.slice(0, -1).join('، ')} و${parts[parts.length - 1]}`;
}

/** Whether a new line's draft holds anything worth asking about before closing. */
export const hasTyped = (d: LineDraft) => typedSummary(d) !== '' || !!d.capacity.trim();
