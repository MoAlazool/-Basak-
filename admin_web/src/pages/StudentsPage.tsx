import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Users, Plus, Trash2, Search, GraduationCap, Phone, CheckCircle2, AlertCircle } from 'lucide-react';

const StudentAvatar: React.FC<{ path: string; name: string }> = ({ path, name }) => {
  const [url, setUrl] = useState('');
  useEffect(() => {
    let active = true;
    void supabase.storage.from('student-avatars').createSignedUrl(path, 600).then(({ data, error }) => {
      if (!error && active && data) setUrl(data.signedUrl);
    });
    return () => { active = false; };
  }, [path]);
  return url ? <img src={url} alt={name} className="ml-2 inline-block h-8 w-8 rounded-full object-cover align-middle" /> : null;
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
    lines?: { name: string } | { name: string }[] | null;
  }[];
}

interface University {
  id: string;
  name: string;
}

interface LineOption {
  id: string; name: string; price_termly: number; price_yearly: number; price_daily: number;
  stations: { id: string; name: string; is_active: boolean }[];
}

export const StudentsPage: React.FC = () => {
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
          subscriptions(id, status, type, price, created_at, lines(name))
        `)
        .order('created_at', { ascending: false });

      if (sErr) throw sErr;
      setStudents(studentsData || []);

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
        .select('id,name,price_termly,price_yearly,price_daily,stations(id,name,is_active)')
        .eq('is_active', true).order('name');
      if (lineError) throw lineError;
      const availableLines = (lineRows || []) as LineOption[];
      setLines(availableLines);
      const selectedLine = availableLines.find((line) => line.id === selectedLineId) || availableLines[0];
      setSelectedLineId(selectedLine?.id || '');
      setSelectedStationId(selectedLine?.stations?.find((station) => station.is_active)?.id || '');
    } catch (err: any) {
      console.error('Error fetching students data:', err);
    } finally {
      setLoading(false);
    }
  };

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
    const line = lines.find((item) => item.id === selectedLineId);
    if (!line?.stations?.some((station) => station.id === selectedStationId && station.is_active)) {
      alert('اختر خطاً ومحطة نشطين تابعين للشركة.');
      return;
    }

    try {
      setIsSubmitting(true);

      const { error } = await supabase.functions.invoke('admin-create-student', {
        body: { fullName: fullName.trim(), phone: cleanPhone, university: finalUniversity, password, lineId: selectedLineId, stationId: selectedStationId, subscriptionType },
      });
      if (error) throw error;

      alert('تم تسجيل الطالب بنجاح!');
      setFullName('');
      setPhone('');
      setPassword('');
      setSelectedLineId(lines[0]?.id || '');
      setSelectedStationId(lines[0]?.stations?.find((station) => station.is_active)?.id || '');
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
      const { error } = await supabase.functions.invoke('admin-delete-student', {
        body: { studentId },
      });
      if (error) throw error;
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
                setSelectedUniversity(selected?.name || '');
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
              <select value={selectedLineId} onChange={(e) => {
                const nextLine = lines.find((line) => line.id === e.target.value);
                setSelectedLineId(e.target.value);
                setSelectedStationId(nextLine?.stations?.find((station) => station.is_active)?.id || '');
              }} className="min-w-0 rounded-xl border border-slate-200 px-3 py-2 text-sm" required>
                {lines.map((line) => <option key={line.id} value={line.id}>{line.name}</option>)}
              </select>
              <select value={selectedStationId} onChange={(e) => setSelectedStationId(e.target.value)} className="min-w-0 rounded-xl border border-slate-200 px-3 py-2 text-sm" required>
                {lines.find((line) => line.id === selectedLineId)?.stations?.filter((station) => station.is_active).map((station) => <option key={station.id} value={station.id}>{station.name}</option>)}
              </select>
            </div>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">نوع الاشتراك الأول</label>
            <select value={subscriptionType} onChange={(e) => setSubscriptionType(e.target.value as 'termly' | 'yearly' | 'daily')} className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm">
              <option value="termly">ترم — {lines.find((line) => line.id === selectedLineId)?.price_termly ?? '—'} ج.م</option>
              <option value="yearly">سنوي — {lines.find((line) => line.id === selectedLineId)?.price_yearly ?? '—'} ج.م</option>
              <option value="daily">يومي — {lines.find((line) => line.id === selectedLineId)?.price_daily ?? '—'} ج.م</option>
            </select>
          </div>

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
              disabled={isSubmitting}
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
                        {s.profile_image_url && <StudentAvatar path={s.profile_image_url} name={s.full_name} />}
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
                            {studentSubscriptions.map((sub) => (
                              <div key={sub.id} className="flex flex-wrap items-center gap-2 text-xs">
        <span className="font-semibold text-slate-700">{(Array.isArray(sub.lines) ? sub.lines[0]?.name : sub.lines?.name) || '—'}</span>
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
