import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAdminScope } from '../lib/adminScope';
import { MapPin, Plus, Clock, ChevronDown, ChevronUp, Power, Pencil, Save, X, GraduationCap, Trash2 } from 'lucide-react';

interface Station {
  id: string;
  line_id: string;
  name: string;
  order_index: number;
  departure_times: string[];
  return_times: string[];
  is_active: boolean;
}

interface StationForm {
  name: string;
  departure_times: string[];
  return_times: string[];
}

interface UniversitySchedule {
  id: string;
  university_id: string;
  departure_time: string;
  return_time: string;
  is_active: boolean;
  universities?: { name: string } | null;
}

interface ScheduleDraft {
  university_id: string;
  departure_time: string;
  return_time: string;
}

const emptyScheduleDraft = (): ScheduleDraft => ({ university_id: '', departure_time: '', return_time: '' });

const activeSchedules = (line?: Line): UniversitySchedule[] =>
  (line?.line_university_schedules ?? []).filter((schedule) => schedule.is_active);

interface Line {
  id: string;
  name: string;
  company_id: string;
  supervisor_id: string | null;
  price_termly: number;
  price_yearly: number;
  price_daily: number;
  is_active: boolean;
  companies?: { name: string };
  stations?: Station[];
  line_university_schedules?: UniversitySchedule[];
}

// ── Helper: editable list of time inputs ──────────────────────────
interface TimeListEditorProps {
  label: string;
  color: 'emerald' | 'amber';
  times: string[];
  onChange: (times: string[]) => void;
}

const TimeListEditor: React.FC<TimeListEditorProps> = ({ label, color, times, onChange }) => {
  const colorMap = {
    emerald: {
      badge: 'bg-emerald-50 text-emerald-700 border-emerald-200',
      btn: 'bg-emerald-500 hover:bg-emerald-600',
      dot: 'bg-emerald-400',
      label: 'text-emerald-600',
    },
    amber: {
      badge: 'bg-amber-50 text-amber-700 border-amber-200',
      btn: 'bg-amber-500 hover:bg-amber-600',
      dot: 'bg-amber-400',
      label: 'text-amber-600',
    },
  }[color];

  const addTime = () => onChange([...times, '']);
  const removeTime = (i: number) => onChange(times.filter((_, idx) => idx !== i));
  const updateTime = (i: number, val: string) =>
    onChange(times.map((t, idx) => (idx === i ? val : t)));

  return (
    <div className="flex-1 min-w-0">
      <p className={`text-xs font-bold mb-2 ${colorMap.label}`}>
        <Clock className="inline h-3.5 w-3.5 mr-1" />
        {label}
      </p>
      <div className="space-y-1.5">
        {times.map((t, i) => (
          <div key={i} className="flex items-center gap-1.5">
            <span className={`h-2 w-2 rounded-full flex-shrink-0 ${colorMap.dot}`} />
            <input
              type="time"
              value={t}
              onChange={(e) => updateTime(i, e.target.value)}
              className="flex-1 rounded-lg border border-slate-200 px-2.5 py-1.5 text-xs focus:border-blue-400 focus:outline-none"
            />
            <button
              type="button"
              onClick={() => removeTime(i)}
              className="text-slate-300 hover:text-rose-400 transition flex-shrink-0"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}
        <button
          type="button"
          onClick={addTime}
          className={`flex items-center gap-1 rounded-lg px-3 py-1.5 text-[11px] font-bold text-white transition ${colorMap.btn}`}
        >
          <Plus className="h-3 w-3" />
          إضافة وقت
        </button>
      </div>
    </div>
  );
};

// ── Helper: one university + departure/return time row ────────────
interface ScheduleRowEditorProps {
  universities: { id: string; name: string }[];
  value: ScheduleDraft;
  takenIds: string[];
  onChange: (patch: Partial<ScheduleDraft>) => void;
  onRemove?: () => void;
}

const ScheduleRowEditor: React.FC<ScheduleRowEditorProps> = ({ universities, value, takenIds, onChange, onRemove }) => (
  <div className="grid grid-cols-1 gap-2 sm:grid-cols-[2fr_1fr_1fr_auto] items-center">
    <select value={value.university_id} onChange={(e) => onChange({ university_id: e.target.value })}
      aria-label="الجامعة" className="rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-xs">
      <option value="">اختر الجامعة</option>
      {universities.map((university) => (
        <option key={university.id} value={university.id} disabled={takenIds.includes(university.id)}>{university.name}</option>
      ))}
    </select>
    <label className="flex items-center gap-1 text-[11px] text-emerald-700">ذهاب
      <input type="time" value={value.departure_time} onChange={(e) => onChange({ departure_time: e.target.value })}
        className="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-xs" />
    </label>
    <label className="flex items-center gap-1 text-[11px] text-amber-700">عودة
      <input type="time" value={value.return_time} onChange={(e) => onChange({ return_time: e.target.value })}
        className="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-xs" />
    </label>
    {onRemove ? (
      <button type="button" onClick={onRemove} className="text-slate-400 hover:text-rose-500" title="إزالة"><X className="h-4 w-4" /></button>
    ) : <span />}
  </div>
);

// ── Main Page ─────────────────────────────────────────────────────
export const LinesPage: React.FC = () => {
  const admin = useAdminScope();
  const [lines, setLines] = useState<Line[]>([]);
  const [companies, setCompanies] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedLine, setExpandedLine] = useState<string | null>(null);
  const [editingStationId, setEditingStationId] = useState<string | null>(null);
  const [editingStation, setEditingStation] = useState<StationForm | null>(null);
  const [pageError, setPageError] = useState('');

  // Line form
  const [selectedCompanyId, setSelectedCompanyId] = useState('');
  const [lineName, setLineName] = useState('');
  const [priceTermly, setPriceTermly] = useState('3500');
  const [priceYearly, setPriceYearly] = useState('6500');
  const [priceDaily, setPriceDaily] = useState('50');
  const [lineSubmitting, setLineSubmitting] = useState(false);

  // Universities served by the new line, each with its own trip time
  const [universities, setUniversities] = useState<{ id: string; name: string }[]>([]);
  const [supervisors, setSupervisors] = useState<{ id: string; full_name: string; company_id: string; is_active: boolean }[]>([]);
  const [newLineSchedules, setNewLineSchedules] = useState<ScheduleDraft[]>([]);
  const [scheduleForms, setScheduleForms] = useState<Record<string, ScheduleDraft>>({});
  const [editingScheduleId, setEditingScheduleId] = useState<string | null>(null);
  const [editingSchedule, setEditingSchedule] = useState<ScheduleDraft | null>(null);

  // Station forms (per line)
  const [stationForms, setStationForms] = useState<Record<string, StationForm>>({});

  useEffect(() => { fetchData(); }, []);

  const fetchData = async () => {
    try {
      setPageError('');
      setLoading(true);
      const { data: linesData, error: lError } = await supabase
        .from('lines')
        .select(`*, companies(name), stations(id, name, order_index, departure_times, return_times, is_active),
          line_university_schedules(id, university_id, departure_time, return_time, is_active, universities(name))`)
        .order('name');
      if (lError) throw lError;
      if (!linesData) throw new Error('لم تُرجع قاعدة البيانات قائمة الخطوط.');
      setLines((linesData || []) as unknown as Line[]);

      const { data: uniData, error: uError } = await supabase
        .from('universities').select('id, name').eq('is_active', true).order('name');
      if (uError) throw uError;
      setUniversities(uniData || []);

      const { data: supData, error: supError } = await supabase
        .from('supervisors').select('id, full_name, company_id, is_active').order('full_name');
      if (supError) throw supError;
      setSupervisors(supData || []);

      if (admin.role === 'company_admin' && admin.company_id) {
        const ownCompany = [{ id: admin.company_id, name: admin.companyName || '' }];
        setCompanies(ownCompany);
        setSelectedCompanyId(admin.company_id);
      } else {
        const { data: compData, error: cError } = await supabase
          .from('companies').select('id, name').eq('is_active', true);
        if (cError) throw cError;
        if (!compData) throw new Error('لم تُرجع قاعدة البيانات قائمة الشركات.');
        setCompanies(compData || []);
        if (compData && compData.length > 0) setSelectedCompanyId(compData[0].id);
      }
    } catch (err) {
      console.error('Error fetching lines data:', err);
      setPageError(err instanceof Error ? err.message : 'تعذر تحميل الخطوط والمحطات.');
    } finally {
      setLoading(false);
    }
  };

  const handleCreateLine = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!lineName.trim() || !selectedCompanyId) return;
    const schedules = newLineSchedules.filter((row) => row.university_id || row.departure_time || row.return_time);
    const scheduleError = validateSchedules(schedules);
    if (scheduleError) { alert(scheduleError); return; }
    try {
      setLineSubmitting(true);
      const { data: created, error } = await supabase.from('lines').insert({
        company_id: selectedCompanyId,
        name: lineName.trim(),
        price_termly: parseFloat(priceTermly),
        price_yearly: parseFloat(priceYearly),
        price_daily: parseFloat(priceDaily),
        is_active: true,
      }).select('id').single();
      if (error) throw error;
      if (schedules.length > 0) {
        const { error: schedulesError } = await supabase.from('line_university_schedules')
          .insert(schedules.map((row) => ({ ...row, line_id: created.id })));
        if (schedulesError) {
          alert('تم حفظ الخط لكن تعذر حفظ مواعيد الجامعات: ' + schedulesError.message + ' — أضفها من بطاقة الخط.');
        }
      }
      setLineName('');
      setNewLineSchedules([]);
      fetchData();
    } catch (err: any) {
      alert('فشل إضافة الخط: ' + err.message);
    } finally {
      setLineSubmitting(false);
    }
  };

  const handleAddStation = async (lineId: string) => {
    const form = stationForms[lineId];
    if (!form?.name?.trim()) { alert('أدخل اسم المحطة أولاً'); return; }

    const line = lines.find((l) => l.id === lineId);
    const nextOrder = Math.max(0, ...(line?.stations ?? []).map((station) => station.order_index)) + 1;

    // Filter out empty time strings
    const depTimes = (form.departure_times || []).filter((t) => t.trim()).sort();
    const retTimes = (form.return_times || []).filter((t) => t.trim()).sort();
    if (activeSchedules(line).length === 0 && (depTimes.length === 0 || retTimes.length === 0)) {
      alert('أضف موعد ذهاب واحدًا وموعد عودة واحدًا على الأقل، أو أضف جامعات بمواعيدها لهذا الخط.');
      return;
    }

    const { error } = await supabase.from('stations').insert({
      line_id: lineId,
      name: form.name.trim(),
      order_index: nextOrder,
      departure_times: depTimes,
      return_times: retTimes,
      departure_time: depTimes[0] ?? null,
      return_time: retTimes[0] ?? null,
    });

    if (error) {
      alert('فشل إضافة المحطة: ' + error.message);
    } else {
      setStationForms((prev) => ({
        ...prev,
        [lineId]: { name: '', departure_times: [], return_times: [] },
      }));
      fetchData();
    }
  };

  const handleToggleStation = async (station: Station) => {
    const next = !station.is_active;
    if (!next && !confirm('تعطيل هذه المحطة للطلبات الجديدة؟ ستبقى بيانات الاشتراكات السابقة محفوظة.')) return;
    const { error } = await supabase.from('stations').update({ is_active: next }).eq('id', station.id).select('id').single();
    if (error) alert('فشل تغيير حالة المحطة: ' + error.message);
    else fetchData();
  };

  // Assigning a supervisor narrows their app to the assigned line(s); with no
  // assignment a supervisor covers every line of their company.
  const handleAssignSupervisor = async (line: Line, supervisorId: string) => {
    const { error } = await supabase.from('lines')
      .update({ supervisor_id: supervisorId || null }).eq('id', line.id).select('id').single();
    if (error) alert('فشل تعيين المشرف: ' + error.message);
    else fetchData();
  };

  const handleToggleLine = async (line: Line) => {
    const next = !line.is_active;
    if (!next && !confirm('تعطيل الخط للاشتراكات الجديدة؟ ستظل اشتراكات الطلاب الحالية وسجلاتها محفوظة.')) return;
    const { error } = await supabase.from('lines').update({ is_active: next }).eq('id', line.id).select('id').single();
    if (error) alert('فشل تغيير حالة الخط: ' + error.message);
    else fetchData();
  };

  const startStationEdit = (station: Station) => {
    setEditingStationId(station.id);
    setEditingStation({
      name: station.name,
      departure_times: (station.departure_times ?? []).map((time) => time.slice(0, 5)).sort(),
      return_times: (station.return_times ?? []).map((time) => time.slice(0, 5)).sort(),
    });
  };

  const saveStationEdit = async (stationId: string) => {
    if (!editingStation?.name.trim()) { alert('اسم المحطة مطلوب.'); return; }
    const departureTimes = editingStation.departure_times.filter(Boolean).sort();
    const returnTimes = editingStation.return_times.filter(Boolean).sort();
    const stationLine = lines.find((line) => line.stations?.some((station) => station.id === stationId));
    if (activeSchedules(stationLine).length === 0 && (!departureTimes.length || !returnTimes.length)) {
      alert('أضف موعد ذهاب وموعد عودة على الأقل.'); return;
    }
    const { error } = await supabase.from('stations').update({
      name: editingStation.name.trim(),
      departure_times: departureTimes,
      return_times: returnTimes,
      departure_time: departureTimes[0] ?? null,
      return_time: returnTimes[0] ?? null,
    }).eq('id', stationId).select('id').single();
    if (error) alert('فشل حفظ مواعيد المحطة: ' + error.message);
    else { setEditingStationId(null); setEditingStation(null); fetchData(); }
  };

  const validateSchedules = (rows: ScheduleDraft[]): string | null => {
    for (const row of rows) {
      if (!row.university_id || !row.departure_time || !row.return_time) {
        return 'لكل جامعة اختر الجامعة وموعد الذهاب وموعد العودة.';
      }
    }
    const ids = rows.map((row) => row.university_id);
    if (new Set(ids).size !== ids.length) return 'لا يمكن تكرار نفس الجامعة في نفس الخط. عدّل موعدها بدلاً من ذلك.';
    return null;
  };

  const getScheduleForm = (lineId: string): ScheduleDraft => scheduleForms[lineId] ?? emptyScheduleDraft();
  const updateScheduleForm = (lineId: string, patch: Partial<ScheduleDraft>) =>
    setScheduleForms((prev) => ({ ...prev, [lineId]: { ...getScheduleForm(lineId), ...patch } }));

  const handleAddSchedule = async (lineId: string) => {
    const draft = getScheduleForm(lineId);
    const error = validateSchedules([draft]);
    if (error) { alert(error); return; }
    const { error: insertError } = await supabase.from('line_university_schedules').insert({ ...draft, line_id: lineId });
    if (insertError) {
      alert(insertError.message.includes('line_university_schedules_unique')
        ? 'هذه الجامعة مضافة بالفعل لهذا الخط. عدّل موعدها بدلاً من إضافتها مرة أخرى.'
        : 'فشل إضافة موعد الجامعة: ' + insertError.message);
      return;
    }
    setScheduleForms((prev) => ({ ...prev, [lineId]: emptyScheduleDraft() }));
    fetchData();
  };

  const saveScheduleEdit = async (scheduleId: string) => {
    if (!editingSchedule?.departure_time || !editingSchedule.return_time) { alert('أدخل موعد الذهاب والعودة.'); return; }
    const { error } = await supabase.from('line_university_schedules').update({
      departure_time: editingSchedule.departure_time,
      return_time: editingSchedule.return_time,
    }).eq('id', scheduleId).select('id').single();
    if (error) alert('فشل حفظ الموعد: ' + error.message);
    else { setEditingScheduleId(null); setEditingSchedule(null); fetchData(); }
  };

  const handleToggleSchedule = async (schedule: UniversitySchedule) => {
    const next = !schedule.is_active;
    if (!next && !confirm('إيقاف هذه الجامعة على الخط؟ لن يتمكن طلابها من الاشتراك الجديد، ويبقى المشتركون الحاليون على موعدهم حتى انتهاء اشتراكهم.')) return;
    const { error } = await supabase.from('line_university_schedules').update({ is_active: next }).eq('id', schedule.id).select('id').single();
    if (error) alert('فشل تغيير حالة الموعد: ' + error.message);
    else fetchData();
  };

  const handleDeleteSchedule = async (schedule: UniversitySchedule) => {
    if (!confirm(`حذف موعد ${schedule.universities?.name ?? 'الجامعة'} من هذا الخط؟`)) return;
    const { error } = await supabase.from('line_university_schedules').delete().eq('id', schedule.id);
    if (error) {
      alert(error.code === '23503'
        ? 'هذا الموعد مرتبط باشتراكات طلاب. أوقفه بدلاً من حذفه.'
        : 'فشل حذف الموعد: ' + error.message);
    } else fetchData();
  };

  const getForm = (lineId: string): StationForm =>
    stationForms[lineId] ?? { name: '', departure_times: [], return_times: [] };

  const updateForm = (lineId: string, patch: Partial<StationForm>) =>
    setStationForms((prev) => ({ ...prev, [lineId]: { ...getForm(lineId), ...patch } }));

  // Format time for display (remove seconds)
  const fmt = (t: string) => t?.substring(0, 5) ?? '';

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة خطوط السير والمحطات</h1>
        <p className="text-sm text-slate-500">
          إضافة خطوط السير، التسعير، ومحطات التوقف مع مواعيد ذهاب وعودة متعددة لكل محطة
        </p>
      </div>

      {pageError && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل الخطوط: {pageError}<button className="mr-3 underline" onClick={fetchData}>إعادة المحاولة</button></div>}

      {/* ── Add Line Form ─────────────────────────────────── */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700">إضافة خط باص جديد</h2>
        <form onSubmit={handleCreateLine} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6">
          <div className="lg:col-span-2">
            <label className="text-xs font-semibold text-slate-500">اسم الخط</label>
            <input type="text" placeholder="مثال: منية النصر - ميت تمامه - البجلات"
              value={lineName} onChange={(e) => setLineName(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>
          {admin.role === 'super_admin' && <div>
            <label className="text-xs font-semibold text-slate-500">الشركة المشغلة</label>
            <select value={selectedCompanyId} onChange={(e) => setSelectedCompanyId(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required>
              {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>}
          <div>
            <label className="text-xs font-semibold text-slate-500">سعر الترم (ج.م)</label>
            <input type="number" value={priceTermly} onChange={(e) => setPriceTermly(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>
          <div>
            <label className="text-xs font-semibold text-slate-500">سعر السنوي (ج.م)</label>
            <input type="number" value={priceYearly} onChange={(e) => setPriceYearly(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>
          <div>
            <label className="text-xs font-semibold text-slate-500">سعر اليومي كاش (ج.م)</label>
            <input type="number" value={priceDaily} onChange={(e) => setPriceDaily(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>
          <div className="sm:col-span-2 lg:col-span-6 rounded-xl border border-indigo-100 bg-indigo-50/40 p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="flex items-center gap-1.5 text-xs font-bold text-indigo-700">
                <GraduationCap className="h-4 w-4" />
                الجامعات التي يخدمها الخط وموعد كل جامعة
              </p>
              <button type="button" onClick={() => setNewLineSchedules((rows) => [...rows, emptyScheduleDraft()])}
                className="flex items-center gap-1 rounded-lg bg-indigo-600 px-3 py-1.5 text-[11px] font-bold text-white hover:bg-indigo-700">
                <Plus className="h-3 w-3" /> إضافة جامعة
              </button>
            </div>
            {newLineSchedules.length === 0 ? (
              <p className="mt-2 text-[11px] text-slate-500">بدون جامعات يستخدم الخط مواعيد المحطات. أضف جامعة ليظهر لكل طالب موعد جامعته فقط.</p>
            ) : (
              <div className="mt-3 space-y-2">
                {newLineSchedules.map((row, index) => (
                  <ScheduleRowEditor key={index} universities={universities} value={row}
                    takenIds={newLineSchedules.filter((_, i) => i !== index).map((other) => other.university_id)}
                    onChange={(patch) => setNewLineSchedules((rows) => rows.map((item, i) => (i === index ? { ...item, ...patch } : item)))}
                    onRemove={() => setNewLineSchedules((rows) => rows.filter((_, i) => i !== index))} />
                ))}
              </div>
            )}
          </div>
          <div className="sm:col-span-2 lg:col-span-6 flex justify-end">
            <button type="submit" disabled={lineSubmitting}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50">
              <Plus className="h-4 w-4" />
              {lineSubmitting ? 'جاري الحفظ...' : 'حفظ الخط الجديد'}
            </button>
          </div>
        </form>
      </div>

      {/* ── Lines List ───────────────────────────────────── */}
      <div className="space-y-4">
        {loading ? (
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
          </div>
        ) : lines.length === 0 ? (
          <div className="rounded-2xl border border-slate-100 bg-white p-8 text-center text-slate-500">
            لا توجد خطوط مسجلة بعد.
          </div>
        ) : (
          lines.map((line) => {
            const isExpanded = expandedLine === line.id;
            const form = getForm(line.id);
            const sortedStations = (line.stations ?? []).slice().sort((a, b) => a.order_index - b.order_index);

            return (
              <div key={line.id} className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-hidden">
                {/* Line Header */}
                <div className="flex flex-wrap items-center justify-between gap-4 p-5 border-b border-slate-100">
                  <div>
                    <h3 className="text-lg font-bold text-slate-800">{line.name}</h3>
                    <p className="text-xs text-slate-500">الشركة: {line.companies?.name || 'غير محدد'}</p>
                    <label className="mt-1.5 flex items-center gap-2 text-xs text-slate-500">
                      المشرف:
                      <select
                        aria-label={`مشرف خط ${line.name}`}
                        value={line.supervisor_id ?? ''}
                        onChange={(e) => void handleAssignSupervisor(line, e.target.value)}
                        className="rounded-lg border border-slate-200 bg-white px-2 py-1 text-xs text-slate-700"
                      >
                        <option value="">كل مشرفي الشركة</option>
                        {supervisors.filter((s) => s.company_id === line.company_id && (s.is_active || s.id === line.supervisor_id)).map((s) => (
                          <option key={s.id} value={s.id}>{s.full_name}{s.is_active ? '' : ' (موقوف)'}</option>
                        ))}
                      </select>
                    </label>
                    {activeSchedules(line).length > 0 && (
                      <div className="mt-2 flex flex-wrap gap-1.5">
                        {activeSchedules(line).slice().sort((a, b) => a.departure_time.localeCompare(b.departure_time)).map((schedule) => (
                          <span key={schedule.id} className="rounded-lg bg-indigo-50 px-2.5 py-1 text-[11px] font-bold text-indigo-700">
                            {schedule.universities?.name ?? 'جامعة'} ← {fmt(schedule.departure_time)}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-3 flex-wrap">
                    <span className="rounded-lg bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700">الترم: {line.price_termly} ج.م</span>
                    <span className="rounded-lg bg-teal-50 px-3 py-1 text-xs font-bold text-teal-700">سنوي: {line.price_yearly} ج.م</span>
                    <span className="rounded-lg bg-amber-50 px-3 py-1 text-xs font-bold text-amber-700">يومي: {line.price_daily} ج.م</span>
                    <button onClick={() => setExpandedLine(isExpanded ? null : line.id)}
                      className="flex items-center gap-1 rounded-xl border border-slate-200 px-3 py-1.5 text-xs font-bold text-slate-600 hover:bg-slate-50 transition">
                      <MapPin className="h-3.5 w-3.5" />
                      المحطات والجامعات ({sortedStations.length})
                      {isExpanded ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                    </button>
                    <button onClick={() => handleToggleLine(line)}
                      className={`${line.is_active ? 'text-rose-400 hover:text-rose-600' : 'text-emerald-500 hover:text-emerald-700'} transition`} title={line.is_active ? 'تعطيل الخط' : 'تفعيل الخط'}>
                      <Power className="h-4 w-4" />
                    </button>
                  </div>
                </div>

                {/* Stations Panel */}
                {isExpanded && (
                  <div className="p-5 bg-slate-50/40 space-y-4">

                    {/* University schedules */}
                    <div className="rounded-xl border border-indigo-100 bg-white p-4 shadow-sm">
                      <p className="mb-3 flex items-center gap-1.5 text-xs font-bold text-indigo-700">
                        <GraduationCap className="h-4 w-4" />
                        مواعيد الجامعات على هذا الخط
                      </p>
                      {(line.line_university_schedules ?? []).length === 0 ? (
                        <p className="mb-3 text-[11px] text-slate-500">لا توجد جامعات بعد — الخط يستخدم مواعيد المحطات لكل الطلاب.</p>
                      ) : (
                        <div className="mb-3 overflow-x-auto">
                          <table className="w-full text-right text-xs">
                            <thead className="text-slate-500"><tr><th className="p-2">الجامعة</th><th className="p-2">الذهاب</th><th className="p-2">العودة</th><th className="p-2">الحالة</th><th className="p-2">إجراءات</th></tr></thead>
                            <tbody className="divide-y divide-slate-100">
                              {(line.line_university_schedules ?? []).slice().sort((a, b) => a.departure_time.localeCompare(b.departure_time)).map((schedule) => (
                                <tr key={schedule.id} className={schedule.is_active ? '' : 'opacity-60'}>
                                  <td className="p-2 font-bold text-slate-700">{schedule.universities?.name ?? '—'}</td>
                                  {editingScheduleId === schedule.id && editingSchedule ? (
                                    <>
                                      <td className="p-2"><input type="time" value={editingSchedule.departure_time} onChange={(e) => setEditingSchedule({ ...editingSchedule, departure_time: e.target.value })} className="rounded-lg border px-2 py-1" aria-label="موعد الذهاب" /></td>
                                      <td className="p-2"><input type="time" value={editingSchedule.return_time} onChange={(e) => setEditingSchedule({ ...editingSchedule, return_time: e.target.value })} className="rounded-lg border px-2 py-1" aria-label="موعد العودة" /></td>
                                    </>
                                  ) : (
                                    <>
                                      <td className="p-2 font-bold text-emerald-700">{fmt(schedule.departure_time)}</td>
                                      <td className="p-2 font-bold text-amber-700">{fmt(schedule.return_time)}</td>
                                    </>
                                  )}
                                  <td className="p-2">{schedule.is_active ? <span className="text-emerald-600">نشط</span> : <span className="text-rose-500">موقوف</span>}</td>
                                  <td className="p-2">
                                    <div className="flex gap-2">
                                      {editingScheduleId === schedule.id ? (
                                        <>
                                          <button onClick={() => saveScheduleEdit(schedule.id)} className="text-blue-600" title="حفظ"><Save className="h-4 w-4" /></button>
                                          <button onClick={() => { setEditingScheduleId(null); setEditingSchedule(null); }} className="text-slate-400" title="إلغاء"><X className="h-4 w-4" /></button>
                                        </>
                                      ) : (
                                        <button onClick={() => { setEditingScheduleId(schedule.id); setEditingSchedule({ university_id: schedule.university_id, departure_time: fmt(schedule.departure_time), return_time: fmt(schedule.return_time) }); }} className="text-blue-500" title="تعديل الموعد"><Pencil className="h-4 w-4" /></button>
                                      )}
                                      <button onClick={() => handleToggleSchedule(schedule)} className={schedule.is_active ? 'text-rose-400' : 'text-emerald-500'} title={schedule.is_active ? 'إيقاف' : 'تفعيل'}><Power className="h-4 w-4" /></button>
                                      <button onClick={() => handleDeleteSchedule(schedule)} className="text-slate-400 hover:text-rose-500" title="حذف"><Trash2 className="h-4 w-4" /></button>
                                    </div>
                                  </td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      )}
                      <div className="flex flex-wrap items-end gap-2">
                        <div className="flex-1 min-w-[260px]">
                          <ScheduleRowEditor universities={universities} value={getScheduleForm(line.id)}
                            takenIds={(line.line_university_schedules ?? []).map((schedule) => schedule.university_id)}
                            onChange={(patch) => updateScheduleForm(line.id, patch)} />
                        </div>
                        <button onClick={() => handleAddSchedule(line.id)}
                          className="flex items-center gap-1 rounded-xl bg-indigo-600 px-4 py-2 text-xs font-bold text-white hover:bg-indigo-700">
                          <Plus className="h-3.5 w-3.5" /> إضافة الجامعة
                        </button>
                      </div>
                      <p className="mt-2 text-[11px] text-slate-500">يرى كل طالب موعد جامعته فقط، ولا يظهر الخط لطلاب الجامعات غير المضافة.</p>
                    </div>

                    {/* Existing Stations */}
                    {sortedStations.map((st, idx) => (
                      <div key={st.id} className={`rounded-xl border border-slate-100 bg-white p-4 shadow-sm ${st.is_active === false ? 'opacity-60' : ''}`}>
                        <div className="flex items-center justify-between mb-3">
                          <div className="flex items-center gap-2">
                            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-blue-100 text-[11px] font-bold text-blue-700">
                              {idx + 1}
                            </span>
                            <MapPin className="h-4 w-4 text-blue-400" />
                            <span className="font-bold text-slate-800 text-sm">{st.name}</span>
                            {st.is_active === false && <span className="text-[10px] text-rose-500">معطّلة</span>}
                          </div>
                          <div className="flex gap-3">
                            <button onClick={() => startStationEdit(st)} className="text-blue-500 hover:text-blue-700" title="تعديل المحطة والمواعيد"><Pencil className="h-4 w-4" /></button>
                            <button onClick={() => handleToggleStation(st)} className={st.is_active === false ? 'text-emerald-500' : 'text-rose-400'} title={st.is_active === false ? 'تفعيل المحطة' : 'تعطيل المحطة'}><Power className="h-4 w-4" /></button>
                          </div>
                        </div>

                        {editingStationId === st.id && editingStation && <div className="mb-4 space-y-3 rounded-xl bg-blue-50/60 p-3">
                          <input value={editingStation.name} onChange={(e) => setEditingStation({ ...editingStation, name: e.target.value })} className="w-full rounded-lg border px-3 py-2 text-sm" aria-label="اسم المحطة" />
                          <div className="flex flex-wrap gap-4">
                            <TimeListEditor label="مواعيد الذهاب" color="emerald" times={editingStation.departure_times} onChange={(times) => setEditingStation({ ...editingStation, departure_times: times })} />
                            <TimeListEditor label="مواعيد العودة" color="amber" times={editingStation.return_times} onChange={(times) => setEditingStation({ ...editingStation, return_times: times })} />
                          </div>
                          <div className="flex justify-end gap-2"><button onClick={() => saveStationEdit(st.id)} className="flex items-center gap-1 rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-bold text-white"><Save className="h-3 w-3" />حفظ التعديلات</button><button onClick={() => { setEditingStationId(null); setEditingStation(null); }} className="rounded-lg border px-3 py-1.5 text-xs">إلغاء</button></div>
                        </div>}

                        {/* Times display */}
                        <div className="grid grid-cols-2 gap-3">
                          {/* Departure times */}
                          <div>
                            <p className="text-[11px] font-bold text-emerald-600 mb-1.5">
                              <Clock className="inline h-3 w-3 mr-1" />
                              مواعيد الذهاب ({st.departure_times?.length || 0})
                            </p>
                            {(st.departure_times || []).length > 0 ? (
                              <div className="flex flex-wrap gap-1.5">
                                {st.departure_times.map((t, i) => (
                                  <span key={i} className="rounded-lg bg-emerald-50 border border-emerald-100 px-2.5 py-1 text-xs font-bold text-emerald-700">
                                    {fmt(t)}
                                  </span>
                                ))}
                              </div>
                            ) : (
                              <span className="text-xs text-slate-400">لم تُحدد بعد</span>
                            )}
                          </div>

                          {/* Return times */}
                          <div>
                            <p className="text-[11px] font-bold text-amber-600 mb-1.5">
                              <Clock className="inline h-3 w-3 mr-1" />
                              مواعيد العودة ({st.return_times?.length || 0})
                            </p>
                            {(st.return_times || []).length > 0 ? (
                              <div className="flex flex-wrap gap-1.5">
                                {st.return_times.map((t, i) => (
                                  <span key={i} className="rounded-lg bg-amber-50 border border-amber-100 px-2.5 py-1 text-xs font-bold text-amber-700">
                                    {fmt(t)}
                                  </span>
                                ))}
                              </div>
                            ) : (
                              <span className="text-xs text-slate-400">لم تُحدد بعد</span>
                            )}
                          </div>
                        </div>
                      </div>
                    ))}

                    {/* No stations yet */}
                    {sortedStations.length === 0 && (
                      <p className="text-xs text-slate-400 text-center py-2">لا توجد محطات مسجلة لهذا الخط حتى الآن.</p>
                    )}

                    {/* ── Add Station Form ──────────────────── */}
                    <div className="rounded-xl border border-blue-100 bg-white p-4 shadow-sm">
                      <p className="mb-3 text-xs font-bold text-blue-700 flex items-center gap-1.5">
                        <Plus className="h-3.5 w-3.5" />
                        إضافة محطة جديدة
                      </p>

                      {/* Station Name */}
                      <div className="mb-4">
                        <label className="text-xs font-semibold text-slate-500">اسم المحطة</label>
                        <input
                          type="text"
                          placeholder="مثال: ميت تمامه"
                          value={form.name}
                          onChange={(e) => updateForm(line.id, { name: e.target.value })}
                          className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none"
                        />
                      </div>

                      {activeSchedules(line).length > 0 && (
                        <p className="mb-3 rounded-lg bg-indigo-50 px-3 py-2 text-[11px] text-indigo-700">مواعيد هذا الخط تُحدد حسب الجامعة. مواعيد المحطة اختيارية.</p>
                      )}
                      {/* Times editors — side by side, fully independent */}
                      <div className="flex gap-4 flex-wrap">
                        <TimeListEditor
                          label="مواعيد الذهاب"
                          color="emerald"
                          times={form.departure_times}
                          onChange={(t) => updateForm(line.id, { departure_times: t })}
                        />
                        <TimeListEditor
                          label="مواعيد العودة"
                          color="amber"
                          times={form.return_times}
                          onChange={(t) => updateForm(line.id, { return_times: t })}
                        />
                      </div>

                      <div className="mt-4 flex justify-end">
                        <button
                          onClick={() => handleAddStation(line.id)}
                          className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-xs font-bold text-white transition hover:bg-blue-700"
                        >
                          <Plus className="h-3.5 w-3.5" />
                          إضافة المحطة
                        </button>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
