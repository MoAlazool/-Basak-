import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys } from './query';

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
  imagePath: string | null;
  imageUrl: string | null;
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

export async function createReceiptImageUrl(reference: string | null | undefined): Promise<string> {
  if (!reference?.trim()) throw new Error('مسار صورة الإيصال غير متاح.');
  const storagePath = normalizeReceiptStoragePath(reference);
  if (!storagePath) {
    if (/^https?:\/\//i.test(reference)) return reference;
    throw new Error('مسار صورة الإيصال غير صالح.');
  }

  const { data, error } = await supabase.storage.from('receipts').createSignedUrl(storagePath, 3600);
  if (error) throw error;
  return data.signedUrl;
}

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
export async function fetchPendingReceipts(companyId: string): Promise<PendingReceiptRow[]> {
  const { data: receiptRows, error } = await supabase.from('receipts')
    .select('id, image_url, attempt_number, created_at, subscription_id, amount')
    .eq('company_id', companyId).eq('status', 'pending').order('created_at', { ascending: true });
  if (error) throw error;
  const receipts = (receiptRows || []) as Row[];
  if (!receipts.length) return [];

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

  return Promise.all(receipts.map(async (receipt) => {
    const imagePath = normalizeReceiptStoragePath(receipt.image_url);
    let imageUrl: string | null = null;
    try {
      imageUrl = await createReceiptImageUrl(receipt.image_url);
    } catch (imageError) {
      // Keep the receipt visible even if its file needs a fresh URL or has been removed.
      console.warn(`Could not create a preview URL for receipt ${receipt.id}:`, imageError);
    }

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
      imageUrl,
      attemptNumber: receipt.attempt_number || 1,
      createdAt: receipt.created_at,
    };
  }));
}

/** The receipts one company still has to review. New ones arrive through the workspace's live topic. */
export function usePendingReceipts(companyId: string) {
  const client = useQueryClient();
  const key = keys.company(companyId, 'receipts', 'pending');
  const query = useQuery({ queryKey: key, queryFn: () => fetchPendingReceipts(companyId) });

  // Approving or rejecting removes the row at once; if the database refuses, it comes back.
  const review = useMutation({
    mutationFn: async ({ id, decision, reason }: { id: string; decision: 'approved' | 'rejected'; reason?: string }) => {
      const { data, error } = await supabase.from('receipts')
        .update(decision === 'approved' ? { status: 'approved' } : { status: 'rejected', rejection_reason: reason })
        .eq('id', id).select('id').single();
      if (error) throw new Error(error.message);
      if (!data) throw new Error('لم يُحفظ القرار؛ تحقق من صلاحيات الحساب ثم أعد المحاولة.');
    },
    onMutate: async ({ id }) => {
      await client.cancelQueries({ queryKey: key });
      const before = client.getQueryData<PendingReceiptRow[]>(key);
      client.setQueryData<PendingReceiptRow[]>(key, (rows) => (rows ?? []).filter((row) => row.id !== id));
      return { before };
    },
    onError: (_error, _input, context) => { if (context?.before) client.setQueryData(key, context.before); },
    onSettled: () => {
      for (const name of ['receipts', 'overview', 'students', 'reports']) {
        void client.invalidateQueries({ queryKey: keys.company(companyId, name) });
      }
    },
  });

  return {
    receipts: query.data ?? [],
    loading: query.isPending,
    error: query.error?.message ?? '',
    refresh: () => void query.refetch(),
    review: (id: string, decision: 'approved' | 'rejected', reason?: string) => review.mutateAsync({ id, decision, reason }),
  };
}
