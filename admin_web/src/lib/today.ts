/**
 * «اليوم» — the company admin's first page (docs/canvas/AdmToday*). One request,
 * `company_today` (supabase/migrations/20261116000001_admin_today.sql); a database
 * without it yet gets the same shape from the older functions (lib/todayLegacy.ts,
 * downloaded only then), with what they cannot tell left empty. The platform's
 * page is lib/platformToday.ts; the shapes and words they share are here.
 *
 * The answer lives under an `overview` key, so lib/sync.ts refreshes it with the
 * overview: receipts, subscriptions and lines at once, ride confirmations while
 * this page (`/c/{id}`) is the one open. This module is on the company's first
 * screen (scripts/check-bundle.mjs): keep it to what that screen needs.
 */
import { useQuery } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';
import { rpcOr } from './rpc';
import type { PlatformNumbers } from './overview';
import { agoText, clock, countText, dayText, num, NOUN } from '../ui/format';
import type { IconName } from '../ui/Icon';
import type { Tone } from '../ui/Status';

// ── Shapes ──────────────────────────────────────────────────────────
export interface TripCount { id: string; time: string | null; riders: number; label?: string | null; direction?: 'departure' | 'return' }
/** Why students cannot see a line (null: they can). */
export type HiddenReason =
  | 'line_inactive' | 'no_stations' | 'no_departure' | 'unserved_university' | 'company_inactive' | 'company_not_selling'
  | 'line_not_offering' | 'no_price' | 'not_in_season' | 'advance_off' | 'nothing_on_sale';
export interface TodayLine {
  id: string; name: string; is_active: boolean; bus_capacity: number | null;
  subscribers: number; going: number; returning: number;
  top_trip: TripCount | null; over: TripCount[]; supervisors: { id: string; name: string }[];
  /** null when the older database could not tell. */
  visible: boolean | null; hidden: HiddenReason | null; unserved_university: string | null;
}
export interface CompanyToday {
  company: { id: string; name: string; status: string; created_at: string };
  today: string; ride_date: string;
  vote_opens_at: string | null; vote_closes_at: string | null; vote_open: boolean | null;
  members: number; subscribers: number; confirmed: number; going: number; returning: number;
  receipts: { waiting: number; oldest_at: string | null; last_attempt: number | null };
  password_requests: number;
  lines: TodayLine[];
  setup: {
    lines: number; first_line: { id: string; name: string; stations: number; departures: number; returns: number } | null;
    payment_methods: number; supervisors: number; on_sale: string[] | null;
    vote_custom: boolean | null; wallet_custom: boolean | null; receipt_info: boolean | null;
  };
}
export interface PlatformCompanyRow extends Omit<PlatformNumbers['per_company'][number], 'baseline'> {
  oldest_receipt_at: string | null; payment_methods: number | null; selling: boolean | null;
}
export interface PlatformToday {
  today: string;
  companies: PlatformNumbers['companies'];
  universities: number | null;
  students: number; active_subscriptions: number; pending_receipts: number; receipt_companies: number;
  next_ride_date: string; riders_next: number; vote_closes_at: string | null; revenue: number;
  corrections: { waiting: number; oldest_at: string | null; companies: string[] };
  password_requests: { waiting: number; without_company: number };
  push_failed_24h: number;
  app_versions: { platform: string; latest_version: string; min_version: string }[];
  per_company: PlatformCompanyRow[];
}

// ── Company: the request and its older form ─────────────────────────
export const companyTodayKey = (companyId: string) => keys.company(companyId, 'overview', 'today');

export function useCompanyToday(companyId: string) {
  const query = useQuery({
    queryKey: companyTodayKey(companyId),
    queryFn: () => loadCompanyToday(companyId),
    // Lines, supervisors and payment methods are changed on other pages and are not
    // announced to this key: coming back here always asks again (showing the last copy meanwhile).
    refetchOnMount: 'always',
  });
  return { data: query.data ?? null, loading: query.isPending, error: query.error, updatedAt: query.dataUpdatedAt, refresh: () => void query.refetch() };
}

export const loadCompanyToday = (companyId: string) => rpcOr<CompanyToday>(
  'company_today',
  () => supabase.rpc('company_today', { p_company_id: companyId }),
  // The older way is downloaded only by a dashboard that meets an older database.
  () => import('./todayLegacy').then((m) => m.legacyCompanyToday(companyId)),
);

// ── Words ───────────────────────────────────────────────────────────
/** «منذ 3 ساعات» → «أقدمها منذ 3 ساعات»; «أمس» → «أقدمها من أمس». */
export function oldestText(iso: string | null | undefined, now: Date = new Date()): string {
  const ago = agoText(iso, now);
  if (!ago) return '';
  if (ago === 'الآن') return 'أقدمها وصل الآن';
  return ago.startsWith('منذ') ? `أقدمها ${ago}` : `أقدمها من ${ago}`;
}

/** Why students cannot see a line, as one sentence. */
export function hiddenText(line: Pick<TodayLine, 'hidden' | 'unserved_university'>): string {
  switch (line.hidden) {
    case 'line_inactive': return 'الخط موقوف';
    case 'no_stations': return 'لم تُضف له محطات بعد';
    case 'no_departure': return 'لم تُضف له رحلة ذهاب بعد';
    case 'unserved_university': return `تنقصه رحلة ذهاب إلى ${line.unserved_university ?? 'إحدى جامعاته'}`;
    case 'company_inactive': return 'الشركة موقوفة';
    case 'company_not_selling': return 'لا يُعرض أي فصل للبيع الآن';
    case 'line_not_offering': return 'لم تفتح فيه الفصل المعروض للبيع';
    case 'no_price': return 'لم تكتب سعر الفصل المعروض للبيع';
    case 'not_in_season': case 'advance_off': return 'لا فصل مفتوح للاشتراك الآن';
    case 'nothing_on_sale': return 'لا يُعرض فيه شيء للبيع';
    default: return '';
  }
}
/** Where the fix for a hidden line is made. */
const hiddenFix = (line: Pick<TodayLine, 'id' | 'hidden'>, base: string): { to: string; action: string } =>
  line.hidden === 'company_not_selling' || line.hidden === 'not_in_season' || line.hidden === 'advance_off'
    ? { to: `${base}/subscription-periods`, action: 'افتح البيع' }
    : { to: `${base}/lines/${line.id}`, action: 'أكمل الخط' };

/** A count that always shows its digits, for figures read at a glance: «1 محطة», «2 محطات», «8 محطات», «168 مشتركاً». */
export function nOf(n: number, forms: readonly [string, string, string, string]): string {
  if (n === 0 || n === 2) return `${n} ${forms[2]}`;
  if (n === 1) return `1 ${forms[0]}`;
  return countText(n, forms as [string, string, string, string]);
}
export const SUBSCRIBER = ['مشترك', 'مشتركان', 'مشتركين', 'مشتركاً'] as const;

/** «7:30 ص · 44 راكباً». */
export const tripText = (t: TripCount | null) => (t ? `${clock(t.time)} · ${countText(t.riders, NOUN.rider)}` : '');

/** «الأحد 11 أكتوبر» (no year: it is always this week). */
export const rideDayText = (day: string) => dayText(day, { weekday: true, year: false });

/** «ركاب الغد», or «ركاب اليوم» while today's own confirmations are still open. */
export function ridersTitle(today: string, ride: string): string {
  if (ride === today) return 'ركاب اليوم';
  return 'ركاب الغد';
}

/** How many seats a line's fullest trip is short by (0 when it fits). */
export const overBy = (line: Pick<TodayLine, 'over' | 'bus_capacity'>) =>
  line.bus_capacity ? Math.max(0, ...line.over.map((t) => t.riders - line.bus_capacity!)) : 0;

/** «الفصل الأول والثاني معروضان للبيع الآن». */
export function onSaleText(names: string[] | null): string {
  if (names == null) return 'المواعيد وما يُعرض للبيع';
  const short = names.map((n) => n.replace(/\s*الدراسي\s*/, ' ').trim());
  if (short.length === 0) return 'لا يُعرض أي فصل للبيع الآن';
  const joined = short.every((n) => n.startsWith('الفصل '))
    ? `الفصل ${short.map((n) => n.slice('الفصل '.length)).join(' و')}`
    : short.join(' و');
  return `${joined} ${short.length === 1 ? 'معروض' : short.length === 2 ? 'معروضان' : 'معروضة'} للبيع الآن`;
}

// ── What waits ──────────────────────────────────────────────────────
export interface Attention { key: string; count?: number; icon?: IconName; tone: Tone; title: string; sub: string; action: string; to: string }

/** «7 إيصالات تنتظر مراجعتك». */
function receiptsTitle(n: number) {
  if (n === 1) return 'إيصال ينتظر مراجعتك';
  if (n === 2) return 'إيصالان ينتظران مراجعتك';
  return `${countText(n, NOUN.receipt)} تنتظر مراجعتك`;
}
/** «طالبان نسيا كلمة المرور». */
export function forgotTitle(n: number) {
  if (n === 1) return 'طالب نسي كلمة المرور';
  if (n === 2) return 'طالبان نسيا كلمة المرور';
  return `${countText(n, NOUN.student)} نسوا كلمة المرور`;
}
const someOf = (n: number) => (n === 1 ? 'واحد' : n === 2 ? 'اثنان' : num(n));
export const names = (list: string[], max = 3) => (list.length <= max ? list.join(' · ') : `${list.slice(0, max).join(' · ')} و${countText(list.length - max, ['آخر', 'آخران', 'أخرى', 'أخرى'])}`);

/**
 * The company's «يحتاج منك الآن», in the order of the board: what blocks money
 * first, then receipts, lines without a supervisor, lines students cannot
 * see, trips over the bus. Password requests are the platform's (platformToday).
 */
export function companyAttention(d: CompanyToday, o: { base: string; now?: Date }): Attention[] {
  const out: Attention[] = [];
  const { base } = o;
  const live = d.lines.filter((l) => l.is_active);
  if (d.setup.payment_methods === 0 && d.setup.lines > 0) {
    out.push({ key: 'pay', icon: 'card', tone: 'danger', title: 'لا توجد وسيلة دفع مفعّلة', sub: 'لا يستطيع الطلاب أن يدفعوا ثمن الاشتراك حتى تضيف واحدة', action: 'أضف وسيلة دفع', to: `${base}/payment-methods` });
  }
  const r = d.receipts;
  if (r.waiting > 0) {
    const parts = [r.waiting === 1 ? agoText(r.oldest_at, o.now) : oldestText(r.oldest_at, o.now)];
    if (r.last_attempt) parts.push(r.waiting === 1 ? 'في آخر محاولة' : `${someOf(r.last_attempt)} منها في آخر محاولة`);
    out.push({ key: 'receipts', count: r.waiting, tone: 'warning', title: receiptsTitle(r.waiting), sub: parts.filter(Boolean).join(' · ') || 'راجعها ليبدأ اشتراك أصحابها', action: 'راجع الإيصالات', to: `${base}/receipts` });
  }
  const alone = live.filter((l) => l.supervisors.length === 0);
  if (alone.length === 1) {
    out.push({ key: 'nosup', icon: 'scan', tone: 'danger', title: `خط ${alone[0].name} بلا مشرف`, sub: 'لا أحد يسجّل ركابه عند الصعود', action: 'عيّن مشرفاً', to: `${base}/supervisors` });
  } else if (alone.length > 1) {
    out.push({ key: 'nosup', icon: 'scan', tone: 'danger', title: `${countText(alone.length, NOUN.line)} بلا مشرف`, sub: names(alone.map((l) => l.name)), action: 'عيّن مشرفين', to: `${base}/supervisors` });
  }
  // A line stopped on purpose is not a problem to fix; one students cannot see by mistake is.
  const hidden = live.filter((l) => l.visible === false);
  if (hidden.length === 1) {
    const fix = hiddenFix(hidden[0], base);
    out.push({ key: 'hidden', icon: 'route', tone: 'danger', title: `خط ${hidden[0].name} لا يظهر للطلاب`, sub: hiddenText(hidden[0]), action: fix.action, to: fix.to });
  } else if (hidden.length > 1) {
    out.push({ key: 'hidden', icon: 'route', tone: 'danger', title: `${countText(hidden.length, NOUN.line)} لا ${hidden.length === 2 ? 'يظهران' : 'تظهر'} للطلاب`, sub: names(hidden.map((l) => l.name)), action: 'اعرض الخطوط', to: `${base}/lines` });
  }
  const over = d.lines.flatMap((l) => l.over.map((t) => ({ line: l, trip: t })));
  if (over.length === 1) {
    const { line, trip } = over[0];
    out.push({
      key: 'over', icon: 'bus', tone: 'warning',
      title: `رحلة ${trip.direction === 'return' ? 'عودة ' : ''}${line.name} ${clock(trip.time)} أكبر من الباص`,
      sub: `${countText(trip.riders, NOUN.rider)} أكّدوا والباص ${countText(line.bus_capacity ?? 0, NOUN.seat)}`,
      action: 'اعرض الرحلة', to: `${base}/lines/${line.id}`,
    });
  } else if (over.length > 1) {
    out.push({ key: 'over', icon: 'bus', tone: 'warning', title: `${countText(over.length, NOUN.trip)} أكبر من الباص`, sub: names(over.map(({ line, trip }) => `${line.name} ${clock(trip.time)}`)), action: 'اعرض الخطوط', to: `${base}/lines` });
  }
  return out;
}

/**
 * The first-run page instead of a page of zeros: while a step that must come
 * before a first subscription is missing and nobody has subscribed yet.
 */
export const isFirstRun = (d: CompanyToday) =>
  d.subscribers === 0 && d.members === 0 && (d.setup.lines === 0 || d.setup.payment_methods === 0 || d.setup.supervisors === 0);

export type SetupState = 'done' | 'current' | 'todo';
/** The three steps of «تجهيز الشركة»: the first one not done is current. */
export function setupSteps(d: CompanyToday): { line: SetupState; pay: SetupState; sup: SetupState; done: number } {
  const done = [d.setup.lines > 0, d.setup.payment_methods > 0, d.setup.supervisors > 0];
  const cur = done.indexOf(false);
  const st = (i: number): SetupState => (done[i] ? 'done' : i === cur ? 'current' : 'todo');
  return { line: st(0), pay: st(1), sup: st(2), done: done.filter(Boolean).length };
}

/** Why students still cannot subscribe ('' when they can). */
export function cannotSubscribeText(d: CompanyToday): string {
  if (d.setup.lines === 0) return 'لا يوجد خط يشتركون فيه بعد.';
  const visible = d.lines.some((l) => l.visible !== false && l.is_active);
  if (!visible) {
    const first = d.lines.find((l) => l.is_active) ?? d.lines[0];
    return `خطك لا يظهر لهم في التطبيق بعد: ${hiddenText(first)}.`;
  }
  if (d.setup.payment_methods === 0) return 'خطك يظهر لهم في التطبيق، لكن لا توجد وسيلة يدفعون بها.';
  return '';
}

