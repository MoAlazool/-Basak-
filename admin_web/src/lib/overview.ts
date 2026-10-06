import { useCallback, useEffect, useState } from 'react';
import { supabase } from './supabase';
import { useCompanyRealtime } from './useCompanyRealtime';

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

const LIVE_TABLES = ['receipts', 'subscriptions', 'company_students', 'daily_ride_status'] as const;

function useNumbers<T>(load: () => PromiseLike<{ data: unknown; error: { message: string } | null }>, companyId: string | null, tables: readonly string[]) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    const { data: result, error: loadError } = await load();
    if (loadError) setError(loadError.message);
    else { setData(result as T); setError(''); }
    setLoading(false);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [companyId]);

  useEffect(() => { void refresh(); }, [refresh]);
  useCompanyRealtime(companyId, tables, () => void refresh());
  return { data, loading, error, refresh };
}

/** One company's numbers, refreshed as its receipts, subscriptions, members and rides change. */
export const useCompanyOverview = (companyId: string) =>
  useNumbers<CompanyNumbers>(() => supabase.rpc('company_overview', { p_company_id: companyId }), companyId, LIVE_TABLES);

/** The whole platform's numbers, refreshed as any company changes. */
export const usePlatformOverview = () =>
  useNumbers<PlatformNumbers>(() => supabase.rpc('platform_overview'), null, [...LIVE_TABLES, 'companies']);

const weekday = new Intl.DateTimeFormat('ar-EG', { weekday: 'long', timeZone: 'UTC' });
/** Shapes riders_week for the weekly chart. */
export const weekPoints = (week: { date: string; riders: number }[] | undefined) =>
  (week ?? []).map(({ date, riders }) => ({ dateStr: date, dayName: weekday.format(new Date(`${date}T00:00:00Z`)), count: riders }));
