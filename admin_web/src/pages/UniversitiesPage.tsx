import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { GraduationCap, Plus, CheckCircle, XCircle, Trash2, MapPin, Search } from 'lucide-react';

interface University {
  id: string;
  name: string;
  city: string;
  is_active: boolean;
  created_at: string;
  students_count?: number;
}

export const UniversitiesPage: React.FC = () => {
  const [universities, setUniversities] = useState<University[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  // Add form
  const [name, setName] = useState('');
  const [city, setCity] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    fetchUniversities();
  }, []);

  const fetchUniversities = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('universities')
        .select('*')
        .order('name', { ascending: true });

      if (error) throw error;

      // Also count students per university if students table exists
      const { data: studentsData } = await supabase
        .from('students')
        .select('university');

      const countMap: Record<string, number> = {};
      (studentsData || []).forEach((s) => {
        if (s.university) {
          countMap[s.university] = (countMap[s.university] || 0) + 1;
        }
      });

      const enriched = (data || []).map((u) => ({
        ...u,
        students_count: countMap[u.name] || 0,
      }));

      setUniversities(enriched);
    } catch (err: any) {
      console.error('Error fetching universities:', err);
    } finally {
      setLoading(false);
    }
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
    if (!confirm(`هل أنت متأكد من حذف ${uniName}؟`)) return;
    try {
      const { error } = await supabase.from('universities').delete().eq('id', id);
      if (error) throw error;
      fetchUniversities();
    } catch (err: any) {
      alert('فشل حذف الجامعة: ' + err.message);
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
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
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
                      {u.students_count || 0} طالب
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
                      title="حذف الجامعة"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};
