import { describe, expect, it } from 'vitest';
import {
  academicYearOf, breakdownFromRows, cellView, contrast, dayProblem, emptyMethod, groups4, ibanChecksumOk, labelColorFor,
  linesWord, methodErrors, methodRow, moved, namesList, optionView, problemSentence, termProblems, termRange, textToneFor,
  unsavedTitle, type Term,
} from './money';
import type { SaleRow } from './saleOptions';

const term = (code: Term['code'], sort: number, sm: number, sd: number, em: number, ed: number, so = 0, eo = 0): Term => ({
  code, name: { first: 'الفصل الأول', second: 'الفصل الثاني', summer: 'الفصل الصيفي' }[code], sort_order: sort,
  start_month: sm, start_day: sd, start_year_offset: so, end_month: em, end_day: ed, end_year_offset: eo, included_in_annual: code !== 'summer', is_on_sale: true,
});
const TERMS = [term('first', 1, 9, 26, 1, 21, 0, 1), term('second', 2, 2, 6, 6, 3, 1, 1), term('summer', 3, 7, 3, 9, 2, 1, 1)];

describe('term dates', () => {
  it('places each edge in its calendar year', () => {
    expect(termRange(TERMS[0], 2026)).toEqual({ start: '2026-09-26', end: '2027-01-21' });
  });
  it('accepts the usual calendar', () => {
    expect(termProblems(TERMS, 2026)).toEqual({});
  });
  it('refuses a day the month does not have, in every year (29 February too)', () => {
    expect(dayProblem(6, 31)).toBe('يونيو 30 يوماً فقط');
    expect(dayProblem(2, 29)).toBe('فبراير 28 يوماً فقط');
    expect(dayProblem(2, 0)).toBe('اكتب اليوم.');
  });
  it('says a term starts before the previous one ended, under its start', () => {
    const terms = [TERMS[0], term('second', 2, 1, 20, 6, 3, 1, 1), { ...TERMS[2], end_day: 31, end_month: 6 }];
    const p = termProblems(terms, 2026);
    expect(p.second.start).toBe('يبدأ قبل نهاية الفصل الأول');
    expect(p.summer.end).toBe('يونيو 30 يوماً فقط');
    expect(problemSentence(p, terms)).toBe('الفصل الثاني يبدأ قبل نهاية الأول، ونهاية الفصل الصيفي ليست يوماً صحيحاً.');
  });
  it('says an end before its start', () => {
    expect(termProblems([term('first', 1, 9, 26, 9, 1, 0, 0)], 2026).first.end).toBe('ينتهي قبل أن يبدأ');
  });
  it('shows the academic year whose periods have not ended', () => {
    expect(academicYearOf([{ academic_year: 2025, end_date: '2026-09-02' }, { academic_year: 2026, end_date: '2027-01-21' }], '2026-10-10')).toBe(2026);
    expect(academicYearOf([], '2027-03-01')).toBe(2026);
  });
  it('counts unsaved changes in Arabic', () => {
    expect(unsavedTitle(1)).toBe('تغيير واحد لم يُحفظ بعد');
    expect(unsavedTitle(2)).toBe('تغييران لم يُحفظا بعد');
    expect(unsavedTitle(4)).toBe('4 تغييرات لم تُحفظ بعد');
  });
});

const row = (option: SaleRow['option'], o: Partial<SaleRow> = {}): SaleRow => ({
  option, label: '', phase: 'current', price: 4500, available: true, reason: null, start_date: '2026-09-26', end_date: '2027-01-21', ...o,
});
describe('what students see', () => {
  const preview = [
    { line_id: 'a', line: 'أ', is_active: true, options: [row('first'), row('second', { phase: 'upcoming', start_date: '2027-02-06' })] },
    { line_id: 'b', line: 'ب', is_active: true, options: [row('first'), row('second', { available: false, reason: 'no_price' })] },
    { line_id: 'c', line: 'ج', is_active: false, options: [row('first', { available: false, reason: 'line_inactive' })] },
  ];
  it('counts the lines that sell an option now or ahead', () => {
    expect(optionView('first', preview)).toMatchObject({ label: 'يُباع الآن', sub: 'في خطين من 3', tone: 'success' });
    expect(optionView('second', preview)).toMatchObject({ label: 'يُباع مقدماً', sub: 'في خط واحد من 3 · يبدأ 6 فبراير', tone: 'teal' });
  });
  it('says why a hidden option is hidden', () => {
    const off = [{ line_id: 'a', line: 'أ', is_active: true, options: [row('summer', { available: false, reason: 'company_not_selling' })] }];
    expect(optionView('summer', off)).toMatchObject({ label: 'لا يظهر للطلاب', sub: 'لا يبيعه أي خط' });
    const ahead = [{ line_id: 'a', line: 'أ', is_active: true, options: [row('second', { available: false, reason: 'advance_off', start_date: '2027-02-06' })] }];
    expect(optionView('second', ahead).sub).toBe('يبدأ 6 فبراير، والدفع المسبق متوقف');
    expect(optionView('first', []).sub).toBe('لا توجد خطوط بعد');
  });
  it('words each line cell as the board does', () => {
    expect(cellView(row('first'))).toEqual({ price: 4500, ahead: false });
    expect(cellView(row('both', { available: false, reason: 'no_price' }))).toEqual({ reason: 'بلا سعر', warn: true });
    expect(cellView(row('both', { available: false, reason: 'line_not_offering' })).reason).toBe('متوقف في هذا الخط');
  });
  it('names line counts', () => {
    expect([1, 2, 7, 12].map(linesWord)).toEqual(['خط واحد', 'خطين', '7 خطوط', '12 خطاً']);
  });
});

describe('payment methods', () => {
  const base = { ...emptyMethod(), display_name: 'فودافون كاش', account_holder: 'سامح فتحي البنا' };
  it('checks a wallet number: 11 digits starting with 01', () => {
    expect(methodErrors({ ...base, method_type: 'vodafone_cash', wallet_phone: '010 2345 67' }).wallet_phone).toBe('الرقم ناقص. اكتب 11 رقماً تبدأ بـ 01.');
    expect(methodErrors({ ...base, method_type: 'vodafone_cash', wallet_phone: '٠١٠٢٣٤٥٦٧٨٩' }).wallet_phone).toBeUndefined();
    expect(methodErrors({ ...base, method_type: 'vodafone_cash', wallet_phone: '0223456789' }).wallet_phone).toBe('رقم المحفظة يبدأ بـ 01.');
  });
  it('checks an InstaPay address', () => {
    expect(methodErrors({ ...base, instapay_address: 'elnawras@instapay' }).instapay_address).toBeUndefined();
    expect(methodErrors({ ...base, instapay_address: 'elnawras' }).instapay_address).toMatch(/name@instapay/);
    expect(methodErrors({ ...base, instapay_address: '01001234567' }).instapay_address).toBeUndefined();
  });
  it('checks a bank account and its IBAN (EG + 27, with its check digits)', () => {
    const bank = { ...base, method_type: 'bank' as const, bank_name: 'البنك الأهلي المصري', bank_account_number: '1234 5678 9012' };
    expect(methodErrors({ ...bank, iban: 'EG38 0019 0005 0000 0000 2631 8000 2' })).toEqual({});
    expect(ibanChecksumOk('EG380019000500000000263180002')).toBe(true);
    expect(methodErrors({ ...bank, iban: 'EG380019000500000000263180003' }).iban).toMatch(/غير صحيح/);
    expect(methodErrors({ ...bank, iban: 'EG3800190005' }).iban).toMatch(/27 رقماً/);
    expect(methodErrors({ ...bank, iban: 'SA0380000000608010167519' }).iban).toMatch(/يبدأ بـ EG/);
    expect(methodErrors({ ...bank, bank_account_number: '12ab' }).bank_account_number).toBe('رقم الحساب أرقام فقط.');
  });
  it('requires a name and a holder', () => {
    const e = methodErrors({ ...emptyMethod(), instapay_address: 'a@instapay' });
    expect(e.display_name).toBeTruthy();
    expect(e.account_holder).toBeTruthy();
  });
  it('stores only the chosen type, cleaned', () => {
    const r = methodRow({ ...base, method_type: 'vodafone_cash', wallet_phone: '010 2345 6789', instapay_address: 'x@instapay', iban: 'EG..' });
    expect(r).toMatchObject({ wallet_phone: '01023456789', instapay_address: null, iban: null, bank_name: null });
    expect(methodRow({ ...base, method_type: 'bank', iban: 'eg38 0019 0005 0000 0000 2631 8000 2', bank_account_number: '12 34' }))
      .toMatchObject({ iban: 'EG380019000500000000263180002', bank_account_number: '1234' });
  });
  it('moves a method and lists names', () => {
    expect(moved(['a', 'b', 'c'], 2, 0)).toEqual(['c', 'a', 'b']);
    expect(moved(['a', 'b'], 0, 5)).toEqual(['a', 'b']);
    expect(namesList(['أ', 'ب', 'ج'])).toBe('أ، ب وج');
    expect(groups4('1234567890123456')).toBe('1234 5678 9012 3456');
  });
});

describe('revenue counted here when the database cannot', () => {
  it('adds up by subscription, line and method', () => {
    const rows = [
      { id: '1', line: 'شربين', period: 'first', type: 'termly', status: 'active', phase: 'current', paid: true, amount: 4500, payment_method: 'إنستاباي' },
      { id: '2', line: 'شربين', period: 'daily', type: 'daily', status: 'active', phase: 'current', paid: true, amount: 60, payment_method: null },
      { id: '3', line: 'الزرقا', period: 'both', type: 'yearly', status: 'active', phase: 'current', paid: true, amount: 8000, payment_method: 'إنستاباي' },
      { id: '4', line: 'الزرقا', period: 'second', type: 'termly', status: 'active', phase: 'upcoming', paid: true, amount: 4500, payment_method: null },
    ];
    const b = breakdownFromRows(rows, { revenue: 17060, paid: 4 }, ['كفر سعد']);
    expect(b.by_line.map((l) => [l.name, l.amount])).toEqual([['الزرقا', 12500], ['شربين', 4560], ['كفر سعد', 0]]);
    expect(b.by_method.map((m) => [m.kind, m.amount])).toEqual([['method', 12500], ['none', 4500], ['cash', 60]]);
    expect(b.by_option.find((o) => o.option === 'second')).toMatchObject({ amount: 4500, upcoming_paid: 1 });
    expect(b.totals.daily_paid).toBe(1);
  });
});

describe('card colours', () => {
  it('picks readable writing and a quieter heading shade', () => {
    expect(textToneFor('#0B6B4C')).toBe('light');
    expect(textToneFor('#EFE5D3')).toBe('dark');
    expect(labelColorFor('#FFFFFF', '#000000')).toBe('#A6A6A6');
    expect(contrast('#FFFFFF', '#000000')).toBeCloseTo(21, 0);
  });
});

import { counted, currentReset, rowStatus, SUBS } from './reports';
describe('revenue words', () => {
  it('counts as the boards do', () => {
    expect([1, 2, 5, 180, 300].map((n) => counted(n, SUBS))).toEqual(['اشتراك واحد', 'اشتراكان', '5 اشتراكات', '180 اشتراكاً', '300 اشتراك']);
  });
  it('maps report rows to the six statuses', () => {
    expect(rowStatus({ status: 'active', phase: 'upcoming', paid: true })).toBe('soon');
    expect(rowStatus({ status: 'pending_review', phase: 'current', paid: false })).toBe('review');
    expect(rowStatus({ status: 'active', phase: 'expired', paid: true })).toBe('ended');
  });
  it('finds the reset in force and the one before', () => {
    const r = (id: string, at: string, undone = false) => ({ id, scope: 'financial' as const, reset_at: at, note: null, undone_at: undone ? at : null });
    const { current, before } = currentReset([r('a', '2026-02-07'), r('b', '2026-09-01'), r('c', '2026-06-14', true)]);
    expect([current?.id, before?.id]).toEqual(['b', 'a']);
  });
});
