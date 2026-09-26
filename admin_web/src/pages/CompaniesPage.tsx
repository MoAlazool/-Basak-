import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Building2, Plus, CheckCircle, XCircle } from 'lucide-react';

interface Company {
  id: string;
  name: string;
  is_active: boolean;
  created_at: string;
}

export const CompaniesPage: React.FC = () => {
  const [companies, setCompanies] = useState<Company[]>([]);
  const [loading, setLoading] = useState(true);
  const [newCompanyName, setNewCompanyName] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    fetchCompanies();
  }, []);

  const fetchCompanies = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('companies')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setCompanies(data || []);
    } catch (err) {
      console.error('Error fetching companies:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleAddCompany = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newCompanyName.trim()) return;

    try {
      setIsSubmitting(true);
      const { error } = await supabase.from('companies').insert({
        name: newCompanyName.trim(),
        is_active: true,
      });

      if (error) throw error;
      setNewCompanyName('');
      fetchCompanies();
    } catch (err: any) {
      alert('فشل إضافة الشركة: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const toggleStatus = async (id: string, currentStatus: boolean) => {
    try {
      const { error } = await supabase
        .from('companies')
        .update({ is_active: !currentStatus })
        .eq('id', id);

      if (error) throw error;
      fetchCompanies();
    } catch (err: any) {
      alert('فشل تعديل حالة الشركة: ' + err.message);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">إدارة شركات النقل</h1>
          <p className="text-sm text-slate-500">إضافة وتفعيل وتعطيل شركات النقل الجامعي</p>
        </div>
      </div>

      {/* Add Company Card */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700">إضافة شركة نقل جديدة</h2>
        <form onSubmit={handleAddCompany} className="mt-4 flex gap-3">
          <input
            type="text"
            placeholder="اسم الشركة (مثال: شركة باصات النيل)"
            value={newCompanyName}
            onChange={(e) => setNewCompanyName(e.target.value)}
            className="flex-1 rounded-xl border border-slate-200 px-4 py-2.5 text-sm focus:border-blue-500 focus:outline-none"
            required
          />
          <button
            type="submit"
            disabled={isSubmitting}
            className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
            إضافة
          </button>
        </form>
      </div>

      {/* Companies List */}
      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-hidden">
        {loading ? (
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
          </div>
        ) : companies.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا توجد شركات مضافة حالياً.</div>
        ) : (
          <table className="w-full text-right text-sm">
            <thead className="border-b border-slate-100 bg-slate-50/50 text-slate-500">
              <tr>
                <th className="p-4 font-bold">اسم الشركة</th>
                <th className="p-4 font-bold">الحالة</th>
                <th className="p-4 font-bold">تاريخ الإضافة</th>
                <th className="p-4 font-bold text-left">الإجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {companies.map((c) => (
                <tr key={c.id} className="hover:bg-slate-50/80">
                  <td className="p-4 font-semibold text-slate-800 flex items-center gap-3">
                    <Building2 className="h-5 w-5 text-slate-400" />
                    {c.name}
                  </td>
                  <td className="p-4">
                    <span
                      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold ${
                        c.is_active
                          ? 'bg-emerald-50 text-emerald-700'
                          : 'bg-rose-50 text-rose-700'
                      }`}
                    >
                      {c.is_active ? (
                        <>
                          <CheckCircle className="h-3.5 w-3.5" /> نشط
                        </>
                      ) : (
                        <>
                          <XCircle className="h-3.5 w-3.5" /> معطل
                        </>
                      )}
                    </span>
                  </td>
                  <td className="p-4 text-slate-500">
                    {new Date(c.created_at).toLocaleDateString('ar-EG')}
                  </td>
                  <td className="p-4 text-left">
                    <button
                      onClick={() => toggleStatus(c.id, c.is_active)}
                      className={`text-xs font-bold px-3 py-1.5 rounded-lg border transition ${
                        c.is_active
                          ? 'border-rose-200 text-rose-600 hover:bg-rose-50'
                          : 'border-emerald-200 text-emerald-600 hover:bg-emerald-50'
                      }`}
                    >
                      {c.is_active ? 'تعطيل' : 'تفعيل'}
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
