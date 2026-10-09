import { useMemo } from 'react';
import { supabase } from './supabase';
import { keys, queryClient, STALE, unwrap, usePageData } from './query';
import type { SaleOption } from './saleOptions';
import type { LineOption, LineOptions } from './lineOptions';

/**
 * The lookups several pages need, each read once under ONE key and reused:
 *
 *   keys.shared('universities')            every university (pages filter what they need)
 *   keys.company(id, 'lines')              the company's lines with stations, trips and prices
 *   keys.company(id, 'lineNames')          the light list for filters and checkboxes
 *   keys.company(id, 'supervisors')        the company's supervisors
 *   keys.company(id, 'supervisorLines')    which supervisor is on which line
 *
 * They change rarely, so they are not re-read on every focus; the workspace's
 * live topic (lib/sync.ts) marks them out of date the moment they do change.
 */
const reference = { staleTime: STALE.reference } as const;

// ── Universities ────────────────────────────────────────────────────
export interface UniversityRow { id: string; name: string; city: string; is_active: boolean }
/** The columns of a university the dashboard shows (also what a write to one answers with). */
export const UNIVERSITY_COLUMNS = 'id, name, city, is_active';

export const universitiesKey = keys.shared('universities');
const loadUniversities = () => unwrap<UniversityRow[]>(
  supabase.from('universities').select(UNIVERSITY_COLUMNS).order('name'));

export const useUniversities = (enabled = true) => usePageData(universitiesKey, loadUniversities, { ...reference, enabled });
export const refreshUniversities = () => queryClient.invalidateQueries({ queryKey: universitiesKey });

// ── Lines ───────────────────────────────────────────────────────────
type Direction = 'departure' | 'return';
interface StationRow { id: string; name: string; order_index: number; is_active: boolean }
interface TripStopRow { station_id: string; stop_time: string }
interface TripRow {
  id: string; direction: Direction; label: string; start_time: string; arrival_time: string | null;
  university_id: string | null; is_active: boolean; line_trip_stops: TripStopRow[];
}
export interface LineRow {
  id: string; name: string; company_id: string; origin_name: string | null; destination_university_id: string | null;
  price_termly: number; price_yearly: number; price_daily: number; is_active: boolean;
  stations: StationRow[];
  line_trips: TripRow[];
  line_universities: { university_id: string }[];
  line_period_prices: { option: SaleOption; price: number; is_enabled: boolean }[];
}

const linesKey = (companyId: string) => keys.company(companyId, 'lines');
const loadLines = (companyId: string) => unwrap<LineRow[]>(
  supabase.from('lines')
    .select(`id, name, company_id, origin_name, destination_university_id, price_termly, price_yearly, price_daily,
      is_active, stations(id, name, order_index, is_active),
      line_trips(id, direction, label, start_time, arrival_time, university_id, is_active,
        line_trip_stops(station_id, stop_time)), line_universities(university_id),
      line_period_prices(option, price, is_enabled)`)
    .eq('company_id', companyId).order('name') as unknown as PromiseLike<{ data: LineRow[] | null; error: { message: string } | null }>);

/** A line's stations that are in use, in route order. */
export const activeStations = <S extends { is_active: boolean; order_index: number }>(line?: { stations?: S[] } | null): S[] =>
  (line?.stations ?? []).filter((station) => station.is_active).sort((a, b) => a.order_index - b.order_index);

/** The company's lines in full (lines page, and what the forms choose from). */
export const useLines = (companyId: string, enabled = true) =>
  usePageData(linesKey(companyId), () => loadLines(companyId), { ...reference, enabled });

/** The pure part of `useLineOptions`: active universities and active lines, in the forms' shape. */
export function toLineOptions(universities: UniversityRow[], lines: LineRow[]): LineOptions {
  return {
    universities: universities.filter((university) => university.is_active).map(({ id, name }) => ({ id, name })),
    lines: lines.filter((line) => line.is_active) as unknown as LineOption[],
  };
}

/**
 * What a form chooses from: the active universities and the company's active
 * lines with their stations and trips. Derived from the two cached lookups
 * above, so no page asks for a near-copy of them under a key of its own.
 * `enabled: false` asks for nothing until the form is actually used.
 */
export function useLineOptions(companyId: string, enabled = true) {
  const universities = useUniversities(enabled);
  const lines = useLines(companyId, enabled);
  const data = useMemo(
    () => (universities.data && lines.data ? toLineOptions(universities.data, lines.data) : undefined),
    [universities.data, lines.data]);
  return {
    data,
    loading: enabled && !data && !universities.error && !lines.error,
    error: universities.error || lines.error,
    reload: async () => { await Promise.all([universities.reload(), lines.reload()]); },
  };
}

export interface LineName { id: string; name: string; is_active: boolean }
/** Just the names: report filters, the supervisors' line checkboxes. */
export const useLineNames = (companyId: string) =>
  usePageData(keys.company(companyId, 'lineNames'), () => unwrap<LineName[]>(
    supabase.from('lines').select('id, name, is_active').eq('company_id', companyId).order('name')), reference);

// ── Supervisors ─────────────────────────────────────────────────────
export interface SupervisorRow {
  id: string; phone: string; full_name: string; is_active: boolean; profile_image_url?: string | null;
}
/** The columns of a supervisor the dashboard shows (also what a write to one answers with). */
export const SUPERVISOR_COLUMNS = 'id, phone, full_name, is_active, profile_image_url';
export const useSupervisors = (companyId: string) =>
  usePageData(keys.company(companyId, 'supervisors'), () => unwrap<SupervisorRow[]>(
    supabase.from('supervisors').select(SUPERVISOR_COLUMNS)
      .eq('company_id', companyId).order('created_at', { ascending: false })), reference);

export interface SupervisorLine { supervisor_id: string; line_id: string }
export const useSupervisorLines = (companyId: string) =>
  usePageData(keys.company(companyId, 'supervisorLines'), () => unwrap<SupervisorLine[]>(
    supabase.from('supervisor_lines').select('supervisor_id, line_id').eq('company_id', companyId)), reference);

// ── Company settings read by more than one page ─────────────────────
export interface Switches { annual_effective?: boolean; daily_effective?: boolean; [key: string]: unknown }
export const switchesKey = (companyId: string | null) => (companyId ? keys.company(companyId, 'switches') : keys.platform('switches'));
export const settingsKey = (companyId: string | null) => (companyId ? keys.company(companyId, 'settings') : keys.platform('defaults'));

/** Every company by name: the platform admin's lookup (filters, the workspace switcher). */
export interface CompanyOption { id: string; name: string; status?: string }
export const usePlatformCompanies = (enabled = true) =>
  usePageData(keys.platform('companyNames'), () =>
    unwrap<CompanyOption[]>(supabase.from('companies').select('id, name, status').order('name')), { ...reference, enabled });
