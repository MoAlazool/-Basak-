import { describe, expect, it } from 'vitest';
import {
  isNewerReview, normalizeReceiptStoragePath, shouldTopUp, toPendingRow, withOptimisticPending, withPendingDelta, withReceipt, withoutReceipt,
  type PendingReceiptRow, type PendingReceipts, type ReceiptAnswerRow,
} from './pendingReceipts';
import { withSubscription, withoutStudent, type StudentsPageAnswer } from './students';
import { mergeReport, nextReportOffset, type ReportPart } from './reports';

const answer = (patch: Partial<ReceiptAnswerRow> = {}): ReceiptAnswerRow => ({
  id: 'r1', image_url: 'company/student/receipt.jpg', attempt_number: 2, created_at: '2026-10-01T08:00:00Z', amount: 3500,
  subscription_id: 's1', student_id: 'st1', student_name: 'أحمد محمد علي', student_phone: '01000000000',
  university: 'جامعة المنصورة', college: 'الهندسة', company_id: 'c1', company_name: 'شركة النقل', line_name: 'خط ١',
  station_name: 'المحطة', departure_time: '07:30:00', return_time: '15:00:00', subscription_type: 'termly',
  period_label: 'الفصل الأول 2026/2027', period_start: '2026-09-20', period_end: '2027-01-20', period_phase: 'current', price: 3000,
  ...patch,
});
const row = (id: string, createdAt: string): PendingReceiptRow => ({ ...toPendingRow(answer({ id, created_at: createdAt })) });
const list = (...rows: PendingReceiptRow[]): PendingReceipts => ({ rows, hasMore: false });

describe('a pending receipt as the table shows it', () => {
  it('takes every field from the server row', () => {
    expect(toPendingRow(answer())).toEqual({
      id: 'r1', subscriptionId: 's1', studentId: 'st1', studentName: 'أحمد محمد علي', studentPhone: '01000000000',
      university: 'جامعة المنصورة', college: 'الهندسة', specialisation: '', companyId: 'c1', companyName: 'شركة النقل', lineName: 'خط ١',
      stationName: 'المحطة', departureTime: '07:30', returnTime: '15:00', subscriptionType: 'termly',
      periodLabel: 'الفصل الأول 2026/2027', periodStart: '2026-09-20', periodEnd: '2027-01-20', periodPhase: 'current',
      price: 3500, imagePath: 'company/student/receipt.jpg', legacyImageUrl: null, attemptNumber: 2, createdAt: '2026-10-01T08:00:00Z',
    });
  });
  it('shows the amount paid, and the subscription price for an older receipt without one', () => {
    expect(toPendingRow(answer({ amount: '3500.00' })).price).toBe(3500);
    expect(toPendingRow(answer({ amount: null })).price).toBe(3000);
    expect(toPendingRow(answer({ amount: null, price: null })).price).toBe(0);
  });
  it('fills what is missing with placeholders instead of failing', () => {
    const shown = toPendingRow(answer({
      student_id: null, student_name: null, student_phone: null, university: null, college: 'غير محدد', company_name: null,
      line_name: null, station_name: null, departure_time: null, return_time: null, subscription_type: null, attempt_number: null, image_url: null,
    }));
    expect(shown).toMatchObject({
      studentId: '', studentName: 'بيانات الطالب غير متاحة', studentPhone: '—', university: '—', college: '', companyName: '—',
      lineName: '—', stationName: '—', departureTime: '', returnTime: '', subscriptionType: 'termly', attemptNumber: 1, imagePath: null,
    });
  });
  it('keeps a link to somewhere else only for very old rows', () => {
    expect(toPendingRow(answer({ image_url: 'https://old.example.com/a.jpg' }))).toMatchObject({ imagePath: null, legacyImageUrl: 'https://old.example.com/a.jpg' });
  });
});

describe('where a receipt image is stored', () => {
  it('accepts a plain storage path', () => {
    expect(normalizeReceiptStoragePath('c1/st1/a.jpg')).toBe('c1/st1/a.jpg');
    expect(normalizeReceiptStoragePath('/receipts/c1/a%20b.jpg?token=x')).toBe('c1/a b.jpg');
  });
  it('reads the path out of an older full link to the bucket', () => {
    expect(normalizeReceiptStoragePath('https://x.supabase.co/storage/v1/object/sign/receipts/c1/a.jpg?token=t')).toBe('c1/a.jpg');
    expect(normalizeReceiptStoragePath('storage/v1/object/public/receipts/c1/a.jpg')).toBe('c1/a.jpg');
  });
  it('refuses nothing, another site and a path that climbs out', () => {
    expect(normalizeReceiptStoragePath(null)).toBeNull();
    expect(normalizeReceiptStoragePath('   ')).toBeNull();
    expect(normalizeReceiptStoragePath('https://elsewhere.example.com/a.jpg')).toBeNull();
    expect(normalizeReceiptStoragePath('c1/../c2/a.jpg')).toBeNull();
  });
});

describe('what a decision does to the queue on screen', () => {
  const a = row('a', '2026-10-01T08:00:00Z');
  const b = row('b', '2026-10-01T09:00:00Z');
  const c = row('c', '2026-10-01T10:00:00Z');

  it('removes the reviewed receipt and nothing else', () => {
    expect(withoutReceipt(list(a, b, c), 'b')?.rows.map((r) => r.id)).toEqual(['a', 'c']);
  });
  it('returns the very same list when the receipt is not in it', () => {
    const before = list(a, c);
    expect(withoutReceipt(before, 'b')).toBe(before);
    expect(withoutReceipt(undefined, 'b')).toBeUndefined();
  });
  it('keeps whether more are waiting', () => {
    expect(withoutReceipt({ rows: [a, b], hasMore: true }, 'a')?.hasMore).toBe(true);
  });
  it('puts a refused decision back in its place, oldest first, once', () => {
    expect(withReceipt(list(a, c), b)?.rows.map((r) => r.id)).toEqual(['a', 'b', 'c']);
    const full = list(a, b, c);
    expect(withReceipt(full, b)).toBe(full);
  });
  it('moves the waiting number and never below zero', () => {
    expect(withPendingDelta({ pending_receipts: 3, revenue: 10 }, -1)).toEqual({ pending_receipts: 2, revenue: 10 });
    expect(withPendingDelta({ pending_receipts: 0 }, -1)).toEqual({ pending_receipts: 0 });
    expect(withPendingDelta({ pending_receipts: 2 }, +1)).toEqual({ pending_receipts: 3 });
    expect(withPendingDelta(undefined, -1)).toBeUndefined();
  });
  it('loads the next ones only when few are left and more are waiting', () => {
    expect(shouldTopUp({ rows: [a, b], hasMore: true })).toBe(true);
    expect(shouldTopUp({ rows: [a, b], hasMore: false })).toBe(false);
    expect(shouldTopUp({ rows: Array.from({ length: 10 }, (_, i) => row(String(i), '2026-10-01T08:00:00Z')), hasMore: true })).toBe(false);
    expect(shouldTopUp(undefined)).toBe(false);
  });
});

describe('what this page\'s own writes do to the students on screen', () => {
  const sub = (id: string, status: string) => ({
    id, status, type: 'termly', price: 3500, created_at: '2026-09-01T00:00:00Z', start_date: '2026-09-20', end_date: '2027-01-20',
    period_label: 'الفصل الأول', period_phase: 'current', departure_time: '07:30:00', return_time: null,
    line_name: 'خط ١', trip_label: null, trip_university: 'جامعة المنصورة',
  });
  const student = (id: string, ...subscriptions: ReturnType<typeof sub>[]) => ({
    id, phone: '010', full_name: `طالب ${id}`, university: 'جامعة', college: '', profile_image_url: null, created_at: '2026-09-01T00:00:00Z', subscriptions,
  });
  const page: StudentsPageAnswer = { rows: [student('x', sub('s1', 'pending_review'), sub('s2', 'expired')), student('y', sub('s3', 'active'))], has_next: true, total: 40 };

  it('changes one subscription to what the server answered', () => {
    const next = withSubscription(page, 's1', { status: 'active', period_phase: 'current' })!;
    expect(next.rows[0].subscriptions.map((s) => s.status)).toEqual(['active', 'expired']);
    expect(next.rows[0].subscriptions[0].line_name).toBe('خط ١');
    // Rows it does not touch keep their identity (they are not drawn again).
    expect(next.rows[1]).toBe(page.rows[1]);
    expect(next.total).toBe(40);
  });
  it('leaves a page alone when the subscription is not on it', () => {
    expect(withSubscription(page, 'nope', { status: 'active' })).toBe(page);
  });
  it('removes a student who left the company', () => {
    expect(withoutStudent(page, 'x')?.rows.map((s) => s.id)).toEqual(['y']);
    expect(withoutStudent(page, 'nope')).toBe(page);
    expect(withoutStudent(undefined, 'x')).toBeUndefined();
  });
});

describe('answers to decisions taken close together', () => {
  it('apply in the order the decisions were saved, not the order they arrive', () => {
    expect(isNewerReview(null, '2026-10-09T10:00:00.100Z')).toBe(true);
    expect(isNewerReview('2026-10-09T10:00:00.100Z', '2026-10-09T10:00:00.250Z')).toBe(true);
    // The older decision's answer arriving last is not applied over the newer numbers.
    expect(isNewerReview('2026-10-09T10:00:00.250Z', '2026-10-09T10:00:00.100Z')).toBe(false);
    // The same instant written with another offset is not older.
    expect(isNewerReview('2026-10-09T10:00:00.250Z', '2026-10-09T13:00:00.250+03:00')).toBe(true);
  });
  it('never raise the waiting number while another decision is still on its way', () => {
    const shown = { pending_receipts: 3, revenue: 100 };
    // Computed before the other decision was saved (still counts it): the screen stays at 3.
    expect(withOptimisticPending({ pending_receipts: 4, revenue: 150 }, shown, 1)).toEqual({ pending_receipts: 3, revenue: 150 });
    // Computed after it: nothing to correct.
    expect(withOptimisticPending({ pending_receipts: 3, revenue: 150 }, shown, 1)).toEqual({ pending_receipts: 3, revenue: 150 });
    // Nothing else on its way: the server's numbers as they are (another admin may have added to them).
    expect(withOptimisticPending({ pending_receipts: 5, revenue: 150 }, shown, 0)).toEqual({ pending_receipts: 5, revenue: 150 });
    expect(withOptimisticPending({ pending_receipts: 5, revenue: 150 }, undefined, 2)).toEqual({ pending_receipts: 5, revenue: 150 });
  });
});

describe('the financial report, a hundred rows at a time', () => {
  const part = (ids: string[], rows_total?: number, count = 250): ReportPart<{ id: string }, { count: number }> =>
    ({ baseline: null, totals: { count }, rows: ids.map((id) => ({ id })), rows_total });
  const ids = (from: number, to: number) => Array.from({ length: to - from }, (_, i) => String(from + i));

  it('asks for the next part from where the loaded rows end, until all are loaded', () => {
    expect(nextReportOffset([part(ids(0, 100), 250)])).toBe(100);
    expect(nextReportOffset([part(ids(0, 100), 250), part(ids(100, 200), 250)])).toBe(200);
    expect(nextReportOffset([part(ids(0, 100), 250), part(ids(100, 200), 250), part(ids(200, 250), 250)])).toBeUndefined();
    expect(nextReportOffset([part(ids(0, 40), 40)])).toBeUndefined();
    expect(nextReportOffset([])).toBeUndefined();
  });
  it('stops when a part comes back empty, whatever the count says', () => {
    expect(nextReportOffset([part(ids(0, 100), 250), part([], 250)])).toBeUndefined();
  });
  it('takes an answer without a count as the whole report (a database that does not page yet)', () => {
    const old = part(ids(0, 2000), undefined, 5000);
    expect(nextReportOffset([old])).toBeUndefined();
    expect(mergeReport([old])).toMatchObject({ rowsTotal: 2000, totals: { count: 5000 } });
  });
  it('joins the parts in order, each row once, with the freshest totals', () => {
    const merged = mergeReport([part(['a', 'b'], 4, 4), part(['b', 'c', 'd'], 4, 5)])!;
    expect(merged.rows.map((row) => row.id)).toEqual(['a', 'b', 'c', 'd']);
    expect(merged.totals).toEqual({ count: 5 });
    expect(merged.rowsTotal).toBe(4);
    expect(mergeReport([])).toBeNull();
  });
});
