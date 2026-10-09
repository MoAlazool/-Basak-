import { useRef, useState } from 'react';
import { keepPreviousData, useMutation, useQuery, useQueryClient, type QueryKey } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';
import { rpcOr } from './rpc';
import { hhmm } from './time';
import type { CompanyNumbers } from './overview';
import { forgetApplied, rememberApplied } from './recentChanges';

export const RECEIPTS_BUCKET = 'receipts';
/** How many pending receipts are loaded at a time (oldest first). */
const RECEIPTS_PAGE = 50;

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

/** One row of get_pending_receipts_page: the receipt with everything the review table shows about it. */
export interface ReceiptAnswerRow {
  id: string; image_url: string | null; attempt_number: number | null; created_at: string; amount: number | string | null;
  subscription_id: string; student_id: string | null; student_name: string | null; student_phone: string | null;
  university: string | null; college: string | null; company_id: string | null; company_name: string | null;
  line_name: string | null; station_name: string | null; departure_time: string | null; return_time: string | null;
  subscription_type: string | null; period_label: string | null; period_start: string | null; period_end: string | null;
  period_phase: string | null; price: number | string | null;
}
export interface ReceiptsPageAnswer { rows: ReceiptAnswerRow[]; has_more: boolean; total?: number }

/** The server's row as the table shows it (placeholders for what is missing, the image as a storage path). */
export function toPendingRow(row: ReceiptAnswerRow): PendingReceiptRow {
  const imagePath = normalizeReceiptStoragePath(row.image_url);
  return {
    id: row.id,
    subscriptionId: row.subscription_id,
    studentId: row.student_id || '',
    studentName: row.student_name || 'بيانات الطالب غير متاحة',
    studentPhone: row.student_phone || '—',
    university: row.university || '—',
    college: row.college && row.college !== 'غير محدد' ? row.college : '',
    companyId: row.company_id || '',
    companyName: row.company_name || '—',
    lineName: row.line_name || '—',
    stationName: row.station_name || '—',
    departureTime: hhmm(row.departure_time),
    returnTime: hhmm(row.return_time),
    subscriptionType: row.subscription_type || 'termly',
    periodLabel: row.period_label || '',
    periodStart: row.period_start || '',
    periodEnd: row.period_end || '',
    periodPhase: row.period_phase || '',
    // The amount recorded with the receipt; older receipts fall back to the subscription price.
    price: Number(row.amount ?? row.price ?? 0),
    imagePath,
    legacyImageUrl: !imagePath && /^https?:\/\//i.test(row.image_url || '') ? String(row.image_url) : null,
    attemptNumber: row.attempt_number || 1,
    createdAt: row.created_at,
  };
}

/** The oldest pending receipts of a company, in ONE request (get_pending_receipts_page). */
export async function fetchPendingReceipts(companyId: string, limit: number = RECEIPTS_PAGE): Promise<PendingReceipts> {
  const page = await rpcOr<ReceiptsPageAnswer>('get_pending_receipts_page',
    () => supabase.rpc('get_pending_receipts_page', { p_company_id: companyId, p_limit: limit }),
    // The older way's code is downloaded only if it is ever needed.
    async () => (await import('./legacy')).legacyPendingReceipts(companyId, limit));
  return { rows: (page?.rows ?? []).map(toPendingRow), hasMore: !!page?.has_more };
}

/** What review_receipt answers: the decision and the company's numbers after it. */
interface ReviewAnswer { id: string; status: string; company_id: string; overview: CompanyNumbers | null; reviewed_at?: string | null }

/**
 * Whether an answer's numbers are newer than the ones already applied. Answers
 * to decisions taken close together can arrive in another order than the
 * decisions were saved; `reviewed_at` is when each was saved.
 */
export function isNewerReview(appliedAt: string | null, reviewedAt: string): boolean {
  return appliedAt === null || Date.parse(reviewedAt) >= Date.parse(appliedAt);
}

/**
 * The numbers of an answer while other decisions of this tab are still on their
 * way: those receipts have already left the screen, whether or not this answer
 * was computed before they were saved, so the waiting number never goes back up.
 */
export function withOptimisticPending<T extends { pending_receipts: number }>(numbers: T, shown: T | undefined, othersRunning: number): T {
  return othersRunning > 0 && shown ? { ...numbers, pending_receipts: Math.min(numbers.pending_receipts, shown.pending_receipts) } : numbers;
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
 * workspace's live topic. A decision is ONE request: the row leaves the list at
 * once, and the server's answer carries the company's numbers after it, which
 * replace the cached ones. Nothing is read again for the admin who decided,
 * not even on the change's own announcement (other admins follow through the
 * live topic).
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
  // Decisions under way. Answers can arrive in another order than the decisions were
  // saved, so each is applied only if it is newer (`reviewed_at`) than the last one
  // applied. `unordered` is for a database whose answers do not say when: after
  // overlapping decisions the numbers are then read once instead.
  const flight = useRef({ running: 0, unordered: false, appliedAt: null as string | null });

  const review = useMutation({
    mutationFn: ({ id, decision, reason }: ReviewInput) => rpcOr<ReviewAnswer | null>('review_receipt',
      () => supabase.rpc('review_receipt', { p_receipt_id: id, p_decision: decision, p_reason: reason ?? null }),
      async () => (await import('./legacy')).legacyReviewReceipt(id, decision, reason)),
    onMutate: async ({ id }) => {
      flight.current.running += 1;
      // A read that is under way would bring the row back; it is repeated once the decision is saved.
      const interrupted = client.isFetching({ queryKey: root }) > 0;
      await client.cancelQueries({ queryKey: root });
      const lists = client.getQueriesData<PendingReceipts>({ queryKey: root });
      const row = lists.flatMap(([, list]) => list?.rows ?? []).find((item) => item.id === id);
      // The database announces this change to us as well (the receipt and its
      // subscription); that echo must re-read neither the queue nor the numbers.
      const echoes = [id, row?.subscriptionId];
      rememberApplied(echoes, APPLIED_HERE);
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
    onSuccess: (answer, _input, context) => {
      // The answer may have taken a while: keep recognising the echo from now.
      rememberApplied(context?.echoes ?? [], APPLIED_HERE);
      const numbers = answer?.overview;
      const others = flight.current.running - 1;
      // No numbers in the answer (the older database): they are read once.
      if (!numbers) void client.invalidateQueries({ queryKey: overviewKey });
      else if (answer.reviewed_at) {
        if (isNewerReview(flight.current.appliedAt, answer.reviewed_at)) {
          flight.current.appliedAt = answer.reviewed_at;
          client.setQueryData<CompanyNumbers>(overviewKey, (shown) => withOptimisticPending(numbers, shown, others));
        }
      } else if (others > 0 || flight.current.unordered) flight.current.unordered = true;
      else client.setQueryData<CompanyNumbers>(overviewKey, numbers);
      // The queue is not read again, except for the next receipts once the loaded ones run out.
      if (context?.interrupted || shouldTopUp(client.getQueryData<PendingReceipts>([...root, limit]))) {
        void client.invalidateQueries({ queryKey: root });
      }
    },
    onSettled: (_data, error, _input, context) => {
      // A refused decision usually means the receipt is no longer waiting (another admin
      // decided it first): the queue is read once to show what is really there.
      if (error) void client.invalidateQueries({ queryKey: root });
      flight.current.running -= 1;
      if (flight.current.running > 0 || !flight.current.unordered) return;
      // Overlapping decisions whose answers carry no time: one read after the last of them settles the numbers.
      flight.current.unordered = false;
      void client.invalidateQueries({ queryKey: overviewKey });
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
    review: async (id: string, decision: 'approved' | 'rejected', reason?: string) => { await review.mutateAsync({ id, decision, reason }); },
  };
}

/** What a decision brings up to date in this tab (names as in lib/sync.ts). */
const APPLIED_HERE = ['receipts', 'overview'] as const;
const EMPTY: PendingReceiptRow[] = [];
interface ReviewInput { id: string; decision: 'approved' | 'rejected'; reason?: string }
interface ReviewContext {
  held: QueryKey[]; row: PendingReceiptRow | undefined; interrupted: boolean; echoes: (string | undefined)[];
}
