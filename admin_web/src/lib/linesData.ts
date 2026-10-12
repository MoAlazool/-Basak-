/**
 * The lines pages' reads and writes. The lines themselves come from
 * lib/reference.ts (`useLines`, one cached lookup shared with other pages);
 * what is added here:
 *
 *   keys.company(id, 'lines', 'stats')   admin_lines_overview: subscribers, tomorrow's riders
 *                                        (per line and per trip), current subscribers per
 *                                        station and per trip, bus seats, has history.
 *                                        Under 'lines', so a live change to a line refreshes it.
 *   saveLine(payload)                    save_line_full: the whole line in one request.
 *   setLineActive / deleteLine           unchanged server functions, cache edited in place.
 *   useSaleContext(companyId)            which options the company sells (settings' cache).
 *   useVoteSettings(companyId)           get_vote_settings / set_vote_settings.
 *
 * Every new function has a fallback for a database that does not have it yet.
 */
import { useMemo } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { supabase } from './supabase';
import { keys, queryClient, STALE, unwrap, usePageData } from './query';
import { rpcOr } from './rpc';
import { rememberApplied } from './recentChanges';
import { settingsKey, switchesKey, type LineName, type LineRow } from './reference';
import { SALE_OPTIONS, type SaleOption } from './saleOptions';
import type { CompanyNumbers } from './overview';
import type { SavePayload } from './lines';
import type { VoteSettings, VoteValues } from './rideConfirmation';

// ── Numbers per line ─────────────────────────────────────────────────────────
export interface LineStats {
  bus_capacity: number | null;
  /** null: not known (older database). */
  subscribers: number | null;
  riders_departure: number | null;
  riders_return: number | null;
  trip_riders: Record<string, number>;
  station_subscribers: Record<string, number>;
  trip_subscribers: Record<string, number>;
  has_history: boolean | null;
}
export interface LinesStats {
  ride_date: string | null;
  vote_open: boolean | null;
  lines: Record<string, LineStats>;
  /** false when read the older way: riders and per-station counts are unknown. */
  complete: boolean;
}
export const linesStatsKey = (companyId: string) => keys.company(companyId, 'lines', 'stats');
const linesKey = (companyId: string) => keys.company(companyId, 'lines');

export const EMPTY_STATS: LineStats = {
  bus_capacity: null, subscribers: null, riders_departure: null, riders_return: null,
  trip_riders: {}, station_subscribers: {}, trip_subscribers: {}, has_history: null,
};

/** Before 20261116000004: the seats from the lines, the subscribers the overview already has. */
async function statsTheOlderWay(companyId: string): Promise<LinesStats> {
  const seats = await supabase.from('lines').select('id, bus_capacity').eq('company_id', companyId);
  const overview = queryClient.getQueryData<CompanyNumbers>(keys.company(companyId, 'overview'));
  const subs = new Map((overview?.top_lines ?? []).map((l) => [l.id, l.subscribers]));
  const lines: Record<string, LineStats> = {};
  ((seats.data ?? []) as { id: string; bus_capacity: number | null }[]).forEach((row) => {
    lines[row.id] = { ...EMPTY_STATS, bus_capacity: row.bus_capacity ?? null, subscribers: subs.get(row.id) ?? null };
  });
  return { ride_date: overview?.next_ride_date ?? null, vote_open: null, lines, complete: false };
}

export function useLinesStats(companyId: string) {
  return usePageData(linesStatsKey(companyId), () => rpcOr<LinesStats>(
    'admin_lines_overview',
    async () => {
      const { data, error } = await supabase.rpc('admin_lines_overview', { p_company_id: companyId });
      return { data: data ? { ...(data as Omit<LinesStats, 'complete'>), complete: true } : null, error };
    },
    () => statsTheOlderWay(companyId)));
}

export const statsFor = (stats: LinesStats | undefined, lineId: string): LineStats => stats?.lines[lineId] ?? EMPTY_STATS;

// ── Saving a line ────────────────────────────────────────────────────────────
/** The older three-request path stopped after saving the line itself. Saving again (with this id) finishes it. */
export class PartialSaveError extends Error {
  constructor(public lineId: string, message: string) { super(message); this.name = 'PartialSaveError'; }
}

/**
 * One request: save_line_full. On a database that does not have it yet, the
 * older way (save_line, then the prices, then the seats); a failure after the
 * first request is a PartialSaveError carrying the line's id, so the page keeps
 * it and a retry edits that line instead of adding a second one.
 */
export async function saveLine(payload: SavePayload): Promise<string> {
  return rpcOr<string>('save_line_full',
    () => supabase.rpc('save_line_full', { p_line: payload }) as unknown as PromiseLike<{ data: string | null; error: { message: string; code?: string } | null }>,
    async () => {
      const { data: id, error } = await supabase.rpc('save_line', { p_line: payload });
      if (error) throw new Error(error.message);
      const lineId = id as string;
      const prices = await supabase.from('line_period_prices').upsert(
        payload.prices.map((p) => ({ line_id: lineId, option: p.option, price: p.price ?? 0, is_enabled: p.is_enabled })),
        { onConflict: 'line_id,option' });
      const seats = await supabase.rpc('set_line_bus_capacity', { p_line_id: lineId, p_capacity: payload.bus_capacity });
      if (prices.error || seats.error) throw new PartialSaveError(lineId, (prices.error ?? seats.error)!.message);
      return lineId;
    });
}

/** After a save: the line's own rows are not re-read twice; the lists that show it are read once. */
export function afterLineSaved(companyId: string, lineId: string, rowIds: (string | undefined)[]) {
  rememberApplied([lineId, ...rowIds], ['lines', 'lineNames', 'periods']);
  void queryClient.invalidateQueries({ queryKey: keys.company(companyId, 'lineNames') });
  void queryClient.invalidateQueries({ queryKey: keys.company(companyId, 'periods') });
  // What the company sells now follows its lines («مواعيد الاشتراك», adding a student).
  void queryClient.invalidateQueries({ queryKey: settingsKey(companyId) });
  void queryClient.invalidateQueries({ queryKey: switchesKey(companyId) });
  return queryClient.invalidateQueries({ queryKey: linesKey(companyId) });
}

/** Switching on/off or deleting is shown from what was asked and confirmed: both cached lists are edited, nothing re-read. */
function applyToLists(companyId: string, line: LineRow, edit: <T extends { id: string; is_active: boolean }>(rows: T[]) => T[]) {
  rememberApplied([line.id, ...line.stations.map((s) => s.id), ...line.line_trips.map((t) => t.id)], ['lines', 'lineNames']);
  queryClient.setQueryData<LineRow[]>(linesKey(companyId), (rows) => (rows ? edit(rows) : rows));
  queryClient.setQueryData<LineName[]>(keys.company(companyId, 'lineNames'), (rows) => (rows ? edit(rows) : rows));
}

export async function setLineActive(companyId: string, line: LineRow, active: boolean) {
  const { error } = await supabase.rpc('set_line_active', { p_line_id: line.id, p_active: active });
  if (error) throw new Error(error.message);
  applyToLists(companyId, line, (rows) => rows.map((row) => (row.id === line.id ? { ...row, is_active: active } : row)));
  void queryClient.invalidateQueries({ queryKey: keys.company(companyId, 'periods') });
}

/** delete_line refuses a line with subscriptions or records: `refused` then, so the page can offer to stop it. */
export async function deleteLine(companyId: string, line: LineRow): Promise<'deleted' | 'refused'> {
  const { error } = await supabase.rpc('delete_line', { p_line_id: line.id });
  if (error) {
    if ((error as { code?: string }).code === '23503' || /اشتراكات أو سجلات/.test(error.message)) return 'refused';
    throw new Error(error.message);
  }
  applyToLists(companyId, line, (rows) => rows.filter((row) => row.id !== line.id));
  return 'deleted';
}

// ── What the company sells (the subscription pages' cache) ───────────────────
export interface SaleContextData {
  /** What the platform lets a line sell (only «both» and daily can be stopped there). */
  sold: Record<SaleOption, boolean> | null; daily: boolean;
  /** What a new line starts with: the company's switches in «مواعيد الاشتراك». */
  defaults: Record<SaleOption, boolean> | null; dailyDefault: boolean | null;
  known: boolean;
}
export function useSaleContext(companyId: string): SaleContextData {
  const switches = usePageData(switchesKey(companyId), () =>
    unwrap<{ daily_global?: boolean; daily_company?: boolean | null }>(supabase.rpc('get_subscription_switches', { p_company_id: companyId })),
  { staleTime: STALE.reference }).data;
  const settings = usePageData(settingsKey(companyId), () =>
    unwrap<{ annual_global?: boolean; annual_company?: boolean | null; terms?: { code: string; is_on_sale: boolean }[] | null }>(
      supabase.rpc('get_subscription_settings', { p_company_id: companyId })),
  { staleTime: STALE.reference }).data;
  return useMemo(() => {
    // The line decides what it sells; above it only the platform's switches.
    const annual = settings ? settings.annual_global !== false : true;
    const sold = settings ? { first: true, second: true, summer: true, both: annual } : null;
    // A company that never saved its terms starts from the platform's: both terms on, summer off.
    const term = (code: string, fallback: boolean) => settings?.terms?.find((t) => t.code === code)?.is_on_sale ?? fallback;
    const defaults = settings ? {
      first: term('first', true), second: term('second', true), summer: term('summer', false), both: annual && settings.annual_company !== false,
    } : null;
    const daily = switches ? switches.daily_global !== false : true;
    return { sold, daily, defaults, dailyDefault: switches ? daily && switches.daily_company !== false : null, known: !!settings };
  }, [settings, switches]);
}

// ── Ride confirmation ────────────────────────────────────────────────────────
export const voteKey = (companyId: string | null) => (companyId ? keys.company(companyId, 'vote') : keys.platform('vote'));

export function useVoteSettings(companyId: string | null) {
  return usePageData(voteKey(companyId), () => unwrap<VoteSettings>(supabase.rpc('get_vote_settings', { p_company_id: companyId })));
}

/** One request; its answer (the settings as they are now) replaces the cached ones. `null` values go back to the platform's. */
export function useSaveVoteSettings(companyId: string | null) {
  const client = useQueryClient();
  return async (values: VoteValues | null) => {
    const { data, error } = await supabase.rpc('set_vote_settings', {
      p_company_id: companyId,
      p_opens_at: values ? values.opens_at : null,
      p_closes_at: values ? values.closes_at : null,
      p_reminder_minutes: values ? values.reminder_minutes : null,
      p_off_weekdays: values ? values.off_weekdays : null,
      p_off_dates: values ? values.off_dates : null,
    });
    if (error) throw new Error(error.message);
    // The company row's announcement refreshes the overview (it shows when the vote closes), nothing else.
    if (companyId) rememberApplied([companyId], ['company', 'settings', 'switches', 'vote']);
    if (data) client.setQueryData<VoteSettings>(voteKey(companyId), data as VoteSettings);
    else await client.invalidateQueries({ queryKey: voteKey(companyId) });
    return data as VoteSettings | null;
  };
}
