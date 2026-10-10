import React, { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { MessageCircle, Save, Smartphone } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { Topbar } from '../components/Topbar';
import { SkeletonForm } from '../components/Skeleton';
import { keys, STALE, unwrap, usePageData } from '../lib/query';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';
import {
  draftChanged, draftFromRow, draftProblem, PLATFORMS, platformName, toSave, WHATS_NEW_MAX,
  type AppVersionDraft, type AppVersionRow, type Platform,
} from '../lib/appVersions';
import { readableWhatsApp, whatsappDigits, whatsappLink } from '../lib/supportWhatsApp';

const versionsKey = keys.platform('appVersions');
const whatsappKey = keys.platform('supportWhatsApp');
const COLUMNS = 'platform, min_version, latest_version, whats_new, store_url, updated_at';

/**
 * The platform admin's page for the app's releases: which version is the oldest
 * still allowed in, which is the newest, what is new in it and where to get it,
 * for each store. The app reads this before sign-in to show "update available"
 * or "update to continue".
 */
export const AppVersionsPage: React.FC = () => {
  const page = usePageData(versionsKey, () =>
    unwrap<AppVersionRow[]>(supabase.from('app_versions').select(COLUMNS).order('platform')), { staleTime: STALE.reference });
  const rows = page.data ?? [];
  return (
    <div className="space-y-6">
      <Topbar title="إعدادات التطبيق" subtitle="متى يطلب التطبيق من المستخدم التحديث، وما الذي يقوله له، ورقم واتساب الدعم." />
      {page.error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر التحميل: {page.error}</div>}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 text-xs leading-6 text-slate-600 shadow-sm">
        <p><span className="font-bold text-slate-700">أقل إصدار مسموح:</span> من يستخدم إصداراً أقدم منه يرى شاشة «حدّث التطبيق للمتابعة» ولا يستطيع المتابعة قبل التحديث. تبقى بطاقة الطالب متاحة له.</p>
        <p><span className="font-bold text-slate-700">آخر إصدار:</span> من يستخدم إصداراً أقدم منه (وليس أقدم من المسموح) يرى «تحديث جديد متاح» مرة واحدة، ويستطيع تأجيله.</p>
        <p>القيمة 0.0.0 لا تطلب تحديثاً من أحد. يقرأ التطبيق هذه القيم عند فتحه.</p>
      </div>
      {page.loading ? <div className="grid gap-6 lg:grid-cols-2"><SkeletonForm fields={4} /><SkeletonForm fields={4} /></div> : (
        <div className="grid gap-6 lg:grid-cols-2">
          {PLATFORMS.map((platform) => (
            <PlatformCard key={platform} platform={platform} row={rows.find((r) => r.platform === platform)} />
          ))}
        </div>
      )}
      <SupportWhatsAppCard />
    </div>
  );
};

const PlatformCard: React.FC<{ platform: Platform; row: AppVersionRow | undefined }> = ({ platform, row }) => {
  const client = useQueryClient();
  const guard = useGuard();
  const [draft, setDraft] = useState<AppVersionDraft>(() => draftFromRow(row));
  const [saving, setSaving] = useState(false);
  // The editable copy follows what is saved, whenever that changes.
  useEffect(() => { setDraft(draftFromRow(row)); }, [row]);

  const patch = (p: Partial<AppVersionDraft>) => setDraft((cur) => ({ ...cur, ...p }));
  const setLine = (index: number, text: string) =>
    setDraft((cur) => ({ ...cur, whatsNew: cur.whatsNew.map((line, i) => (i === index ? text : line)) }));
  const problem = draftProblem(draft);
  const changed = draftChanged(draft, row);

  // One request: the function answers with the row as saved, which replaces the cached one.
  const save = () => guard('save', async () => {
    if (problem) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('save_app_version', toSave(platform, draft));
    setSaving(false);
    if (error) { notifyError('تعذر حفظ إعدادات الإصدار', error.message); return; }
    const saved = data as AppVersionRow | null;
    if (saved) {
      client.setQueryData<AppVersionRow[]>(versionsKey, (all) => [...(all ?? []).filter((r) => r.platform !== platform), saved]);
    } else {
      await client.invalidateQueries({ queryKey: versionsKey });
    }
    notifyDone(`تم حفظ إعدادات ${platformName[platform]}`);
  });

  const input = 'mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-sm';
  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
      <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
        <Smartphone className="h-5 w-5 text-blue-600" /> {platformName[platform]}
      </h2>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-xs font-semibold text-slate-600">
          أقل إصدار مسموح
          <input dir="ltr" inputMode="decimal" value={draft.minVersion} onChange={(e) => patch({ minVersion: e.target.value })}
            placeholder="2.3.0" className={`${input} text-left font-mono`} />
          <span className="mt-1 block text-[11px] font-normal text-slate-400">الأقدم منه يُطلب منه التحديث للمتابعة</span>
        </label>
        <label className="text-xs font-semibold text-slate-600">
          آخر إصدار في المتجر
          <input dir="ltr" inputMode="decimal" value={draft.latestVersion} onChange={(e) => patch({ latestVersion: e.target.value })}
            placeholder="2.5.0" className={`${input} text-left font-mono`} />
          <span className="mt-1 block text-[11px] font-normal text-slate-400">الأقدم منه يُعرض عليه التحديث</span>
        </label>
      </div>

      <fieldset className="mt-4">
        <legend className="text-xs font-semibold text-slate-600">ما الجديد (حتى ثلاثة أسطر، تظهر للمستخدم كما تكتبها)</legend>
        {draft.whatsNew.map((line, index) => (
          <input key={index} value={line} maxLength={WHATS_NEW_MAX} onChange={(e) => setLine(index, e.target.value)}
            placeholder={index === 0 ? 'مثال: دخول أسرع ببصمة الوجه أو الإصبع' : ''} aria-label={`السطر ${index + 1} من ما الجديد`}
            className={input} />
        ))}
      </fieldset>

      <label className="mt-4 block text-xs font-semibold text-slate-600">
        رابط التطبيق في المتجر
        <input dir="ltr" type="url" value={draft.storeUrl} onChange={(e) => patch({ storeUrl: e.target.value })}
          placeholder={platform === 'ios' ? 'https://apps.apple.com/app/…' : 'https://play.google.com/store/apps/details?id=…'}
          className={`${input} text-left`} />
        <span className="mt-1 block text-[11px] font-normal text-slate-400">يفتحه زر «تحديث الآن» في التطبيق.</span>
      </label>

      {problem && changed && <p role="alert" className="mt-3 rounded-lg bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700">{problem}</p>}
      <div className="mt-4 flex justify-end">
        <button disabled={saving || !changed || !!problem} onClick={() => void save()}
          className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-50">
          <Save className="h-4 w-4" /> {saving ? 'جاري الحفظ...' : 'حفظ'}
        </button>
      </div>
    </div>
  );
};

/**
 * The platform's WhatsApp number: students who forgot their password open a
 * chat with it from the app's "enter the code" screen, to be given the code.
 * Empty hides that button.
 */
const SupportWhatsAppCard: React.FC = () => {
  const client = useQueryClient();
  const guard = useGuard();
  const page = usePageData(whatsappKey, () => unwrap<string | null>(supabase.rpc('get_support_whatsapp')), { staleTime: STALE.reference });
  const saved = page.data ?? '';
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  // The editable copy follows what is saved, whenever that changes.
  useEffect(() => { setDraft(saved ? readableWhatsApp(saved) : ''); }, [saved]);

  const digits = whatsappDigits(draft);
  const changed = digits !== null && digits !== saved;

  const save = () => guard('save', async () => {
    if (digits === null) return;
    setSaving(true);
    const { data, error } = await supabase.rpc('save_support_whatsapp', { p_phone: digits });
    setSaving(false);
    if (error) { notifyError('تعذر حفظ رقم واتساب', error.message); return; }
    client.setQueryData(whatsappKey, (data as string | null) ?? null);
    notifyDone(data ? 'تم حفظ رقم واتساب الدعم' : 'تم إخفاء زر واتساب من التطبيق');
  });

  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
      <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
        <MessageCircle className="h-5 w-5 text-emerald-600" /> واتساب استعادة كلمة المرور
      </h2>
      <p className="mt-1 text-xs leading-6 text-slate-500">
        في شاشة «أدخل الرمز» يظهر للطالب زر «اطلب الرمز على واتساب» يفتح محادثة مع هذا الرقم ومعها رقم هاتفه. اتركه فارغاً لإخفاء الزر.
      </p>
      {page.error && <p role="alert" className="mt-3 text-xs font-semibold text-rose-700">تعذر التحميل: {page.error}</p>}
      <div className="mt-4 flex flex-wrap items-end gap-3">
        <label className="min-w-[220px] flex-1 text-xs font-semibold text-slate-600">
          رقم واتساب
          <input dir="ltr" type="tel" value={draft} disabled={page.loading} onChange={(e) => setDraft(e.target.value)}
            placeholder="01012345678" className="mt-1 w-full rounded-lg border border-slate-200 px-3 py-2 text-left font-mono text-sm" />
        </label>
        {saved && !changed && (
          <a href={whatsappLink(saved)} target="_blank" rel="noreferrer" className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-600">
            جرّب المحادثة
          </a>
        )}
        <button disabled={saving || !changed} onClick={() => void save()}
          className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-50">
          <Save className="h-4 w-4" /> {saving ? 'جاري الحفظ...' : 'حفظ'}
        </button>
      </div>
      {digits === null && <p role="alert" className="mt-3 rounded-lg bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700">اكتب رقم واتساب صحيحاً، مثل 01012345678.</p>}
    </div>
  );
};
