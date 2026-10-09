import React, { useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import { keys, queryClient, STALE, unwrap, usePageData } from '../lib/query';
import {
  activeStations, settingsKey, switchesKey, useLines, useSupervisorLines, useSupervisors, useUniversities, type LineName, type LineRow,
} from '../lib/reference';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { clockLabel, hhmm } from '../lib/time';
import { notifyError } from '../lib/toasts';
import { SkeletonCards } from '../components/Skeleton';
import { SALE_OPTIONS, optionName, type SaleOption, type SaleRow } from '../lib/saleOptions';
import {
  ArrowDown, ArrowUp, Bus, ChevronDown, ChevronUp, Clock, Copy, GraduationCap, MapPin, Pencil,
  Plus, Power, Save, Trash2, UserCheck, Wand2, X,
} from 'lucide-react';

// ── Types ───────────────────────────────────────────────────────────
type Direction = 'departure' | 'return';
type PriceDraft = Record<SaleOption, { price: string; enabled: boolean }>;
interface Option { id: string; name: string }

/** Editor state — stations by position; trip stop times keyed by station key. */
interface StationDraft { key: string; id?: string; name: string }
interface TripDraft {
  key: string; id?: string; direction: Direction; label: string; start_time: string; arrival_time: string;
  university_id: string; is_active: boolean; times: Record<string, string>;
}
interface LineDraft {
  id?: string; company_id: string; name: string; origin_name: string; destination_university_id: string;
  /** Universities served by the line (shared route, stored once). */
  university_ids: string[];
  /** One price and one switch per subscription option. */
  prices: PriceDraft;
  price_daily: string; is_active: boolean;
  stations: StationDraft[]; trips: TripDraft[];
}

// ── Helpers ─────────────────────────────────────────────────────────
const fmt12 = (t?: string | null) => clockLabel(t) || '—';
const addMinutes = (t: string, minutes: number) => {
  const [h, m] = t.split(':').map(Number);
  const total = Math.min(23 * 60 + 59, Math.max(0, h * 60 + m + minutes));
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
};
let keySeq = 0;
const newKey = () => `k${++keySeq}`;
const tripsOf = (line: LineRow, direction: Direction) =>
  (line.line_trips ?? []).filter((t) => t.direction === direction).sort((a, b) => a.start_time.localeCompare(b.start_time));

const emptyTrip = (direction: Direction, start = ''): TripDraft => ({
  key: newKey(), direction, label: '', start_time: start, arrival_time: '', university_id: '', is_active: true, times: {},
});

/**
 * save_line's timing rules, checked while typing: stops in route order and not
 * before the start, and the arrival not before the last stop. `route` is the
 * trip's stations in travel order.
 */
const tripProblem = (trip: TripDraft, route: StationDraft[]): string | null => {
  if (!trip.start_time) return null;
  let prev = trip.start_time;
  let prevLabel = 'موعد الانطلاق';
  for (const s of route) {
    const time = trip.times[s.key];
    if (!time) continue;
    if (time < prev) {
      return `موعد محطة «${s.name || 'بدون اسم'}» (${fmt12(time)}) قبل ${prevLabel} (${fmt12(prev)}). المواعيد يجب أن تكون بترتيب المسار.`;
    }
    prev = time;
    prevLabel = `محطة «${s.name || 'بدون اسم'}»`;
  }
  if (trip.arrival_time && trip.arrival_time < prev) {
    return `موعد الوصول (${fmt12(trip.arrival_time)}) قبل ${prevLabel} (${fmt12(prev)}). عدّل موعد الوصول أو امسحه، أو صحّح موعد المحطة.`;
  }
  return null;
};

const draftFromLine = (line: LineRow): LineDraft => {
  const stations = activeStations(line).map((s) => ({ key: s.id, id: s.id, name: s.name }));
  return {
    id: line.id, company_id: line.company_id, name: line.name, origin_name: line.origin_name || line.name,
    destination_university_id: line.destination_university_id || '',
    university_ids: (line.line_universities ?? []).map((u) => u.university_id).length
      ? (line.line_universities ?? []).map((u) => u.university_id)
      : (line.destination_university_id ? [line.destination_university_id] : []),
    prices: Object.fromEntries(SALE_OPTIONS.map((o) => {
      const row = (line.line_period_prices ?? []).find((p) => p.option === o);
      return [o, row ? { price: String(row.price), enabled: row.is_enabled }
        : { price: String(o === 'both' ? line.price_yearly : line.price_termly), enabled: o === 'first' || o === 'second' }];
    })) as PriceDraft,
    price_daily: String(line.price_daily),
    is_active: line.is_active, stations,
    trips: (line.line_trips ?? []).filter((t) => t.is_active)
      .sort((a, b) => a.direction.localeCompare(b.direction) || a.start_time.localeCompare(b.start_time))
      .map((t) => ({
        key: t.id, id: t.id, direction: t.direction, label: t.label || '', start_time: hhmm(t.start_time),
        arrival_time: hhmm(t.arrival_time), university_id: t.university_id || '', is_active: t.is_active,
        // The way back has no station times: only when the bus leaves the university.
        times: t.direction === 'return' ? {}
          : Object.fromEntries((t.line_trip_stops ?? []).map((s) => [s.station_id, hhmm(s.stop_time)])),
      })),
  };
};

const emptyDraft = (companyId: string): LineDraft => ({
  company_id: companyId, name: '', origin_name: '', destination_university_id: '', university_ids: [],
  prices: {
    first: { price: '3500', enabled: true }, second: { price: '3500', enabled: true },
    both: { price: '6500', enabled: false }, summer: { price: '0', enabled: false },
  },
  price_daily: '50', is_active: true,
  stations: [{ key: newKey(), name: '' }],
  trips: [emptyTrip('departure', '07:00'), emptyTrip('return', '14:00')],
});

// ── Page ────────────────────────────────────────────────────────────
export const LinesPage: React.FC = () => {
  const company = useCompany();
  const [expanded, setExpanded] = useState<string | null>(null);
  const [draft, setDraft] = useState<LineDraft | null>(null);
  const [busyLine, setBusyLine] = useState<string | null>(null);

  // Same cache entry as the settings page: switching a type off shows here at once.
  const switches = usePageData(switchesKey(company.id), () =>
    unwrap<{ annual_effective: boolean; daily_effective: boolean }>(
      supabase.rpc('get_subscription_switches', { p_company_id: company.id })), { staleTime: STALE.reference }).data;
  // Each lookup is cached once and shared with the other pages that show it.
  const page = useLines(company.id);
  const allUniversities = useUniversities().data;
  const supervisors = useSupervisors(company.id).data ?? [];
  const assignments = useSupervisorLines(company.id).data;
  const lines = page.data ?? [];
  const universities = useMemo(() => (allUniversities ?? []).filter((u) => u.is_active), [allUniversities]);
  const lineSupervisors = useMemo(() => {
    const byLine: Record<string, string[]> = {};
    (assignments ?? []).forEach((row) => { (byLine[row.line_id] ||= []).push(row.supervisor_id); });
    return byLine;
  }, [assignments]);
  const loading = page.loading;
  const pageError = page.error;
  // After a line is saved: the lines, plus the light list and the payable periods derived from them.
  const fetchData = async () => {
    void queryClient.invalidateQueries({ queryKey: keys.company(company.id, 'lineNames') });
    void queryClient.invalidateQueries({ queryKey: keys.company(company.id, 'periods') });
    await page.reload();
  };
  const guard = useGuard();
  const linesKey = keys.company(company.id, 'lines');
  const namesKey = keys.company(company.id, 'lineNames');
  // Switching a line on/off or deleting it is shown from what was asked and confirmed
  // by the server: both cached lists are edited, and the announcement of the line's own
  // rows re-reads neither (the payable periods and the company's numbers still follow it).
  const applyToLists = (line: LineRow, edit: <T extends { id: string; is_active: boolean }>(rows: T[]) => T[]) => {
    rememberApplied([line.id, ...line.stations.map((s) => s.id), ...line.line_trips.map((t) => t.id)], ['lines', 'lineNames']);
    queryClient.setQueryData<LineRow[]>(linesKey, (rows) => (rows ? edit(rows) : rows));
    queryClient.setQueryData<LineName[]>(namesKey, (rows) => (rows ? edit(rows) : rows));
  };

  const uniName = (id?: string | null) => (allUniversities ?? []).find((u) => u.id === id)?.name;

  const toggleLine = (line: LineRow) => guard(line.id, async () => {
    const next = !line.is_active;
    if (!next && !confirm(`تعطيل خط "${line.name}"؟\nسيبقى بكل بياناته واشتراكاته وسجلاته، لكنه لن يظهر للطلاب ولن يُسند لمشرفين جدد.`)) return;
    setBusyLine(line.id);
    const { error } = await supabase.rpc('set_line_active', { p_line_id: line.id, p_active: next });
    setBusyLine(null);
    if (error) notifyError('تعذر تغيير حالة الخط', error.message);
    else applyToLists(line, (rows) => rows.map((row) => (row.id === line.id ? { ...row, is_active: next } : row)));
  });

  const deleteLine = (line: LineRow) => guard(line.id, async () => {
    if (!confirm(`حذف خط "${line.name}" نهائياً مع محطاته ورحلاته؟\nلا يمكن التراجع. الخطوط التي لها اشتراكات أو سجلات لا تُحذف — عطّلها بدلاً من ذلك.`)) return;
    setBusyLine(line.id);
    const { error } = await supabase.rpc('delete_line', { p_line_id: line.id });
    setBusyLine(null);
    if (error) notifyError('تعذر حذف الخط', error.message);
    else applyToLists(line, (rows) => rows.filter((row) => row.id !== line.id));
  });

  const defaultCompany = company.id;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">إدارة خطوط السير</h1>
          <p className="text-sm text-slate-500">كل خط له اسم قصير، الجامعات التي يخدمها، محطات الصعود، ورحلات الذهاب ومواعيد العودة من الجامعة</p>
        </div>
        <button
          onClick={() => setDraft(emptyDraft(defaultCompany))}
          className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50"
        >
          <Plus className="h-4 w-4" /> إنشاء خط جديد
        </button>
      </div>

      {pageError && (
        <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
          تعذر تحميل الخطوط: {pageError}
          <button className="mr-3 underline" onClick={() => void fetchData()}>إعادة المحاولة</button>
        </div>
      )}

      {loading ? (
        <SkeletonCards count={3} />
      ) : lines.length === 0 ? (
        <div className="rounded-2xl border border-slate-100 bg-white p-10 text-center text-slate-500">
          لا توجد خطوط بعد. اضغط «إنشاء خط جديد» لإضافة الخط بمحطاته ورحلاته في خطوة واحدة.
        </div>
      ) : (
        <div className="space-y-4">
          {lines.map((line) => {
            const stations = activeStations(line);
            const dep = tripsOf(line, 'departure').filter((t) => t.is_active);
            const ret = tripsOf(line, 'return').filter((t) => t.is_active);
            const isOpen = expanded === line.id;
            const sups = (lineSupervisors[line.id] ?? []).map((id) => supervisors.find((s) => s.id === id)?.full_name).filter(Boolean);
            return (
              <div key={line.id} className={`overflow-hidden rounded-2xl border bg-white shadow-sm ${line.is_active ? 'border-slate-100' : 'border-slate-200 opacity-75'}`}>
                <div className="flex flex-wrap items-start justify-between gap-4 p-5">
                  <div className="min-w-0 flex-1 space-y-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="text-lg font-bold text-slate-800">{line.name}</h3>
                      <span className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold ${line.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>
                        {line.is_active ? 'نشط' : 'معطّل'}
                      </span>
                    </div>
                    {/* Boarding stations in order; each student ends at their own university */}
                    <div className="flex flex-wrap items-center gap-1.5 text-xs">
                      <span className="text-slate-400">المحطات:</span>
                      {stations.map((st) => (
                        <span key={st.id} className="rounded-lg bg-slate-50 px-2 py-1 text-slate-600">{st.name}</span>
                      ))}
                    </div>
                    <div className="flex flex-wrap items-center gap-1.5 text-[11px]">
                      <span className="text-slate-400">الوجهة (الجامعات):</span>
                      {(line.line_universities ?? []).length === 0
                        ? <span className="rounded-lg bg-amber-50 px-2 py-0.5 font-semibold text-amber-700">غير محددة — عدّل الخط واختر الجامعات</span>
                        : (line.line_universities ?? []).map((u) => (
                          <span key={u.university_id} className="rounded-lg bg-indigo-50/70 px-2 py-0.5 font-semibold text-indigo-700">{uniName(u.university_id)}</span>
                        ))}
                    </div>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-slate-500">
                      <span className="rounded-lg bg-emerald-50 px-2 py-1 font-semibold text-emerald-700">{dep.length} رحلة ذهاب</span>
                      <span className="rounded-lg bg-amber-50 px-2 py-1 font-semibold text-amber-700">{ret.length} رحلة عودة</span>
                      <span>{[
                        ...SALE_OPTIONS.map((o) => (line.line_period_prices ?? []).find((p) => p.option === o))
                          .filter((p) => p?.is_enabled && !(p.option === 'both' && switches && !switches.annual_effective))
                          .map((p) => `${optionName[p!.option]} ${p!.price} ج.م`),
                        switches && !switches.daily_effective ? 'يومي معطّل' : `يومي ${line.price_daily} ج.م`,
                      ].join(' · ')}</span>
                      <span className="inline-flex items-center gap-1"><UserCheck className="h-3.5 w-3.5" />{sups.length ? sups.join('، ') : 'بدون مشرف (من صفحة المشرفين)'}</span>
                    </div>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <button onClick={() => setExpanded(isOpen ? null : line.id)} className="flex items-center gap-1 rounded-xl border border-slate-200 px-3 py-2 text-xs font-bold text-slate-600 hover:bg-slate-50">
                      <Clock className="h-3.5 w-3.5" /> المواعيد {isOpen ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                    </button>
                    <button onClick={() => setDraft(draftFromLine(line))} className="flex items-center gap-1 rounded-xl bg-blue-50 px-3 py-2 text-xs font-bold text-blue-700 hover:bg-blue-100">
                      <Pencil className="h-3.5 w-3.5" /> تعديل
                    </button>
                    <button disabled={busyLine === line.id} onClick={() => void toggleLine(line)}
                      className={`flex items-center gap-1 rounded-xl px-3 py-2 text-xs font-bold ${line.is_active ? 'bg-amber-50 text-amber-700 hover:bg-amber-100' : 'bg-emerald-50 text-emerald-700 hover:bg-emerald-100'}`}>
                      <Power className="h-3.5 w-3.5" /> {line.is_active ? 'تعطيل' : 'تفعيل'}
                    </button>
                    <button disabled={busyLine === line.id} onClick={() => void deleteLine(line)} className="flex items-center gap-1 rounded-xl bg-rose-50 px-3 py-2 text-xs font-bold text-rose-600 hover:bg-rose-100">
                      <Trash2 className="h-3.5 w-3.5" /> حذف
                    </button>
                  </div>
                </div>
                {isOpen && <Timetable line={line} uniName={uniName} />}
              </div>
            );
          })}
        </div>
      )}

      {draft && (
        <LineEditor
          initial={draft}
          universities={universities}
          onClose={() => setDraft(null)}
          onSaved={() => { setDraft(null); void fetchData(); }}
        />
      )}
    </div>
  );
};

// ── Read-only timetable (departure / return tabs, stop list per trip) ─
const Timetable: React.FC<{ line: LineRow; uniName: (id?: string | null) => string | undefined }> = ({ line, uniName }) => {
  const [tab, setTab] = useState<Direction>('departure');
  const stations = activeStations(line);
  const trips = tripsOf(line, tab).filter((t) => t.is_active);
  const ordered = stations;
  return (
    <div className="border-t border-slate-100 bg-slate-50/50 p-5">
      <div className="mb-4 inline-flex rounded-xl bg-white p-1 shadow-sm">
        {(['departure', 'return'] as Direction[]).map((d) => (
          <button key={d} onClick={() => setTab(d)}
            className={`rounded-lg px-4 py-1.5 text-xs font-bold ${tab === d ? 'bg-blue-600 text-white' : 'text-slate-500'}`}>
            {d === 'departure' ? 'الذهاب' : 'العودة'} ({tripsOf(line, d).filter((t) => t.is_active).length})
          </button>
        ))}
      </div>
      {trips.length === 0 ? (
        <p className="text-sm text-slate-400">لا توجد رحلات {tab === 'departure' ? 'ذهاب' : 'عودة'}.</p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {trips.map((trip) => {
            const times = Object.fromEntries((trip.line_trip_stops ?? []).map((s) => [s.station_id, s.stop_time]));
            return (
              <div key={trip.id} className="rounded-2xl border-r-4 border-emerald-400 bg-white p-4 shadow-sm">
                <div className="mb-3 flex items-center justify-between gap-2">
                  <div>
                    <p className="text-xl font-extrabold text-slate-800">{fmt12(trip.start_time)}</p>
                    <p className="text-xs text-slate-500">{trip.label || (tab === 'departure' ? 'رحلة ذهاب' : 'رحلة عودة')}</p>
                  </div>
                  <span className="rounded-full bg-indigo-50 px-2.5 py-1 text-[11px] font-bold text-indigo-700">
                    {trip.university_id ? uniName(trip.university_id) : 'كل الجامعات'}
                  </span>
                </div>
                {tab === 'return' ? (
                  <p className="text-xs text-slate-500">يتحرك الباص من الجامعة في هذا الموعد ويعيد كل طالب إلى محطته.</p>
                ) : (
                  <ol className="relative space-y-2 border-r-2 border-emerald-100 pr-4">
                    {ordered.map((s) => (
                      <li key={s.id} className="relative flex items-center justify-between rounded-xl bg-slate-50 px-3 py-2 text-sm">
                        <span className={`absolute -right-[23px] h-3 w-3 rounded-full border-2 ${times[s.id] ? 'border-emerald-500 bg-white' : 'border-slate-200 bg-slate-100'}`} />
                        <span className="text-slate-700">{s.name}</span>
                        <span className={`rounded-lg px-2 py-0.5 text-xs font-bold ${times[s.id] ? 'bg-emerald-50 text-emerald-700' : 'text-slate-300'}`}>
                          {times[s.id] ? fmt12(times[s.id]) : 'لا يقف'}
                        </span>
                      </li>
                    ))}
                  </ol>
                )}
                {tab === 'departure' && trip.arrival_time && <p className="mt-3 text-xs text-slate-500">الوصول: {fmt12(trip.arrival_time)}</p>}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

// ── Create / edit a complete line in one save ───────────────────────
interface LineEditorProps {
  initial: LineDraft;
  universities: Option[];
  onClose: () => void;
  onSaved: () => void;
}

const LineEditor: React.FC<LineEditorProps> = ({ initial, universities, onClose, onSaved }) => {
  const [d, setD] = useState<LineDraft>(initial);
  const [tab, setTab] = useState<Direction>('departure');
  const [gap, setGap] = useState('10');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const patch = (p: Partial<LineDraft>) => setD((cur) => ({ ...cur, ...p }));

  // A subscription type the company (or the platform) has switched off: its
  // price is locked here; the saved price stays as it was.
  // Both are read through the cache the settings page fills: opening the form
  // asks the network for neither when they are already known.
  const switchesData = usePageData(switchesKey(d.company_id), () =>
    unwrap<{ daily_effective?: boolean }>(supabase.rpc('get_subscription_switches', { p_company_id: d.company_id })),
  { enabled: !!d.company_id, staleTime: STALE.reference }).data;
  const offered = { daily: switchesData ? !!switchesData.daily_effective : true };
  // The company is the ceiling: an option it does not sell stays off for students
  // whatever the line says, so it is shown greyed here with the reason.
  const settingsData = usePageData(settingsKey(d.company_id), () =>
    unwrap<{ sale_periods?: SaleRow[] }>(supabase.rpc('get_subscription_settings', { p_company_id: d.company_id })),
  { enabled: !!d.company_id, staleTime: STALE.reference }).data;
  const companySells = useMemo(() => {
    if (!settingsData) return null;
    const rows = settingsData.sale_periods ?? [];
    return Object.fromEntries(SALE_OPTIONS.map((o) => {
      const row = rows.find((r) => r.option === o);
      return [o, !!row && row.reason !== 'company_not_selling' && row.reason !== 'company_inactive'];
    })) as Record<SaleOption, boolean>;
  }, [settingsData]);
  const patchPrice = (o: SaleOption, p: Partial<PriceDraft[SaleOption]>) =>
    setD((cur) => ({ ...cur, prices: { ...cur.prices, [o]: { ...cur.prices[o], ...p } } }));
  const priceOf = (o: SaleOption) => Number(d.prices[o].price) || 0;
  const bothWarning = !d.prices.both.enabled || priceOf('both') <= 0 ? null
    : priceOf('both') < Math.max(priceOf('first'), priceOf('second'))
      ? 'سعر الفصلين معاً أقل من سعر فصل واحد. راجع السعر.'
      : priceOf('both') > priceOf('first') + priceOf('second')
        ? 'سعر الفصلين معاً أكبر من مجموع الفصلين. راجع السعر.' : null;

  const patchTrip = (key: string, p: Partial<TripDraft>) =>
    setD((cur) => ({ ...cur, trips: cur.trips.map((t) => (t.key === key ? { ...t, ...p } : t)) }));
  const routeFor = (direction: Direction) => (direction === 'departure' ? d.stations : [...d.stations].reverse());

  // Stations
  const moveStation = (i: number, delta: number) => setD((cur) => {
    const list = [...cur.stations];
    const j = i + delta;
    if (j < 0 || j >= list.length) return cur;
    [list[i], list[j]] = [list[j], list[i]];
    return { ...cur, stations: list };
  });
  const removeStation = (key: string) => setD((cur) => ({
    ...cur,
    stations: cur.stations.filter((s) => s.key !== key),
    trips: cur.trips.map((t) => { const times = { ...t.times }; delete times[key]; return { ...t, times }; }),
  }));

  // Fill a trip's stop times from its start time, N minutes between stations.
  const autoFill = (trip: TripDraft) => {
    if (!trip.start_time) { setError('حدد موعد انطلاق الرحلة أولاً.'); return; }
    const step = Math.max(0, Number(gap) || 0);
    const times: Record<string, string> = {};
    routeFor(trip.direction).forEach((s, i) => { times[s.key] = addMinutes(trip.start_time, step * (i + 1)); });
    const arrival = addMinutes(trip.start_time, step * (d.stations.length + 1));
    const lastStop = addMinutes(trip.start_time, step * d.stations.length);
    // A return trip keeps its own arrival, unless it now falls before the last stop.
    const keepArrival = trip.direction === 'return' && trip.arrival_time && trip.arrival_time >= lastStop;
    patchTrip(trip.key, { times, arrival_time: keepArrival ? trip.arrival_time : arrival });
  };


  const duplicate = (trip: TripDraft) => setD((cur) => ({
    ...cur, trips: [...cur.trips, { ...trip, key: newKey(), id: undefined, label: '', times: { ...trip.times } }],
  }));

  const saveGuard = useGuard();
  // One save at a time: a second click cannot send the line twice.
  const save = () => saveGuard('save', saveLine);
  const saveLine = async () => {
    setError('');
    if (d.university_ids.length === 0) { setError('اختر جامعة واحدة على الأقل يخدمها الخط.'); return; }
    const noPrice = SALE_OPTIONS.find((o) => d.prices[o].enabled && priceOf(o) <= 0);
    if (noPrice) { setError(`اكتب سعر «${optionName[noPrice]}» أو عطّله.`); return; }
    const noReturnTime = d.trips.find((t) => t.direction === 'return' && !t.start_time);
    if (noReturnTime) { setTab('return'); setError('حدد موعد تحرك كل رحلة عودة من الجامعة.'); return; }
    const noStops = d.trips.find((t) => t.direction === 'departure' && !Object.values(t.times).some(Boolean));
    if (noStops) {
      setTab('departure');
      setError(`رحلة الذهاب ${fmt12(noStops.start_time)}: حدد موعد مرورها على المحطات، فالطلاب يركبون منها.`);
      return;
    }
    const badTrip = d.trips.find((t) => t.direction === 'departure' && tripProblem(t, routeFor(t.direction)));
    if (badTrip) {
      setTab(badTrip.direction);
      setError(`${badTrip.direction === 'departure' ? 'رحلة الذهاب' : 'رحلة العودة'} ${fmt12(badTrip.start_time)}: ${tripProblem(badTrip, routeFor(badTrip.direction))}`);
      return;
    }
    const stations = d.stations.map((s) => ({ ...s, name: s.name.trim() }));
    const indexOf = new Map(stations.map((s, i) => [s.key, i]));
    const payload = {
      id: d.id ?? null,
      company_id: d.company_id,
      // The short name defaults to where the line starts.
      // Empty: the server names it after the first station. The start point
      // and the destination are not entered: the student's station and university are.
      name: d.name.trim(),
      origin_name: '',
      destination_university_id: null,
      university_ids: d.university_ids,
      // Older clients read these two; the per-option prices below are what is sold.
      price_termly: priceOf('first'), price_yearly: priceOf('both'), price_daily: Number(d.price_daily),
      is_active: d.is_active,
      stations: stations.map((s) => ({ id: s.id ?? null, name: s.name })),
      trips: d.trips.map((t) => ({
        id: t.id ?? null, direction: t.direction, label: t.label.trim(), start_time: t.start_time,
        arrival_time: t.direction === 'departure' ? t.arrival_time || null : null,
        university_id: t.university_id || null, is_active: t.is_active,
        // A return trip is a time and a university; it has no stops.
        stops: t.direction === 'return' ? []
          : Object.entries(t.times).filter(([key, time]) => time && indexOf.has(key))
            .map(([key, time]) => ({ station_index: indexOf.get(key), time })),
      })),
    };
    setSaving(true);
    const { data: lineId, error: rpcError } = await supabase.rpc('save_line', { p_line: payload });
    if (rpcError) { setSaving(false); setError(rpcError.message); return; }
    const { error: priceError } = await supabase.from('line_period_prices').upsert(
      SALE_OPTIONS.map((o) => ({ line_id: lineId as string, option: o, price: priceOf(o), is_enabled: d.prices[o].enabled })),
      { onConflict: 'line_id,option' });
    setSaving(false);
    // The page reads the saved line once (below, through onSaved). The rows it already knew
    // announce their change too; that announcement does not read the lines a second time.
    rememberApplied([lineId as string, ...d.stations.map((s) => s.id), ...d.trips.map((t) => t.id)], ['lines', 'lineNames', 'periods']);
    if (priceError) setError('تم حفظ الخط لكن تعذر حفظ الأسعار: ' + priceError.message);
    else onSaved();
  };

  const tripsInTab = d.trips.filter((t) => t.direction === tab);
  const input = 'w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none';

  return (
    <div className="fixed inset-0 z-50 flex items-stretch justify-center bg-slate-900/40 p-0 sm:p-6" dir="rtl">
      <div className="flex w-full max-w-5xl flex-col overflow-hidden bg-white shadow-2xl sm:rounded-3xl">
        <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
          <h2 className="text-lg font-bold text-slate-800">{d.id ? `تعديل خط: ${initial.name}` : 'إنشاء خط جديد'}</h2>
          <button onClick={onClose} className="rounded-lg p-1 text-slate-400 hover:bg-slate-100" aria-label="إغلاق"><X className="h-5 w-5" /></button>
        </div>

        <div className="flex-1 space-y-6 overflow-y-auto px-6 py-5">
          {/* 1. Line details */}
          <section className="space-y-3">
            <h3 className="text-sm font-bold text-slate-700">١. بيانات الخط</h3>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <label className="text-xs font-semibold text-slate-500 sm:col-span-2">اسم الخط (قصير)
                <input value={d.name} maxLength={40} onChange={(e) => patch({ name: e.target.value.replace(/[←→]/g, '') })}
                  placeholder={d.stations[0]?.name.trim() || 'مثال: منية النصر'} className={`mt-1 ${input}`} />
                <span className="mt-1 block text-[11px] font-normal text-slate-400">
                  اسم المنطقة يكفي. إذا تركته فارغاً يأخذ اسم أول محطة. لا تكتب فيه الجامعات: وجهة كل طالب هي جامعته، وبدايته هي المحطة التي يختارها.
                </span>
              </label>
              <fieldset className="sm:col-span-2 lg:col-span-4">
                <legend className="text-xs font-semibold text-slate-500">وجهة الخط: الجامعات التي يخدمها ({d.university_ids.length} مختارة)</legend>
                <div className="mt-1 flex flex-wrap gap-2 rounded-xl border border-slate-200 p-2">
                  {universities.map((u) => {
                    const on = d.university_ids.includes(u.id);
                    return (
                      <label key={u.id} className={`flex cursor-pointer items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-xs font-semibold ${on ? 'border-indigo-400 bg-indigo-50 text-indigo-700' : 'border-slate-200 text-slate-600'}`}>
                        <input type="checkbox" checked={on} onChange={() => setD((cur) => {
                          const ids = on ? cur.university_ids.filter((x) => x !== u.id) : [...cur.university_ids, u.id];
                          return {
                            ...cur, university_ids: ids,
                            destination_university_id: ids.includes(cur.destination_university_id) ? cur.destination_university_id : '',
                            // A trip can only target a university the line serves.
                            trips: cur.trips.map((t) => (t.university_id && !ids.includes(t.university_id) ? { ...t, university_id: '' } : t)),
                          };
                        })} />
                        {u.name}
                      </label>
                    );
                  })}
                </div>
              </fieldset>
              <fieldset className="sm:col-span-2 lg:col-span-4">
                <legend className="text-xs font-semibold text-slate-500">أسعار الاشتراك لهذا الخط</legend>
                <div className="mt-1 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  {SALE_OPTIONS.map((o) => {
                    const sold = companySells ? companySells[o] : true;
                    const on = d.prices[o].enabled;
                    return (
                      <div key={o} className={`rounded-xl border p-3 ${!sold ? 'border-slate-200 bg-slate-50' : on ? 'border-blue-200 bg-blue-50/40' : 'border-slate-200'}`}>
                        <label className="flex cursor-pointer items-center justify-between gap-2 text-xs font-bold text-slate-700">
                          {optionName[o]}
                          <input type="checkbox" checked={on} onChange={(e) => patchPrice(o, { enabled: e.target.checked })} aria-label={`بيع ${optionName[o]} على هذا الخط`} />
                        </label>
                        <div className="mt-2 flex items-center gap-1">
                          <input type="number" min={0} value={d.prices[o].price} disabled={!on}
                            onChange={(e) => patchPrice(o, { price: e.target.value })}
                            className={`${input} disabled:bg-slate-100 disabled:text-slate-400`} aria-label={`سعر ${optionName[o]}`} />
                          <span className="text-[11px] text-slate-400">ج.م</span>
                        </div>
                        <span className="mt-1 block text-[11px] font-normal text-slate-400">
                          {!sold ? 'الشركة لا تبيع هذه الفترة (من الإعدادات)، فلن تظهر للطلاب.' : on ? 'يظهر للطلاب في موعده.' : 'معطّل على هذا الخط.'}
                        </span>
                      </div>
                    );
                  })}
                </div>
                {bothWarning && <p role="alert" className="mt-2 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-700">{bothWarning}</p>}
              </fieldset>
              <label className="text-xs font-semibold text-slate-500">سعر اليومي كاش (ج.م)
                <input type="number" min={0} value={offered.daily ? d.price_daily : 0} disabled={!offered.daily}
                  onChange={(e) => patch({ price_daily: e.target.value })} className={`mt-1 ${input} disabled:bg-slate-100 disabled:text-slate-400`} />
                {!offered.daily && <span className="mt-1 block text-[11px] font-normal text-slate-400">الاشتراك اليومي معطّل من الإعدادات.</span>}
              </label>
            </div>
          </section>

          {/* 2. Route */}
          <section className="space-y-3">
            <h3 className="text-sm font-bold text-slate-700">٢. محطات الصعود (بترتيب المسار)</h3>
            <div className="space-y-2 rounded-2xl bg-slate-50 p-4">
              {d.stations.map((s, i) => (
                <div key={s.key} className="flex items-center gap-2">
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white text-xs font-bold text-slate-500 shadow-sm">{i + 1}</span>
                  <MapPin className="h-4 w-4 shrink-0 text-slate-400" />
                  <input value={s.name} placeholder={`اسم المحطة ${i + 1}`}
                    onChange={(e) => setD((cur) => ({ ...cur, stations: cur.stations.map((x) => (x.key === s.key ? { ...x, name: e.target.value } : x)) }))}
                    className={input} />
                  <button onClick={() => moveStation(i, -1)} disabled={i === 0} className="rounded-lg p-1.5 text-slate-400 hover:bg-white disabled:opacity-30" title="لأعلى"><ArrowUp className="h-4 w-4" /></button>
                  <button onClick={() => moveStation(i, 1)} disabled={i === d.stations.length - 1} className="rounded-lg p-1.5 text-slate-400 hover:bg-white disabled:opacity-30" title="لأسفل"><ArrowDown className="h-4 w-4" /></button>
                  <button onClick={() => removeStation(s.key)} disabled={d.stations.length === 1} className="rounded-lg p-1.5 text-slate-400 hover:text-rose-500 disabled:opacity-30" title="حذف المحطة"><Trash2 className="h-4 w-4" /></button>
                </div>
              ))}
              <button onClick={() => setD((cur) => ({ ...cur, stations: [...cur.stations, { key: newKey(), name: '' }] }))}
                className="flex items-center gap-1 rounded-xl border border-dashed border-slate-300 px-3 py-2 text-xs font-bold text-slate-600 hover:bg-white">
                <Plus className="h-3.5 w-3.5" /> إضافة محطة
              </button>
              <div className="flex items-center gap-2 rounded-xl bg-indigo-50 px-3 py-2 text-sm font-bold text-indigo-700"><GraduationCap className="h-4 w-4" /> الوجهة: {d.university_ids.map((id) => universities.find((u) => u.id === id)?.name).filter(Boolean).join('، ') || 'اختر الجامعات أعلاه'}</div>
            </div>
          </section>

          {/* 3. Trips */}
          <section className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h3 className="text-sm font-bold text-slate-700">٣. الرحلات والمواعيد</h3>
              <label className={`flex items-center gap-2 text-xs text-slate-500 ${tab === 'return' ? 'invisible' : ''}`}>
                <Wand2 className="h-4 w-4 text-blue-500" /> التعبئة التلقائية: كل
                <input type="number" min={0} value={gap} onChange={(e) => setGap(e.target.value)} className="w-16 rounded-lg border border-slate-200 px-2 py-1 text-xs" />
                دقيقة بين المحطات
              </label>
            </div>
            <div className="inline-flex rounded-xl bg-slate-100 p-1">
              {(['departure', 'return'] as Direction[]).map((dir) => (
                <button key={dir} onClick={() => setTab(dir)}
                  className={`rounded-lg px-4 py-1.5 text-xs font-bold ${tab === dir ? 'bg-white text-blue-700 shadow-sm' : 'text-slate-500'}`}>
                  {dir === 'departure' ? 'رحلات الذهاب' : 'العودة من الجامعة'} ({d.trips.filter((t) => t.direction === dir).length})
                </button>
              ))}
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              {tripsInTab.map((trip) => (
                tab === 'return' ? (
                <div key={trip.key} className="space-y-3 rounded-2xl border border-slate-200 p-4">
                  <div className="grid grid-cols-2 gap-2">
                    <label className="text-[11px] font-semibold text-slate-500">موعد التحرك من الجامعة
                      <input type="time" value={trip.start_time} onChange={(e) => patchTrip(trip.key, { start_time: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                    <label className="text-[11px] font-semibold text-slate-500">من جامعة
                      <select value={trip.university_id} onChange={(e) => patchTrip(trip.key, { university_id: e.target.value })} className={`mt-1 ${input}`}>
                        <option value="">كل جامعات الخط</option>
                        {universities.filter((u) => d.university_ids.includes(u.id)).map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
                      </select>
                    </label>
                    <label className="col-span-2 text-[11px] font-semibold text-slate-500">اسم الرحلة (اختياري)
                      <input value={trip.label} placeholder="مثال: عودة الظهر" onChange={(e) => patchTrip(trip.key, { label: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                  </div>
                  <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
                    <button onClick={() => duplicate(trip)} className="flex items-center gap-1 rounded-lg bg-slate-100 px-2.5 py-1.5 text-[11px] font-bold text-slate-600"><Copy className="h-3 w-3" /> نسخ الموعد</button>
                    <button onClick={() => setD((cur) => ({ ...cur, trips: cur.trips.filter((t) => t.key !== trip.key) }))}
                      className="flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-[11px] font-bold text-rose-500 hover:bg-rose-50"><Trash2 className="h-3 w-3" /> حذف</button>
                  </div>
                </div>
                ) : (
                <div key={trip.key} className="space-y-3 rounded-2xl border border-slate-200 p-4">
                  <div className="grid grid-cols-2 gap-2">
                    <label className="text-[11px] font-semibold text-slate-500">موعد الانطلاق
                      <input type="time" value={trip.start_time} onChange={(e) => patchTrip(trip.key, { start_time: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                    <label className="text-[11px] font-semibold text-slate-500">موعد الوصول (اختياري)
                      <input type="time" value={trip.arrival_time} onChange={(e) => patchTrip(trip.key, { arrival_time: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                    <label className="text-[11px] font-semibold text-slate-500">اسم الرحلة (اختياري)
                      <input value={trip.label} placeholder="مثال: أول رحلة صباحية" onChange={(e) => patchTrip(trip.key, { label: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                    <label className="text-[11px] font-semibold text-slate-500">الجامعة
                      <select value={trip.university_id} onChange={(e) => patchTrip(trip.key, { university_id: e.target.value })} className={`mt-1 ${input}`}>
                        <option value="">كل جامعات الخط</option>
                        {universities.filter((u) => d.university_ids.includes(u.id)).map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
                      </select>
                    </label>
                  </div>
                  <div className="space-y-1.5">
                    {routeFor(tab).map((s) => (
                      <div key={s.key} className="flex items-center gap-2 rounded-xl bg-slate-50 px-3 py-1.5">
                        <span className="flex-1 truncate text-sm text-slate-700">{s.name || 'محطة بدون اسم'}</span>
                        <input type="time" value={trip.times[s.key] ?? ''}
                          onChange={(e) => patchTrip(trip.key, { times: { ...trip.times, [s.key]: e.target.value } })}
                          className="w-28 rounded-lg border border-slate-200 bg-white px-2 py-1 text-xs" aria-label={`موعد ${s.name}`} />
                        {trip.times[s.key] && (
                          <button onClick={() => { const times = { ...trip.times }; delete times[s.key]; patchTrip(trip.key, { times }); }}
                            className="text-slate-300 hover:text-rose-400" title="الرحلة لا تقف هنا"><X className="h-3.5 w-3.5" /></button>
                        )}
                      </div>
                    ))}
                  </div>
                  {tripProblem(trip, routeFor(tab)) && (
                    <p role="alert" className="rounded-xl bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700">{tripProblem(trip, routeFor(tab))}</p>
                  )}
                  <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
                    <div className="flex gap-2">
                      <button onClick={() => autoFill(trip)} className="flex items-center gap-1 rounded-lg bg-blue-50 px-2.5 py-1.5 text-[11px] font-bold text-blue-700"><Wand2 className="h-3 w-3" /> تعبئة تلقائية</button>
                      <button onClick={() => duplicate(trip)} className="flex items-center gap-1 rounded-lg bg-slate-100 px-2.5 py-1.5 text-[11px] font-bold text-slate-600"><Copy className="h-3 w-3" /> نسخ الرحلة</button>
                    </div>
                    <button onClick={() => setD((cur) => ({ ...cur, trips: cur.trips.filter((t) => t.key !== trip.key) }))}
                      className="flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-[11px] font-bold text-rose-500 hover:bg-rose-50"><Trash2 className="h-3 w-3" /> حذف الرحلة</button>
                  </div>
                </div>
                )
              ))}
              <button onClick={() => setD((cur) => ({ ...cur, trips: [...cur.trips, emptyTrip(tab)] }))}
                className="flex min-h-[120px] items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-slate-200 text-sm font-bold text-slate-500 hover:bg-slate-50">
                <Bus className="h-4 w-4" /> {tab === 'departure' ? 'إضافة رحلة ذهاب' : 'إضافة موعد عودة'}
              </button>
            </div>
            {(() => {
              // Universities with no departure trip would never see the line.
              const uncovered = d.university_ids.filter((id) => !d.trips.some((t) => t.direction === 'departure' && (!t.university_id || t.university_id === id)));
              return uncovered.length > 0 && (
                <p role="alert" className="rounded-xl bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                  لا توجد رحلة ذهاب لـ: {uncovered.map((id) => universities.find((u) => u.id === id)?.name).join('، ')} — طلابها لن يروا الخط. اجعل رحلة لـ«كل جامعات الخط» أو أضف رحلة لها.
                </p>
              );
            })()}
            <p className="text-[11px] text-slate-400">
              {tab === 'departure'
                ? 'مواعيد المحطات بترتيب المسار. اترك موعد محطة فارغاً إذا كانت الرحلة لا تقف عندها. الرحلة المخصصة لجامعة تظهر لطلاب هذه الجامعة فقط.'
                : 'العودة تبدأ من جامعة الطالب: حدد موعد تحرك الباص من كل جامعة فقط، ويعود كل طالب إلى محطته. لا توجد محطات للعودة.'}
            </p>
          </section>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 px-6 py-4">
          {error ? <p role="alert" className="flex-1 rounded-xl bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p> : <span className="flex-1 text-xs text-slate-400">يُحفظ الخط بمحطاته ورحلاته في عملية واحدة.</span>}
          <div className="flex gap-2">
            <button onClick={onClose} className="rounded-xl border border-slate-200 px-5 py-2.5 text-sm font-bold text-slate-600">إلغاء</button>
            <button onClick={() => void save()} disabled={saving}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white hover:bg-blue-700 disabled:opacity-50">
              <Save className="h-4 w-4" /> {saving ? 'جاري الحفظ...' : 'حفظ الخط'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
