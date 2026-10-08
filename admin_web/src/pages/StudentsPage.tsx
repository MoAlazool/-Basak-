import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { useAdminScope, useCompany } from '../lib/adminScope';
import { useQueryClient } from '@tanstack/react-query';
import { keys, usePageData } from '../lib/query';
import { SkeletonRows } from '../components/Skeleton';
import { Users, Plus, Trash2, Search, GraduationCap, Phone, CheckCircle2, AlertCircle, KeyRound, PencilLine, UserMinus } from 'lucide-react';
import { ResetStudentPasswordDialog } from '../components/ResetStudentPasswordDialog';
import { PasswordResetRequests } from '../components/PasswordResetRequests';
import { MembershipRequests } from '../components/MembershipRequests';

const StudentAvatar: React.FC<{ url?: string; name: string }> = ({ url, name }) =>
  url ? <img src={url} alt={name} className="ml-2 inline-block h-8 w-8 rounded-full object-cover align-middle" /> : null;

/** One request for all photos; a missing file yields no URL instead of a failed request per row. */
const PAGE_SIZE = 25;

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
    departure_trip?: { label: string; universities?: { name: string } | null } | null;
  }[];
}

type LineRef = { name: string };

const one = <T,>(value: T | T[] | null | undefined): T | undefined => (Array.isArray(value) ? value[0] : value ?? undefined);

interface University {
  id: string;
  name: string;
}

interface StationOption {
  id: string; name: string; is_active: boolean; order_index: number;
}

interface TripOption {
  id: string; direction: 'departure' | 'return'; label: string; start_time: string;
  university_id: string | null; is_active: boolean;
  line_trip_stops: { station_id: string; stop_time: string }[];
}

interface LineOption {
  id: string; name: string; company_id: string; price_termly: number; price_yearly: number; price_daily: number;
  line_period_prices?: { option: string; price: number }[];
  stations: StationOption[];
  line_trips: TripOption[];
}


const activeStations = (line?: LineOption) =>
  (line?.stations ?? []).filter((station) => station.is_active).sort((a, b) => a.order_index - b.order_index);
const fmtTime = (time: string) => time.slice(0, 5);
// Active trips of a line open to this university (or to every university).
const tripsServing = (line: LineOption | undefined, direction: 'departure' | 'return', universityId: string | undefined) =>
  (line?.line_trips ?? []).filter((trip) => trip.is_active && trip.direction === direction
    && (!trip.university_id || trip.university_id === universityId));
// Trips that stop at the station, with the stop time there, earliest first.
const stopOptions = (line: LineOption | undefined, direction: 'departure' | 'return', stationId: string, universityId: string | undefined) =>
  tripsServing(line, direction, universityId)
    .map((trip) => ({ trip, time: trip.line_trip_stops.find((stop) => stop.station_id === stationId)?.stop_time }))
    .filter((option): option is { trip: TripOption; time: string } => !!option.time)
    .sort((a, b) => a.time.localeCompare(b.time));
const lineServesUniversity = (line: LineOption, universityId: string | undefined) =>
  tripsServing(line, 'departure', universityId).length > 0;

export const StudentsPage: React.FC = () => {
  const admin = useAdminScope();
  const company = useCompany();
  const selectedCompanyId = company.id;
  const [departureTripId, setDepartureTripId] = useState('');
  const [returnTripId, setReturnTripId] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [search, setSearch] = useState('');   // what the list is actually filtered by (debounced)
  const [pageIndex, setPageIndex] = useState(0);

  // Add Student Form
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [selectedUniversity, setSelectedUniversity] = useState('');
  const [selectedLineId, setSelectedLineId] = useState('');
  const [selectedStationId, setSelectedStationId] = useState('');
  const [subscriptionType, setSubscriptionType] = useState<'termly' | 'yearly' | 'daily'>('termly');
  const [password, setPassword] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [resetTarget, setResetTarget] = useState<Student | null>(null);
  const [periods, setPeriods] = useState<PurchasablePeriod[]>([]);
  const [periodKey, setPeriodKey] = useState('');

  useEffect(() => {
    const timer = window.setTimeout(() => { setSearch(searchQuery.trim()); setPageIndex(0); }, 300);
    return () => window.clearTimeout(timer);
  }, [searchQuery]);

  // The company's active members, a page at a time, each with their subscriptions to
  // this company only. Searching is done by the database, not over what happens to be loaded.
  const studentsPage = usePageData(keys.company(company.id, 'students', { search, pageIndex }), async () => {
    let query = supabase
      .from('students')
      .select(`
        id, phone, full_name, university, college, profile_image_url, created_at,
        company_students!inner(company_id, status),
        subscriptions(id, status, type, price, created_at, start_date, end_date, period_label, period_phase, departure_time, return_time, lines(name),
          departure_trip:departure_trip_id(label, universities(name)))
      `, { count: 'exact' })
      .eq('company_students.company_id', company.id)
      .eq('company_students.status', 'active')
      .eq('subscriptions.company_id', company.id);
    if (search) {
      const term = search.replace(/[%,()]/g, ' ');
      query = query.or(`full_name.ilike.%${term}%,phone.ilike.%${term}%,university.ilike.%${term}%`);
    }
    const { data, error, count } = await query
      .order('created_at', { ascending: false })
      .range(pageIndex * PAGE_SIZE, pageIndex * PAGE_SIZE + PAGE_SIZE - 1);
    if (error) throw new Error(error.message);
    return { rows: (data || []) as unknown as Student[], total: count ?? 0 };
  }, { keepPrevious: true });
  const students = studentsPage.data?.rows ?? [];
  const totalStudents = studentsPage.data?.total ?? 0;
  const loading = studentsPage.loading;

  // Signed photo links expire, so they are fetched for the rows on screen and never stored.
  const photoPaths = students.map((st) => st.profile_image_url).filter((x): x is string => !!x);
  const avatarUrls = usePageData(keys.company(company.id, 'avatars', photoPaths), () => signAvatarUrls(photoPaths),
    { enabled: photoPaths.length > 0, keepPrevious: true }).data ?? {};

  // What the add-student form chooses from.
  const options = usePageData(keys.company(company.id, 'lineOptions'), async () => {
    const [uniRes, lineRes] = await Promise.all([
      supabase.from('universities').select('id, name').eq('is_active', true).order('name'),
      supabase.from('lines')
        .select('id,name,company_id,price_termly,price_yearly,price_daily,line_period_prices(option,price),stations(id,name,is_active,order_index),line_trips(id,direction,label,start_time,university_id,is_active,line_trip_stops(station_id,stop_time))')
        .eq('company_id', company.id).eq('is_active', true).order('name'),
    ]);
    if (uniRes.error) throw new Error(uniRes.error.message);
    if (lineRes.error) throw new Error(lineRes.error.message);
    return { universities: (uniRes.data || []) as University[], lines: (lineRes.data || []) as unknown as LineOption[] };
  });
  const universities = options.data?.universities ?? [];
  const lines = options.data?.lines ?? [];

  // First arrival of the options picks sensible defaults; later refreshes keep what the admin chose.
  useEffect(() => {
    if (!options.data || selectedLineId) return;
    const uniName = selectedUniversity || options.data.universities[0]?.name || '';
    const uniId = options.data.universities.find((university) => university.name === uniName)?.id;
    const firstLine = options.data.lines.find((line) => lineServesUniversity(line, uniId));
    const firstStation = activeStations(firstLine)[0];
    if (!selectedUniversity) setSelectedUniversity(uniName);
    setSelectedLineId(firstLine?.id || '');
    setSelectedStationId(firstStation?.id || '');
    setDepartureTripId(stopOptions(firstLine, 'departure', firstStation?.id || '', uniId)[0]?.trip.id || '');
    setReturnTripId(stopOptions(firstLine, 'return', firstStation?.id || '', uniId)[0]?.trip.id || '');
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [options.data]);

  const fetchInitialData = studentsPage.reload;
  const client = useQueryClient();

  const universityIdOf = (name: string) => universities.find((university) => university.name === name)?.id;

  const applyTimes = (line: LineOption | undefined, station: StationOption | undefined, universityName = selectedUniversity) => {
    const universityId = universityIdOf(universityName);
    setDepartureTripId(stopOptions(line, 'departure', station?.id || '', universityId)[0]?.trip.id || '');
    setReturnTripId(stopOptions(line, 'return', station?.id || '', universityId)[0]?.trip.id || '');
  };

  const applyLine = (lineId: string, source: LineOption[] = lines, universityName = selectedUniversity) => {
    const line = source.find((item) => item.id === lineId);
    const station = activeStations(line)[0];
    setSelectedLineId(line?.id || '');
    setSelectedStationId(station?.id || '');
    applyTimes(line, station, universityName);
  };

  const applyCompany = (companyId: string, source: LineOption[] = lines, universityName = selectedUniversity) => {
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
  const departureOptions = stopOptions(selectedLine, 'departure', selectedStationId, selectedUniversityId);
  const returnOptions = stopOptions(selectedLine, 'return', selectedStationId, selectedUniversityId);

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

  // The daily switch of the line's company (platform AND company).
  const [dailyAvailable, setDailyAvailable] = useState(true);
  useEffect(() => {
    let active = true;
    if (!selectedLine?.company_id) return;
    void supabase.rpc('get_subscription_switches', { p_company_id: selectedLine.company_id }).then(({ data }) => {
      if (active && data) setDailyAvailable(!!(data as { daily_effective?: boolean }).daily_effective);
    });
    return () => { active = false; };
  }, [selectedLine?.company_id]);

  const periodsForType = periods.filter((p) => p.subscription_type === subscriptionType);
  const annualAvailable = periods.some((p) => p.subscription_type === 'yearly');
  // Each period has its own price on the line ('annual' is the older name of both).
  const periodPrice = (code: string) =>
    selectedLine?.line_period_prices?.find((x) => x.option === (code === 'annual' ? 'both' : code))?.price ?? '—';
  useEffect(() => {
    if (subscriptionType === 'yearly' && periods.length > 0 && !annualAvailable) setSubscriptionType('termly');
    if (subscriptionType === 'daily' && !dailyAvailable) setSubscriptionType('termly');
    const keys = periodsForType.map((p) => `${p.period_code}:${p.academic_year}`);
    if (!keys.includes(periodKey)) setPeriodKey(keys[0] || '');
  }, [periods, subscriptionType, dailyAvailable]);

  const handleAddStudent = async (e: React.FormEvent) => {
    e.preventDefault();

    // 1. Validate name: at least 3 parts, same rule as the app's sign-up
    const nameParts = fullName.trim().split(/\s+/);
    if (nameParts.length < 3) {
      alert('يرجى كتابة اسم الطالب ثلاثياً على الأقل.');
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
    if (!selectedLine || !selectedStation) {
      alert('اختر خطاً ومحطة نشطين تابعين للشركة المختارة ويخدمان جامعة الطالب.');
      return;
    }
    if (!departureTripId || (returnOptions.length > 0 && !returnTripId)) {
      alert('اختر رحلة الذهاب والعودة. إن لم تظهر رحلات، أضفها للخط من صفحة الخطوط.');
      return;
    }
    if (password.length < 8) {
      alert('كلمة المرور يجب ألا تقل عن 8 أحرف.');
      return;
    }
    if (subscriptionType !== 'daily' && !periodKey) {
      alert('لا توجد فترة اشتراك متاحة للدفع الآن لهذا النوع.');
      return;
    }
    const [periodCode, academicYear] = periodKey.split(':');

    try {
      setIsSubmitting(true);

      const created = await invokeEdgeFunction<{ id?: string; invited?: boolean }>('admin-create-student', {
        fullName: fullName.trim(), phone: cleanPhone, university: finalUniversity, password,
        lineId: selectedLineId, stationId: selectedStationId, subscriptionType,
        departureTripId, returnTripId: returnTripId || null,
        ...(subscriptionType !== 'daily' ? { periodCode, academicYear: Number(academicYear) } : {}),
      });

      alert(created?.invited
        ? 'لهذا الرقم حساب في باصك بالفعل، فأُرسلت له دعوة للانضمام إلى شركتك. يظهر في قائمتك بعد أن يوافق من التطبيق (بحسابه وكلمة مروره الحاليين).'
        : 'تم تسجيل الطالب بنجاح!');
      void client.invalidateQueries({ queryKey: keys.company(company.id, 'invites') });
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

  // A company ends its relationship with a student; the person's account, QR,
  // wallet card and any other company they ride with are not touched.
  const handleRemoveStudent = async (studentId: string, studentName: string) => {
    if (!confirm(`إزالة الطالب "${studentName}" من ${company.name}؟\nتنتهي اشتراكاته المفتوحة مع الشركة ولا يظهر في قوائمها. يبقى حسابه في التطبيق كما هو، وتبقى الإيرادات المسجلة في تقارير الشركة.`)) {
      return;
    }
    const { error } = await supabase.rpc('company_remove_student', { p_company_id: company.id, p_student_id: studentId });
    if (error) alert('تعذرت إزالة الطالب: ' + error.message);
    else await fetchInitialData();
  };

  // A member's name belongs to their account, which other companies may share:
  // the company proposes the fix and the platform admin applies it.
  const requestCorrection = async (student: Student) => {
    const value = window.prompt(`الاسم الصحيح للطالب (رباعي). الاسم الحالي: ${student.full_name}\nيُرسل الطلب لإدارة المنصة للاعتماد.`, student.full_name);
    if (!value || value.trim() === student.full_name) return;
    const { error } = await supabase.rpc('request_student_correction', {
      p_company_id: company.id, p_student_id: student.id, p_field: 'full_name', p_new_value: value.trim(),
    });
    if (error) alert('تعذر إرسال الطلب: ' + error.message);
    else { alert('أُرسل طلب التصحيح إلى إدارة المنصة.'); void client.invalidateQueries({ queryKey: keys.company(company.id, 'corrections') }); }
  };

  // Deleting the whole account is the platform admin's call (or the student's own, in the app).
  const handleDeleteStudent = async (studentId: string, studentName: string) => {
    if (!confirm(`حذف حساب الطالب "${studentName}" نهائياً من المنصة؟\nيُحذف حسابه وبياناته واشتراكاته لدى كل الشركات، مع الاحتفاظ بمبالغ الإيرادات في السجل المالي. لا يمكن التراجع.`)) {
      return;
    }

    try {
      await invokeEdgeFunction('admin-delete-student', { studentId });
      alert('تم حذف حساب الطالب.');
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

  const filteredStudents = students;
  const pageCount = Math.max(1, Math.ceil(totalStudents / PAGE_SIZE));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة الطلاب والمشتركين</h1>
        <p className="text-sm text-slate-500">
          إضافة وحذف الطلاب المسجلين بالمنظومة، وإدارة بيانات الوصول وحالة الاشتراكات
        </p>
      </div>

      <PasswordResetRequests companyId={company.id} />
      <MembershipRequests companyId={company.id} />

      {/* Add Student Card */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700 flex items-center gap-2">
          <Users className="h-5 w-5 text-blue-600" />
          إضافة طالب جديد للمنظومة
        </h2>
        <form onSubmit={handleAddStudent} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {/* Full Name */}
          <div>
            <label className="text-xs font-semibold text-slate-500">الاسم بالكامل (ثلاثي أو رباعي)</label>
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
            {/* Trips that stop at the student's station and serve their university. */}
            <div className="mt-1 grid grid-cols-2 gap-2">
              <select aria-label="رحلة الذهاب" value={departureTripId} onChange={(e) => setDepartureTripId(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm" required>
                {departureOptions.length === 0 && <option value="">لا رحلات ذهاب من هذه المحطة</option>}
                {departureOptions.map(({ trip, time }) => (
                  <option key={trip.id} value={trip.id}>ذهاب {fmtTime(time)}{trip.label ? ` · ${trip.label}` : ''}</option>
                ))}
              </select>
              <select aria-label="رحلة العودة" value={returnTripId} onChange={(e) => setReturnTripId(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm">
                {returnOptions.length === 0 && <option value="">لا رحلات عودة</option>}
                {returnOptions.map(({ trip, time }) => (
                  <option key={trip.id} value={trip.id}>عودة {fmtTime(time)}{trip.label ? ` · ${trip.label}` : ''}</option>
                ))}
              </select>
            </div>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">نوع الاشتراك الأول</label>
            <select value={subscriptionType} onChange={(e) => setSubscriptionType(e.target.value as 'termly' | 'yearly' | 'daily')} className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm">
              <option value="termly">فصل دراسي</option>
              <option value="yearly" disabled={!annualAvailable}>الفصلان معاً{annualAvailable ? '' : ' (غير متاح الآن)'}</option>
              <option value="daily" disabled={!dailyAvailable}>يومي — {selectedLine?.price_daily ?? '—'} ج.م{dailyAvailable ? '' : ' (غير مفعّل)'}</option>
            </select>
          </div>

          {subscriptionType !== 'daily' && (
            <div>
              <label className="text-xs font-semibold text-slate-500">فترة الاشتراك</label>
              <select value={periodKey} onChange={(e) => setPeriodKey(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm" required>
                {periodsForType.length === 0 && <option value="">لا توجد فترة متاحة الآن</option>}
                {periodsForType.map((p) => (
                  <option key={`${p.period_code}:${p.academic_year}`} value={`${p.period_code}:${p.academic_year}`}>
                    {p.label} — {periodPrice(p.period_code)} ج.م{p.phase === 'upcoming' ? ' — دفع مقدم' : ''}
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
              placeholder="8 أحرف على الأقل"
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
            إجمالي الطلاب: {totalStudents.toLocaleString('ar-EG')}{studentsPage.refreshing ? ' • جاري التحديث…' : ''}
          </span>
        </div>

        {loading ? (
          <SkeletonRows rows={5} />
        ) : studentsPage.error ? (
          <div role="alert" className="p-8 text-center text-rose-700">تعذر تحميل الطلاب: {studentsPage.error}</div>
        ) : filteredStudents.length === 0 ? (
          <div className="p-8 text-center text-slate-500">{search ? 'لا يوجد طلاب مطابقون للبحث.' : 'لا يوجد طلاب مسجلون في هذه الشركة بعد.'}</div>
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
                                <span className="font-semibold text-slate-700">{one(sub.lines)?.name || '—'}</span>
                                {sub.departure_time && (
                                  <span className="rounded-md bg-indigo-50 px-1.5 py-0.5 text-[11px] font-semibold text-indigo-700">
                                    {one(sub.departure_trip)?.universities?.name ? `${one(sub.departure_trip)?.universities?.name} ← ` : ''}
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
                        {admin.role === 'super_admin' && (
                          <button
                            onClick={() => setResetTarget(s)}
                            className="ml-3 text-amber-500 hover:text-amber-600 transition"
                            title="إعادة تعيين كلمة المرور"
                          >
                            <KeyRound className="h-4 w-4" />
                          </button>
                        )}
                        <button
                          onClick={() => void requestCorrection(s)}
                          className="ml-3 text-slate-400 hover:text-sky-600 transition"
                          title="طلب تصحيح الاسم (تعتمده إدارة المنصة)"
                        >
                          <PencilLine className="h-4 w-4" />
                        </button>
                        <button
                          onClick={() => void handleRemoveStudent(s.id, s.full_name)}
                          className="text-slate-400 hover:text-rose-600 transition"
                          title="إزالة الطالب من الشركة"
                        >
                          <UserMinus className="h-4 w-4" />
                        </button>
                        {admin.role === 'super_admin' && (
                          <button
                            onClick={() => handleDeleteStudent(s.id, s.full_name)}
                            className="mr-3 text-rose-400 hover:text-rose-600 transition"
                            title="حذف الحساب نهائياً من المنصة"
                          >
                            <Trash2 className="h-4 w-4" />
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        {pageCount > 1 && (
          <div className="flex items-center justify-between border-t border-slate-100 p-3 text-xs text-slate-500">
            <button disabled={pageIndex === 0} onClick={() => setPageIndex(pageIndex - 1)} className="rounded-lg border border-slate-200 px-3 py-1.5 font-bold disabled:opacity-40">السابق</button>
            <span>صفحة {(pageIndex + 1).toLocaleString('ar-EG')} من {pageCount.toLocaleString('ar-EG')}</span>
            <button disabled={pageIndex >= pageCount - 1} onClick={() => setPageIndex(pageIndex + 1)} className="rounded-lg border border-slate-200 px-3 py-1.5 font-bold disabled:opacity-40">التالي</button>
          </div>
        )}
      </div>
      {resetTarget && (
        <ResetStudentPasswordDialog
          student={{
            id: resetTarget.id, full_name: resetTarget.full_name, phone: resetTarget.phone, university: resetTarget.university,
            company: company.name,
          }}
          onClose={() => setResetTarget(null)}
        />
      )}
    </div>
  );
};
