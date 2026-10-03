import React, { useCallback, useEffect, useState } from 'react';
import { CalendarRange, Save, ToggleLeft, ToggleRight } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useAdminScope } from '../lib/adminScope';

interface Term {
  code: 'first' | 'second' | 'summer';
  name: string;
  sort_order: number;
  start_month: number; start_day: number; start_year_offset: number;
  end_month: number; end_day: number; end_year_offset: number;
  included_in_annual: boolean;
}
interface Period { period_code: string; academic_year: number; label: string; start_date: string; end_date: string; }
interface CompanySetting { id: string; name: string; annual_enabled: boolean; effective: boolean; }
interface Settings {
  annual_global: boolean;
  can_edit_global: boolean;
  terms: Term[];
  periods: Period[] | null;
  purchasable: (Period & { phase: string; subscription_type: string })[] | null;
  companies: CompanySetting[];
}

const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

const Toggle: React.FC<{ on: boolean; disabled?: boolean; onClick: () => void }> = ({ on, disabled, onClick }) => (
  <button type="button" disabled={disabled} onClick={onClick}
    className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-bold transition disabled:opacity-50 ${
      on ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}>
    {on ? <ToggleRight className="h-4 w-4" /> : <ToggleLeft className="h-4 w-4" />}
    {on ? 'مفعّل' : 'معطّل'}
  </button>
);

/** Semester dates (one source: academic_terms) and the annual subscription switch. */
export const SubscriptionSettingsPage: React.FC = () => {
  const admin = useAdminScope();
  const [settings, setSettings] = useState<Settings | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Term>>({});
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    const { data, error: loadError } = await supabase.rpc('get_subscription_settings');
    if (loadError) { setError(loadError.message); return; }
    setError('');
    const loaded = data as Settings;
    setSettings(loaded);
    setDrafts(Object.fromEntries((loaded.terms || []).map((t) => [t.code, { ...t }])));
  }, []);

  useEffect(() => { void load(); }, [load]);

  const setAnnual = async (enabled: boolean, companyId: string | null) => {
    const { error: setError_ } = await supabase.rpc('set_annual_subscription', {
      p_enabled: enabled, p_company_id: companyId,
    });
    if (setError_) alert('تعذر حفظ الإعداد: ' + setError_.message);
    await load();
  };

  const saveTerms = async () => {
    if (!settings) return;
    try {
      setSaving(true);
      // One term at a time; the database validates (no overlap, valid dates) after each.
      for (const term of settings.terms) {
        const d = drafts[term.code];
        const changed = (['name', 'start_month', 'start_day', 'end_month', 'end_day'] as const).some((k) => d[k] !== term[k]);
        if (!changed) continue;
        const { error: saveError } = await supabase.from('academic_terms').update({
          name: d.name.trim(), start_month: d.start_month, start_day: d.start_day,
          end_month: d.end_month, end_day: d.end_day,
        }).eq('code', term.code).select('code').single();
        if (saveError) throw saveError;
      }
      await load();
      alert('تم حفظ مواعيد الفصول الدراسية وتحديث الاشتراكات المفتوحة.');
    } catch (err: any) {
      alert('تعذر حفظ المواعيد: ' + err.message);
      await load();
    } finally {
      setSaving(false);
    }
  };

  const editable = admin.role === 'super_admin';
  const update = (code: string, patch: Partial<Term>) => setDrafts((all) => ({ ...all, [code]: { ...all[code], ...patch } }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إعدادات الاشتراكات</h1>
        <p className="text-sm text-slate-500">
          مواعيد الفصول الدراسية مصدرها الوحيد هذا الإعداد: يستخدمه التطبيق والإيصالات وانتهاء الاشتراكات وكل اللوحات.
        </p>
      </div>
      {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر التحميل: {error}</div>}

      {settings && (
        <>
          <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
            <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
              <CalendarRange className="h-5 w-5 text-blue-600" /> الفصول الدراسية
            </h2>
            {!editable && <p className="mt-1 text-xs text-slate-500">تعديل المواعيد متاح لمدير النظام فقط.</p>}
            <div className="mt-4 overflow-x-auto">
              <table className="w-full min-w-[620px] text-right text-sm">
                <thead className="text-xs text-slate-500">
                  <tr><th className="p-2">الفصل</th><th className="p-2">البداية</th><th className="p-2">النهاية</th><th className="p-2">ضمن السنوي</th></tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {settings.terms.map((term) => {
                    const d = drafts[term.code] ?? term;
                    const dayMonth = (dayKey: 'start_day' | 'end_day', monthKey: 'start_month' | 'end_month') => (
                      <div className="flex gap-1">
                        <input type="number" min={1} max={31} disabled={!editable} value={d[dayKey]}
                          onChange={(e) => update(term.code, { [dayKey]: Number(e.target.value) } as Partial<Term>)}
                          className="w-16 rounded-lg border border-slate-200 px-2 py-1 text-sm disabled:bg-slate-50" />
                        <select disabled={!editable} value={d[monthKey]}
                          onChange={(e) => update(term.code, { [monthKey]: Number(e.target.value) } as Partial<Term>)}
                          className="rounded-lg border border-slate-200 px-2 py-1 text-sm disabled:bg-slate-50">
                          {months.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
                        </select>
                      </div>
                    );
                    return (
                      <tr key={term.code}>
                        <td className="p-2">
                          <input disabled={!editable} value={d.name} onChange={(e) => update(term.code, { name: e.target.value })}
                            className="w-48 rounded-lg border border-slate-200 px-2 py-1 text-sm font-semibold disabled:bg-slate-50" />
                        </td>
                        <td className="p-2">{dayMonth('start_day', 'start_month')}</td>
                        <td className="p-2">{dayMonth('end_day', 'end_month')}</td>
                        <td className="p-2 text-xs">{term.included_in_annual ? 'نعم' : 'لا'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {editable && (
              <div className="mt-3 flex justify-end">
                <button disabled={saving} onClick={() => void saveTerms()}
                  className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-50">
                  <Save className="h-4 w-4" /> {saving ? 'جاري الحفظ...' : 'حفظ المواعيد'}
                </button>
              </div>
            )}

            <h3 className="mt-6 text-sm font-bold text-slate-700">الفترات الحالية والقادمة</h3>
            <div className="mt-2 flex flex-wrap gap-2">
              {(settings.periods || []).map((p) => (
                <span key={`${p.period_code}${p.academic_year}`} className="rounded-xl bg-slate-50 px-3 py-1.5 text-xs text-slate-600">
                  <b className="text-slate-800">{p.label}</b> <span dir="ltr">{p.start_date} → {p.end_date}</span>
                </span>
              ))}
            </div>
            <p className="mt-3 text-xs text-slate-500">
              متاح للدفع الآن: {(settings.purchasable || []).map((p) => `${p.label}${p.phase === 'upcoming' ? ' (مقدماً)' : ''}`).join('، ') || '—'}
            </p>
          </div>

          <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
            <h2 className="text-base font-bold text-slate-700">الاشتراك السنوي (الفصلان الأول والثاني)</h2>
            <p className="mt-1 text-xs text-slate-500">
              عند التعطيل لا يظهر خيار الاشتراك السنوي للطلاب ولا يمكن إنشاؤه. الإعداد العام يتحكم فيه مدير النظام، وكل شركة تتحكم في خيارها.
            </p>
            <div className="mt-4 flex items-center justify-between rounded-xl bg-slate-50 p-3">
              <span className="text-sm font-semibold text-slate-700">الإعداد العام لكل الشركات</span>
              <Toggle on={settings.annual_global} disabled={!settings.can_edit_global}
                onClick={() => void setAnnual(!settings.annual_global, null)} />
            </div>
            <div className="mt-3 space-y-2">
              {settings.companies.map((c) => (
                <div key={c.id} className="flex items-center justify-between rounded-xl border border-slate-100 p-3">
                  <div>
                    <p className="text-sm font-semibold text-slate-700">{c.name}</p>
                    <p className="text-[11px] text-slate-500">
                      {c.effective ? 'يظهر للطلاب' : !settings.annual_global ? 'معطّل عاماً من مدير النظام' : 'لا يظهر للطلاب'}
                    </p>
                  </div>
                  <Toggle on={c.annual_enabled} onClick={() => void setAnnual(!c.annual_enabled, c.id)} />
                </div>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
};
