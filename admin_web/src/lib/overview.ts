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
  /** The day students are confirming for right now (tomorrow, once its vote opens), and how many have. */
  next_ride_date: string;
  riders_next: number;
  /** When the company's vote closes (HH:MM). */
  vote_closes_at?: string;
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
  next_ride_date: string;
  riders_next: number;
  vote_closes_at?: string;
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

const dayName = new Intl.DateTimeFormat('ar-EG', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' });
/**
 * The riders card. Students confirm the evening before, so once the vote for
 * the next ride is open that is the number that moves: it becomes the headline
 * and today's stays beside it. Before that, today is the headline.
 */
export function ridersCard(numbers: Parameters<typeof nextRideHint>[0], fallbackHint: string): { label: string; value: number; hint: string } {
  if (!numbers) return { label: 'نازلين اليوم (مؤكدين)', value: 0, hint: fallbackHint };
  const today = numbers.riders_week[numbers.riders_week.length - 1]?.date;
  if (numbers.next_ride_date && numbers.next_ride_date !== today) {
    const day = dayName.format(new Date(`${numbers.next_ride_date}T00:00:00Z`));
    return {
      label: `مؤكدون لرحلة ${day}`,
      value: numbers.riders_next,
      hint: `التأكيد مفتوح الآن • نزل اليوم: ${numbers.riders_today.toLocaleString('ar-EG')}`,
    };
  }
  return { label: 'نازلين اليوم (مؤكدين)', value: numbers.riders_today, hint: nextRideHint(numbers) || fallbackHint };
}

/**
 * The line under "riding today": confirmations for the next ride, which is the
 * number that moves while students vote in the evening.
 */
function nextRideHint(numbers: { riders_today: number; riders_next: number; next_ride_date: string; vote_closes_at?: string; riders_week: { date: string }[] } | null): string {
  if (!numbers) return '';
  const today = numbers.riders_week[numbers.riders_week.length - 1]?.date;
  if (!numbers.next_ride_date || numbers.next_ride_date === today) {
    return numbers.vote_closes_at ? `التأكيد مفتوح لرحلة اليوم حتى ${clockLabel(numbers.vote_closes_at)}` : 'التأكيد مفتوح لرحلة اليوم';
  }
  return `لرحلة ${dayName.format(new Date(`${numbers.next_ride_date}T00:00:00Z`))}: ${numbers.riders_next.toLocaleString('ar-EG')} مؤكد حتى الآن`;
}

/** "16:30" -> "٤:٣٠ م" */
export function clockLabel(hhmm: string): string {
  const [h, m] = hhmm.slice(0, 5).split(':').map(Number);
  const hour = (h % 12 === 0 ? 12 : h % 12).toLocaleString('ar-EG');
  const minute = m ? `:${m.toLocaleString('ar-EG', { minimumIntegerDigits: 2 })}` : '';
  return `${hour}${minute} ${h < 12 ? 'ص' : 'م'}`;
}
