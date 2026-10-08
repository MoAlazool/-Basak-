import React, { useEffect, useMemo, useState } from 'react';
import { SkeletonTable } from '../components/Skeleton';
import { supabase } from '../lib/supabase';
import { keys, unwrap, usePageData } from '../lib/query';
import { refreshUniversities, useUniversities } from '../lib/reference';
import { GraduationCap, Plus, CheckCircle, XCircle, MapPin, Search } from 'lucide-react';

interface University {
  id: string;
  name: string;
  city: string;
  is_active: boolean;
  created_at: string;
  students_count?: number;
}
interface College { id: string; university_id: string; name: string; is_active: boolean }

/**
 * Students per university name, counted by the database. If the function is not
 * there yet (dashboard deployed before the migration) or refuses, the page
 * still works and simply shows no numbers.
 */
async function loadStudentCounts(): Promise<Record<string, number> | null> {
  const { data, error } = await supabase.rpc('university_student_counts');
  if (error || !data || typeof data !== 'object') {
    if (error) console.warn('university_student_counts unavailable:', error.message);
    return null;
  }
  return data as Record<string, number>;
}

export const UniversitiesPage: React.FC = () => {
  const [searchQuery, setSearchQuery] = useState('');

  // Add form
  const [name, setName] = useState('');
  const [city, setCity] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [collegeName, setCollegeName] = useState('');
  const [collegeUniversityId, setCollegeUniversityId] = useState('');

  // The shared university list (the one every form reads), the colleges, and the
  // number of students per university counted by the database: three small reads
  // instead of downloading every student to count them here.
  const page = useUniversities();
  const collegesPage = usePageData(keys.shared('colleges'), () =>
    unwrap<College[]>(supabase.from('colleges').select('id, university_id, name, is_active').order('name')));
  const counts = usePageData(keys.platform('universityCounts'), loadStudentCounts).data;
  const universities: University[] = useMemo(
    () => (page.data ?? []).map((u) => ({ ...u, students_count: counts ? counts[u.name] ?? 0 : undefined })),
    [page.data, counts]);
  const colleges = collegesPage.data ?? [];
  const loading = page.loading;
  const pageError = page.error || collegesPage.error;
  // After this page's own writes: every page that lists universities sees the change.
  const fetchUniversities = async () => { await Promise.all([refreshUniversities(), collegesPage.reload()]); };
  useEffect(() => {
    if (!collegeUniversityId && universities.length) setCollegeUniversityId(universities[0].id);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page.data]);

  const handleAddCollege = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!collegeName.trim() || !collegeUniversityId) return;
    try {
      setIsSubmitting(true);
      const { error } = await supabase.from('colleges').insert({
        name: collegeName.trim(), university_id: collegeUniversityId, is_active: true,
      });
      if (error) throw error;
      setCollegeName('');
      await fetchUniversities();
    } catch (err: any) {
      alert('فشل إضافة الكلية: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const toggleCollegeStatus = async (college: College) => {
    const { error } = await supabase.from('colleges').update({ is_active: !college.is_active }).eq('id', college.id).select('id').single();
    if (error) alert('فشل تعديل حالة الكلية: ' + error.message);
    else fetchUniversities();
  };

  const handleAddUniversity = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;

    try {
      setIsSubmitting(true);
      const { error } = await supabase.from('universities').insert({
        name: name.trim(),
        city: city.trim() || 'المنصورة',
        is_active: true,
      });

      if (error) throw error;
      setName('');
      setCity('');
      fetchUniversities();
      alert('تمت إضافة الجامعة بنجاح!');
    } catch (err: any) {
      alert('فشل إضافة الجامعة: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const toggleStatus = async (id: string, currentStatus: boolean) => {
    try {
      const { error } = await supabase
        .from('universities')
        .update({ is_active: !currentStatus })
        .eq('id', id);

      if (error) throw error;
      fetchUniversities();
    } catch (err: any) {
      alert('فشل تعديل حالة الجامعة: ' + err.message);
    }
  };

  const handleDelete = async (id: string, uniName: string) => {
    if (!confirm(`تعطيل ${uniName}؟ ستظل بياناتها محفوظة، ولن تظهر في تسجيل الطلاب.`)) return;
    try {
      const { error } = await supabase.from('universities').update({ is_active: false }).eq('id', id);
      if (error) throw error;
      fetchUniversities();
    } catch (err: any) {
      alert('فشل تعطيل الجامعة: ' + err.message);
    }
  };

  const filteredUniversities = universities.filter(
    (u) =>
      u.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (u.city && u.city.toLowerCase().includes(searchQuery.toLowerCase()))
  );

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة الجامعات ووجهات الوصول</h1>
        <p className="text-sm text-slate-500">
          إضافة وتعديل الجامعات ونقاط الوصول التي تتوجه إليها خطوط الباصات ويشترك فيها الطلاب
        </p>
      </div>

      {/* Add University Form */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700 flex items-center gap-2">
          <GraduationCap className="h-5 w-5 text-blue-600" />
          إضافة وجهة جامعة جديدة
        </h2>
        <form onSubmit={handleAddUniversity} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div className="sm:col-span-2">
            <label className="text-xs font-semibold text-slate-500">اسم الجامعة / الكلية</label>
            <input
              type="text"
              placeholder="مثال: جامعة المنصورة (مجمع الكليات)"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">المدينة / المنطقة</label>
            <input
              type="text"
              placeholder="مثال: المنصورة أو جمصة"
              value={city}
              onChange={(e) => setCity(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
            />
          </div>

          <div className="sm:col-span-3 flex justify-end">
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50"
            >
              <Plus className="h-4 w-4" />
              {isSubmitting ? 'جاري الإضافة...' : 'إضافة الوجهة الجامعية'}
            </button>
          </div>
        </form>
      </div>

      {/* Search and Table */}
      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-hidden">
        <div className="p-4 border-b border-slate-100 flex flex-wrap items-center justify-between gap-3">
          <div className="relative flex-1 min-w-[200px] max-w-md">
            <Search className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
            <input
              type="text"
              placeholder="بحث عن جامعة أو مدينة..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full rounded-xl border border-slate-200 pr-9 pl-4 py-2 text-xs focus:border-blue-500 focus:outline-none"
            />
          </div>
          <span className="text-xs font-semibold text-slate-400">
            إجمالي الوجهات: {universities.length}
          </span>
        </div>

        {loading ? (
          <SkeletonTable rows={6} columns={3} />
        ) : pageError && universities.length === 0 ? (
          <div role="alert" className="p-8 text-center text-rose-700">
            تعذر تحميل الجامعات: {pageError}
            <button className="mr-3 font-bold underline" onClick={() => void fetchUniversities()}>إعادة المحاولة</button>
          </div>
        ) : filteredUniversities.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا توجد جامعات مطابقة للبحث.</div>
        ) : (
          <table className="w-full text-right text-sm">
            <thead className="border-b border-slate-100 bg-slate-50/50 text-slate-500">
              <tr>
                <th className="p-4 font-bold">الجامعة / الوجهة</th>
                <th className="p-4 font-bold">المدينة / المقر</th>
                <th className="p-4 font-bold">الطلاب المسجلين</th>
                <th className="p-4 font-bold">الحالة</th>
                <th className="p-4 font-bold text-left">إجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filteredUniversities.map((u) => (
                <tr key={u.id} className="hover:bg-slate-50/80">
                  <td className="p-4 font-bold text-slate-800 flex items-center gap-3">
                    <div className="h-9 w-9 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center flex-shrink-0">
                      <GraduationCap className="h-5 w-5" />
                    </div>
                    {u.name}
                  </td>
                  <td className="p-4 text-slate-600">
                    <span className="inline-flex items-center gap-1">
                      <MapPin className="h-3.5 w-3.5 text-slate-400" />
                      {u.city || 'المنصورة'}
                    </span>
                  </td>
                  <td className="p-4">
                    <span className="rounded-lg bg-slate-100 px-2.5 py-1 text-xs font-bold text-slate-700">
                      {u.students_count === undefined ? '—' : `${u.students_count} طالب`}
                    </span>
                  </td>
                  <td className="p-4">
                    <button
                      onClick={() => toggleStatus(u.id, u.is_active)}
                      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold transition hover:opacity-80 ${
                        u.is_active
                          ? 'bg-emerald-50 text-emerald-700'
                          : 'bg-rose-50 text-rose-700'
                      }`}
                    >
                      {u.is_active ? <CheckCircle className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                      {u.is_active ? 'نشط' : 'معطل'}
                    </button>
                  </td>
                  <td className="p-4 text-left">
                    <button
                      onClick={() => handleDelete(u.id, u.name)}
                      className="text-rose-400 hover:text-rose-600 transition"
                      title="تعطيل الجامعة مع الاحتفاظ ببياناتها"
                    >
                      <XCircle className="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <section className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm space-y-4">
        <div>
          <h2 className="text-base font-bold text-slate-700">إدارة كليات كل جامعة</h2>
          <p className="mt-1 text-xs text-slate-500">الكليات النشطة هي التي تظهر للطالب أثناء إنشاء الحساب.</p>
        </div>
        <form onSubmit={handleAddCollege} className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <select value={collegeUniversityId} onChange={(e) => setCollegeUniversityId(e.target.value)} className="rounded-xl border border-slate-200 px-3 py-2 text-sm" required>
            <option value="">اختر الجامعة</option>
            {universities.filter((university) => university.is_active).map((university) => <option key={university.id} value={university.id}>{university.name}</option>)}
          </select>
          <input value={collegeName} onChange={(e) => setCollegeName(e.target.value)} placeholder="اسم الكلية كما يظهر للطالب" className="rounded-xl border border-slate-200 px-3 py-2 text-sm" required />
          <button disabled={isSubmitting} className="rounded-xl bg-blue-600 px-4 py-2 text-sm font-bold text-white disabled:opacity-50"><Plus className="ml-1 inline h-4 w-4" />إضافة كلية</button>
        </form>
        {colleges.length === 0 ? <p className="text-sm text-slate-500">لا توجد كليات بعد؛ أضف الكليات الصحيحة لكل جامعة لتظهر في التسجيل.</p> : (
          <div className="grid gap-2 md:grid-cols-2">
            {colleges.map((college) => {
              const university = universities.find((item) => item.id === college.university_id);
              return <div key={college.id} className="flex items-center justify-between rounded-xl border border-slate-100 p-3">
                <div><p className="font-semibold text-slate-700">{college.name}</p><p className="text-xs text-slate-500">{university?.name ?? 'جامعة غير مفعّلة'}</p></div>
                <button onClick={() => toggleCollegeStatus(college)} className={`rounded-lg px-3 py-1 text-xs font-bold ${college.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-rose-50 text-rose-600'}`}>{college.is_active ? 'نشطة' : 'معطلة'}</button>
              </div>;
            })}
          </div>
        )}
      </section>
    </div>
  );
};
