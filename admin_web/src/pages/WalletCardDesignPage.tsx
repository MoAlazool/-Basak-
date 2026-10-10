import React, { useEffect, useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Building2, CreditCard, ImagePlus, RefreshCw, Save, Trash2 } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import { keys, unwrap, usePageData } from '../lib/query';
import { Skeleton, SkeletonForm } from '../components/Skeleton';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { useGuard } from '../lib/guard';
import { ACCEPTED_IMAGES, uploadWalletArtwork, validateImage, walletArtworkUrl } from '../lib/walletArtwork';

interface Settings {
  company_id: string;
  company_name: string;
  logo_path: string | null;
  contact_phone: string | null;
  contact_label: string | null;
  background_color: string;
  foreground_color: string;
  label_color: string;
  card_title: string | null;
  banner_path: string | null;
  revision: number;
  updated_at: string | null;
  updated_by_name: string | null;
  apple_cards: number;
  google_cards: number;
  pending_cards: number;
}
interface Draft { background: string; foreground: string; label: string; title: string; phone: string; phoneLabel: string; }
/** undefined = keep the saved image, null = remove it, File = replace it. */
type ArtworkChange = File | null | undefined;
interface SyncResult { updated: number; failed: number; remaining: number; done: boolean; errors: string[]; }
interface Rollout { running: boolean; updated: number; total: number; message: string; failed: boolean; }

const HEX = /^#[0-9a-fA-F]{6}$/;
const PHONE = /^[0-9+][0-9 ()+-]{4,24}$/;
const inputClass = 'w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-blue-500 focus:outline-none';
const cardClass = 'rounded-2xl border border-slate-100 bg-white p-5 shadow-sm';
const badge = (text: string) => (
  <span className="mr-1 rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-bold text-slate-500">{text}</span>
);

const toDraft = (s: Settings): Draft => ({
  background: s.background_color, foreground: s.foreground_color, label: s.label_color,
  title: s.card_title ?? '', phone: s.contact_phone ?? '', phoneLabel: s.contact_label ?? '',
});

const ColorField: React.FC<{ label: string; only?: string; value: string; onChange: (value: string) => void }> = ({ label, only, value, onChange }) => {
  const valid = HEX.test(value);
  return (
    <label className="block text-sm font-bold text-slate-700">
      {label} {only && badge(only)}
      <div className="mt-1 flex items-center gap-2">
        <input type="color" aria-label={label} value={valid ? value : '#000000'} onChange={(e) => onChange(e.target.value.toUpperCase())}
          className="h-10 w-12 flex-shrink-0 cursor-pointer rounded-lg border border-slate-200 bg-white p-1" />
        <input dir="ltr" value={value} maxLength={7} spellCheck={false} placeholder="#00897B"
          onChange={(e) => onChange(e.target.value.trim().toUpperCase())}
          className={`${inputClass} font-mono ${valid ? '' : 'border-rose-300 focus:border-rose-500'}`} />
      </div>
      {!valid && <span className="mt-1 block text-xs font-normal text-rose-600">اكتب اللون بصيغة HEX مثل ‎#00897B</span>}
    </label>
  );
};

const ArtworkField: React.FC<{
  label: React.ReactNode; hint: string; preview: string | null;
  onPick: (file: File) => void; onRemove: () => void;
}> = ({ label, hint, preview, onPick, onRemove }) => (
  <div>
    <p className="text-sm font-bold text-slate-700">{label}</p>
    <p className="mt-0.5 text-xs text-slate-500">{hint}</p>
    <div className="mt-2 flex flex-wrap items-center gap-3">
      {preview && <img src={preview} alt="" className="h-12 max-w-[160px] rounded-lg border border-slate-200 bg-slate-50 object-contain p-1" />}
      <label className="flex cursor-pointer items-center gap-2 rounded-xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-600 hover:bg-slate-50">
        <ImagePlus className="h-4 w-4" /> اختيار صورة
        <input type="file" accept={ACCEPTED_IMAGES} className="hidden"
          onChange={(e) => { const file = e.target.files?.[0]; e.target.value = ''; if (file) onPick(file); }} />
      </label>
      {preview && (
        <button type="button" onClick={onRemove} className="flex items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-bold text-rose-600 hover:bg-rose-50">
          <Trash2 className="h-4 w-4" /> إزالة
        </button>
      )}
    </div>
  </div>
);

/** A stand-in pattern: the real card shows each student's own permanent QR. */
const SampleQr: React.FC<{ className: string }> = ({ className }) => (
  <svg viewBox="0 0 9 9" className={className} shapeRendering="crispEdges" aria-hidden="true">
    <rect width="9" height="9" fill="#fff" />
    {['0,0', '6,0', '0,6'].map((corner) => {
      const [x, y] = corner.split(',').map(Number);
      return <g key={corner}><rect x={x} y={y} width="3" height="3" fill="#111" /><rect x={x + 1} y={y + 1} width="1" height="1" fill="#fff" /></g>;
    })}
    {['4,0', '4,2', '3,4', '5,4', '7,4', '4,6', '6,6', '8,6', '5,7', '7,8', '4,8', '1,4', '8,3'].map((cell) => {
      const [x, y] = cell.split(',').map(Number);
      return <rect key={cell} x={x} y={y} width="1" height="1" fill="#111" />;
    })}
  </svg>
);

const Portrait: React.FC<{ className: string }> = ({ className }) => (
  <div className={`flex items-end justify-center overflow-hidden bg-white/25 ${className}`} aria-hidden="true">
    <svg viewBox="0 0 24 24" className="h-[85%] w-[85%] text-white/80" fill="currentColor">
      <circle cx="12" cy="8.5" r="4.2" /><path d="M3.5 24c0-5 3.8-8.2 8.5-8.2s8.5 3.200 8.500 8.200z" />
    </svg>
  </div>
);

interface PreviewProps { title: string; background: string; foreground: string; label: string; logo: string | null; banner: string | null; }
const SAMPLE = [['محطة الركوب', 'اسم المحطة'], ['الخط', 'اسم الخط'], ['الجامعة', 'اسم الجامعة'], ['الاشتراك', 'الفصل الدراسي الأول']];

/** Apple's ID-style pass: logo and name on top, photo beside the student's name, four small fields, QR. */
const ApplePreview: React.FC<PreviewProps> = ({ title, background, foreground, label, logo }) => (
  <div dir="rtl" className="mx-auto w-full max-w-[320px] rounded-2xl p-4 shadow-xl" style={{ background }}>
    <div className="flex items-center justify-between gap-2">
      <div className="flex min-w-0 items-center gap-2">
        {logo && <img src={logo} alt="" className="h-8 max-w-[90px] object-contain" />}
        <p className="truncate text-sm font-bold" style={{ color: foreground }}>{title}</p>
      </div>
      <div className="flex-shrink-0 text-left">
        <p className="text-[9px] font-bold" style={{ color: label }}>بطاقة</p>
        <p className="text-xs font-bold" style={{ color: foreground }}>نقل طلاب</p>
      </div>
    </div>
    <div className="mt-4 flex items-center justify-between gap-3">
      <div>
        <p className="text-[9px] font-bold" style={{ color: label }}>الطالب</p>
        <p className="text-lg font-bold leading-tight" style={{ color: foreground }}>اسم الطالب</p>
      </div>
      <Portrait className="h-16 w-16 flex-shrink-0 rounded-lg" />
    </div>
    <div className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2">
      {SAMPLE.map(([name, value]) => (
        <div key={name}>
          <p className="text-[9px] font-bold" style={{ color: label }}>{name}</p>
          <p className="text-xs font-bold" style={{ color: foreground }}>{value}</p>
        </div>
      ))}
    </div>
    <div className="mt-4 flex justify-center"><div className="rounded-xl bg-white p-2"><SampleQr className="h-20 w-20" /></div></div>
  </div>
);

/** Google decides the text colour itself: white on dark backgrounds, dark on light ones. */
const readableOn = (hex: string) => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return (r * 299 + g * 587 + b * 114) / 1000 > 150 ? '#1F2937' : '#FFFFFF';
};

const GooglePreview: React.FC<PreviewProps> = ({ title, background, logo, banner }) => {
  const text = readableOn(background);
  return (
    <div dir="rtl" className="mx-auto w-full max-w-[320px] overflow-hidden rounded-3xl shadow-xl" style={{ background, color: text }}>
      <div className="flex items-center gap-2 px-4 pt-4">
        <div className="flex h-7 w-7 flex-shrink-0 items-center justify-center overflow-hidden rounded-full bg-white">
          {logo ? <img src={logo} alt="" className="h-full w-full object-contain" /> : <span className="text-xs font-bold text-slate-500">{title.slice(0, 1)}</span>}
        </div>
        <p className="truncate text-xs font-bold">{title}</p>
      </div>
      <div className="px-4 pt-3">
        <p className="text-[10px] opacity-80">بطاقة نقل طلاب</p>
        <p className="text-xl font-bold leading-tight">اسم الطالب</p>
      </div>
      <div className="grid grid-cols-2 gap-x-4 gap-y-2 px-4 py-3">
        {SAMPLE.map(([name, value]) => (
          <div key={name}><p className="text-[9px] opacity-80">{name}</p><p className="text-xs font-bold">{value}</p></div>
        ))}
      </div>
      <div className="flex justify-center pb-4"><div className="rounded-xl bg-white p-2"><SampleQr className="h-20 w-20" /></div></div>
      {banner && <img src={banner} alt="" className="h-[92px] w-full object-cover" />}
    </div>
  );
};

/** Each transport company's own Wallet card: identity, design, and rollout to its students' cards. */
export const WalletCardDesignPage: React.FC = () => {
  const companyId = useCompany().id;
  const [draft, setDraft] = useState<Draft | null>(null);
  const [logoChange, setLogoChange] = useState<ArtworkChange>(undefined);
  const [bannerChange, setBannerChange] = useState<ArtworkChange>(undefined);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [rollout, setRollout] = useState<Rollout | null>(null);

  // Cached like every other page of the workspace: a revisit shows the saved design
  // at once and checks for changes behind it (the live topic refreshes this key too).
  const client = useQueryClient();
  const queryKey = keys.company(companyId, 'walletCard');
  const fetchSettings = () => unwrap<Settings>(supabase.rpc('get_wallet_card_settings', { p_company_id: companyId }));
  const page = usePageData(queryKey, fetchSettings);
  const settings = page.data ?? null;
  /** What the form started from: a background refresh never overwrites what the admin is editing. */
  const [base, setBase] = useState<Draft | null>(null);
  useEffect(() => {
    if (!settings) return;
    if (draft && base && JSON.stringify(draft) !== JSON.stringify(base)) return;
    const fresh = toDraft(settings);
    setDraft(fresh);
    setBase(fresh);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings]);

  /** Reads the saved settings again, now (after a save or a rollout). */
  const load = async (resetDraft: boolean) => {
    try {
      const loaded = await client.fetchQuery({ queryKey, queryFn: fetchSettings, staleTime: 0 });
      if (resetDraft) { setDraft(toDraft(loaded)); setBase(toDraft(loaded)); setLogoChange(undefined); setBannerChange(undefined); }
      return loaded;
    } catch (err: any) {
      setError(`تعذر التحميل: ${err.message}`);
      return null;
    }
  };

  const logoFileUrl = useMemo(() => (logoChange ? URL.createObjectURL(logoChange) : null), [logoChange]);
  const bannerFileUrl = useMemo(() => (bannerChange ? URL.createObjectURL(bannerChange) : null), [bannerChange]);
  useEffect(() => () => { if (logoFileUrl) URL.revokeObjectURL(logoFileUrl); }, [logoFileUrl]);
  useEffect(() => () => { if (bannerFileUrl) URL.revokeObjectURL(bannerFileUrl); }, [bannerFileUrl]);

  const savedLogo = settings?.logo_path ? walletArtworkUrl(settings.logo_path, 'master.png') : null;
  const savedBanner = settings?.banner_path ? walletArtworkUrl(settings.banner_path, 'google.png') : null;
  const logoPreview = logoFileUrl ?? (logoChange === null ? null : savedLogo);
  const bannerPreview = bannerFileUrl ?? (bannerChange === null ? null : savedBanner);

  const pick = (setChange: (change: ArtworkChange) => void) => (file: File) => {
    const problem = validateImage(file);
    if (problem) { setError(problem); return; }
    setError('');
    setChange(file);
  };

  /** Delivers the saved card to this company's installed cards, one batch per call. */
  const publish = async (total: number) => {
    let updated = 0;
    let failed = 0;
    let lastError = '';
    setRollout({ running: true, updated, total, message: '', failed: false });
    try {
      for (;;) {
        const result = await invokeEdgeFunction<SyncResult>('wallet-sync', { companyId });
        updated += result.updated;
        failed += result.failed;
        lastError = result.errors[0] ?? lastError;
        setRollout({ running: !result.done, updated, total, message: '', failed: false });
        if (result.done) break;
      }
      const left = (await load(false))?.pending_cards ?? 0;
      setRollout({
        running: false, updated, total, failed: failed > 0 || left > 0,
        message: failed > 0 || left > 0
          ? `تم تحديث ${updated} بطاقة وبقيت ${left} بطاقة لم تُحدَّث. ${lastError}`
          : total > 0 ? 'تم تحديث البطاقات المثبّتة بالتصميم الجديد.' : 'لا توجد بطاقات مثبّتة لهذه الشركة بعد؛ البطاقات الجديدة ستستخدم هذا التصميم.',
      });
    } catch (err: any) {
      setRollout({ running: false, updated, total, failed: true, message: `توقف نشر التصميم: ${err.message}` });
      await load(false);
    }
  };

  const guard = useGuard();
  // Saving uploads the artwork and then updates the installed cards: one run at a time.
  const save = () => guard('save', async () => {
    if (!settings || !draft) return;
    try {
      setSaving(true);
      setError('');
      setRollout(null);
      const logoPath = logoChange ? await uploadWalletArtwork(companyId, 'logo', logoChange) : logoChange === null ? null : settings.logo_path;
      const bannerPath = bannerChange ? await uploadWalletArtwork(companyId, 'banner', bannerChange) : bannerChange === null ? null : settings.banner_path;
      const { error: saveError } = await supabase.rpc('set_wallet_card_settings', {
        p_company_id: companyId,
        p_background_color: draft.background, p_foreground_color: draft.foreground, p_label_color: draft.label,
        p_card_title: draft.title, p_banner_path: bannerPath,
        p_logo_path: logoPath, p_contact_phone: draft.phone, p_contact_label: draft.phoneLabel,
      });
      if (saveError) throw saveError;
      const saved = await load(true);
      if (saved) await publish(saved.pending_cards);
    } catch (err: any) {
      setError(`تعذر حفظ التصميم: ${err.message}`);
    } finally {
      setSaving(false);
    }
  });

  const phoneValid = !draft || draft.phone.trim() === '' || PHONE.test(draft.phone.trim());
  const valid = !!draft && HEX.test(draft.background) && HEX.test(draft.foreground) && HEX.test(draft.label)
    && draft.title.trim().length <= 40 && draft.phoneLabel.trim().length <= 30 && phoneValid;
  const dirty = !!settings && !!draft && (JSON.stringify(draft) !== JSON.stringify(base)
    || logoChange !== undefined || bannerChange !== undefined);
  const busy = saving || !!rollout?.running;
  const update = (patch: Partial<Draft>) => setDraft((current) => (current ? { ...current, ...patch } : current));
  const color = (value: string, fallback: string) => (HEX.test(value) ? value : fallback);
  const preview: PreviewProps | null = draft && settings ? {
    title: draft.title.trim() || settings.company_name,
    background: color(draft.background, '#00658D'), foreground: color(draft.foreground, '#FFFFFF'), label: color(draft.label, '#D6EEF9'),
    logo: logoPreview, banner: bannerPreview,
  } : null;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">بطاقة المحفظة</h1>
          <p className="max-w-3xl text-sm text-slate-500">
            بطاقة الطالب في Apple Wallet و Google Wallet تحمل هوية شركة النقل وتصميمها. غيّر التصميم مع كل فصل دراسي ليسهل تمييز البطاقة الحالية.
            لون البطاقة للتمييز فقط: صلاحية الاشتراك يتحقق منها النظام عند مسح الرمز.
          </p>
        </div>
      </div>
      {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">{error}</div>}
      {!error && page.error && !settings && (
        <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
          تعذر التحميل: {page.error}
          <button className="mr-3 font-bold underline" onClick={() => void page.reload()}>إعادة المحاولة</button>
        </div>
      )}
      {/* First visit only: the shape of the form while the saved design arrives. Later visits open from the cache. */}
      {page.loading && (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px]">
          <div className="space-y-6"><SkeletonForm fields={2} /><SkeletonForm fields={3} /></div>
          <Skeleton className="mx-auto h-[420px] w-full max-w-[320px] rounded-3xl" />
        </div>
      )}
      {rollout && (
        <div role="status" className={`rounded-xl border p-4 text-sm ${rollout.failed
          ? 'border-amber-200 bg-amber-50 text-amber-800' : 'border-emerald-200 bg-emerald-50 text-emerald-800'}`}>
          {rollout.running ? `جاري تحديث البطاقات المثبّتة... ${rollout.updated} من ${rollout.total}` : rollout.message}
        </div>
      )}

      {settings && draft && preview && (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px]">
          <div className="space-y-6">
            <div className={`${cardClass} space-y-5`}>
              <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
                <Building2 className="h-5 w-5 text-blue-600" /> هوية الشركة: {settings.company_name}
              </h2>
              <ArtworkField label="شعار الشركة" hint="هو نفسه شعار «هوية الشركة» في إعدادات الشركة: تغييره هنا يغيّره هناك. يظهر أعلى البطاقة بجوار اسم الشركة. يفضّل PNG بخلفية شفافة. بدون شعار يظهر الاسم فقط."
                preview={logoPreview} onPick={pick(setLogoChange)} onRemove={() => setLogoChange(null)} />
              <div className="grid gap-4 sm:grid-cols-2">
                <label className="block text-sm font-bold text-slate-700">
                  رقم التواصل
                  <input dir="ltr" value={draft.phone} maxLength={25} placeholder="0100 000 0000" onChange={(e) => update({ phone: e.target.value })}
                    className={`${inputClass} mt-1 ${phoneValid ? '' : 'border-rose-300 focus:border-rose-500'}`} />
                  <span className={`mt-1 block text-xs font-normal ${phoneValid ? 'text-slate-500' : 'text-rose-600'}`}>
                    {phoneValid ? 'يظهر في تفاصيل البطاقة لا على وجهها. اتركه فارغاً لإخفائه.' : 'اكتب رقماً صحيحاً.'}
                  </span>
                </label>
                <label className="block text-sm font-bold text-slate-700">
                  وصف الرقم
                  <input value={draft.phoneLabel} maxLength={30} placeholder="مكتب النقل" onChange={(e) => update({ phoneLabel: e.target.value })} className={`${inputClass} mt-1`} />
                  <span className="mt-1 block text-xs font-normal text-slate-500">مثل: مكتب النقل، خدمة العملاء، المنسّق.</span>
                </label>
              </div>
            </div>

            <div className={`${cardClass} space-y-5`}>
              <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
                <CreditCard className="h-5 w-5 text-blue-600" /> تصميم الفصل الحالي
              </h2>
              <div className="grid gap-4 sm:grid-cols-3">
                <ColorField label="لون الخلفية" value={draft.background} onChange={(background) => update({ background })} />
                <ColorField label="لون النص" only="Apple Wallet فقط" value={draft.foreground} onChange={(foreground) => update({ foreground })} />
                <ColorField label="لون العناوين الصغيرة" only="Apple Wallet فقط" value={draft.label} onChange={(label) => update({ label })} />
              </div>
              <label className="block text-sm font-bold text-slate-700">
                عنوان بديل للبطاقة (اختياري)
                <input value={draft.title} maxLength={40} placeholder={settings.company_name} onChange={(e) => update({ title: e.target.value })} className={`${inputClass} mt-1`} />
                <span className="mt-1 block text-xs font-normal text-slate-500">يظهر مكان اسم الشركة. اتركه فارغاً لاستخدام اسم الشركة.</span>
              </label>
              <ArtworkField label={<>صورة عرضية (اختياري) {badge('Google Wallet فقط')}</>} hint="شريط عريض أسفل البطاقة، بنسبة 3 إلى 1 تقريباً."
                preview={bannerPreview} onPick={pick(setBannerChange)} onRemove={() => setBannerChange(null)} />
              <div className="flex flex-wrap items-center gap-3 border-t border-slate-100 pt-4">
                <button type="button" onClick={save} disabled={!valid || !dirty || busy}
                  className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-50">
                  <Save className="h-4 w-4" /> {saving ? 'جاري الحفظ...' : 'حفظ ونشر على بطاقات الشركة'}
                </button>
                {dirty && !busy && (
                  <button type="button" onClick={() => { void load(true); }}
                    className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-600">
                    تراجع عن التغييرات
                  </button>
                )}
              </div>
            </div>

            <div className={cardClass}>
              <h2 className="text-base font-bold text-slate-700">حالة التصميم</h2>
              <dl className="mt-3 grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
                <div><dt className="text-xs text-slate-500">آخر تحديث للتصميم</dt>
                  <dd className="font-bold text-slate-700">{settings.updated_at
                    ? new Date(settings.updated_at).toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short' }) : 'التصميم الافتراضي'}</dd></div>
                <div><dt className="text-xs text-slate-500">بواسطة</dt>
                  <dd className="font-bold text-slate-700">{settings.updated_by_name ?? '—'}</dd></div>
                <div><dt className="text-xs text-slate-500">بطاقات Apple Wallet</dt>
                  <dd className="font-bold text-slate-700">{settings.apple_cards.toLocaleString('ar-EG')}</dd></div>
                <div><dt className="text-xs text-slate-500">بطاقات Google Wallet</dt>
                  <dd className="font-bold text-slate-700">{settings.google_cards.toLocaleString('ar-EG')}</dd></div>
              </dl>
              {settings.pending_cards > 0 && !busy && (
                <div className="mt-4 flex flex-wrap items-center gap-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                  <span>{settings.pending_cards.toLocaleString('ar-EG')} بطاقة مثبّتة لم تصلها آخر التغييرات بعد.</span>
                  <button type="button" onClick={() => { void publish(settings.pending_cards); }}
                    className="flex items-center gap-1.5 rounded-xl bg-amber-600 px-4 py-1.5 text-sm font-bold text-white">
                    <RefreshCw className="h-4 w-4" /> استكمال النشر
                  </button>
                </div>
              )}
            </div>
          </div>

          <div className={`${cardClass} h-fit space-y-5 xl:sticky xl:top-6`}>
            <h2 className="text-base font-bold text-slate-700">معاينة تقريبية</h2>
            <div>
              <p className="mb-2 text-xs font-bold text-slate-500">Apple Wallet</p>
              <ApplePreview {...preview} />
            </div>
            <div>
              <p className="mb-2 text-xs font-bold text-slate-500">Google Wallet</p>
              <GooglePreview {...preview} />
            </div>
            <p className="text-xs leading-relaxed text-slate-500">
              الخط ومحطة الركوب يظهران فقط للطالب صاحب اشتراك معتمد، وأي بيان غير متوفر يختفي من البطاقة.
              في Google Wallet تظهر صورة الطالب ورقم التواصل في تفاصيل البطاقة، ويختار النظام لون النص تلقائياً.
            </p>
          </div>
        </div>
      )}
    </div>
  );
};
