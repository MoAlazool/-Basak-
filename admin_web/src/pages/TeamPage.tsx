import React, { useState } from 'react';
import { KeyRound, Mail, Plus, ShieldCheck, UserRound } from 'lucide-react';
import { Topbar } from '../components/Topbar';
import { supabase } from '../lib/supabase';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { useAdminScope, useCompany } from '../lib/adminScope';
import { keys, unwrap, usePageData } from '../lib/query';
import { SkeletonTable } from '../components/Skeleton';
import { useGuard } from '../lib/guard';

interface TeamAdmin { id: string; email: string; full_name: string; created_at: string; }

const input = 'mt-1 w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800';

/** Who manages this company's workspace. New admin accounts are issued by the platform admin. */
export const TeamPage: React.FC = () => {
  const me = useAdminScope();
  const company = useCompany();
  const canAdd = me.role === 'super_admin';
  const [form, setForm] = useState({ fullName: '', email: '', password: '' });
  const [submitting, setSubmitting] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');

  const page = usePageData(keys.company(company.id, 'team'), () =>
    unwrap<TeamAdmin[]>(supabase.from('admins').select('id, email, full_name, created_at').eq('company_id', company.id).order('created_at')));
  const admins = page.data ?? [];
  const loading = page.loading;
  const load = page.reload;

  const guard = useGuard();
  const createAdmin = (event: React.FormEvent) => {
    event.preventDefault();
    if (form.password && form.password.length < 8) { setError('كلمة المرور يجب ألا تقل عن 8 أحرف.'); return; }
    // A second submit while the first is on its way does nothing (the account must not be created twice).
    void guard('create', submitAdmin);
  };
  const submitAdmin = async () => {
    setSubmitting(true);
    setError('');
    setNotice('');
    try {
      const result = await invokeEdgeFunction<{ invited?: boolean }>('admin-create-company-admin', {
        companyId: company.id, fullName: form.fullName.trim(), email: form.email.trim(), password: form.password || undefined,
      });
      setNotice(result?.invited
        ? 'تم إرسال دعوة بالبريد. يفتح المدير الرابط ويختار كلمة المرور.'
        : 'تم إنشاء الحساب. يمكن للمدير تسجيل الدخول الآن بالبريد وكلمة المرور.');
      setForm({ fullName: '', email: '', password: '' });
      await load();
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'تعذر إنشاء مدير الشركة.');
    }
    setSubmitting(false);
  };

  return (
    <div className="space-y-6">
      <Topbar title="فريق الإدارة" subtitle={`الحسابات التي تدير مساحة ${company.name}`} />

      {canAdd && (
        <form onSubmit={createAdmin} className="glass-panel p-5 space-y-4">
          <h2 className="flex items-center gap-2 font-bold text-slate-700"><Plus className="h-5 w-5 text-sky-600" /> إضافة مدير لهذه الشركة</h2>
          <div className="grid gap-4 md:grid-cols-3">
            <label className="text-xs font-semibold text-slate-500">اسم المدير
              <input required value={form.fullName} onChange={(e) => setForm({ ...form, fullName: e.target.value })} className={input} />
            </label>
            <label className="text-xs font-semibold text-slate-500">البريد الإلكتروني
              <input required type="email" dir="ltr" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} className={input} />
            </label>
            <label className="text-xs font-semibold text-slate-500">كلمة مرور مبدئية (اختياري)
              <input type="password" dir="ltr" autoComplete="new-password" minLength={8} value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} className={input} />
            </label>
          </div>
          <button disabled={submitting} className="flex items-center gap-2 rounded-xl bg-sky-700 px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50">
            {form.password ? <KeyRound className="h-4 w-4" /> : <Mail className="h-4 w-4" />}
            {submitting ? 'جاري الإنشاء...' : form.password ? 'إنشاء الحساب' : 'إرسال دعوة بالبريد'}
          </button>
        </form>
      )}

      {notice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
      {(error || page.error) && <p role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">{error || page.error}</p>}

      <div className="glass-panel overflow-hidden">
        {loading ? <SkeletonTable rows={2} columns={3} /> : admins.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا يوجد مديرون لهذه الشركة بعد.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead className="bg-slate-50/60 text-slate-500"><tr><th className="p-4">المدير</th><th className="p-4">البريد</th><th className="p-4">تاريخ الإنشاء</th></tr></thead>
              <tbody className="divide-y divide-slate-100">
                {admins.map((admin) => (
                  <tr key={admin.id}>
                    <td className="p-4 font-semibold text-slate-800">
                      <span className="inline-flex items-center gap-2"><UserRound className="h-4 w-4 text-sky-600" />{admin.full_name}</span>
                      {admin.id === me.id && <span className="mr-2 rounded-full bg-[#D6EEF9] px-2 py-0.5 text-[10.5px] font-bold text-[#3E8FBF]">أنت</span>}
                    </td>
                    <td className="p-4 text-slate-600" dir="ltr">{admin.email}</td>
                    <td className="p-4 text-slate-500">{new Date(admin.created_at).toLocaleDateString('ar-EG')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      <p className="flex items-center gap-2 text-xs text-slate-500">
        <ShieldCheck className="h-4 w-4 text-emerald-600" />
        {canAdd ? 'كل حساب هنا يرى بيانات هذه الشركة فقط.' : 'لإضافة مدير جديد أو إيقاف حساب، تواصل مع إدارة المنصة.'}
      </p>
    </div>
  );
};
