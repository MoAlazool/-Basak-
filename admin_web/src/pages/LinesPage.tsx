import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import {
  ArrowDown, ArrowUp, Bus, ChevronDown, ChevronUp, Clock, Copy, Flag, GraduationCap, MapPin, Pencil,
  Plus, Power, Save, Trash2, UserCheck, Wand2, X,
} from 'lucide-react';

// ── Types ───────────────────────────────────────────────────────────
type Direction = 'departure' | 'return';

interface StationRow { id: string; name: string; order_index: number; is_active: boolean }
interface TripStopRow { station_id: string; stop_time: string }
interface TripRow {
  id: string; direction: Direction; label: string; start_time: string; arrival_time: string | null;
  university_id: string | null; is_active: boolean; line_trip_stops: TripStopRow[];
}
interface LineRow {
  id: string; name: string; company_id: string; origin_name: string | null; destination_university_id: string | null;
  price_termly: number; price_yearly: number; price_daily: number; is_active: boolean;
  stations: StationRow[];
  line_trips: TripRow[];
  line_universities: { university_id: string }[];
}
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
  price_termly: string; price_yearly: string; price_daily: string; is_active: boolean;
  stations: StationDraft[]; trips: TripDraft[];
}

// ── Helpers ─────────────────────────────────────────────────────────
const hhmm = (t?: string | null) => (t ? t.slice(0, 5) : '');
const fmt12 = (t?: string | null) => {
  if (!t) return '—';
  const [h, m] = t.slice(0, 5).split(':').map(Number);
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'ص' : 'م'}`;
};
const addMinutes = (t: string, minutes: number) => {
  const [h, m] = t.split(':').map(Number);
  const total = Math.min(23 * 60 + 59, Math.max(0, h * 60 + m + minutes));
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
};
let keySeq = 0;
const newKey = () => `k${++keySeq}`;
const activeStations = (line: LineRow) =>
  (line.stations ?? []).filter((s) => s.is_active).sort((a, b) => a.order_index - b.order_index);
const tripsOf = (line: LineRow, direction: Direction) =>
  (line.line_trips ?? []).filter((t) => t.direction === direction).sort((a, b) => a.start_time.localeCompare(b.start_time));

const emptyTrip = (direction: Direction, start = ''): TripDraft => ({
  key: newKey(), direction, label: '', start_time: start, arrival_time: '', university_id: '', is_active: true, times: {},
});

const draftFromLine = (line: LineRow): LineDraft => {
  const stations = activeStations(line).map((s) => ({ key: s.id, id: s.id, name: s.name }));
  return {
    id: line.id, company_id: line.company_id, name: line.name, origin_name: line.origin_name || line.name,
    destination_university_id: line.destination_university_id || '',
    university_ids: (line.line_universities ?? []).map((u) => u.university_id).length
      ? (line.line_universities ?? []).map((u) => u.university_id)
      : (line.destination_university_id ? [line.destination_university_id] : []),
    price_termly: String(line.price_termly), price_yearly: String(line.price_yearly), price_daily: String(line.price_daily),
    is_active: line.is_active, stations,
    trips: (line.line_trips ?? []).filter((t) => t.is_active)
      .sort((a, b) => a.direction.localeCompare(b.direction) || a.start_time.localeCompare(b.start_time))
      .map((t) => ({
        key: t.id, id: t.id, direction: t.direction, label: t.label || '', start_time: hhmm(t.start_time),
        arrival_time: hhmm(t.arrival_time), university_id: t.university_id || '', is_active: t.is_active,
        times: Object.fromEntries((t.line_trip_stops ?? []).map((s) => [s.station_id, hhmm(s.stop_time)])),
      })),
  };
};

const emptyDraft = (companyId: string): LineDraft => ({
  company_id: companyId, name: '', origin_name: '', destination_university_id: '', university_ids: [],
  price_termly: '3500', price_yearly: '6500', price_daily: '50', is_active: true,
  stations: [{ key: newKey(), name: '' }],
  trips: [emptyTrip('departure', '07:00'), emptyTrip('return', '14:00')],
});

// ── Page ────────────────────────────────────────────────────────────
export const LinesPage: React.FC = () => {
  const company = useCompany();
  const [lines, setLines] = useState<LineRow[]>([]);
  const [universities, setUniversities] = useState<Option[]>([]);
  const [supervisors, setSupervisors] = useState<{ id: string; full_name: string }[]>([]);
  const [lineSupervisors, setLineSupervisors] = useState<Record<string, string[]>>({});
  const [loading, setLoading] = useState(true);
  const [pageError, setPageError] = useState('');
  const [expanded, setExpanded] = useState<string | null>(null);
  const [draft, setDraft] = useState<LineDraft | null>(null);
  const [busyLine, setBusyLine] = useState<string | null>(null);

  const fetchData = async () => {
    try {
      setPageError('');
      setLoading(true);
      const { data: lineRows, error } = await supabase.from('lines')
        .select(`id, name, company_id, origin_name, destination_university_id, price_termly, price_yearly, price_daily,
          is_active, stations(id, name, order_index, is_active),
          line_trips(id, direction, label, start_time, arrival_time, university_id, is_active,
            line_trip_stops(station_id, stop_time)), line_universities(university_id)`)
        .eq('company_id', company.id).order('name');
      if (error) throw error;
      setLines((lineRows || []) as unknown as LineRow[]);

      const [{ data: uniRows, error: uError }, { data: supRows }, { data: assignRows }] = await Promise.all([
        supabase.from('universities').select('id, name').eq('is_active', true).order('name'),
        supabase.from('supervisors').select('id, full_name').eq('company_id', company.id).order('full_name'),
        supabase.from('supervisor_lines').select('supervisor_id, line_id').eq('company_id', company.id),
      ]);
      if (uError) throw uError;
      setUniversities(uniRows || []);
      setSupervisors(supRows || []);
      const byLine: Record<string, string[]> = {};
      (assignRows || []).forEach((row) => { (byLine[row.line_id] ||= []).push(row.supervisor_id); });
      setLineSupervisors(byLine);

    } catch (err) {
      setPageError(err instanceof Error ? err.message : 'تعذر تحميل الخطوط.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void fetchData(); }, []);

  const uniName = (id?: string | null) => universities.find((u) => u.id === id)?.name;

  const toggleLine = async (line: LineRow) => {
    const next = !line.is_active;
    if (!next && !confirm(`تعطيل خط "${line.name}"؟\nسيبقى بكل بياناته واشتراكاته وسجلاته، لكنه لن يظهر للطلاب ولن يُسند لمشرفين جدد.`)) return;
    setBusyLine(line.id);
    const { error } = await supabase.rpc('set_line_active', { p_line_id: line.id, p_active: next });
    setBusyLine(null);
    if (error) alert('تعذر تغيير حالة الخط: ' + error.message);
    else void fetchData();
  };

  const deleteLine = async (line: LineRow) => {
    if (!confirm(`حذف خط "${line.name}" نهائياً مع محطاته ورحلاته؟\nلا يمكن التراجع. الخطوط التي لها اشتراكات أو سجلات لا تُحذف — عطّلها بدلاً من ذلك.`)) return;
    setBusyLine(line.id);
    const { error } = await supabase.rpc('delete_line', { p_line_id: line.id });
    setBusyLine(null);
    if (error) alert(error.message);
    else void fetchData();
  };

  const defaultCompany = company.id;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">إدارة خطوط السير</h1>
          <p className="text-sm text-slate-500">كل خط = نقطة بداية ← محطات بالترتيب ← الجامعة، وله رحلات ذهاب وعودة بموعد لكل محطة</p>
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
        <div className="flex h-40 items-center justify-center">
          <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
        </div>
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
                    {/* Route: origin → stations → destination */}
                    <div className="flex flex-wrap items-center gap-1.5 text-xs">
                      <span className="inline-flex items-center gap-1 rounded-lg bg-blue-50 px-2 py-1 font-bold text-blue-700"><Flag className="h-3 w-3" />{line.origin_name || line.name}</span>
                      {stations.map((s) => (
                        <React.Fragment key={s.id}>
                          <span className="text-slate-300">←</span>
                          <span className="rounded-lg bg-slate-50 px-2 py-1 text-slate-600">{s.name}</span>
                        </React.Fragment>
                      ))}
                      <span className="text-slate-300">←</span>
                      <span className="inline-flex items-center gap-1 rounded-lg bg-indigo-50 px-2 py-1 font-bold text-indigo-700"><GraduationCap className="h-3 w-3" />{uniName(line.destination_university_id) || 'الوجهة غير محددة'}</span>
                    </div>
                    <div className="flex flex-wrap items-center gap-1.5 text-[11px]">
                      <span className="text-slate-400">الجامعات:</span>
                      {(line.line_universities ?? []).length === 0
                        ? <span className="rounded-lg bg-amber-50 px-2 py-0.5 font-semibold text-amber-700">غير محددة — عدّل الخط واختر الجامعات</span>
                        : (line.line_universities ?? []).map((u) => (
                          <span key={u.university_id} className="rounded-lg bg-indigo-50/70 px-2 py-0.5 font-semibold text-indigo-700">{uniName(u.university_id)}</span>
                        ))}
                    </div>
                    <div className="flex flex-wrap items-center gap-2 text-xs text-slate-500">
                      <span className="rounded-lg bg-emerald-50 px-2 py-1 font-semibold text-emerald-700">{dep.length} رحلة ذهاب</span>
                      <span className="rounded-lg bg-amber-50 px-2 py-1 font-semibold text-amber-700">{ret.length} رحلة عودة</span>
                      <span>ترم {line.price_termly} · سنوي {line.price_yearly} · يومي {line.price_daily} ج.م</span>
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
  const ordered = tab === 'departure' ? stations : [...stations].reverse();
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
                {trip.arrival_time && <p className="mt-3 text-xs text-slate-500">الوصول: {fmt12(trip.arrival_time)}</p>}
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
  const patchTrip = (key: string, p: Partial<TripDraft>) =>
    setD((cur) => ({ ...cur, trips: cur.trips.map((t) => (t.key === key ? { ...t, ...p } : t)) }));
  const routeFor = (direction: Direction) => (direction === 'departure' ? d.stations : [...d.stations].reverse());
  const destName = universities.find((u) => u.id === (d.destination_university_id || d.university_ids[0]))?.name || 'الجامعة (الوجهة)';

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
    patchTrip(trip.key, { times, arrival_time: trip.direction === 'departure' ? arrival : trip.arrival_time || arrival });
  };

  const duplicate = (trip: TripDraft) => setD((cur) => ({
    ...cur, trips: [...cur.trips, { ...trip, key: newKey(), id: undefined, label: '', times: { ...trip.times } }],
  }));

  const save = async () => {
    setError('');
    if (d.university_ids.length === 0) { setError('اختر جامعة واحدة على الأقل يخدمها الخط.'); return; }
    const stations = d.stations.map((s) => ({ ...s, name: s.name.trim() }));
    const indexOf = new Map(stations.map((s, i) => [s.key, i]));
    const payload = {
      id: d.id ?? null,
      company_id: d.company_id,
      name: d.name.trim(),
      origin_name: d.origin_name.trim(),
      destination_university_id: d.destination_university_id || d.university_ids[0] || null,
      university_ids: d.university_ids,
      price_termly: Number(d.price_termly), price_yearly: Number(d.price_yearly), price_daily: Number(d.price_daily),
      is_active: d.is_active,
      stations: stations.map((s) => ({ id: s.id ?? null, name: s.name })),
      trips: d.trips.map((t) => ({
        id: t.id ?? null, direction: t.direction, label: t.label.trim(), start_time: t.start_time,
        arrival_time: t.arrival_time || null, university_id: t.university_id || null, is_active: t.is_active,
        stops: Object.entries(t.times).filter(([key, time]) => time && indexOf.has(key))
          .map(([key, time]) => ({ station_index: indexOf.get(key), time })),
      })),
    };
    setSaving(true);
    const { error: rpcError } = await supabase.rpc('save_line', { p_line: payload });
    setSaving(false);
    if (rpcError) setError(rpcError.message);
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
              <label className="text-xs font-semibold text-slate-500">اسم الخط
                <input value={d.name} onChange={(e) => patch({ name: e.target.value })} placeholder="مثال: منية النصر - جامعة الدلتا" className={`mt-1 ${input}`} />
              </label>
              <label className="text-xs font-semibold text-slate-500">نقطة البداية
                <input value={d.origin_name} onChange={(e) => patch({ origin_name: e.target.value })} placeholder="مثال: منية النصر" className={`mt-1 ${input}`} />
              </label>
              <label className="text-xs font-semibold text-slate-500">الوجهة (نهاية المسار)
                <select value={d.destination_university_id} onChange={(e) => patch({ destination_university_id: e.target.value })} className={`mt-1 ${input}`}>
                  <option value="">أول جامعة مختارة</option>
                  {universities.filter((u) => d.university_ids.includes(u.id)).map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
                </select>
              </label>
              <fieldset className="sm:col-span-2 lg:col-span-4">
                <legend className="text-xs font-semibold text-slate-500">الجامعات التي يخدمها الخط ({d.university_ids.length} مختارة)</legend>
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
              <label className="text-xs font-semibold text-slate-500">سعر الترم (ج.م)
                <input type="number" min={0} value={d.price_termly} onChange={(e) => patch({ price_termly: e.target.value })} className={`mt-1 ${input}`} />
              </label>
              <label className="text-xs font-semibold text-slate-500">سعر السنوي (ج.م)
                <input type="number" min={0} value={d.price_yearly} onChange={(e) => patch({ price_yearly: e.target.value })} className={`mt-1 ${input}`} />
              </label>
              <label className="text-xs font-semibold text-slate-500">سعر اليومي كاش (ج.م)
                <input type="number" min={0} value={d.price_daily} onChange={(e) => patch({ price_daily: e.target.value })} className={`mt-1 ${input}`} />
              </label>
            </div>
          </section>

          {/* 2. Route */}
          <section className="space-y-3">
            <h3 className="text-sm font-bold text-slate-700">٢. المسار والمحطات (بالترتيب)</h3>
            <div className="space-y-2 rounded-2xl bg-slate-50 p-4">
              <div className="flex items-center gap-2 rounded-xl bg-blue-50 px-3 py-2 text-sm font-bold text-blue-700"><Flag className="h-4 w-4" /> البداية: {d.origin_name || '—'}</div>
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
              <div className="flex items-center gap-2 rounded-xl bg-indigo-50 px-3 py-2 text-sm font-bold text-indigo-700"><GraduationCap className="h-4 w-4" /> الوجهة: {destName}</div>
            </div>
          </section>

          {/* 3. Trips */}
          <section className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h3 className="text-sm font-bold text-slate-700">٣. الرحلات ومواعيد المحطات</h3>
              <label className="flex items-center gap-2 text-xs text-slate-500">
                <Wand2 className="h-4 w-4 text-blue-500" /> التعبئة التلقائية: كل
                <input type="number" min={0} value={gap} onChange={(e) => setGap(e.target.value)} className="w-16 rounded-lg border border-slate-200 px-2 py-1 text-xs" />
                دقيقة بين المحطات
              </label>
            </div>
            <div className="inline-flex rounded-xl bg-slate-100 p-1">
              {(['departure', 'return'] as Direction[]).map((dir) => (
                <button key={dir} onClick={() => setTab(dir)}
                  className={`rounded-lg px-4 py-1.5 text-xs font-bold ${tab === dir ? 'bg-white text-blue-700 shadow-sm' : 'text-slate-500'}`}>
                  {dir === 'departure' ? 'رحلات الذهاب' : 'رحلات العودة'} ({d.trips.filter((t) => t.direction === dir).length})
                </button>
              ))}
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              {tripsInTab.map((trip) => (
                <div key={trip.key} className="space-y-3 rounded-2xl border border-slate-200 p-4">
                  <div className="grid grid-cols-2 gap-2">
                    <label className="text-[11px] font-semibold text-slate-500">موعد الانطلاق {tab === 'departure' ? `من ${d.origin_name || 'البداية'}` : `من ${destName}`}
                      <input type="time" value={trip.start_time} onChange={(e) => patchTrip(trip.key, { start_time: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                    <label className="text-[11px] font-semibold text-slate-500">موعد الوصول (اختياري)
                      <input type="time" value={trip.arrival_time} onChange={(e) => patchTrip(trip.key, { arrival_time: e.target.value })} className={`mt-1 ${input}`} />
                    </label>
                    <label className="text-[11px] font-semibold text-slate-500">اسم الرحلة (اختياري)
                      <input value={trip.label} placeholder={tab === 'departure' ? 'مثال: أول رحلة صباحية' : 'مثال: عودة الظهر'} onChange={(e) => patchTrip(trip.key, { label: e.target.value })} className={`mt-1 ${input}`} />
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
                  <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
                    <div className="flex gap-2">
                      <button onClick={() => autoFill(trip)} className="flex items-center gap-1 rounded-lg bg-blue-50 px-2.5 py-1.5 text-[11px] font-bold text-blue-700"><Wand2 className="h-3 w-3" /> تعبئة تلقائية</button>
                      <button onClick={() => duplicate(trip)} className="flex items-center gap-1 rounded-lg bg-slate-100 px-2.5 py-1.5 text-[11px] font-bold text-slate-600"><Copy className="h-3 w-3" /> نسخ الرحلة</button>
                    </div>
                    <button onClick={() => setD((cur) => ({ ...cur, trips: cur.trips.filter((t) => t.key !== trip.key) }))}
                      className="flex items-center gap-1 rounded-lg px-2.5 py-1.5 text-[11px] font-bold text-rose-500 hover:bg-rose-50"><Trash2 className="h-3 w-3" /> حذف الرحلة</button>
                  </div>
                </div>
              ))}
              <button onClick={() => setD((cur) => ({ ...cur, trips: [...cur.trips, emptyTrip(tab)] }))}
                className="flex min-h-[120px] items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-slate-200 text-sm font-bold text-slate-500 hover:bg-slate-50">
                <Bus className="h-4 w-4" /> إضافة رحلة {tab === 'departure' ? 'ذهاب' : 'عودة'}
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
            <p className="text-[11px] text-slate-400">المواعيد يجب أن تكون بترتيب المسار. اترك موعد محطة فارغاً إذا كانت الرحلة لا تقف عندها. الرحلة المخصصة لجامعة تظهر لطلاب هذه الجامعة فقط.</p>
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
