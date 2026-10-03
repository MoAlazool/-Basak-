import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { useAdminScope } from '../lib/adminScope';
import { Users, Plus, Trash2, Search, GraduationCap, Phone, CheckCircle2, AlertCircle, Building2 } from 'lucide-react';
import { PasswordResetRequests } from '../components/PasswordResetRequests';

const StudentAvatar: React.FC<{ url?: string; name: string }> = ({ url, name }) =>
  url ? <img src={url} alt={name} className="ml-2 inline-block h-8 w-8 rounded-full object-cover align-middle" /> : null;

/** One request for all photos; a missing file yields no URL instead of a failed request per row. */
async function signAvatarUrls(paths: string[]): Promise<Record<string, string>> {
  if (!paths.length) return {};
  const { data, error } = await supabase.storage.from('student-avatars').createSignedUrls(paths, 600);
  if (error) {
    console.warn('Could not sign student photos:', error.message);
    return {};
  }
  const urls: Record<string, string> = {};
  (data || []).forEach((item) => { if (item.path && item.signedUrl && !item.error) urls[item.path] = item.signedUrl; });
  return urls;
}

interface PurchasablePeriod {
  period_code: string; academic_year: number; label: string; subscription_type: string;
  start_date: string; end_date: string; phase: 'current' | 'upcoming';
}

const phaseLabels: Record<string, { label: string; className: string }> = {
  current: { label: 'الحالي', className: 'bg-emerald-50 text-emerald-700' },
  upcoming: { label: 'الفترة القادمة', className: 'bg-indigo-50 text-indigo-700' },
  expired: { label: 'منتهي', className: 'bg-slate-100 text-slate-500' },
};

interface Student {
  id: string;
  phone: string;
  full_name: string;
  university: string;
  college: string;
  profile_image_url?: string | null;
  created_at: string;
  subscriptions?: {
    id: string;
    status: string;
    type: string;
    price: number;
    created_at: string;
    start_date?: string | null;
    end_date?: string | null;
    period_label?: string | null;
    period_phase?: string | null;
    departure_time?: string | null;
    return_time?: string | null;
    lines?: LineRef | LineRef[] | null;
    line_university_schedules?: { universities?: { name: string } | null } | null;
  }[];
}

type LineRef = { name: string; companies?: { name: string } | { name: string }[] | null };

const one = <T,>(value: T | T[] | null | undefined): T | undefined => (Array.isArray(value) ? value[0] : value ?? undefined);

interface University {
  id: string;
  name: string;
}

interface StationOption {
  id: string; name: string; is_active: boolean; order_index: number;
  departure_times: string[] | null; return_times: string[] | null;
}

interface ScheduleOption {
  id: string; university_id: string; departure_time: string; return_time: string; is_active: boolean;
}

interface LineOption {
  id: string; name: string; company_id: string; price_termly: number; price_yearly: number; price_daily: number;
  stations: StationOption[];
  line_university_schedules: ScheduleOption[];
}

interface CompanyOption { id: string; name: string; }

const activeStations = (line?: LineOption) =>
  (line?.stations ?? []).filter((station) => station.is_active).sort((a, b) => a.order_index - b.order_index);
const fmtTime = (time: string) => time.slice(0, 5);
const lineUsesSchedules = (line?: LineOption) =>
  (line?.line_university_schedules ?? []).some((schedule) => schedule.is_active);
// The trip a student of this university rides on (undefined for legacy station-time lines).
const scheduleFor = (line: LineOption | undefined, universityId: string | undefined) =>
  (line?.line_university_schedules ?? []).find((schedule) => schedule.is_active && schedule.university_id === universityId);
const lineServesUniversity = (line: LineOption, universityId: string | undefined) =>
  !lineUsesSchedules(line) || !!scheduleFor(line, universityId);

export const StudentsPage: React.FC = () => {
  const admin = useAdminScope();
  const [companies, setCompanies] = useState<CompanyOption[]>([]);
  const [selectedCompanyId, setSelectedCompanyId] = useState('');
  const [departureTime, setDepartureTime] = useState('');
  const [returnTime, setReturnTime] = useState('');
  const [students, setStudents] = useState<Student[]>([]);
  const [universities, setUniversities] = useState<University[]>([]);
  const [lines, setLines] = useState<LineOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  // Add Student Form
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [selectedUniversity, setSelectedUniversity] = useState('');
  const [selectedLineId, setSelectedLineId] = useState('');
  const [selectedStationId, setSelectedStationId] = useState('');
  const [subscriptionType, setSubscriptionType] = useState<'termly' | 'yearly' | 'daily'>('termly');
  const [password, setPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [avatarUrls, setAvatarUrls] = useState<Record<string, string>>({});
  const [periods, setPeriods] = useState<PurchasablePeriod[]>([]);
  const [periodKey, setPeriodKey] = useState('');

  useEffect(() => {
    fetchInitialData();
  }, []);

  const fetchInitialData = async () => {
    try {
      setLoading(true);

      // Fetch students with active subscriptions and line names
      const { data: studentsData, error: sErr } = await supabase
        .from('students')
        .select(`
          id, phone, full_name, university, college, profile_image_url, created_at,
          subscriptions(id, status, type, price, created_at, start_date, end_date, period_label, period_phase, departure_time, return_time, lines(name, companies(name)),
            line_university_schedules(universities(name)))
        `)
        .order('created_at', { ascending: false });

      if (sErr) throw sErr;
      const loadedStudents = (studentsData || []) as unknown as Student[];
      setStudents(loadedStudents);
      void signAvatarUrls(loadedStudents.map((st) => st.profile_image_url).filter((x): x is string => !!x))
        .then(setAvatarUrls);

      // Fetch active universities
      const { data: uniData, error: uniError } = await supabase
        .from('universities')
        .select('id, name')
        .eq('is_active', true)
        .order('name');

      if (uniError) throw uniError;
      setUniversities(uniData || []);
      if (uniData && uniData.length > 0) {
        setSelectedUniversity((current) => current || uniData[0].name);
      }

      const { data: lineRows, error: lineError } = await supabase.from('lines')
        .select('id,name,company_id,price_termly,price_yearly,price_daily,stations(id,name,is_active,order_index,departure_times,return_times),line_university_schedules(id,university_id,departure_time,return_time,is_active)')
        .eq('is_active', true).order('name');
      if (lineError) throw lineError;
      const availableLines = (lineRows || []) as unknown as LineOption[];
      setLines(availableLines);

      let companyOptions: CompanyOption[];
      if (admin.role === 'company_admin' && admin.company_id) {
        companyOptions = [{ id: admin.company_id, name: admin.companyName || 'شركتي' }];
      } else {
        const { data: companyRows, error: companyError } = await supabase
          .from('companies').select('id,name').eq('is_active', true).order('name');
        if (companyError) throw companyError;
        companyOptions = (companyRows || []) as CompanyOption[];
      }
      setCompanies(companyOptions);
      const companyId = companyOptions.some((company) => company.id === selectedCompanyId)
        ? selectedCompanyId
        : (companyOptions.find((company) => availableLines.some((line) => line.company_id === company.id)) ?? companyOptions[0])?.id || '';
      // State from this load is not visible to the apply* helpers yet, so resolve here.
      const uniName = selectedUniversity || uniData?.[0]?.name || '';
      const uniId = (uniData || []).find((university) => university.name === uniName)?.id;
      const firstLine = availableLines.find((line) => line.company_id === companyId && lineServesUniversity(line, uniId));
      const firstStation = activeStations(firstLine)[0];
      const firstSchedule = scheduleFor(firstLine, uniId);
      setSelectedCompanyId(companyId);
      setSelectedLineId(firstLine?.id || '');
      setSelectedStationId(firstStation?.id || '');
      setDepartureTime(firstSchedule?.departure_time || firstStation?.departure_times?.[0] || '');
      setReturnTime(firstSchedule?.return_time || firstStation?.return_times?.[0] || '');
    } catch (err: any) {
      console.error('Error fetching students data:', err);
    } finally {
      setLoading(false);
    }
  };

  const universityIdOf = (name: string) => universities.find((university) => university.name === name)?.id;

  const applyTimes = (line: LineOption | undefined, station: StationOption | undefined, universityName = selectedUniversity) => {
    const schedule = scheduleFor(line, universityIdOf(universityName));
    setDepartureTime(schedule?.departure_time || station?.departure_times?.[0] || '');
    setReturnTime(schedule?.return_time || station?.return_times?.[0] || '');
  };

  const applyLine = (lineId: string, source: LineOption[] = lines, universityName = selectedUniversity) => {
    const line = source.find((item) => item.id === lineId);
    const station = activeStations(line)[0];
    setSelectedLineId(line?.id || '');
    setSelectedStationId(station?.id || '');
    applyTimes(line, station, universityName);
  };

  const applyCompany = (companyId: string, source: LineOption[] = lines, universityName = selectedUniversity) => {
    setSelectedCompanyId(companyId);
    const universityId = universityIdOf(universityName);
    const firstLine = source.find((line) => line.company_id === companyId && lineServesUniversity(line, universityId));
    applyLine(firstLine?.id || '', source, universityName);
  };

  const applyUniversity = (universityName: string) => {
    setSelectedUniversity(universityName);
    const current = lines.find((line) => line.id === selectedLineId);
    if (current && lineServesUniversity(current, universityIdOf(universityName))) {
      applyTimes(current, activeStations(current).find((station) => station.id === selectedStationId), universityName);
    } else {
      applyCompany(selectedCompanyId, lines, universityName);
    }
  };

  const applyStation = (stationId: string) => {
    const line = lines.find((item) => item.id === selectedLineId);
    const station = activeStations(line).find((item) => item.id === stationId);
    setSelectedStationId(stationId);
    applyTimes(line, station);
  };

  const selectedUniversityId = universityIdOf(selectedUniversity);
  const companyLines = lines.filter((line) => line.company_id === selectedCompanyId && lineServesUniversity(line, selectedUniversityId));
  const selectedLine = companyLines.find((line) => line.id === selectedLineId);
  const selectedStation = activeStations(selectedLine).find((station) => station.id === selectedStationId);
  const selectedSchedule = scheduleFor(selectedLine, selectedUniversityId);

  // Payable periods come from the database (academic_terms + annual switch).
  useEffect(() => {
    let active = true;
    if (!selectedLineId) { setPeriods([]); return; }
    void supabase.rpc('get_purchasable_periods', { p_line_id: selectedLineId }).then(({ data, error }) => {
      if (!active) return;
      if (error) { console.warn('Could not load periods:', error.message); setPeriods([]); return; }
      setPeriods((data || []) as PurchasablePeriod[]);
    });
    return () => { active = false; };
  }, [selectedLineId]);

  const periodsForType = periods.filter((p) => p.subscription_type === subscriptionType);
  const annualAvailable = periods.some((p) => p.subscription_type === 'yearly');
  useEffect(() => {
    if (subscriptionType === 'yearly' && periods.length > 0 && !annualAvailable) setSubscriptionType('termly');
    const keys = periodsForType.map((p) => `${p.period_code}:${p.academic_year}`);
    if (!keys.includes(periodKey)) setPeriodKey(keys[0] || '');
  }, [periods, subscriptionType]);

  const handleAddStudent = async (e: React.FormEvent) => {
    e.preventDefault();

    // 1. Validate 4-part name (Core Rule)
    const nameParts = fullName.trim().split(/\s+/);
    if (nameParts.length < 4) {
      alert('يرجى كتابة الاسم الرباعي كاملاً (4 مقاطع على الأقل) طبقاً لقواعد النظام.');
      return;
    }

    const cleanPhone = phone.trim().replace(/[^0-9]/g, '');
    if (!cleanPhone || cleanPhone.length < 10) {
      alert('يرجى إدخال رقم هاتف صحيح.');
      return;
    }

    const finalUniversity = selectedUniversity.trim();
    if (!finalUniversity) {
      alert('اختر الجامعة من القائمة.');
      return;
    }
    if (!selectedCompanyId) {
      alert('اختر الشركة أولاً.');
      return;
    }
    if (!selectedLine || !selectedStation) {
      alert('اختر خطاً ومحطة نشطين تابعين للشركة المختارة ويخدمان جامعة الطالب.');
      return;
    }
    if (!departureTime || !returnTime) {
      alert('هذه المحطة ليس لها مواعيد ذهاب وعودة. أضف المواعيد من صفحة الخطوط أولاً.');
      return;
    }
    if (password.length < 6) {
      alert('كلمة المرور يجب ألا تقل عن 6 أحرف.');
      return;
    }
    if (subscriptionType !== 'daily' && !periodKey) {
      alert('لا توجد فترة اشتراك متاحة للدفع الآن لهذا النوع.');
      return;
    }
    const [periodCode, academicYear] = periodKey.split(':');

    try {
      setIsSubmitting(true);

      await invokeEdgeFunction('admin-create-student', {
        fullName: fullName.trim(), phone: cleanPhone, university: finalUniversity, password,
        lineId: selectedLineId, stationId: selectedStationId, subscriptionType, departureTime, returnTime,
        ...(subscriptionType !== 'daily' ? { periodCode, academicYear: Number(academicYear) } : {}),
      });

      alert('تم تسجيل الطالب بنجاح!');
      setFullName('');
      setPhone('');
      setPassword('');
      fetchInitialData();
    } catch (err: any) {
      alert('فشل إضافة الطالب: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDeleteStudent = async (studentId: string, studentName: string) => {
    if (!confirm(`هل أنت متأكد من حذف الطالب "${studentName}"؟ سيتم حذف حسابه واشتراكاته وبياناته، مع الاحتفاظ بمبلغ الإيراد في السجل المالي.`)) {
      return;
    }

    try {
      await invokeEdgeFunction('admin-delete-student', { studentId });
      alert('تم حذف الطالب بنجاح.');
      fetchInitialData();
    } catch (err: any) {
      alert('فشل حذف الطالب: ' + err.message);
    }
  };

  const updateSubscriptionStatus = async (subscriptionId: string, status: string) => {
    const { error } = await supabase.from('subscriptions').update({ status }).eq('id', subscriptionId).select('id').single();
    if (error) alert('فشل تحديث حالة الاشتراك: ' + error.message);
    else await fetchInitialData();
  };

  const statusLabels: Record<string, string> = {
    pending_payment: 'بانتظار الدفع', pending_review: 'قيد مراجعة الإيصال', active: 'نشط', rejected: 'مرفوض', expired: 'منتهي',
  };

  const filteredStudents = students.filter((s) => {
    const q = searchQuery.toLowerCase();
    return (
      s.full_name.toLowerCase().includes(q) ||
      s.phone.includes(q) ||
      (s.university && s.university.toLowerCase().includes(q))
    );
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة الطلاب والمشتركين</h1>
        <p className="text-sm text-slate-500">
          إضافة وحذف الطلاب المسجلين بالمنظومة، وإدارة بيانات الوصول وحالة الاشتراكات
        </p>
      </div>

      <PasswordResetRequests />

      {/* Add Student Card */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700 flex items-center gap-2">
          <Users className="h-5 w-5 text-blue-600" />
          إضافة طالب جديد للمنظومة
        </h2>
        <form onSubmit={handleAddStudent} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {/* Full Name */}
          <div>
            <label className="text-xs font-semibold text-slate-500">الاسم الرباعي كاملاً</label>
            <input
              type="text"
              placeholder="مثال: أحمد محمد علي إبراهيم"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          {/* Phone */}
          <div>
            <label className="text-xs font-semibold text-slate-500">رقم الهاتف (الفريد للدخول)</label>
            <input
              type="tel"
              placeholder="01xxxxxxxxx"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          {/* University Dropdown */}
          <div>
            <label className="text-xs font-semibold text-slate-500">الجامعة / نقطة الوصول</label>
            <select
              value={selectedUniversity}
              onChange={(e) => {
                const selected = universities.find((university) => university.name === e.target.value);
                applyUniversity(selected?.name || '');
              }}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            >
              {universities.map((u) => (
                <option key={u.id} value={u.name}>
                  {u.name}
                </option>
              ))}
            </select>
          </div>

          {/* Company */}
          <div>
            <label className="text-xs font-semibold text-slate-500">الشركة</label>
            <div className="relative mt-1">
              <Building2 className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
              <select
                value={selectedCompanyId}
                onChange={(e) => applyCompany(e.target.value)}
                disabled={admin.role === 'company_admin'}
                className="w-full rounded-xl border border-slate-200 bg-white py-2 pl-3 pr-9 text-sm focus:border-blue-500 focus:outline-none disabled:bg-slate-50 disabled:text-slate-600"
                required
              >
                {companies.length === 0 && <option value="">لا توجد شركات مفعّلة</option>}
                {companies.map((company) => <option key={company.id} value={company.id}>{company.name}</option>)}
              </select>
            </div>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">الخط والمحطة</label>
            <div className="mt-1 grid grid-cols-2 gap-2">
              <select value={selectedLineId} onChange={(e) => applyLine(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm" required>
                {companyLines.length === 0 && <option value="">لا توجد خطوط تخدم هذه الجامعة</option>}
                {companyLines.map((line) => <option key={line.id} value={line.id}>{line.name}</option>)}
              </select>
              <select value={selectedStationId} onChange={(e) => applyStation(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm" required>
                {activeStations(selectedLine).length === 0 && <option value="">لا توجد محطات</option>}
                {activeStations(selectedLine).map((station) => <option key={station.id} value={station.id}>{station.name}</option>)}
              </select>
            </div>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">موعد الذهاب والعودة</label>
            {selectedSchedule ? (
              <div className="mt-1 rounded-xl border border-indigo-100 bg-indigo-50/60 px-3 py-2 text-sm font-bold text-indigo-800">
                ذهاب {fmtTime(selectedSchedule.departure_time)} · عودة {fmtTime(selectedSchedule.return_time)}
                <span className="block text-[11px] font-medium text-indigo-600">موعد جامعة {selectedUniversity} على هذا الخط</span>
              </div>
            ) : (
            <div className="mt-1 grid grid-cols-2 gap-2">
              <select aria-label="موعد الذهاب" value={departureTime} onChange={(e) => setDepartureTime(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm" required>
                {(selectedStation?.departure_times ?? []).length === 0 && <option value="">لا مواعيد ذهاب</option>}
                {(selectedStation?.departure_times ?? []).map((time) => <option key={time} value={time}>ذهاب {fmtTime(time)}</option>)}
              </select>
              <select aria-label="موعد العودة" value={returnTime} onChange={(e) => setReturnTime(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm" required>
                {(selectedStation?.return_times ?? []).length === 0 && <option value="">لا مواعيد عودة</option>}
                {(selectedStation?.return_times ?? []).map((time) => <option key={time} value={time}>عودة {fmtTime(time)}</option>)}
              </select>
            </div>
            )}
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">نوع الاشتراك الأول</label>
            <select value={subscriptionType} onChange={(e) => setSubscriptionType(e.target.value as 'termly' | 'yearly' | 'daily')} className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm">
              <option value="termly">ترم — {selectedLine?.price_termly ?? '—'} ج.م</option>
              <option value="yearly" disabled={!annualAvailable}>سنوي — {selectedLine?.price_yearly ?? '—'} ج.م{annualAvailable ? '' : ' (غير مفعّل)'}</option>
              <option value="daily">يومي — {selectedLine?.price_daily ?? '—'} ج.م</option>
            </select>
          </div>

          {subscriptionType !== 'daily' && (
            <div>
              <label className="text-xs font-semibold text-slate-500">فترة الاشتراك</label>
              <select value={periodKey} onChange={(e) => setPeriodKey(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm" required>
                {periodsForType.length === 0 && <option value="">لا توجد فترة متاحة الآن</option>}
                {periodsForType.map((p) => (
                  <option key={`${p.period_code}:${p.academic_year}`} value={`${p.period_code}:${p.academic_year}`}>
                    {p.label} ({p.start_date} ← {p.end_date}){p.phase === 'upcoming' ? ' — دفع مقدم' : ''}
                  </option>
                ))}
              </select>
            </div>
          )}

          {/* Password */}
          <div>
            <label className="text-xs font-semibold text-slate-500">كلمة مرور التطبيق</label>
            <input
              type="text"
              placeholder="6 أحرف على الأقل"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div className="sm:col-span-2 lg:col-span-3 flex justify-end">
            <button
              type="submit"
              disabled={isSubmitting || !selectedStation}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50"
            >
              <Plus className="h-4 w-4" />
              {isSubmitting ? 'جاري التسجيل...' : 'تسجيل الطالب'}
            </button>
          </div>
        </form>
      </div>

      {/* Students Table */}
      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-hidden">
        <div className="p-4 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
          <div className="relative flex-1 min-w-[200px] max-w-md">
            <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
            <input
              type="text"
              placeholder="بحث باسم الطالب، الهاتف، أو الجامعة..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-xl border border-slate-200 pr-9 pl-4 py-2 text-xs focus:border-blue-500 focus:outline-none"
            />
          </div>
          <span className="text-xs font-semibold text-slate-400">
            إجمالي الطلاب: {students.length}
          </span>
        </div>

        {loading ? (
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
          </div>
        ) : filteredStudents.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا يوجد طلاب مطابقون للبحث.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead className="border-b border-slate-100 bg-slate-50/50 text-slate-500">
                <tr>
                  <th className="p-4 font-bold">اسم الطالب</th>
                  <th className="p-4 font-bold">رقم الهاتف</th>
                  <th className="p-4 font-bold">الجامعة / الكلية</th>
                  <th className="p-4 font-bold">الاشتراك وخط السير</th>
                  <th className="p-4 font-bold">تاريخ التسجيل</th>
                  <th className="p-4 font-bold text-left">إجراءات</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredStudents.map((s) => {
                  const studentSubscriptions = s.subscriptions || [];
                  return (
                    <tr key={s.id} className="hover:bg-slate-50/80">
                      <td className="p-4 font-bold text-slate-800">
                        {s.profile_image_url && <StudentAvatar url={avatarUrls[s.profile_image_url]} name={s.full_name} />}
                        {s.full_name}
                      </td>
                      <td className="p-4 text-slate-600 font-mono text-xs">
                        <span className="inline-flex items-center gap-1.5">
                          <Phone className="h-3.5 w-3.5 text-slate-400" />
                          {s.phone}
                        </span>
                      </td>
                      <td className="p-4 text-slate-600 text-xs">
                        <span className="inline-flex items-center gap-1.5">
                          <GraduationCap className="h-3.5 w-3.5 text-blue-500" />
                          {s.university || 'غير محدد'}
                          <span className="block pr-5 text-slate-400">{s.college || 'الكلية غير محددة'}</span>
                        </span>
                      </td>
                      <td className="p-4">
                        {studentSubscriptions.length ? (
                          <div className="space-y-2">
                            {studentSubscriptions.slice().sort((a, b) => (b.start_date || '').localeCompare(a.start_date || '')).map((sub) => (
                              <div key={sub.id} className="flex flex-wrap items-center gap-2 text-xs">
                                {sub.period_phase && phaseLabels[sub.period_phase] && (
                                  <span className={`rounded-md px-1.5 py-0.5 text-[11px] font-bold ${phaseLabels[sub.period_phase].className}`}>
                                    {phaseLabels[sub.period_phase].label}
                                  </span>
                                )}
                                {sub.period_label && (
                                  <span className="font-semibold text-slate-600" title={`${sub.start_date ?? ''} → ${sub.end_date ?? ''}`}>{sub.period_label}</span>
                                )}
                                <span className="inline-flex items-center gap-1 rounded-md bg-sky-50 px-1.5 py-0.5 text-[11px] font-semibold text-sky-700"><Building2 className="h-3 w-3" />{one(one(sub.lines)?.companies)?.name || '—'}</span>
                                <span className="font-semibold text-slate-700">{one(sub.lines)?.name || '—'}</span>
                                {sub.departure_time && (
                                  <span className="rounded-md bg-indigo-50 px-1.5 py-0.5 text-[11px] font-semibold text-indigo-700">
                                    {one(sub.line_university_schedules)?.universities?.name ? `${one(sub.line_university_schedules)?.universities?.name} ← ` : ''}
                                    {fmtTime(sub.departure_time)}{sub.return_time ? ` / ${fmtTime(sub.return_time)}` : ''}
                                  </span>
                                )}
                                <span className="text-slate-500">{Number(sub.price).toLocaleString('ar-EG')} ج.م</span>
                                <select aria-label={`حالة اشتراك ${s.full_name}`} value={sub.status} onChange={(e) => void updateSubscriptionStatus(sub.id, e.target.value)} className="rounded-lg border border-slate-200 bg-white px-2 py-1 text-xs">
                                  {Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                                </select>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <div className="inline-flex items-center gap-1.5 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-500">
                            <AlertCircle className="h-3.5 w-3.5" />
                            <span>بدون اشتراك نشط</span>
                          </div>
                        )}
                      </td>
                      <td className="p-4 text-slate-400 text-xs">
                        {new Date(s.created_at).toLocaleDateString('ar-EG')}
                      </td>
                      <td className="p-4 text-left">
                        <button
                          onClick={() => handleDeleteStudent(s.id, s.full_name)}
                          className="text-rose-400 hover:text-rose-600 transition"
                          title="حذف الطالب والاشتراكات"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};
