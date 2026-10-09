import { supabase } from './supabase';
import { rpcOr } from './rpc';

/** One subscription of a student in the open company, as get_company_students_page answers it. */
export interface StudentSubscription {
  id: string; status: string; type: string; price: number | string; created_at: string;
  start_date: string | null; end_date: string | null; period_label: string | null; period_phase: string | null;
  departure_time: string | null; return_time: string | null;
  line_name: string | null; trip_label: string | null; trip_university: string | null;
}

/** An active member of the company with their subscriptions to it. */
export interface StudentRow {
  id: string; phone: string; full_name: string; university: string; college: string;
  profile_image_url: string | null; created_at: string;
  subscriptions: StudentSubscription[];
}

/** `total` is filled only when it was asked for. */
export interface StudentsPageAnswer { rows: StudentRow[]; has_next: boolean; total: number | null }
export interface StudentsPageRequest { companyId: string; search: string; limit: number; offset: number; withTotal: boolean }

/** A page of the company's active members, newest first, in ONE request; the search is done by the database. */
export async function fetchStudentsPage(request: StudentsPageRequest): Promise<StudentsPageAnswer> {
  const page = await rpcOr<StudentsPageAnswer>('get_company_students_page',
    () => supabase.rpc('get_company_students_page', {
      p_company_id: request.companyId, p_search: request.search || null, p_limit: request.limit, p_offset: request.offset,
      p_with_total: request.withTotal,
    }),
    // The older way's code is downloaded only if it is ever needed.
    async () => (await import('./legacy')).legacyStudentsPage(request));
  return { rows: page?.rows ?? [], has_next: !!page?.has_next, total: page?.total ?? null };
}

// ── Pure cache edits (what this page's own writes do to what is on screen) ──

/** The page with one subscription changed to what the server answered. */
export function withSubscription(page: StudentsPageAnswer | undefined, subscriptionId: string, patch: Partial<StudentSubscription>): StudentsPageAnswer | undefined {
  if (!page || !page.rows.some((student) => student.subscriptions.some((sub) => sub.id === subscriptionId))) return page;
  return {
    ...page,
    rows: page.rows.map((student) => (student.subscriptions.some((sub) => sub.id === subscriptionId)
      ? { ...student, subscriptions: student.subscriptions.map((sub) => (sub.id === subscriptionId ? { ...sub, ...patch } : sub)) }
      : student)),
  };
}

/** The page without a student who left the company. */
export function withoutStudent(page: StudentsPageAnswer | undefined, studentId: string): StudentsPageAnswer | undefined {
  if (!page || !page.rows.some((student) => student.id === studentId)) return page;
  return { ...page, rows: page.rows.filter((student) => student.id !== studentId) };
}
