import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Users, Plus, Trash2, Search, GraduationCap, Phone, Key, Bus, CheckCircle2, AlertCircle, Eye, EyeOff } from 'lucide-react';

interface Student {
  id: string;
  phone: string;
  full_name: string;
  university: string;
  password?: string;
  created_at: string;
  subscriptions?: {
    id: string;
    status: string;
    type: string;
    price: number;
    lines?: { name: string };
  }[];
}

interface University {
  id: string;
  name: string;
}

interface Line {
  id: string;
  name: string;
}

export const StudentsPage: React.FC = () => {
  const [students, setStudents] = useState<Student[]>([]);
  const [universities, setUniversities] = useState<University[]>([]);
  const [lines, setLines] = useState<Line[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [visiblePasswords, setVisiblePasswords] = useState<Record<string, boolean>>({});

  // Add Student Form
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [selectedUniversity, setSelectedUniversity] = useState('');
  const [customUniversity, setCustomUniversity] = useState('');
  const [password, setPassword] = useState('123456');
  const [selectedLineId, setSelectedLineId] = useState('');
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
          id, phone, full_name, university, password, created_at,
          subscriptions(id, status, type, price, lines(name))
        `)
        .order('created_at', { ascending: false });

      if (sErr) throw sErr;
      setStudents(studentsData || []);

      // Fetch active universities
      const { data: uniData } = await supabase
        .from('universities')
        .select('id, name')
        .eq('is_active', true)
        .order('name');

      setUniversities(uniData || []);
      if (uniData && uniData.length > 0) {
        setSelectedUniversity(uniData[0].name);
      }

      // Fetch active lines
      const { data: linesData } = await supabase
        .from('lines')
        .select('id, name')
        .eq('is_active', true)
        .order('name');

      setLines(linesData || []);
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

    const finalUniversity = (selectedUniversity === 'other' ? customUniversity : selectedUniversity).trim();
    if (!finalUniversity) {
      alert('يرجى تحديد أو كتابة الجامعة.');
      return;
    }

    try {
      setIsSubmitting(true);

      // 1. Insert into students table
      const { data: newStudent, error: stError } = await supabase
        .from('students')
        .insert({
          full_name: fullName.trim(),
          phone: cleanPhone,
          university: finalUniversity,
          password: password.trim() || '123456',
        })
        .select()
        .single();

      if (stError) throw stError;

      // 2. If a line was assigned, optionally create an active subscription
      if (selectedLineId && newStudent) {
        await supabase.from('subscriptions').insert({
          student_id: newStudent.id,
          line_id: selectedLineId,
          type: 'termly',
          price: 3500,
          status: 'active',
        });
      }

      alert('تم تسجيل الطالب بنجاح!');
      setFullName('');
      setPhone('');
      setPassword('123456');
      setSelectedLineId('');
      fetchInitialData();
    } catch (err: any) {
      alert('فشل إضافة الطالب: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDeleteStudent = async (studentId: string, studentName: string) => {
    if (!confirm(`هل أنت متأكد من حذف الطالب "${studentName}"؟ سيتم حذف اشتراكاته وسجلاته بالكامل.`)) {
      return;
    }

    try {
      // First delete associated subscriptions, receipts, daily_ride_status to be 100% clean
      await supabase.from('daily_ride_status').delete().eq('student_id', studentId);
      await supabase.from('subscriptions').delete().eq('student_id', studentId);
      const { error } = await supabase.from('students').delete().eq('id', studentId);

      if (error) throw error;
      alert('تم حذف الطالب بنجاح.');
      fetchInitialData();
    } catch (err: any) {
      alert('فشل حذف الطالب: ' + err.message);
    }
  };

  const togglePasswordVisibility = (studentId: string) => {
    setVisiblePasswords((prev) => ({
      ...prev,
      [studentId]: !prev[studentId],
    }));
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
              onChange={(e) => setSelectedUniversity(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            >
              {universities.map((u) => (
                <option key={u.id} value={u.name}>
                  {u.name}
                </option>
              ))}
              <option value="other">+ جامعة أخرى...</option>
            </select>
          </div>

          {/* Custom University if other */}
          {selectedUniversity === 'other' && (
            <div>
              <label className="text-xs font-semibold text-slate-500">اكتب اسم الجامعة</label>
              <input
                type="text"
                placeholder="مثال: جامعة المنصورة الأهلية"
                value={customUniversity}
                onChange={(e) => setCustomUniversity(e.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
                required
              />
            </div>
          )}

          {/* Password */}
          <div>
            <label className="text-xs font-semibold text-slate-500">كلمة مرور التطبيق</label>
            <input
              type="text"
              placeholder="مثال: 123456"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          {/* Assign Line (Optional) */}
          <div>
            <label className="text-xs font-semibold text-slate-500">تعيين خط سير فوري (اختياري)</label>
            <select
              value={selectedLineId}
              onChange={(e) => setSelectedLineId(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
            >
              <option value="">بدون تعيين خط سير حالياً</option>
              {lines.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.name}
                </option>
              ))}
            </select>
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
                  <th className="p-4 font-bold">الجامعة</th>
                  <th className="p-4 font-bold">كلمة المرور</th>
                  <th className="p-4 font-bold">الاشتراك وخط السير</th>
                  <th className="p-4 font-bold">تاريخ التسجيل</th>
                  <th className="p-4 font-bold text-left">إجراءات</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredStudents.map((s) => {
                  const activeSub = (s.subscriptions || []).find((sub) => sub.status === 'active');
                  const isPassVisible = visiblePasswords[s.id];

                  return (
                    <tr key={s.id} className="hover:bg-slate-50/80">
                      <td className="p-4 font-bold text-slate-800">
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
                        </span>
                      </td>
                      <td className="p-4">
                        <div className="inline-flex items-center gap-1.5 bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-1 text-xs font-mono">
                          <Key className="h-3 w-3 text-slate-400" />
                          <span>{isPassVisible ? (s.password || '123456') : '••••••'}</span>
                          <button
                            type="button"
                            onClick={() => togglePasswordVisibility(s.id)}
                            className="text-slate-400 hover:text-slate-600 transition ml-1"
                          >
                            {isPassVisible ? <EyeOff className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
                          </button>
                        </div>
                      </td>
                      <td className="p-4">
                        {activeSub ? (
                          <div className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700">
                            <CheckCircle2 className="h-3.5 w-3.5" />
                            <span>{activeSub.lines?.name || 'مشترك نشط'}</span>
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
