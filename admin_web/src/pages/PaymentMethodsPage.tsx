import React, { useEffect, useState } from 'react';
import { ArrowDown, ArrowUp, Landmark, Pencil, Plus, Power, Smartphone, Trash2, Wallet, X } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import { keys, unwrap, usePageData } from '../lib/query';
import { SkeletonRows } from '../components/Skeleton';

type MethodType = 'instapay' | 'vodafone_cash' | 'bank';

interface PaymentMethod {
  id: string; company_id: string; method_type: MethodType; display_name: string;
  account_holder: string | null; instapay_address: string | null; wallet_phone: string | null;
  bank_name: string | null; bank_account_number: string | null; iban: string | null;
  instructions: string | null; is_active: boolean; sort_order: number;
}
type Draft = Omit<PaymentMethod, 'id'> & { id?: string };

const TYPES: Record<MethodType, { label: string; icon: React.ReactNode }> = {
  instapay: { label: 'InstaPay', icon: <Wallet className="h-4 w-4" /> },
  vodafone_cash: { label: 'Vodafone Cash', icon: <Smartphone className="h-4 w-4" /> },
  bank: { label: 'حساب بنكي', icon: <Landmark className="h-4 w-4" /> },
};

const empty = (companyId: string, order: number): Draft => ({
  company_id: companyId, method_type: 'instapay', display_name: 'InstaPay', account_holder: '', instapay_address: '',
  wallet_phone: '', bank_name: '', bank_account_number: '', iban: '', instructions: '', is_active: true, sort_order: order,
});

/** Company-specific payment methods shown to students when they pay (no hardcoded accounts). */
export const PaymentMethodsPage: React.FC = () => {
  const companyId = useCompany().id;
  const [draft, setDraft] = useState<Draft | null>(null);
  const [error, setError] = useState('');

  const page = usePageData(keys.company(companyId, 'paymentMethods'), async () =>
    unwrap<PaymentMethod[]>(supabase.from('company_payment_methods').select('*')
      .eq('company_id', companyId).order('sort_order').order('created_at')));
  const methods = page.data ?? [];
  const loading = page.loading;
  const load = page.reload;

  const save = async () => {
    if (!draft) return;
    setError('');
    const clean = (v: string | null) => (v && v.trim() ? v.trim() : null);
    // Only the fields of the chosen type are stored.
    const row = {
      company_id: draft.company_id, method_type: draft.method_type, display_name: draft.display_name.trim(),
      account_holder: clean(draft.account_holder),
      instapay_address: draft.method_type === 'instapay' ? clean(draft.instapay_address) : null,
      wallet_phone: draft.method_type === 'vodafone_cash' ? clean(draft.wallet_phone)?.replace(/\D/g, '') ?? null : null,
      bank_name: draft.method_type === 'bank' ? clean(draft.bank_name) : null,
      bank_account_number: draft.method_type === 'bank' ? clean(draft.bank_account_number) : null,
      iban: draft.method_type === 'bank' ? clean(draft.iban) : null,
      instructions: clean(draft.instructions), is_active: draft.is_active, sort_order: draft.sort_order,
      updated_at: new Date().toISOString(),
    };
    const { error: saveError } = draft.id
      ? await supabase.from('company_payment_methods').update(row).eq('id', draft.id).select('id').single()
      : await supabase.from('company_payment_methods').insert(row).select('id').single();
    if (saveError) {
      setError(saveError.message.includes('payment_method_fields')
        ? 'أكمل بيانات الوسيلة: عنوان InstaPay، أو رقم محفظة فودافون كاش (01xxxxxxxxx)، أو اسم البنك ورقم الحساب.'
        : saveError.message);
      return;
    }
    setDraft(null);
    void load();
  };

  const update = async (m: PaymentMethod, patch: Partial<PaymentMethod>) => {
    const { error: e } = await supabase.from('company_payment_methods').update(patch).eq('id', m.id).select('id').single();
    if (e) alert(e.message); else void load();
  };
  const move = async (index: number, delta: number) => {
    const a = methods[index]; const b = methods[index + delta];
    if (!a || !b) return;
    await supabase.from('company_payment_methods').update({ sort_order: b.sort_order }).eq('id', a.id);
    await supabase.from('company_payment_methods').update({ sort_order: a.sort_order === b.sort_order ? a.sort_order + delta : a.sort_order }).eq('id', b.id);
    void load();
  };
  const remove = async (m: PaymentMethod) => {
    if (!confirm(`حذف "${m.display_name}"؟ الإيصالات السابقة تبقى محفوظة بدون ربط بالوسيلة. يمكنك تعطيلها بدلاً من الحذف.`)) return;
    const { error: e } = await supabase.from('company_payment_methods').delete().eq('id', m.id);
    if (e) alert(e.message); else void load();
  };

  const input = 'mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none';
  const detail = (m: PaymentMethod) => m.method_type === 'instapay' ? m.instapay_address
    : m.method_type === 'vodafone_cash' ? m.wallet_phone : `${m.bank_name} · ${m.bank_account_number}${m.iban ? ` · ${m.iban}` : ''}`;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">وسائل الدفع</h1>
          <p className="text-sm text-slate-500">ما يراه الطالب عند الدفع لهذه الشركة: InstaPay وفودافون كاش والحسابات البنكية.</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => setDraft(empty(companyId, (methods[methods.length - 1]?.sort_order ?? 0) + 1))}
            className="flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-2 text-sm font-bold text-white disabled:opacity-50">
            <Plus className="h-4 w-4" /> إضافة وسيلة دفع
          </button>
        </div>
      </div>

      {(error || page.error) && !draft && <p role="alert" className="rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}

      <div className="space-y-3">
        {loading ? <SkeletonRows /> : methods.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center text-slate-500">لا توجد وسائل دفع لهذه الشركة. أضف وسيلة ليتمكن الطلاب من الدفع.</div>
        ) : methods.map((m, i) => (
          <div key={m.id} className={`flex flex-wrap items-center justify-between gap-3 rounded-2xl border bg-white p-4 shadow-sm ${m.is_active ? 'border-slate-100' : 'border-slate-200 opacity-60'}`}>
            <div className="flex items-center gap-3">
              <div className="rounded-xl bg-blue-50 p-2.5 text-blue-600">{TYPES[m.method_type].icon}</div>
              <div>
                <p className="font-bold text-slate-800">{m.display_name} <span className="text-xs font-medium text-slate-400">· {TYPES[m.method_type].label}</span></p>
                <p className="font-mono text-xs text-slate-500" dir="ltr">{detail(m)}</p>
                {m.account_holder && <p className="text-xs text-slate-500">باسم: {m.account_holder}</p>}
              </div>
            </div>
            <div className="flex items-center gap-1">
              <span className={`ml-2 rounded-full px-2 py-0.5 text-[11px] font-bold ${m.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>{m.is_active ? 'مفعّلة' : 'معطّلة'}</span>
              <button onClick={() => void move(i, -1)} disabled={i === 0} className="rounded-lg p-1.5 text-slate-400 disabled:opacity-30" title="لأعلى"><ArrowUp className="h-4 w-4" /></button>
              <button onClick={() => void move(i, 1)} disabled={i === methods.length - 1} className="rounded-lg p-1.5 text-slate-400 disabled:opacity-30" title="لأسفل"><ArrowDown className="h-4 w-4" /></button>
              <button onClick={() => setDraft({ ...m })} className="rounded-lg p-1.5 text-blue-500" title="تعديل"><Pencil className="h-4 w-4" /></button>
              <button onClick={() => void update(m, { is_active: !m.is_active })} className={m.is_active ? 'rounded-lg p-1.5 text-amber-500' : 'rounded-lg p-1.5 text-emerald-600'} title={m.is_active ? 'تعطيل' : 'تفعيل'}><Power className="h-4 w-4" /></button>
              <button onClick={() => void remove(m)} className="rounded-lg p-1.5 text-rose-400" title="حذف"><Trash2 className="h-4 w-4" /></button>
            </div>
          </div>
        ))}
      </div>

      {draft && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4" dir="rtl">
          <div className="w-full max-w-lg space-y-4 rounded-3xl bg-white p-6 shadow-2xl">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-slate-800">{draft.id ? 'تعديل وسيلة الدفع' : 'وسيلة دفع جديدة'}</h2>
              <button onClick={() => setDraft(null)} className="text-slate-400" aria-label="إغلاق"><X className="h-5 w-5" /></button>
            </div>
            <div className="grid grid-cols-3 gap-2">
              {(Object.keys(TYPES) as MethodType[]).map((type) => (
                <button key={type} onClick={() => setDraft({ ...draft, method_type: type, display_name: draft.display_name && !Object.values(TYPES).some((t) => t.label === draft.display_name) ? draft.display_name : TYPES[type].label })}
                  className={`flex items-center justify-center gap-1.5 rounded-xl border px-2 py-2 text-xs font-bold ${draft.method_type === type ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-slate-200 text-slate-600'}`}>
                  {TYPES[type].icon}{TYPES[type].label}
                </button>
              ))}
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="text-xs font-semibold text-slate-500">الاسم الظاهر للطالب<input value={draft.display_name} onChange={(e) => setDraft({ ...draft, display_name: e.target.value })} className={input} /></label>
              <label className="text-xs font-semibold text-slate-500">اسم صاحب الحساب<input value={draft.account_holder ?? ''} onChange={(e) => setDraft({ ...draft, account_holder: e.target.value })} className={input} /></label>
              {draft.method_type === 'instapay' && (
                <label className="text-xs font-semibold text-slate-500 sm:col-span-2">عنوان InstaPay أو معرّف الحساب<input dir="ltr" value={draft.instapay_address ?? ''} onChange={(e) => setDraft({ ...draft, instapay_address: e.target.value })} placeholder="name@instapay" className={input} /></label>
              )}
              {draft.method_type === 'vodafone_cash' && (
                <label className="text-xs font-semibold text-slate-500 sm:col-span-2">رقم محفظة فودافون كاش<input dir="ltr" inputMode="tel" value={draft.wallet_phone ?? ''} onChange={(e) => setDraft({ ...draft, wallet_phone: e.target.value })} placeholder="010xxxxxxxx" className={input} /></label>
              )}
              {draft.method_type === 'bank' && (<>
                <label className="text-xs font-semibold text-slate-500">اسم البنك<input value={draft.bank_name ?? ''} onChange={(e) => setDraft({ ...draft, bank_name: e.target.value })} className={input} /></label>
                <label className="text-xs font-semibold text-slate-500">رقم الحساب<input dir="ltr" value={draft.bank_account_number ?? ''} onChange={(e) => setDraft({ ...draft, bank_account_number: e.target.value })} className={input} /></label>
                <label className="text-xs font-semibold text-slate-500 sm:col-span-2">IBAN (اختياري)<input dir="ltr" value={draft.iban ?? ''} onChange={(e) => setDraft({ ...draft, iban: e.target.value })} className={input} /></label>
              </>)}
              <label className="text-xs font-semibold text-slate-500 sm:col-span-2">تعليمات الدفع للطالب<textarea rows={3} value={draft.instructions ?? ''} onChange={(e) => setDraft({ ...draft, instructions: e.target.value })} placeholder="مثال: حوّل المبلغ كاملاً ثم ارفع صورة إيصال التحويل." className={input} /></label>
              <label className="flex items-center gap-2 text-sm text-slate-600"><input type="checkbox" checked={draft.is_active} onChange={(e) => setDraft({ ...draft, is_active: e.target.checked })} />مفعّلة وتظهر للطلاب</label>
            </div>
            {error && <p role="alert" className="rounded-xl bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>}
            <div className="flex justify-end gap-2">
              <button onClick={() => setDraft(null)} className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-600">إلغاء</button>
              <button onClick={() => void save()} className="rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white">حفظ</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
