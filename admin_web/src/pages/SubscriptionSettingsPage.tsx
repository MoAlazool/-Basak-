import React, { useEffect, useState } from 'react';
import { CalendarRange, Save, ToggleLeft, ToggleRight } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { Topbar } from '../components/Topbar';
import { useAdminScope, useCompany } from '../lib/adminScope';
import { keys, unwrap, usePageData } from '../lib/query';
import { SkeletonRows } from '../components/Skeleton';

interface Term {
  code: 'first' | 'second' | 'summer';
  name: string;
  sort_order: number;
  start_month: number; start_day: number; start_year_offset: number;
  end_month: number; end_day: number; end_year_offset: number;
  included_in_annual: boolean;
}
interface Period { period_code: string; academic_year: number; label: string; start_date: string; end_date: string; }
interface Settings {
  company_id: string | null;
  annual_company: boolean | null;
  annual_effective: boolean;
  annual_global: boolean;
  can_edit_global: boolean;
  terms: Term[];
  periods: Period[] | null;
  purchasable: (Period & { phase: string; subscription_type: string })[] | null;
}

interface Switches {
  daily_global: boolean;
  daily_company: boolean | null;
  daily_effective: boolean;
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

/** A company's own semester dates and annual plan, edited by that company. */
export const CompanySettingsPage: React.FC = () => {
  const company = useCompany();
  return <SettingsView companyId={company.id} companyName={company.name} />;
};

/** What a newly created company starts with, and the platform-wide annual switch. */
export const PlatformDefaultsPage: React.FC = () => <SettingsView companyId={null} companyName="" />;

const SettingsView: React.FC<{ companyId: string | null; companyName: string }> = ({ companyId, companyName }) => {
  const admin = useAdminScope();
  const [drafts, setDrafts] = useState<Record<string, Term>>({});
  const [saving, setSaving] = useState(false);

  const page = usePageData(companyId ? keys.company(companyId, 'settings') : keys.platform('defaults'), () =>
    unwrap<Settings>(supabase.rpc('get_subscription_settings', { p_company_id: companyId })));
  const settings = page.data ?? null;
  const switchesPage = usePageData(companyId ? keys.company(companyId, 'switches') : keys.platform('switches'), () =>
    unwrap<Switches>(supabase.rpc('get_subscription_switches', { p_company_id: companyId })));
  const switches = switchesPage.data ?? null;
  const error = page.error;
  const load = page.reload;
  // The editable copy follows what is saved, whenever that changes.
  useEffect(() => {
    if (settings) setDrafts(Object.fromEntries((settings.terms || []).map((t) => [t.code, { ...t }])));
  }, [settings]);

  const setAnnual = async (enabled: boolean, target: string | null) => {
    const { error: setError_ } = await supabase.rpc('set_annual_subscription', {
      p_enabled: enabled, p_company_id: target,
    });
    if (setError_) alert('تعذر حفظ الإعداد: ' + setError_.message);
    await Promise.all([load(), switchesPage.reload()]);
  };

  const setDaily = async (enabled: boolean, target: string | null) => {
    const { error: setError_ } = await supabase.rpc('set_daily_subscription', {
      p_enabled: enabled, p_company_id: target,
    });
    if (setError_) alert('تعذر حفظ الإعداد: ' + setError_.message);
    await switchesPage.reload();
  };

  const saveTerms = async () => {
    if (!settings) return;
    const changed = settings.terms.filter((term) => {
      const d = drafts[term.code];
      return (['name', 'start_month', 'start_day', 'end_month', 'end_day'] as const).some((k) => d[k] !== term[k]);
    }).map((term) => drafts[term.code]);
    if (changed.length === 0) return;
    try {
      setSaving(true);
      if (companyId) {
        // The company's terms are checked and saved together, then its open subscriptions follow.
        const { data, error: saveError } = await supabase.rpc('save_company_terms', {
          p_company_id: companyId,
          p_terms: changed.map((d) => ({
            code: d.code, name: d.name.trim(), start_month: d.start_month, start_day: d.start_day,
            end_month: d.end_month, end_day: d.end_day,
          })),
        });
        if (saveError) throw saveError;
        const moved = Number((data as { moved_subscriptions?: number } | null)?.moved_subscriptions ?? 0);
        alert(moved > 0 ? `تم حفظ المواعيد وتحديث ${moved.toLocaleString('ar-EG')} اشتراك مفتوح.` : 'تم حفظ مواعيد الفصول الدراسية.');
      } else {
        // The defaults: one term at a time; the database validates after each.
        for (const d of changed) {
          const { error: saveError } = await supabase.from('academic_terms').update({
            name: d.name.trim(), start_month: d.start_month, start_day: d.start_day,
            end_month: d.end_month, end_day: d.end_day,
          }).eq('code', d.code).select('code').single();
          if (saveError) throw saveError;
        }
        alert('تم حفظ المواعيد الافتراضية. تُطبّق على الشركات التي تُنشأ بعد الآن.');
      }
      await load();
    } catch (err: any) {
      alert('تعذر حفظ المواعيد: ' + err.message);
      await load();
    } finally {
      setSaving(false);
    }
  };

  const editable = companyId ? true : admin.role === 'super_admin';
  const update = (code: string, patch: Partial<Term>) => setDrafts((all) => ({ ...all, [code]: { ...all[code], ...patch } }));

  return (
    <div className="space-y-6">
      {companyId ? (
        <Topbar title="إعدادات الشركة" subtitle={`مواعيد الفصول والاشتراك السنوي واليومي الخاصة بـ ${companyName}`} />
      ) : (
        <Topbar title="الإعدادات الافتراضية" subtitle="ما تبدأ به كل شركة جديدة. تغييرها لا يمس الشركات القائمة." />
      )}
      {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر التحميل: {error}</div>}

      {page.loading && <div className="rounded-2xl border border-slate-100 bg-white"><SkeletonRows /></div>}
      {settings && (
        <>
          <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
            <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
              <CalendarRange className="h-5 w-5 text-blue-600" /> الفصول الدراسية
            </h2>
            <p className="mt-1 text-xs text-slate-500">
              {companyId
                ? 'هذه المواعيد خاصة بهذه الشركة: يستخدمها تطبيق طلابها وإيصالاتها وانتهاء اشتراكاتها. تغييرها لا يمس أي شركة أخرى.'
                : 'تُنسخ هذه المواعيد إلى كل شركة عند إنشائها، ثم تعدّلها الشركة من إعداداتها.'}
            </p>
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
              عند التعطيل لا يظهر خيار الاشتراك السنوي للطلاب ولا يمكن إنشاؤه.
            </p>
            {companyId ? (
              <div className="mt-4 flex items-center justify-between rounded-xl border border-slate-100 p-3">
                <div>
                  <p className="text-sm font-semibold text-slate-700">الاشتراك السنوي لدى {companyName}</p>
                  <p className="text-[11px] text-slate-500">
                    {settings.annual_effective ? 'يظهر للطلاب' : !settings.annual_global ? 'معطّل على مستوى المنصة حالياً' : 'لا يظهر للطلاب'}
                  </p>
                </div>
                <Toggle on={!!settings.annual_company} onClick={() => void setAnnual(!settings.annual_company, companyId)} />
              </div>
            ) : (
              <div className="mt-4 flex items-center justify-between rounded-xl bg-slate-50 p-3">
                <div>
                  <p className="text-sm font-semibold text-slate-700">السماح بالاشتراك السنوي على المنصة</p>
                  <p className="text-[11px] text-slate-500">عند التعطيل يتوقف لدى كل الشركات. عند التفعيل تقرر كل شركة من إعداداتها.</p>
                </div>
                <Toggle on={settings.annual_global} disabled={!settings.can_edit_global}
                  onClick={() => void setAnnual(!settings.annual_global, null)} />
              </div>
            )}
          </div>

          {switches && (
            <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
              <h2 className="text-base font-bold text-slate-700">الاشتراك اليومي (كاش)</h2>
              <p className="mt-1 text-xs text-slate-500">
                عند التعطيل لا يظهر خيار الاشتراك اليومي للطلاب ولا يمكن إنشاؤه، ويُقفل سعره في شاشة الخطوط.
              </p>
              {companyId ? (
                <div className="mt-4 flex items-center justify-between rounded-xl border border-slate-100 p-3">
                  <div>
                    <p className="text-sm font-semibold text-slate-700">الاشتراك اليومي لدى {companyName}</p>
                    <p className="text-[11px] text-slate-500">
                      {switches.daily_effective ? 'يظهر للطلاب' : !switches.daily_global ? 'معطّل على مستوى المنصة حالياً' : 'لا يظهر للطلاب'}
                    </p>
                  </div>
                  <Toggle on={!!switches.daily_company} onClick={() => void setDaily(!switches.daily_company, companyId)} />
                </div>
              ) : (
                <div className="mt-4 flex items-center justify-between rounded-xl bg-slate-50 p-3">
                  <div>
                    <p className="text-sm font-semibold text-slate-700">السماح بالاشتراك اليومي على المنصة</p>
                    <p className="text-[11px] text-slate-500">عند التعطيل يتوقف لدى كل الشركات. عند التفعيل تقرر كل شركة من إعداداتها.</p>
                  </div>
                  <Toggle on={switches.daily_global} disabled={!settings.can_edit_global}
                    onClick={() => void setDaily(!switches.daily_global, null)} />
                </div>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
};
