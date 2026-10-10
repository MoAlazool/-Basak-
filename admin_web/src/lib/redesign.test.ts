import { describe, expect, it } from 'vitest';
import {
  compareVersions, draftChanged, draftFromRow, draftProblem, filledLines, toSave, versionParts, type AppVersionRow,
} from './appVersions';
import { capacityText, parseBusCapacity } from './lineCapacity';
import { toPendingRow, type ReceiptAnswerRow } from './pendingReceipts';
import { studyLine } from './students';

const saved: AppVersionRow = {
  platform: 'ios', min_version: '2.3.0', latest_version: '2.5.0', whats_new: ['دخول أسرع بالبصمة', 'ملخّص الترم'],
  store_url: 'https://apps.apple.com/app/id1',
};

describe('app versions', () => {
  it('reads a version as up to three numbers', () => {
    expect(versionParts('2.5.1')).toEqual([2, 5, 1]);
    expect(versionParts(' 2.5 ')).toEqual([2, 5, 0]);
    expect(versionParts('3')).toEqual([3, 0, 0]);
    for (const bad of ['', 'v2', '2.5.1.4', '2..5', '2.5-beta', '٢.٥', '2.']) expect(versionParts(bad)).toBeNull();
  });
  it('compares number by number, not as text', () => {
    expect(compareVersions('2.9.0', '2.10.0')).toBeLessThan(0);
    expect(compareVersions('2.10', '2.9.9')).toBeGreaterThan(0);
    expect(compareVersions('2.5', '2.5.0')).toBe(0);
    expect(compareVersions('10.0.0', '9.99.99')).toBeGreaterThan(0);
  });
  it('shows a saved row as a form of three lines, and a missing row as 0.0.0', () => {
    expect(draftFromRow(saved)).toEqual({
      minVersion: '2.3.0', latestVersion: '2.5.0', whatsNew: ['دخول أسرع بالبصمة', 'ملخّص الترم', ''],
      storeUrl: 'https://apps.apple.com/app/id1',
    });
    expect(draftFromRow(undefined)).toEqual({ minVersion: '0.0.0', latestVersion: '0.0.0', whatsNew: ['', '', ''], storeUrl: '' });
    expect(draftFromRow({ ...saved, whats_new: null, store_url: null })).toMatchObject({ whatsNew: ['', '', ''], storeUrl: '' });
    expect(draftFromRow({ ...saved, whats_new: ['1', '2', '3', '4'] }).whatsNew).toEqual(['1', '2', '3']);
  });
  it('accepts a form that follows the rules', () => {
    expect(draftProblem(draftFromRow(saved))).toBeNull();
    expect(draftProblem(draftFromRow(undefined))).toBeNull();
    expect(draftProblem({ ...draftFromRow(saved), minVersion: '2.5.0' })).toBeNull();
  });
  it('says what is wrong with one that does not', () => {
    const draft = draftFromRow(saved);
    expect(draftProblem({ ...draft, latestVersion: 'latest' })).toMatch(/رقم الإصدار/);
    expect(draftProblem({ ...draft, minVersion: '2.10.0', latestVersion: '2.9.0' })).toMatch(/أقل إصدار/);
    expect(draftProblem({ ...draft, whatsNew: ['س'.repeat(121), '', ''] })).toMatch(/طويل/);
    expect(draftProblem({ ...draft, whatsNew: ['س'.repeat(120), '', ''] })).toBeNull();
    expect(draftProblem({ ...draft, storeUrl: 'http://example.com' })).toMatch(/https/);
    expect(draftProblem({ ...draft, storeUrl: 'apps.apple.com/app' })).toMatch(/https/);
    expect(draftProblem({ ...draft, storeUrl: '' })).toBeNull();
  });
  it('sends trimmed values, without empty lines, and no link as null', () => {
    expect(toSave('android', { minVersion: ' 1.0.0 ', latestVersion: '1.2', whatsNew: ['  أول ', '   ', 'ثانٍ'], storeUrl: '  ' })).toEqual({
      p_platform: 'android', p_min_version: '1.0.0', p_latest_version: '1.2', p_whats_new: ['أول', 'ثانٍ'], p_store_url: null,
    });
    expect(filledLines(['', ' ', ''])).toEqual([]);
  });
  it('knows when there is something to save', () => {
    const draft = draftFromRow(saved);
    expect(draftChanged(draft, saved)).toBe(false);
    expect(draftChanged({ ...draft, minVersion: ' 2.3.0 ', whatsNew: ['دخول أسرع بالبصمة ', '', 'ملخّص الترم'] }, saved)).toBe(false);
    expect(draftChanged({ ...draft, latestVersion: '2.6.0' }, saved)).toBe(true);
    expect(draftChanged({ ...draft, whatsNew: ['دخول أسرع بالبصمة', '', ''] }, saved)).toBe(true);
    expect(draftChanged({ ...draft, storeUrl: '' }, saved)).toBe(true);
    expect(draftChanged(draftFromRow(undefined), undefined)).toBe(false);
  });
});

describe('the bus capacity of a line', () => {
  it('reads an empty field as "not set"', () => {
    expect(parseBusCapacity('')).toEqual({ ok: true, value: null });
    expect(parseBusCapacity('   ')).toEqual({ ok: true, value: null });
  });
  it('reads a whole number from 1 to 500, in either kind of digits', () => {
    expect(parseBusCapacity('50')).toEqual({ ok: true, value: 50 });
    expect(parseBusCapacity(' ٥٠ ')).toEqual({ ok: true, value: 50 });
    expect(parseBusCapacity('1')).toEqual({ ok: true, value: 1 });
    expect(parseBusCapacity('500')).toEqual({ ok: true, value: 500 });
  });
  it('refuses zero, negatives, fractions, words and anything above 500', () => {
    for (const bad of ['0', '-5', '12.5', 'خمسون', '501', '1e2']) expect(parseBusCapacity(bad).ok).toBe(false);
  });
  it('shows a saved capacity in the field, and nothing when there is none', () => {
    expect(capacityText(50)).toBe('50');
    expect(capacityText(null)).toBe('');
    expect(capacityText(undefined)).toBe('');
  });
});

describe('the specialisation of a student on the dashboard', () => {
  const receipt = (patch: Partial<ReceiptAnswerRow> = {}): ReceiptAnswerRow => ({
    id: 'r1', image_url: 'c/s/r.jpg', attempt_number: 1, created_at: '2026-10-01T08:00:00Z', amount: 3500, subscription_id: 's1',
    student_id: 'st1', student_name: 'أحمد محمد علي', student_phone: '01000000000', university: 'جامعة المنصورة', college: 'الهندسة',
    company_id: 'c1', company_name: 'شركة', line_name: 'خط ١', station_name: 'المحطة', departure_time: null, return_time: null,
    subscription_type: 'termly', period_label: null, period_start: null, period_end: null, period_phase: null, price: 3000,
    ...patch,
  });
  it('follows the college, separated by a dot', () => {
    expect(studyLine('الهندسة', 'مدني')).toBe('الهندسة • مدني');
    expect(studyLine('الهندسة', '  ')).toBe('الهندسة');
    expect(studyLine('الهندسة', null)).toBe('الهندسة');
    expect(studyLine('الهندسة', undefined)).toBe('الهندسة');
  });
  it('stands alone when no college was chosen', () => {
    expect(studyLine('غير محدد', 'محاسبة')).toBe('محاسبة');
    expect(studyLine('', 'محاسبة')).toBe('محاسبة');
  });
  it('leaves the placeholder when there is neither', () => {
    expect(studyLine('غير محدد', null, 'الكلية غير محددة')).toBe('الكلية غير محددة');
    expect(studyLine(null, undefined)).toBe('');
  });
  it('is carried by a pending receipt, and is empty from a database that does not have it yet', () => {
    expect(toPendingRow(receipt({ specialisation: ' مدني ' })).specialisation).toBe('مدني');
    expect(toPendingRow(receipt({ specialisation: null })).specialisation).toBe('');
    expect(toPendingRow(receipt()).specialisation).toBe('');
  });
});
