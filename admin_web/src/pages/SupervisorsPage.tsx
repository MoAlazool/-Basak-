import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { UserCheck, Plus, CheckCircle, XCircle, Trash2 } from 'lucide-react';

interface Supervisor {
  id: string;
  phone: string;
  full_name: string;
  company_id: string;
  is_active: boolean;
  created_at: string;
  companies?: { name: string };
}

export const SupervisorsPage: React.FC = () => {
  const [supervisors, setSupervisors] = useState<Supervisor[]>([]);
  const [companies, setCompanies] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);

  // New supervisor form
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [companyId, setCompanyId] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const { data: supData, error: sError } = await supabase
        .from('supervisors')
        .select(`*, companies(name)`)
        .order('created_at', { ascending: false });
      if (sError) throw sError;
      setSupervisors(supData || []);

      const { data: compData, error: cError } = await supabase
        .from('companies')
        .select('id, name')
        .eq('is_active', true);
      if (cError) throw cError;
      setCompanies(compData || []);
      if (compData && compData.length > 0) setCompanyId(compData[0].id);
    } catch (err) {
      console.error('Error fetching supervisors:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleAddSupervisor = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!fullName.trim() || !phone.trim() || !companyId) return;

    try {
      setIsSubmitting(true);
      const { error } = await supabase.from('supervisors').insert({
        full_name: fullName.trim(),
        phone: phone.trim(),
        company_id: companyId,
        is_active: true,
      });

      if (error) throw error;
      setFullName('');
      setPhone('');
      fetchData();
      alert('تمت إضافة المشرف بنجاح!');
    } catch (err: any) {
      alert('فشل إضافة المشرف: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleToggleActive = async (sup: Supervisor) => {
    const { error } = await supabase
      .from('supervisors')
      .update({ is_active: !sup.is_active })
      .eq('id', sup.id);
    if (error) alert('فشل تغيير الحالة: ' + error.message);
    else fetchData();
  };

  const handleDelete = async (id: string) => {
    if (!confirm('هل أنت متأكد من حذف هذا المشرف؟')) return;
    const { error } = await supabase.from('supervisors').delete().eq('id', id);
    if (error) alert('فشل الحذف: ' + error.message);
    else fetchData();
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة المشرفين</h1>
        <p className="text-sm text-slate-500">
          إضافة مشرفي الباصات وتعيينهم للشركات (إنشاء الحسابات بيد الإدارة حصراً)
        </p>
      </div>

      {/* Add Supervisor Card */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700">تعيين مشرف جديد</h2>
        <form onSubmit={handleAddSupervisor} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <label className="text-xs font-semibold text-slate-500">اسم المشرف</label>
            <input
              type="text"
              placeholder="مثال: أحمد محمود"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">رقم الهاتف (الفريد)</label>
            <input
              type="tel"
              placeholder="01xxxxxxxxx"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">الشركة التابع لها</label>
            <select
              value={companyId}
              onChange={(e) => setCompanyId(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            >
              {companies.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          <div className="sm:col-span-3 flex justify-end">
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50"
            >
              <Plus className="h-4 w-4" />
              {isSubmitting ? 'جاري الإضافة...' : 'إضافة المشرف'}
            </button>
          </div>
        </form>
      </div>

      {/* Supervisors Table */}
      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-hidden">
        {loading ? (
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
          </div>
        ) : supervisors.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا يوجد مشرفون مسجلون حالياً.</div>
        ) : (
          <table className="w-full text-right text-sm">
            <thead className="border-b border-slate-100 bg-slate-50/50 text-slate-500">
              <tr>
                <th className="p-4 font-bold">اسم المشرف</th>
                <th className="p-4 font-bold">رقم الهاتف</th>
                <th className="p-4 font-bold">الشركة</th>
                <th className="p-4 font-bold">الحالة</th>
                <th className="p-4 font-bold">إجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {supervisors.map((s) => (
                <tr key={s.id} className="hover:bg-slate-50/80">
                  <td className="p-4 font-semibold text-slate-800">
                    <div className="flex items-center gap-3">
                      <UserCheck className="h-5 w-5 text-slate-400" />
                      {s.full_name}
                    </div>
                  </td>
                  <td className="p-4 text-slate-600">{s.phone}</td>
                  <td className="p-4 text-slate-600">{s.companies?.name || '-'}</td>
                  <td className="p-4">
                    <button
                      onClick={() => handleToggleActive(s)}
                      className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold transition hover:opacity-80 ${
                        s.is_active
                          ? 'bg-emerald-50 text-emerald-700'
                          : 'bg-rose-50 text-rose-700'
                      }`}
                    >
                      {s.is_active ? <CheckCircle className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                      {s.is_active ? 'نشط' : 'معطل'}
                    </button>
                  </td>
                  <td className="p-4">
                    <button
                      onClick={() => handleDelete(s.id)}
                      className="text-rose-400 hover:text-rose-600 transition"
                      title="حذف المشرف"
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
