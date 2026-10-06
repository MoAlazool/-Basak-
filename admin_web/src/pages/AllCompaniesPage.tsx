import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Building2, Plus, X } from 'lucide-react';
import { Topbar } from '../components/Topbar';
import { count, egp } from '../components/StatsRow';
import { supabase } from '../lib/supabase';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { companyStatusLabel, CompanyStatus } from '../lib/adminScope';
import { usePlatformOverview } from '../lib/overview';

const input = 'w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm focus:border-[#7EC8E3] focus:outline-none';
const statusStyle: Record<CompanyStatus, string> = {
  active: 'bg-emerald-50 text-emerald-700',
  suspended: 'bg-amber-100 text-amber-800',
  archived: 'bg-slate-200 text-slate-600',
};

/** Every company on the platform, with live counts and the way into each workspace. */
export const AllCompaniesPage: React.FC = () => {
  const { data, loading, error, refresh } = usePlatformOverview();
  const [filter, setFilter] = useState<CompanyStatus | 'all'>('all');
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [actionError, setActionError] = useState('');

  const companies = (data?.per_company ?? []).filter((row) => filter === 'all' ? row.company.status !== 'archived' : row.company.status === filter);

  const setStatus = async (id: string, name: string, status: CompanyStatus) => {
    const question = {
      suspended: `إيقاف «${name}»؟ سيفقد مديروها ومشرفوها الدخول فوراً، وتختفي من تطبيق الطلاب. لا تُحذف أي بيانات.`,
      archived: `أرشفة «${name}»؟ تُخفى من القوائم ويتوقف العمل بها. لا تُحذف أي بيانات ويمكن إعادة تفعيلها.`,
      active: `إعادة تفعيل «${name}»؟`,
    }[status];
    if (!window.confirm(question)) return;
    setBusy(id);
    setActionError('');
    const { error: updateError } = await supabase.from('companies').update({ status }).eq('id', id).select('id').single();
    if (updateError) setActionError(updateError.message);
    await refresh();
    setBusy(null);
  };

  return (
    <div className="space-y-6">
      <Topbar title="كل الشركات" subtitle="أنشئ شركة جديدة أو ادخل مساحة أي شركة" />

      <div className="flex flex-wrap items-center gap-2">
        {(['all', 'active', 'suspended', 'archived'] as const).map((key) => (
          <button key={key} onClick={() => setFilter(key)}
            className={`rounded-full px-3.5 py-1.5 text-xs font-bold transition ${filter === key ? 'bg-[#3E8FBF] text-white' : 'bg-white text-slate-600 hover:bg-slate-100'}`}>
            {key === 'all' ? 'الحالية' : companyStatusLabel[key]}
          </button>
        ))}
        <button onClick={() => setCreating(true)} className="mr-auto inline-flex items-center gap-2 rounded-xl bg-[#3E8FBF] px-4 py-2.5 text-sm font-bold text-white hover:bg-[#3580AC]">
          <Plus className="h-4 w-4" /> شركة جديدة
        </button>
      </div>

      {(error || actionError) && <div role="alert" className="glass-panel p-4 text-sm text-rose-700">{error || actionError}</div>}

      {loading ? (
        <div className="glass-panel p-10 text-center text-sm text-slate-500">جاري تحميل الشركات...</div>
      ) : companies.length === 0 ? (
        <div className="glass-panel p-10 text-center text-sm text-slate-500">لا توجد شركات في هذا التصنيف.</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {companies.map((row) => (
            <div key={row.company.id} className="glass-panel p-5 flex flex-col gap-4">
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3 min-w-0">
                  <div className="h-10 w-10 flex-shrink-0 rounded-xl bg-[#D6EEF9] text-[#3E8FBF] flex items-center justify-center"><Building2 className="h-5 w-5" /></div>
                  <div className="min-w-0">
                    <h2 className="truncate text-[15px] font-extrabold text-[#1F2937]">{row.company.name}</h2>
                    <p className="text-[11.5px] text-[#5B6B7A]">منذ {new Date(row.company.created_at).toLocaleDateString('ar-EG')}</p>
                  </div>
                </div>
                <span className={`rounded-full px-2.5 py-1 text-[11px] font-bold ${statusStyle[row.company.status]}`}>{companyStatusLabel[row.company.status]}</span>
              </div>

              <dl className="grid grid-cols-3 gap-2 text-center">
                {[
                  ['الطلاب', count(row.members)],
                  ['اشتراكات سارية', count(row.active_subscriptions)],
                  ['نازلين اليوم', count(row.riders_today)],
                  ['الخطوط', count(row.lines)],
                  ['المشرفون', count(row.supervisors)],
                  ['إيصالات معلقة', count(row.pending_receipts)],
                ].map(([label, value]) => (
                  <div key={label} className="rounded-xl bg-white/60 px-2 py-2">
                    <dd className="text-[15px] font-extrabold text-[#1F2937]">{value}</dd>
                    <dt className="text-[10.5px] font-medium text-[#5B6B7A]">{label}</dt>
                  </div>
                ))}
              </dl>

              <div className="flex items-center justify-between border-t border-slate-100 pt-3">
                <span className="text-sm font-extrabold text-[#1F2937]">{egp(Number(row.revenue))}</span>
                <div className="flex items-center gap-2">
                  {row.company.status === 'active' ? (
                    <button disabled={busy === row.company.id} onClick={() => void setStatus(row.company.id, row.company.name, 'suspended')}
                      className="rounded-lg border border-amber-200 px-3 py-1.5 text-xs font-bold text-amber-700 hover:bg-amber-50 disabled:opacity-50">إيقاف</button>
                  ) : (
                    <>
                      {row.company.status === 'suspended' && (
                        <button disabled={busy === row.company.id} onClick={() => void setStatus(row.company.id, row.company.name, 'archived')}
                          className="rounded-lg border border-slate-200 px-3 py-1.5 text-xs font-bold text-slate-600 hover:bg-slate-50 disabled:opacity-50">أرشفة</button>
                      )}
                      <button disabled={busy === row.company.id} onClick={() => void setStatus(row.company.id, row.company.name, 'active')}
                        className="rounded-lg border border-emerald-200 px-3 py-1.5 text-xs font-bold text-emerald-700 hover:bg-emerald-50 disabled:opacity-50">تفعيل</button>
                    </>
                  )}
                  <Link to={`/c/${row.company.id}`} className="rounded-lg bg-[#3E8FBF] px-3.5 py-1.5 text-xs font-bold text-white hover:bg-[#3580AC]">دخول</Link>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {creating && <CreateCompanyWizard onClose={() => setCreating(false)} onCreated={() => void refresh()} />}
    </div>
  );
};

type MethodType = '' | 'instapay' | 'vodafone_cash' | 'bank';
const steps = ['بيانات الشركة', 'مدير الشركة', 'وسيلة الدفع'];

/**
 * Three short steps, one request: the company, its first admin and (optionally)
 * how students pay it are created together, or not at all.
 */
const CreateCompanyWizard: React.FC<{ onClose: () => void; onCreated: () => void }> = ({ onClose, onCreated }) => {
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [company, setCompany] = useState({ name: '', contactPhone: '', contactLabel: '' });
  const [admin, setAdmin] = useState({ fullName: '', email: '', password: '' });
  const [method, setMethod] = useState({
    methodType: '' as MethodType, displayName: '', accountHolder: '', instapayAddress: '', walletPhone: '', bankName: '', bankAccountNumber: '', iban: '',
  });

  const problem = (): string => {
    if (step === 0 && company.name.trim().length < 2) return 'اكتب اسم الشركة.';
    if (step === 1) {
      if (!admin.fullName.trim()) return 'اكتب اسم مدير الشركة.';
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(admin.email.trim())) return 'اكتب بريداً إلكترونياً صحيحاً لمدير الشركة.';
      if (admin.password && admin.password.length < 8) return 'كلمة المرور يجب ألا تقل عن 8 أحرف (أو اتركها فارغة لإرسال دعوة بالبريد).';
    }
    if (step === 2 && method.methodType) {
      if (!method.displayName.trim()) return 'اكتب الاسم الذي يظهر للطالب لوسيلة الدفع.';
      if (method.methodType === 'instapay' && !method.instapayAddress.trim()) return 'اكتب عنوان InstaPay.';
      if (method.methodType === 'vodafone_cash' && !/^01[0-9]{9}$/.test(method.walletPhone.trim())) return 'اكتب رقم محفظة صحيحاً من 11 رقماً.';
      if (method.methodType === 'bank' && (!method.bankName.trim() || !method.bankAccountNumber.trim())) return 'اكتب اسم البنك ورقم الحساب.';
    }
    return '';
  };

  const next = async () => {
    const message = problem();
    setError(message);
    if (message) return;
    if (step < steps.length - 1) { setStep(step + 1); return; }
    setSaving(true);
    try {
      const created = await invokeEdgeFunction<{ id: string }>('admin-create-company', {
        ...company, admin, paymentMethod: method.methodType ? method : null,
      });
      onCreated();
      navigate(`/c/${created.id}`);
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'تعذر إنشاء الشركة.');
      setSaving(false);
    }
  };

  const field = (label: string, node: React.ReactNode, hint?: string) => (
    <label className="block">
      <span className="text-xs font-bold text-slate-600">{label}</span>
      <div className="mt-1">{node}</div>
      {hint && <span className="mt-1 block text-[11px] text-slate-400">{hint}</span>}
    </label>
  );

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/40 p-4" dir="rtl" role="dialog" aria-modal="true" aria-label="إنشاء شركة جديدة">
      <div className="w-full max-w-lg rounded-3xl bg-white p-6 shadow-2xl">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-extrabold text-[#1F2937]">إنشاء شركة جديدة</h2>
          <button onClick={onClose} aria-label="إغلاق" className="rounded-full p-1.5 text-slate-400 hover:bg-slate-100"><X className="h-5 w-5" /></button>
        </div>

        <ol className="mt-4 flex items-center gap-2 text-[11.5px] font-bold">
          {steps.map((name, index) => (
            <li key={name} className={`flex-1 rounded-full px-3 py-1.5 text-center ${index === step ? 'bg-[#3E8FBF] text-white' : index < step ? 'bg-[#D6EEF9] text-[#3E8FBF]' : 'bg-slate-100 text-slate-400'}`}>
              {index + 1}. {name}
            </li>
          ))}
        </ol>

        <div className="mt-5 space-y-4">
          {step === 0 && (
            <>
              {field('اسم الشركة', <input autoFocus value={company.name} onChange={(e) => setCompany({ ...company, name: e.target.value })} className={input} placeholder="مثال: شركة باصات النيل" />)}
              {field('رقم التواصل (اختياري)', <input value={company.contactPhone} onChange={(e) => setCompany({ ...company, contactPhone: e.target.value })} className={input} dir="ltr" inputMode="tel" placeholder="01xxxxxxxxx" />,
                'يظهر للطلاب على بطاقة المحفظة. يمكن تغييره لاحقاً من مساحة الشركة.')}
              {field('اسم جهة التواصل (اختياري)', <input value={company.contactLabel} onChange={(e) => setCompany({ ...company, contactLabel: e.target.value })} className={input} placeholder="مثال: خدمة العملاء" />)}
              <p className="rounded-xl bg-slate-50 p-3 text-[11.5px] leading-6 text-slate-500">
                تُنشأ للشركة نسختها الخاصة من مواعيد الفصول الدراسية وتصميم بطاقة المحفظة. الشعار والألوان تُضبط من مساحة الشركة بعد الإنشاء.
              </p>
            </>
          )}
          {step === 1 && (
            <>
              {field('اسم مدير الشركة', <input autoFocus value={admin.fullName} onChange={(e) => setAdmin({ ...admin, fullName: e.target.value })} className={input} />)}
              {field('البريد الإلكتروني', <input value={admin.email} onChange={(e) => setAdmin({ ...admin, email: e.target.value })} className={input} dir="ltr" type="email" autoComplete="off" />)}
              {field('كلمة مرور مبدئية', <input value={admin.password} onChange={(e) => setAdmin({ ...admin, password: e.target.value })} className={input} dir="ltr" type="password" autoComplete="new-password" />,
                '8 أحرف على الأقل. اتركها فارغة لإرسال دعوة بالبريد بدلاً منها (يتطلب إعداد SMTP).')}
            </>
          )}
          {step === 2 && (
            <>
              {field('وسيلة الدفع الأولى', (
                <select value={method.methodType} onChange={(e) => setMethod({ ...method, methodType: e.target.value as MethodType })} className={input}>
                  <option value="">لاحقاً — تضيفها الشركة من مساحتها</option>
                  <option value="instapay">InstaPay</option>
                  <option value="vodafone_cash">محفظة إلكترونية</option>
                  <option value="bank">حساب بنكي</option>
                </select>
              ), 'بدون وسيلة دفع لا يستطيع الطلاب رفع إيصالاتهم لهذه الشركة.')}
              {method.methodType && field('الاسم الظاهر للطالب', <input value={method.displayName} onChange={(e) => setMethod({ ...method, displayName: e.target.value })} className={input} />)}
              {method.methodType && field('اسم صاحب الحساب (اختياري)', <input value={method.accountHolder} onChange={(e) => setMethod({ ...method, accountHolder: e.target.value })} className={input} />)}
              {method.methodType === 'instapay' && field('عنوان InstaPay', <input value={method.instapayAddress} onChange={(e) => setMethod({ ...method, instapayAddress: e.target.value })} className={input} dir="ltr" />)}
              {method.methodType === 'vodafone_cash' && field('رقم المحفظة', <input value={method.walletPhone} onChange={(e) => setMethod({ ...method, walletPhone: e.target.value })} className={input} dir="ltr" inputMode="tel" />)}
              {method.methodType === 'bank' && (
                <>
                  {field('اسم البنك', <input value={method.bankName} onChange={(e) => setMethod({ ...method, bankName: e.target.value })} className={input} />)}
                  {field('رقم الحساب', <input value={method.bankAccountNumber} onChange={(e) => setMethod({ ...method, bankAccountNumber: e.target.value })} className={input} dir="ltr" />)}
                  {field('IBAN (اختياري)', <input value={method.iban} onChange={(e) => setMethod({ ...method, iban: e.target.value })} className={input} dir="ltr" />)}
                </>
              )}
            </>
          )}
        </div>

        {error && <p role="alert" className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}

        <div className="mt-6 flex items-center justify-between">
          <button onClick={() => (step === 0 ? onClose() : setStep(step - 1))} disabled={saving} className="rounded-xl px-4 py-2.5 text-sm font-bold text-slate-600 hover:bg-slate-100 disabled:opacity-50">
            {step === 0 ? 'إلغاء' : 'السابق'}
          </button>
          <button onClick={() => void next()} disabled={saving} className="rounded-xl bg-[#3E8FBF] px-5 py-2.5 text-sm font-bold text-white hover:bg-[#3580AC] disabled:opacity-50">
            {saving ? 'جاري الإنشاء...' : step === steps.length - 1 ? 'إنشاء الشركة' : 'التالي'}
          </button>
        </div>
      </div>
    </div>
  );
};
