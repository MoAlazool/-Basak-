/**
 * Pure logic of the money pages (docs/admin-redesign · «مواعيد الاشتراك»,
 * «وسائل الدفع», «الإيرادات», «بطاقة الطالب»): term dates and their checks,
 * what students see for each option, payment-method fields and their checks,
 * the revenue breakdown when the database cannot count it yet, and the card's
 * colours. Nothing here touches the network or React.
 */
import { dayText } from '../ui/format';
import type { SaleOption, SaleRow } from './saleOptions';

// ───────────────────────────────────────────────────────── term dates ────

export type TermCode = 'first' | 'second' | 'summer';
export interface Term {
  code: TermCode; name: string; sort_order: number;
  start_month: number; start_day: number; start_year_offset: number;
  end_month: number; end_day: number; end_year_offset: number;
  included_in_annual: boolean; is_on_sale: boolean; is_active?: boolean;
}

export const MONTHS = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
/** Days a month may have in EVERY year (the database checks leap and common years alike, so 29 February is refused). */
export const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

const pad = (n: number) => String(n).padStart(2, '0');
const iso = (y: number, m: number, d: number) => `${y}-${pad(m)}-${pad(d)}`;

/** A term's start and end as calendar days in the academic year that starts in `year`. */
export function termRange(t: Pick<Term, 'start_month' | 'start_day' | 'start_year_offset' | 'end_month' | 'end_day' | 'end_year_offset'>, year: number) {
  return {
    start: iso(year + (t.start_year_offset ?? 0), t.start_month, t.start_day),
    end: iso(year + (t.end_year_offset ?? 0), t.end_month, t.end_day),
  };
}

/** «20 سبتمبر 2026» for a term edge (day + month + the year it falls in). */
export const termDayText = (year: number, month: number, day: number, withYear = true) => dayText(iso(year, month, day), { year: withYear });

/** The academic year on screen: the earliest year whose periods have not all ended. */
export function academicYearOf(periods: { academic_year: number; end_date: string }[] | null | undefined, today: string): number {
  const open = (periods ?? []).filter((p) => p.end_date >= today).map((p) => p.academic_year);
  if (open.length) return Math.min(...open);
  const y = Number(today.slice(0, 4));
  return Number(today.slice(5, 7)) >= 8 ? y : y - 1;
}

export interface EdgeProblem { start?: string; end?: string }
/** A day that exists in that month in every year ('' = fine). */
export function dayProblem(month: number, day: number): string {
  if (!Number.isInteger(day) || day < 1) return 'اكتب اليوم.';
  if (!Number.isInteger(month) || month < 1 || month > 12) return 'اختر الشهر.';
  if (day > MONTH_DAYS[month - 1]) return `${MONTHS[month - 1]} ${MONTH_DAYS[month - 1]} يوماً فقط`;
  return '';
}

const shortName = (name: string) => name.replace(/^الفصل\s+/, '');

/**
 * What is wrong with the dates, under the field it belongs to: a day that does
 * not exist, an end before its start, a term that starts before the one before
 * it ended. The database checks the same and refuses the save.
 */
export function termProblems(terms: Term[], year: number): Record<string, EdgeProblem> {
  const out: Record<string, EdgeProblem> = {};
  const set = (code: string, edge: 'start' | 'end', text: string) => { out[code] = { ...out[code], [edge]: out[code]?.[edge] ?? text }; };
  const ordered = [...terms].filter((t) => t.is_active !== false).sort((a, b) => a.sort_order - b.sort_order);
  let prev: { term: Term; end: string } | null = null;
  for (const t of ordered) {
    const s = dayProblem(t.start_month, t.start_day);
    const e = dayProblem(t.end_month, t.end_day);
    if (s) set(t.code, 'start', s);
    if (e) set(t.code, 'end', e);
    if (s || e) { prev = null; continue; }
    const r = termRange(t, year);
    if (r.end <= r.start) set(t.code, 'end', 'ينتهي قبل أن يبدأ');
    else if (prev && r.start <= prev.end) set(t.code, 'start', `يبدأ قبل نهاية ${prev.term.name}`);
    prev = { term: t, end: r.end };
  }
  return out;
}

/** One sentence for the red note on top: «الفصل الثاني يبدأ قبل نهاية الأول، ونهاية الفصل الصيفي ليست يوماً صحيحاً.» */
export function problemSentence(problems: Record<string, EdgeProblem>, terms: Term[]): string {
  const parts: string[] = [];
  const ordered = [...terms].sort((a, b) => a.sort_order - b.sort_order);
  ordered.forEach((t, i) => {
    const p = problems[t.code];
    if (!p) return;
    if (p.start?.startsWith('يبدأ قبل نهاية')) {
      const before = ordered.slice(0, i).reverse().find((x) => p.start!.endsWith(x.name));
      parts.push(`${t.name} يبدأ قبل نهاية ${before ? shortName(before.name) : 'الفصل السابق'}`);
    } else if (p.start) parts.push(`بداية ${t.name} ليست يوماً صحيحاً`);
    if (p.end === 'ينتهي قبل أن يبدأ') parts.push(`${t.name} ينتهي قبل أن يبدأ`);
    else if (p.end) parts.push(`نهاية ${t.name} ليست يوماً صحيحاً`);
  });
  if (!parts.length) return '';
  return `${parts.slice(0, -1).join('، ')}${parts.length > 1 ? '، و' : ''}${parts[parts.length - 1]}.`;
}

export const problemCount = (problems: Record<string, EdgeProblem>) =>
  Object.values(problems).reduce((n, p) => n + (p.start ? 1 : 0) + (p.end ? 1 : 0), 0);

// ─────────────────────────────────────────────── what students see now ────

/** «في 7 خطوط من 8», «في خط واحد من 8». */
export function linesWord(n: number): string {
  if (n === 1) return 'خط واحد';
  if (n === 2) return 'خطين';
  if (n >= 3 && n <= 10) return `${n} خطوط`;
  return `${n.toLocaleString('en-US')} خطاً`;
}

export interface LinePreview { line_id: string; line: string; is_active: boolean; options: SaleRow[] | null }

export interface OptionView {
  /** success = sold now, teal = sold ahead, neutral = students do not see it. */
  tone: 'success' | 'teal' | 'neutral';
  label: string;
  sub: string;
  /** How many lines show it, and of how many. */
  lines: number; total: number;
}

/** Why an option is hidden for the whole company, in the board's words. */
const COMPANY_REASON: Record<string, string> = {
  company_not_selling: 'لا يبيعه أي خط',
  company_inactive: 'الشركة موقوفة',
  line_inactive: 'كل الخطوط متوقفة',
  line_not_offering: 'متوقف في كل الخطوط',
  no_price: 'لم يُكتب له سعر في أي خط',
};

/** The «ما يراه الطلاب الآن» cell of one option, from the saved preview. */
export function optionView(option: SaleOption, preview: LinePreview[], o: { platformOff?: boolean } = {}): OptionView {
  const total = preview.length;
  const rows = preview.map((l) => (l.options ?? []).find((x) => x.option === option)).filter(Boolean) as SaleRow[];
  const sold = rows.filter((r) => r.available);
  if (o.platformOff) return { tone: 'neutral', label: 'لا يظهر للطلاب', sub: 'أوقفته إدارة المنصة عند كل الشركات', lines: 0, total };
  if (total === 0) return { tone: 'neutral', label: 'لا يظهر للطلاب', sub: 'لا توجد خطوط بعد', lines: 0, total };
  if (sold.length) {
    const ahead = sold[0].phase === 'upcoming';
    const start = dayText(sold[0].start_date, { year: false });
    const sub = `في ${linesWord(sold.length)} من ${total}${ahead ? ` · يبدأ ${start}` : option === 'both' ? ' · حتى نهاية الفصل الأول' : ''}`;
    return { tone: ahead ? 'teal' : 'success', label: ahead ? 'يُباع مقدماً' : 'يُباع الآن', sub, lines: sold.length, total };
  }
  const first = rows[0];
  if (!first) return { tone: 'neutral', label: 'لا يظهر للطلاب', sub: 'ليس وقته الآن', lines: 0, total };
  const reasons = new Set(rows.map((r) => r.reason));
  const start = dayText(first.start_date, { year: false });
  let sub = '';
  if (reasons.has('company_not_selling')) sub = COMPANY_REASON.company_not_selling;
  else if (reasons.has('company_inactive')) sub = COMPANY_REASON.company_inactive;
  else if (reasons.has('advance_off')) sub = `يبدأ ${start}، والدفع المسبق متوقف`;
  else if (reasons.has('not_in_season')) sub = `يبدأ ${start}`;
  else if (reasons.size === 1) sub = COMPANY_REASON[first.reason ?? ''] ?? 'ليس وقته الآن';
  else sub = 'لا يُباع في أي خط';
  return { tone: 'neutral', label: 'لا يظهر للطلاب', sub, lines: 0, total };
}

/** One line's cell for one option: the price, or why students do not see it there. */
export function cellView(row: SaleRow | undefined): { price?: number; ahead?: boolean; reason?: string; warn?: boolean } {
  if (!row) return { reason: 'ليس وقته بعد' };
  if (row.available) return { price: Number(row.price ?? 0), ahead: row.phase === 'upcoming' };
  switch (row.reason) {
    case 'company_not_selling': return { reason: 'لا يبيعه أي خط' };
    case 'line_inactive': return { reason: 'الخط متوقف' };
    case 'line_not_offering': return { reason: 'متوقف في هذا الخط' };
    case 'no_price': return { reason: 'بلا سعر', warn: true };
    case 'advance_off': return { reason: 'الدفع المسبق متوقف' };
    case 'company_inactive': return { reason: 'الشركة موقوفة' };
    default: return { reason: 'ليس وقته بعد' };
  }
}

/** «تغيير واحد لم يُحفظ بعد», «تغييران لم يُحفظا بعد», «3 تغييرات لم تُحفظ بعد». */
export function unsavedTitle(n: number): string {
  if (n === 1) return 'تغيير واحد لم يُحفظ بعد';
  if (n === 2) return 'تغييران لم يُحفظا بعد';
  if (n <= 10) return `${n} تغييرات لم تُحفظ بعد`;
  return `${n} تغييراً لم يُحفظ بعد`;
}
/** «حفظ تغيير واحد…», «حفظ تغييرين…», «حفظ 3 تغييرات…». */
export function changesWord(n: number): string {
  if (n === 1) return 'تغيير واحد';
  if (n === 2) return 'تغييرين';
  if (n <= 10) return `${n} تغييرات`;
  return `${n} تغييراً`;
}

// ───────────────────────────────────────────────────── payment methods ────

export type MethodType = 'instapay' | 'vodafone_cash' | 'bank';
export const METHOD_TYPES: MethodType[] = ['instapay', 'vodafone_cash', 'bank'];
export const METHOD_LABEL: Record<MethodType, string> = { instapay: 'إنستاباي', vodafone_cash: 'فودافون كاش', bank: 'تحويل بنكي' };

export interface PaymentMethod {
  id: string; company_id: string; method_type: MethodType; display_name: string;
  account_holder: string | null; instapay_address: string | null; wallet_phone: string | null;
  bank_name: string | null; bank_account_number: string | null; iban: string | null;
  instructions: string | null; is_active: boolean; sort_order: number; created_at?: string;
}
export interface MethodDraft {
  id?: string; method_type: MethodType; display_name: string; account_holder: string; instapay_address: string;
  wallet_phone: string; bank_name: string; bank_account_number: string; iban: string; instructions: string; is_active: boolean;
}
export const INSTRUCTIONS_MAX = 300;
export const DISPLAY_NAME_MAX = 40;

export const emptyMethod = (): MethodDraft => ({
  method_type: 'instapay', display_name: '', account_holder: '', instapay_address: '', wallet_phone: '',
  bank_name: '', bank_account_number: '', iban: '', instructions: '', is_active: true,
});
export const methodToDraft = (m: PaymentMethod): MethodDraft => ({
  id: m.id, method_type: m.method_type, display_name: m.display_name, account_holder: m.account_holder ?? '',
  instapay_address: m.instapay_address ?? '', wallet_phone: m.wallet_phone ?? '', bank_name: m.bank_name ?? '',
  bank_account_number: groups4(m.bank_account_number ?? ''), iban: groups4(m.iban ?? ''), instructions: m.instructions ?? '', is_active: m.is_active,
});

/** Arabic or Persian digits typed on a phone keyboard, as Western digits. */
export const westernDigits = (s: string) => s.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
export const onlyDigits = (s: string) => westernDigits(s).replace(/\D/g, '');
export const normalizeIban = (s: string) => westernDigits(s).replace(/[\s-]/g, '').toUpperCase();
/** «1234567890123456» → «1234 5678 9012 3456». */
export const groups4 = (s: string) => s.replace(/\s/g, '').replace(/(.{4})(?=.)/g, '$1 ');

/** The IBAN's own check (ISO 13616, mod 97). */
export function ibanChecksumOk(iban: string): boolean {
  const s = normalizeIban(iban);
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]+$/.test(s)) return false;
  const moved = s.slice(4) + s.slice(0, 4);
  let rest = 0;
  for (const ch of moved) {
    const v = /\d/.test(ch) ? ch : String(ch.charCodeAt(0) - 55);
    for (const d of v) rest = (rest * 10 + Number(d)) % 97;
  }
  return rest === 1;
}

const INSTAPAY = /^[a-z0-9._-]{2,}@instapay$/i;

/** Errors under each field ('' fields are fine). The database checks the same essentials again. */
export function methodErrors(d: MethodDraft): Partial<Record<keyof MethodDraft, string>> {
  const e: Partial<Record<keyof MethodDraft, string>> = {};
  if (!d.display_name.trim()) e.display_name = 'اكتب الاسم الذي يراه الطالب.';
  else if (d.display_name.trim().length > DISPLAY_NAME_MAX) e.display_name = `الاسم أطول من ${DISPLAY_NAME_MAX} حرفاً.`;
  if (!d.account_holder.trim()) e.account_holder = 'اكتب اسم صاحب الحساب كما يظهر للطالب عند التحويل.';
  if (d.method_type === 'instapay') {
    const v = westernDigits(d.instapay_address.trim());
    const phone = onlyDigits(v);
    if (!v) e.instapay_address = 'اكتب عنوان إنستاباي.';
    else if (!INSTAPAY.test(v) && !(/^[\d\s+-]+$/.test(v) && /^01\d{9}$/.test(phone))) {
      e.instapay_address = 'اكتب العنوان كاملاً مثل name@instapay، أو رقم الهاتف المربوط به (11 رقماً).';
    }
  }
  if (d.method_type === 'vodafone_cash') {
    const p = onlyDigits(d.wallet_phone);
    if (!p) e.wallet_phone = 'اكتب رقم المحفظة.';
    else if (!p.startsWith('01')) e.wallet_phone = 'رقم المحفظة يبدأ بـ 01.';
    else if (p.length < 11) e.wallet_phone = 'الرقم ناقص. اكتب 11 رقماً تبدأ بـ 01.';
    else if (p.length > 11) e.wallet_phone = 'الرقم زائد. اكتب 11 رقماً تبدأ بـ 01.';
  }
  if (d.method_type === 'bank') {
    if (!d.bank_name.trim()) e.bank_name = 'اكتب اسم البنك.';
    const acc = westernDigits(d.bank_account_number).replace(/[\s-]/g, '');
    if (!acc) e.bank_account_number = 'اكتب رقم الحساب.';
    else if (!/^\d+$/.test(acc)) e.bank_account_number = 'رقم الحساب أرقام فقط.';
    else if (acc.length < 6 || acc.length > 30) e.bank_account_number = 'رقم الحساب بين 6 و30 رقماً.';
    const iban = normalizeIban(d.iban);
    if (iban) {
      if (!iban.startsWith('EG')) e.iban = 'رقم الآيبان المصري يبدأ بـ EG.';
      else if (iban.length !== 29 || !/^EG\d{27}$/.test(iban)) e.iban = `رقم الآيبان EG ثم 27 رقماً (كتبت ${Math.max(0, iban.length - 2)}).`;
      else if (!ibanChecksumOk(iban)) e.iban = 'رقم الآيبان غير صحيح. انسخه كما هو من كشف الحساب.';
    }
  }
  if (d.instructions.trim().length > INSTRUCTIONS_MAX) e.instructions = `التعليمات أطول من ${INSTRUCTIONS_MAX} حرفاً.`;
  return e;
}

/** The row to store: only the chosen type's fields, cleaned. */
export function methodRow(d: MethodDraft) {
  const clean = (v: string) => (v.trim() ? v.trim() : null);
  const insta = westernDigits(d.instapay_address.trim());
  return {
    method_type: d.method_type, display_name: d.display_name.trim(), account_holder: clean(d.account_holder),
    instapay_address: d.method_type === 'instapay' ? (INSTAPAY.test(insta) ? insta.toLowerCase() : onlyDigits(insta)) || null : null,
    wallet_phone: d.method_type === 'vodafone_cash' ? onlyDigits(d.wallet_phone) || null : null,
    bank_name: d.method_type === 'bank' ? clean(d.bank_name) : null,
    bank_account_number: d.method_type === 'bank' ? westernDigits(d.bank_account_number).replace(/[\s-]/g, '') || null : null,
    iban: d.method_type === 'bank' ? normalizeIban(d.iban) || null : null,
    instructions: clean(d.instructions), is_active: d.is_active,
  };
}

/** The account a student transfers to, as shown in lists. */
export function accountText(m: Pick<PaymentMethod, 'method_type' | 'instapay_address' | 'wallet_phone' | 'bank_account_number' | 'iban'>): string {
  if (m.method_type === 'instapay') return m.instapay_address ?? '';
  if (m.method_type === 'vodafone_cash') {
    const p = m.wallet_phone ?? '';
    return /^01\d{9}$/.test(p) ? `${p.slice(0, 3)} ${p.slice(3, 7)} ${p.slice(7)}` : p;
  }
  return groups4(m.bank_account_number ?? '');
}

/** The methods as listed: by position, then as they were added. */
export const inOrder = <M extends { sort_order: number; created_at?: string }>(list: M[]) =>
  [...list].sort((a, b) => a.sort_order - b.sort_order || String(a.created_at ?? '').localeCompare(String(b.created_at ?? '')));

/** A new order after moving one method (`to` is its new index). */
export function moved<M>(list: M[], from: number, to: number): M[] {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) return list;
  const next = [...list];
  const [m] = next.splice(from, 1);
  next.splice(to, 0, m);
  return next;
}

/** «وسيلتان تعملان: إنستاباي النورس والبنك الأهلي المصري». */
export function namesList(names: string[]): string {
  if (names.length <= 1) return names[0] ?? '';
  return `${names.slice(0, -1).join('، ')} و${names[names.length - 1]}`;
}

/** «5 وسائل», «وسيلتان», «وسيلة واحدة». */
export function methodsWord(n: number): string {
  if (n === 1) return 'وسيلة واحدة';
  if (n === 2) return 'وسيلتان';
  if (n >= 3 && n <= 10) return `${n} وسائل`;
  return `${n} وسيلة`;
}

// ───────────────────────────────────────────────────────────── revenue ────

export type RevenueOption = 'both' | 'first' | 'second' | 'daily' | 'summer';
export const REVENUE_OPTIONS: RevenueOption[] = ['both', 'first', 'second', 'daily', 'summer'];
export const REVENUE_OPTION_LABEL: Record<RevenueOption, string> = {
  both: 'الفصلان معاً', first: 'الفصل الأول', second: 'الفصل الثاني', daily: 'اليومي (نقداً)', summer: 'الفصل الصيفي',
};

export interface Breakdown {
  baseline: string | null;
  totals: { count: number; paid: number; unpaid: number; in_review?: number; upcoming: number; upcoming_paid: number; daily_paid: number; revenue: number };
  by_option: { option: RevenueOption; paid: number; amount: number; upcoming: number; upcoming_paid: number }[];
  by_line: { line_id: string | null; name: string; is_active?: boolean; paid: number; amount: number }[];
  by_method: { kind: 'method' | 'cash' | 'none' | 'deleted'; method_id: string | null; name: string | null; method_type?: string | null; paid: number; amount: number }[];
}

/** A report row as the fallback needs it. */
export interface RevenueRow {
  id: string; line: string; period: string; type: string; status: string; phase: string; paid: boolean;
  amount: number | null; payment_method: string | null;
}

/**
 * The breakdown counted here, from the report's rows, for a database that does
 * not have company_revenue_breakdown yet. The rows are every paid subscription
 * (asked for with `payment: 'paid'`), so the sums are exact up to the report's
 * 2,000-row page; `totals` come from the report itself, which counts everything.
 */
export function breakdownFromRows(rows: RevenueRow[], totals: Partial<Breakdown['totals']> & { revenue: number; paid: number }, lineNames: string[] = []): Breakdown {
  const paid = rows.filter((r) => r.paid);
  const sum = (list: RevenueRow[]) => list.reduce((n, r) => n + Number(r.amount ?? 0), 0);
  const optionOf = (r: RevenueRow): RevenueOption => (r.type === 'daily' ? 'daily' : (r.period === 'annual' ? 'both' : r.period) as RevenueOption);
  const by_option = REVENUE_OPTIONS.map((option) => {
    const of = rows.filter((r) => optionOf(r) === option);
    const p = of.filter((r) => r.paid);
    return { option, paid: p.length, amount: sum(p), upcoming: of.filter((r) => r.phase === 'upcoming').length, upcoming_paid: p.filter((r) => r.phase === 'upcoming').length };
  });
  const lines = new Map<string, RevenueRow[]>();
  lineNames.forEach((n) => lines.set(n, []));
  paid.forEach((r) => lines.set(r.line, [...(lines.get(r.line) ?? []), r]));
  const by_line = [...lines.entries()].map(([name, list]) => ({ line_id: null, name, paid: list.length, amount: sum(list) }))
    .sort((a, b) => b.amount - a.amount || a.name.localeCompare(b.name, 'ar'));
  const methods = new Map<string, { kind: Breakdown['by_method'][number]['kind']; name: string | null; list: RevenueRow[] }>();
  paid.forEach((r) => {
    const kind = r.payment_method ? 'method' : r.type === 'daily' ? 'cash' : 'none';
    const key = `${kind}:${r.payment_method ?? ''}`;
    const known = methods.get(key) ?? { kind, name: r.payment_method, list: [] };
    known.list.push(r);
    methods.set(key, known);
  });
  const by_method = [...methods.values()].map((m) => ({ kind: m.kind, method_id: null, name: m.name, paid: m.list.length, amount: sum(m.list) }))
    .sort((a, b) => b.amount - a.amount);
  return {
    baseline: null,
    totals: {
      count: totals.count ?? rows.length, paid: totals.paid, unpaid: totals.unpaid ?? 0, upcoming: totals.upcoming ?? 0,
      upcoming_paid: totals.upcoming_paid ?? 0, daily_paid: by_option.find((o) => o.option === 'daily')!.paid, revenue: totals.revenue,
    },
    by_option, by_line, by_method,
  };
}

/** The share of the largest amount, for the bars (0–100). */
export const share = (amount: number, max: number) => (max > 0 ? Math.max(amount > 0 ? 2 : 0, Math.round((amount / max) * 100)) : 0);

// ───────────────────────────────────────────────────────── card colours ────

export const CARD_SWATCHES: { name: string; hex: string }[] = [
  { name: 'أزرق باصك', hex: '#00658D' }, { name: 'كحلي', hex: '#17384A' }, { name: 'أخضر', hex: '#0B6B4C' }, { name: 'نبيتي', hex: '#7A1E3A' },
  { name: 'بنفسجي', hex: '#4A3488' }, { name: 'برتقالي', hex: '#A8440F' }, { name: 'أسود', hex: '#1C1C1E' }, { name: 'رملي فاتح', hex: '#EFE5D3' },
];
export const TEXT_LIGHT = '#FFFFFF';
export const TEXT_DARK = '#17384A';
export const isHex = (v: string | null | undefined): v is string => !!v && /^#[0-9a-fA-F]{6}$/.test(v);

const channels = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
function luminance(hex: string): number {
  const [r, g, b] = channels(hex).map((c) => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
/** WCAG contrast ratio of two colours. */
export function contrast(a: string, b: string): number {
  const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m);
  return (x + 0.05) / (y + 0.05);
}
/** Light writing for dark cards, dark writing for light ones. */
export const textToneFor = (bg: string): 'light' | 'dark' => (contrast(bg, TEXT_LIGHT) >= contrast(bg, TEXT_DARK) ? 'light' : 'dark');
/** The small headings: the writing colour 35% of the way to the card colour (a quieter shade of the same). */
export function labelColorFor(fg: string, bg: string): string {
  const a = channels(fg); const b = channels(bg);
  return `#${a.map((c, i) => Math.round(c + (b[i] - c) * 0.35).toString(16).padStart(2, '0')).join('').toUpperCase()}`;
}
/** Writing that will not be read on this card (below 3:1). */
export const unreadable = (bg: string, fg: string) => contrast(bg, fg) < 3;
/** The swatch's name, or null for a colour of one's own. */
export const swatchName = (hex: string) => CARD_SWATCHES.find((s) => s.hex.toLowerCase() === hex.toLowerCase())?.name ?? null;
