import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { createClient } from '@supabase/supabase-js';
import { useAdminScope } from '../lib/adminScope';
import { UserCheck, Plus, CheckCircle, XCircle, Trash2, Key, Eye, EyeOff } from 'lucide-react';

interface Supervisor {
  id: string;
  phone: string;
  full_name: string;
  company_id: string;
  password?: string;
  is_active: boolean;
  created_at: string;
  companies?: { name: string };
}

export const SupervisorsPage: React.FC = () => {
  const admin = useAdminScope();
  const [supervisors, setSupervisors] = useState<Supervisor[]>([]);
  const [companies, setCompanies] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [visiblePasswords, setVisiblePasswords] = useState<Record<string, boolean>>({});

  // New supervisor form
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('123456');
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

      if (admin.role === 'company_admin' && admin.company_id) {
        setCompanies([{ id: admin.company_id, name: admin.companyName || '' }]);
        setCompanyId(admin.company_id);
      } else {
        const { data: compData, error: cError } = await supabase
          .from('companies').select('id, name').eq('is_active', true);
        if (cError) throw cError;
        setCompanies(compData || []);
        if (compData && compData.length > 0) setCompanyId(compData[0].id);
      }
    } catch (err) {
      console.error('Error fetching supervisors:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleAddSupervisor = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanPhone = phone.trim().replace(/[^0-9]/g, '');
    const cleanPass = password.trim() || '123456';

    if (!fullName.trim() || !cleanPhone || !companyId) {
      alert('يرجى ملء جميع الحقول المطلوبة.');
      return;
    }

    try {
      setIsSubmitting(true);

      // 1. Try to create Supabase Auth User with a standalone client so it doesn't disturb admin session
      let authUserId: string | null = null;
      try {
        const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
        const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
        const authClient = createClient(supabaseUrl, supabaseAnonKey, {
          auth: { persistSession: false, autoRefreshToken: false },
        });

        const { data: authData } = await authClient.auth.signUp({
          email: `${cleanPhone}@busak.app`,
          password: cleanPass,
          options: {
            data: {
              role: 'supervisor',
              full_name: fullName.trim(),
              phone: cleanPhone,
            },
          },
        });
        if (authData.user?.id) {
          authUserId = authData.user.id;
        }
      } catch (authErr) {
        console.warn('Note: Auth signup notice (table insert will still proceed):', authErr);
      }

      // 2. Insert into supervisors table with password and matching id if available
      const insertPayload: any = {
        full_name: fullName.trim(),
        phone: cleanPhone,
        company_id: companyId,
        password: cleanPass,
        is_active: true,
      };

      if (authUserId) {
        insertPayload.id = authUserId;
      }

      const { error } = await supabase.from('supervisors').insert(insertPayload);
      if (error) throw error;

      setFullName('');
      setPhone('');
      setPassword('123456');
      fetchData();
      alert('تمت إضافة المشرف بنجاح وتعيين كلمة المرور لتسجيل الدخول في التطبيق!');
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

  const handleDelete = async (id: string, name: string) => {
    if (!confirm(`هل أنت متأكد من حذف المشرف "${name}"؟`)) return;
    const { error } = await supabase.from('supervisors').delete().eq('id', id);
    if (error) alert('فشل الحذف: ' + error.message);
    else fetchData();
  };

  const togglePasswordVisibility = (id: string) => {
    setVisiblePasswords((prev) => ({
      ...prev,
      [id]: !prev[id],
    }));
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة المشرفين</h1>
        <p className="text-sm text-slate-500">
          إضافة مشرفي الباصات، تعيين شركاتهم، وتحديد كلمات المرور التي يدخلون بها لتطبيق الهاتف
        </p>
      </div>

      {/* Add Supervisor Card */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700">تعيين مشرف جديد</h2>
        <form onSubmit={handleAddSupervisor} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
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

          <div>
            <label className="text-xs font-semibold text-slate-500">كلمة المرور لتطبيق الهاتف</label>
            <input
              type="text"
              placeholder="مثال: 123456"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          {admin.role === 'super_admin' && <div>
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
          </div>}

          <div className="sm:col-span-2 lg:col-span-4 flex justify-end">
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
                <th className="p-4 font-bold">كلمة المرور</th>
                <th className="p-4 font-bold">الشركة</th>
                <th className="p-4 font-bold">الحالة</th>
                <th className="p-4 font-bold">إجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {supervisors.map((s) => {
                const isPassVisible = visiblePasswords[s.id];
                return (
                  <tr key={s.id} className="hover:bg-slate-50/80">
                    <td className="p-4 font-semibold text-slate-800">
                      <div className="flex items-center gap-3">
                        <UserCheck className="h-5 w-5 text-slate-400" />
                        {s.full_name}
                      </div>
                    </td>
                    <td className="p-4 text-slate-600 font-mono text-xs">{s.phone}</td>
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
                        onClick={() => handleDelete(s.id, s.full_name)}
                        className="text-rose-400 hover:text-rose-600 transition"
                        title="حذف المشرف"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};
