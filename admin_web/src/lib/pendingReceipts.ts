import { useState } from 'react';
import { keepPreviousData, useMutation, useQuery, useQueryClient, type QueryKey } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';
import type { CompanyNumbers } from './overview';
import { forgetApplied, rememberApplied } from './recentChanges';

export const RECEIPTS_BUCKET = 'receipts';
/** How many pending receipts are loaded at a time (oldest first). */
export const RECEIPTS_PAGE = 50;

export interface PendingReceiptRow {
  id: string;
  subscriptionId: string;
  studentId: string;
  studentName: string;
  studentPhone: string;
  university: string;
  college: string;
  companyId: string;
  companyName: string;
  lineName: string;
  stationName: string;
  departureTime: string;
  returnTime: string;
  subscriptionType: string;
  /** e.g. "الفصل الدراسي الثاني 2026/2027" (from academic_terms via the period_label computed field). */
  periodLabel: string;
  periodStart: string;
  periodEnd: string;
  /** current | upcoming | expired */
  periodPhase: string;
  price: number;
  /** Where the image is stored. Its signed link is kept apart (lib/signedUrls.ts), so re-reading the list never re-signs it. */
  imagePath: string | null;
  /** Only for very old rows that stored a full link to somewhere else. */
  legacyImageUrl: string | null;
  attemptNumber: number;
  createdAt: string;
}

function decodeStoragePath(path: string): string {
  return path.split('/').map((part) => {
    try { return decodeURIComponent(part); } catch { return part; }
  }).join('/');
}

/** Accepts both current storage object paths and legacy Supabase object URLs. */
export function normalizeReceiptStoragePath(value: string | null | undefined): string | null {
  if (!value) return null;
  const raw = value.trim();
  if (!raw) return null;

  let candidate = raw;
  if (/^https?:\/\//i.test(raw)) {
    try {
      const pathname = new URL(raw).pathname;
      const bucketMarker = '/receipts/';
      const bucketIndex = pathname.indexOf(bucketMarker);
      if (bucketIndex < 0) return null;
      candidate = pathname.slice(bucketIndex + bucketMarker.length);
    } catch {
      return null;
    }
  } else {
    candidate = candidate.split(/[?#]/, 1)[0];
    candidate = candidate.replace(/^\/+/, '');
    candidate = candidate.replace(/^receipts\//i, '');
    const objectMarker = /^(?:storage\/v1\/)?object\/(?:public|sign|authenticated)\/receipts\//i;
    candidate = candidate.replace(objectMarker, '');
  }

  const decoded = decodeStoragePath(candidate.replace(/^\/+/, ''));
  return decoded && !decoded.split('/').some((part) => part === '..') ? decoded : null;
}

export interface PendingReceipts { rows: PendingReceiptRow[]; hasMore: boolean }

type Row = Record<string, any>;
const one = <T,>(value: T | T[] | null | undefined): T | undefined => (Array.isArray(value) ? value[0] : value ?? undefined);
const byId = (rows: Row[] | null | undefined) => new Map((rows || []).map((row) => [row.id as string, row]));
const uniq = (values: (string | null | undefined)[]) => [...new Set(values.filter((value): value is string => !!value))];
const hhmm = (value?: string | null) => (value ? String(value).slice(0, 5) : '');

/**
 * Loads pending receipts and joins student / company / line / station details with
 * separate scoped queries. Nested embeds silently returned null when a relation
 * was ambiguous or blocked, which left the review table without student data.
 */
export async function fetchPendingReceipts(companyId: string, limit: number = RECEIPTS_PAGE): Promise<PendingReceipts> {
  // One row more than asked for tells whether there is more to load, without a count.
  const { data: receiptRows, error } = await supabase.from('receipts')
    .select('id, image_url, attempt_number, created_at, subscription_id, amount')
    .eq('company_id', companyId).eq('status', 'pending').order('created_at', { ascending: true }).range(0, limit);
  if (error) throw error;
  const all = (receiptRows || []) as Row[];
  const hasMore = all.length > limit;
  const receipts = all.slice(0, limit);
  if (!receipts.length) return { rows: [], hasMore: false };

  const { data: subRows, error: subError } = await supabase.from('subscriptions')
    .select('id, type, price, student_id, line_id, station_id, departure_time, return_time, start_date, end_date, period_label, period_phase')
    .in('id', uniq(receipts.map((r) => r.subscription_id)));
  if (subError) throw subError;
  const subscriptions = byId(subRows as Row[]);
  const subs = [...subscriptions.values()];

  const [studentsRes, linesRes, stationsRes] = await Promise.all([
    supabase.from('students').select('id, full_name, phone, university, college').in('id', uniq(subs.map((x) => x.student_id))),
    supabase.from('lines').select('id, name, company_id, companies(name)').in('id', uniq(subs.map((x) => x.line_id))),
    supabase.from('stations').select('id, name').in('id', uniq(subs.map((x) => x.station_id))),
  ]);
  if (studentsRes.error) throw studentsRes.error;
  if (linesRes.error) throw linesRes.error;
  if (stationsRes.error) throw stationsRes.error;
  const students = byId(studentsRes.data as Row[]);
  const lines = byId(linesRes.data as Row[]);
  const stations = byId(stationsRes.data as Row[]);

  const rows = receipts.map((receipt): PendingReceiptRow => {
    const imagePath = normalizeReceiptStoragePath(receipt.image_url);
    const legacyImageUrl = !imagePath && /^https?:\/\//i.test(receipt.image_url || '') ? String(receipt.image_url) : null;

    const subscription = subscriptions.get(receipt.subscription_id);
    const student = subscription ? students.get(subscription.student_id) : undefined;
    const line = subscription ? lines.get(subscription.line_id) : undefined;
    const station = subscription ? stations.get(subscription.station_id) : undefined;
    return {
      id: receipt.id,
      subscriptionId: receipt.subscription_id,
      studentId: subscription?.student_id || '',
      studentName: student?.full_name || 'بيانات الطالب غير متاحة',
      studentPhone: student?.phone || '—',
      university: student?.university || '—',
      college: student?.college && student.college !== 'غير محدد' ? student.college : '',
      companyId: line?.company_id || '',
      companyName: one<Row>(line?.companies)?.name || '—',
      lineName: line?.name || '—',
      stationName: station?.name || '—',
      departureTime: hhmm(subscription?.departure_time),
      returnTime: hhmm(subscription?.return_time),
      subscriptionType: subscription?.type || 'termly',
      periodLabel: subscription?.period_label || '',
      periodStart: subscription?.start_date || '',
      periodEnd: subscription?.end_date || '',
      periodPhase: subscription?.period_phase || '',
      // The amount recorded with the receipt; older receipts fall back to the subscription price.
      price: Number(receipt.amount ?? subscription?.price ?? 0),
      imagePath,
      legacyImageUrl,
      attemptNumber: receipt.attempt_number || 1,
      createdAt: receipt.created_at,
    };
  });
  return { rows, hasMore };
}

// ── Pure cache edits (what an approval or rejection does to what is on screen) ──

/** The list without the reviewed receipt. */
export function withoutReceipt(list: PendingReceipts | undefined, id: string): PendingReceipts | undefined {
  if (!list || !list.rows.some((row) => row.id === id)) return list;
  return { ...list, rows: list.rows.filter((row) => row.id !== id) };
}

/** The list with a receipt put back in its place (oldest first) after a refused decision. */
export function withReceipt(list: PendingReceipts | undefined, row: PendingReceiptRow): PendingReceipts | undefined {
  if (!list || list.rows.some((item) => item.id === row.id)) return list;
  return { ...list, rows: [...list.rows, row].sort((a, b) => a.createdAt.localeCompare(b.createdAt)) };
}

/** The overview with its "receipts waiting" number moved by `delta` (never below zero). */
export function withPendingDelta<T extends { pending_receipts: number }>(overview: T | undefined, delta: number): T | undefined {
  return overview ? { ...overview, pending_receipts: Math.max(0, overview.pending_receipts + delta) } : overview;
}

/** Few rows left on screen while more wait in the database: time to load the next ones. */
export const shouldTopUp = (list: PendingReceipts | undefined, threshold = 10) =>
  !!list && list.hasMore && list.rows.length < threshold;

/**
 * The receipts one company still has to review. New ones arrive through the
 * workspace's live topic. A decision is applied to the cache directly: the row
 * leaves the list, the waiting counter drops, and nothing is read again for
 * the admin who decided (other admins follow through the live topic).
 */
export function usePendingReceipts(companyId: string) {
  const client = useQueryClient();
  const [limit, setLimit] = useState(RECEIPTS_PAGE);
  const root = keys.company(companyId, 'receipts', 'pending');
  const overviewKey = keys.company(companyId, 'overview');
  const query = useQuery({
    queryKey: [...root, limit],
    queryFn: () => fetchPendingReceipts(companyId, limit),
    placeholderData: keepPreviousData,   // "load more" keeps the rows on screen
  });

  const review = useMutation({
    mutationFn: async ({ id, decision, reason }: ReviewInput) => {
      const { data, error } = await supabase.from('receipts')
        .update(decision === 'approved' ? { status: 'approved' } : { status: 'rejected', rejection_reason: reason })
        .eq('id', id).select('id').single();
      if (error) throw new Error(error.message);
      if (!data) throw new Error('لم يُحفظ القرار؛ تحقق من صلاحيات الحساب ثم أعد المحاولة.');
    },
    onMutate: async ({ id }) => {
      // A read that is under way would bring the row back; it is repeated once the decision is saved.
      const interrupted = client.isFetching({ queryKey: root }) > 0;
      await client.cancelQueries({ queryKey: root });
      const lists = client.getQueriesData<PendingReceipts>({ queryKey: root });
      const row = lists.flatMap(([, list]) => list?.rows ?? []).find((item) => item.id === id);
      // The database announces this change to us as well; that echo must not re-read the list.
      const echoes = [id, row?.subscriptionId];
      rememberApplied(echoes);
      client.setQueriesData<PendingReceipts>({ queryKey: root }, (list) => withoutReceipt(list, id));
      if (row) client.setQueryData<CompanyNumbers>(overviewKey, (numbers) => withPendingDelta(numbers, -1));
      return { held: lists.filter(([, list]) => list?.rows.some((item) => item.id === id)).map(([key]) => key), row, interrupted, echoes } satisfies ReviewContext;
    },
    onError: (_error, _input, context) => {
      if (!context) return;
      forgetApplied(context.echoes);
      const { row } = context;
      if (!row) return;
      // Only this receipt comes back: other decisions taken meanwhile stay as they are.
      context.held.forEach((key) => client.setQueryData<PendingReceipts>(key, (list) => withReceipt(list, row)));
      client.setQueryData<CompanyNumbers>(overviewKey, (numbers) => withPendingDelta(numbers, +1));
    },
    onSettled: (_data, error, _input, context) => {
      if (error && context?.interrupted) void client.invalidateQueries({ queryKey: root });
    },
    onSuccess: (_data, _input, context) => {
      // The answer may have taken a while: keep recognising the echo from now.
      rememberApplied(context?.echoes ?? []);
      // Nothing is read again, except the next receipts once the loaded ones run out.
      if (context?.interrupted || shouldTopUp(client.getQueryData<PendingReceipts>([...root, limit]))) {
        void client.invalidateQueries({ queryKey: root });
      }
    },
  });

  const shown = query.data;
  return {
    receipts: shown?.rows ?? EMPTY,
    hasMore: shown?.hasMore ?? false,
    loadingMore: query.isPlaceholderData,
    loadMore: () => setLimit((current) => current + RECEIPTS_PAGE),
    loading: query.isPending,
    error: query.error?.message ?? '',
    refresh: () => void query.refetch(),
    review: (id: string, decision: 'approved' | 'rejected', reason?: string) => review.mutateAsync({ id, decision, reason }),
  };
}

const EMPTY: PendingReceiptRow[] = [];
interface ReviewInput { id: string; decision: 'approved' | 'rejected'; reason?: string }
interface ReviewContext {
  held: QueryKey[]; row: PendingReceiptRow | undefined; interrupted: boolean; echoes: (string | undefined)[];
}
