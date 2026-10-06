import { useQuery } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, queryClient, unwrap } from './query';

/** The numbers of one company, as computed by the database (company_overview). */
export interface CompanyNumbers {
  company: { id: string; name: string; status: 'active' | 'suspended' | 'archived'; created_at: string };
  baseline: string | null;
  members: number;
  active_subscriptions: number;
  pending_receipts: number;
  revenue: number;
  riders_today: number;
  riders_week: { date: string; riders: number }[];
  lines: number;
  active_lines: number;
  supervisors: number;
  admins: number;
  top_lines: { id: string; name: string; is_active: boolean; subscribers: number; company?: string }[];
}

/** Platform totals plus one row per company (platform_overview). */
export interface PlatformNumbers {
  companies: { total: number; active: number; suspended: number; archived: number };
  students: number;
  members: number;
  active_subscriptions: number;
  pending_receipts: number;
  revenue: number;
  riders_today: number;
  riders_week: { date: string; riders: number }[];
  lines: number;
  supervisors: number;
  top_lines: CompanyNumbers['top_lines'];
  per_company: Omit<CompanyNumbers, 'top_lines' | 'riders_week'>[];
}

/** One company's numbers. Live events mark them stale; they are also re-read on focus. */
export function useCompanyOverview(companyId: string) {
  const query = useQuery({
    queryKey: keys.company(companyId, 'overview'),
    queryFn: () => unwrap<CompanyNumbers>(supabase.rpc('company_overview', { p_company_id: companyId })),
  });
  return { data: query.data ?? null, loading: query.isPending, error: query.error?.message ?? '', refresh: () => void query.refetch() };
}

/** The whole platform's numbers. */
export function usePlatformOverview() {
  const query = useQuery({
    queryKey: keys.platform('overview'),
    queryFn: () => unwrap<PlatformNumbers>(supabase.rpc('platform_overview')),
  });
  return { data: query.data ?? null, loading: query.isPending, error: query.error?.message ?? '', refresh: () => query.refetch() };
}

/** Warms a company's overview before its workspace is opened (hovering its card). */
export const prefetchCompanyOverview = (companyId: string) => queryClient.prefetchQuery({
  queryKey: keys.company(companyId, 'overview'),
  queryFn: () => unwrap<CompanyNumbers>(supabase.rpc('company_overview', { p_company_id: companyId })),
});

const weekday = new Intl.DateTimeFormat('ar-EG', { weekday: 'long', timeZone: 'UTC' });
/** Shapes riders_week for the weekly chart. */
export const weekPoints = (week: { date: string; riders: number }[] | undefined) =>
  (week ?? []).map(({ date, riders }) => ({ dateStr: date, dayName: weekday.format(new Date(`${date}T00:00:00Z`)), count: riders }));
