import React, { useEffect, useState } from 'react';
import { Building2, Mail, Plus, ShieldCheck, UserRound, KeyRound } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { keys, usePageData } from '../lib/query';
import { SkeletonRows } from '../components/Skeleton';

interface Company { id: string; name: string; }
interface CompanyAdmin { id: string; email: string; full_name: string; company_id: string; created_at: string; }

export const CompanyAdminsPage: React.FC = () => {
  const [companyId, setCompanyId] = useState('');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [notice, setNotice] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  const page = usePageData(keys.platform('companyAdmins'), async () => {
    const [{ data: companyRows, error: companyError }, { data: adminRows, error: adminError }] = await Promise.all([
      supabase.from('companies').select('id,name').eq('is_active', true).order('name'),
      supabase.from('admins').select('id,email,full_name,company_id,created_at').eq('role', 'company_admin').order('created_at', { ascending: false }),
    ]);
    if (companyError || adminError) throw new Error(companyError?.message || adminError?.message || 'تعذر تحميل البيانات.');
    return { companies: (companyRows || []) as Company[], admins: (adminRows || []) as CompanyAdmin[] };
  });
  const companies = page.data?.companies ?? [];
  const admins = page.data?.admins ?? [];
  const loading = page.loading;
  const load = page.reload;
  useEffect(() => {
    setCompanyId((current) => current && companies.some((company) => company.id === current) ? current : (companies[0]?.id || ''));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page.data]);

  const createAdmin = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!companyId) { setError('أضف شركة وفعّلها أولاً.'); return; }
    if (password && password.length < 8) { setError('كلمة المرور يجب ألا تقل عن 8 أحرف.'); return; }
    setSubmitting(true);
    setError('');
    setNotice('');
    try {
      const result = await invokeEdgeFunction<{ invited?: boolean }>('admin-create-company-admin', {
        companyId, fullName: fullName.trim(), email: email.trim(), password: password || undefined,
      });
      setNotice(result?.invited
        ? 'تم إرسال دعوة بالبريد. يفتح المدير الرابط ويختار كلمة المرور.'
        : 'تم إنشاء الحساب. يمكن للمدير تسجيل الدخول الآن بالبريد وكلمة المرور.');
      setFullName('');
      setEmail('');
      setPassword('');
      await load();
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'تعذر إنشاء مدير الشركة.');
    }
    setSubmitting(false);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">مديرو الشركات</h1>
        <p className="text-sm text-slate-500">أنشئ حسابات إدارة للشركات الموجودة. تُربط كل صلاحية بشركة واحدة داخل قاعدة البيانات.</p>
      </div>

      <form onSubmit={createAdmin} className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm space-y-4">
        <h2 className="flex items-center gap-2 font-bold text-slate-700"><Plus className="h-5 w-5 text-sky-600" /> إضافة مدير شركة</h2>
        {companies.length === 0 ? (
          <p className="rounded-xl bg-amber-50 p-4 text-sm text-amber-800">لا توجد شركات مفعّلة. أضف شركة أولاً.</p>
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <label className="text-xs font-semibold text-slate-500">الشركة
              <select value={companyId} onChange={(e) => setCompanyId(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-800">
                {companies.map((company) => <option value={company.id} key={company.id}>{company.name}</option>)}
              </select>
            </label>
            <label className="text-xs font-semibold text-slate-500">اسم المدير
              <input required value={fullName} onChange={(e) => setFullName(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800" placeholder="الاسم بالكامل" />
            </label>
            <label className="text-xs font-semibold text-slate-500">البريد الإلكتروني
              <input required type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800" placeholder="manager@example.com" />
            </label>
            <label className="text-xs font-semibold text-slate-500">كلمة المرور (اختياري)
              <input type="text" autoComplete="new-password" minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800" placeholder="8 أحرف على الأقل — أو اتركها لإرسال دعوة" />
            </label>
          </div>
        )}
         {notice && <p role="status" className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{notice}</p>}
        {error && <p role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
        <button disabled={submitting || companies.length === 0} className="flex items-center gap-2 rounded-xl bg-sky-700 px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50">
          {password ? <KeyRound className="h-4 w-4" /> : <Mail className="h-4 w-4" />}{submitting ? 'جاري الإنشاء...' : password ? 'إنشاء الحساب وتعيين الشركة' : 'إرسال دعوة وتعيين الشركة'}
        </button>
      </form>

      <div className="overflow-hidden rounded-2xl border border-slate-100 bg-white shadow-sm">
        <div className="border-b border-slate-100 p-5"><h2 className="font-bold text-slate-700">الحسابات المرتبطة بالشركات</h2></div>
        {loading ? <SkeletonRows rows={3} /> : admins.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا يوجد مديرو شركات بعد.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead className="bg-slate-50 text-slate-500"><tr><th className="p-4">المدير</th><th className="p-4">البريد</th><th className="p-4">الشركة المخصصة</th><th className="p-4">تاريخ الإنشاء</th></tr></thead>
              <tbody className="divide-y divide-slate-100">{admins.map((admin) => <tr key={admin.id}>
                <td className="p-4 font-semibold text-slate-800"><span className="inline-flex items-center gap-2"><UserRound className="h-4 w-4 text-sky-600" />{admin.full_name}</span></td>
                <td className="p-4 text-slate-600">{admin.email}</td>
                <td className="p-4 text-slate-600"><span className="inline-flex items-center gap-2"><Building2 className="h-4 w-4" />{companies.find((company) => company.id === admin.company_id)?.name || 'شركة غير مفعّلة'}</span></td>
                <td className="p-4 text-slate-500">{new Date(admin.created_at).toLocaleDateString('ar-EG')}</td>
              </tr>)}</tbody>
            </table>
          </div>
        )}
      </div>
      <p className="flex items-center gap-2 text-xs text-slate-500"><ShieldCheck className="h-4 w-4 text-emerald-600" />لا تُحفظ كلمة المرور في قاعدة البيانات. سلّمها للمدير مباشرة، أو اتركها فارغة ليختارها من رابط الدعوة (يتطلب SMTP مخصص).</p>
    </div>
  );
};
