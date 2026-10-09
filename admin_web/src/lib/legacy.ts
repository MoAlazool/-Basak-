/**
 * The older way of doing what three server functions now do in one request
 * each (get_pending_receipts_page, review_receipt, get_company_students_page).
 * Used only when the database does not have the function yet (lib/rpc.ts), and
 * to be deleted once every environment has it. Each loader answers in the
 * server function's own shape, so the rest of the dashboard knows one shape.
 */
import { supabase } from './supabase';
import { one } from './query';
import type { ReceiptsPageAnswer } from './pendingReceipts';
import type { StudentsPageAnswer, StudentsPageRequest } from './students';

type Row = Record<string, any>;
const byId = (rows: Row[] | null | undefined) => new Map((rows || []).map((row) => [row.id as string, row]));
const uniq = (values: (string | null | undefined)[]) => [...new Set(values.filter((value): value is string => !!value))];

/** Five requests in three stages: receipts, their subscriptions, then students / lines / stations. */
export async function legacyPendingReceipts(companyId: string, limit: number): Promise<ReceiptsPageAnswer> {
  // One row more than asked for tells whether there is more to load, without a count.
  const { data: receiptRows, error } = await supabase.from('receipts')
    .select('id, image_url, attempt_number, created_at, subscription_id, amount')
    .eq('company_id', companyId).eq('status', 'pending').order('created_at', { ascending: true }).range(0, limit);
  if (error) throw new Error(error.message);
  const all = (receiptRows || []) as Row[];
  const receipts = all.slice(0, limit);
  if (!receipts.length) return { rows: [], has_more: false, total: 0 };

  const { data: subRows, error: subError } = await supabase.from('subscriptions')
    .select('id, type, price, student_id, line_id, station_id, departure_time, return_time, start_date, end_date, period_label, period_phase')
    .in('id', uniq(receipts.map((r) => r.subscription_id)));
  if (subError) throw new Error(subError.message);
  const subscriptions = byId(subRows as Row[]);
  const subs = [...subscriptions.values()];

  const [studentsRes, linesRes, stationsRes] = await Promise.all([
    supabase.from('students').select('id, full_name, phone, university, college').in('id', uniq(subs.map((x) => x.student_id))),
    supabase.from('lines').select('id, name, company_id, companies(name)').in('id', uniq(subs.map((x) => x.line_id))),
    supabase.from('stations').select('id, name').in('id', uniq(subs.map((x) => x.station_id))),
  ]);
  const failed = studentsRes.error ?? linesRes.error ?? stationsRes.error;
  if (failed) throw new Error(failed.message);
  const students = byId(studentsRes.data as Row[]);
  const lines = byId(linesRes.data as Row[]);
  const stations = byId(stationsRes.data as Row[]);

  return {
    rows: receipts.map((receipt) => {
      const subscription = subscriptions.get(receipt.subscription_id);
      const student = subscription ? students.get(subscription.student_id) : undefined;
      const line = subscription ? lines.get(subscription.line_id) : undefined;
      const station = subscription ? stations.get(subscription.station_id) : undefined;
      return {
        id: receipt.id, image_url: receipt.image_url, attempt_number: receipt.attempt_number, created_at: receipt.created_at,
        amount: receipt.amount, subscription_id: receipt.subscription_id,
        student_id: subscription?.student_id ?? null, student_name: student?.full_name ?? null, student_phone: student?.phone ?? null,
        university: student?.university ?? null, college: student?.college ?? null,
        company_id: line?.company_id ?? null, company_name: one<Row>(line?.companies)?.name ?? null,
        line_name: line?.name ?? null, station_name: station?.name ?? null,
        departure_time: subscription?.departure_time ?? null, return_time: subscription?.return_time ?? null,
        subscription_type: subscription?.type ?? null, period_label: subscription?.period_label ?? null,
        period_start: subscription?.start_date ?? null, period_end: subscription?.end_date ?? null,
        period_phase: subscription?.period_phase ?? null, price: subscription?.price ?? null,
      };
    }),
    has_more: all.length > limit,
    // Not counted here: the waiting number on screen is the overview's.
    total: receipts.length,
  };
}

/** The decision as a plain update. The overview is not in the answer: the change's own announcement refreshes it. */
export async function legacyReviewReceipt(id: string, decision: 'approved' | 'rejected', reason?: string): Promise<null> {
  const { data, error } = await supabase.from('receipts')
    .update(decision === 'approved' ? { status: 'approved' } : { status: 'rejected', rejection_reason: reason })
    .eq('id', id).select('id').single();
  if (error) throw new Error(error.message);
  if (!data) throw new Error('لم يُحفظ القرار؛ تحقق من صلاحيات الحساب ثم أعد المحاولة.');
  return null;
}

/** The search box as a PostgREST filter over name, phone and university. */
const searchFilter = (search: string) => {
  const term = search.replace(/[%,()]/g, ' ');
  return `full_name.ilike.%${term}%,phone.ilike.%${term}%,university.ilike.%${term}%`;
};

/** The nested select, plus a separate exact count when the total is asked for. */
export async function legacyStudentsPage({ companyId, search, limit, offset, withTotal }: StudentsPageRequest): Promise<StudentsPageAnswer> {
  let rowsQuery = supabase.from('students')
    .select(`
      id, phone, full_name, university, college, profile_image_url, created_at,
      company_students!inner(company_id, status),
      subscriptions(id, status, type, price, created_at, start_date, end_date, period_label, period_phase, departure_time, return_time, lines(name),
        departure_trip:departure_trip_id(label, universities(name)))
    `)
    .eq('company_students.company_id', companyId)
    .eq('company_students.status', 'active')
    .eq('subscriptions.company_id', companyId);
  if (search) rowsQuery = rowsQuery.or(searchFilter(search));
  const rowsRequest = rowsQuery.order('created_at', { ascending: false }).range(offset, offset + limit);

  let countQuery = supabase.from('students')
    .select('id, company_students!inner(company_id, status)', { count: 'exact', head: true })
    .eq('company_students.company_id', companyId)
    .eq('company_students.status', 'active');
  if (search) countQuery = countQuery.or(searchFilter(search));

  const [rowsAnswer, countAnswer] = await Promise.all([rowsRequest, withTotal ? countQuery : null]);
  const failed = rowsAnswer.error ?? countAnswer?.error;
  if (failed) throw new Error(failed.message);
  const rows = (rowsAnswer.data || []) as Row[];
  return {
    rows: rows.slice(0, limit).map((student) => ({
      id: student.id, phone: student.phone, full_name: student.full_name, university: student.university, college: student.college,
      profile_image_url: student.profile_image_url, created_at: student.created_at,
      subscriptions: ((student.subscriptions || []) as Row[]).map((sub) => {
        const trip = one<Row>(sub.departure_trip);
        return {
          id: sub.id, status: sub.status, type: sub.type, price: sub.price, created_at: sub.created_at,
          start_date: sub.start_date, end_date: sub.end_date, period_label: sub.period_label, period_phase: sub.period_phase,
          departure_time: sub.departure_time, return_time: sub.return_time,
          line_name: one<Row>(sub.lines)?.name ?? null, trip_label: trip?.label ?? null,
          trip_university: one<Row>(trip?.universities)?.name ?? null,
        };
      }),
    })),
    has_next: rows.length > limit,
    total: withTotal ? countAnswer?.count ?? 0 : null,
  };
}
