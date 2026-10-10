import React, { useEffect, useMemo, useState } from 'react';
import { ImagePlus, RotateCcw, Save, Trash2 } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { applySavedBranding, useCompanyOverview } from '../lib/overview';
import {
  BRAND_SOURCE_TYPES, checkBrandDimensions, checkBrandFile, isSquarish, logoUrl, brandFileUrl, nextPath,
  type BrandChange, type BrandKind, type SavedBranding,
} from '../lib/branding';
import { imageSize, removeArtworkFolders, uploadWalletArtwork } from '../lib/walletArtwork';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';
import { CompanyMark } from './CompanyMark';
import { SkeletonForm } from './Skeleton';

/** The lists a change to the company's row makes out of date that this card has already brought up to date (lib/sync.ts). */
const SHOWN_ALREADY = ['company', 'overview', 'settings', 'switches', 'vote'];
const ACCEPT = BRAND_SOURCE_TYPES.join(',');
/** PostgREST: the function is not in the database yet. */
const MISSING_FUNCTION = 'PGRST202';

const TEXT: Record<BrandKind, { title: string; where: string; advice: string; drop: string }> = {
  logo: {
    title: 'الشعار',
    where: 'الشكل الكامل لعلامة الشركة. يظهر على إيصال الاشتراك، وبطاقة المحفظة، وعند اختيار الشركة في التطبيق.',
    advice: 'يُفضّل PNG بخلفية شفافة، بعرض 1024 بكسل أو أكثر. يُقبل أيضاً JPG و WebP حتى 5 ميجابايت. يُحفظ بنسبته كما هو ويُصغَّر إلى 1024 بكسل.',
    drop: 'اسحب صورة الشعار إلى هنا',
  },
  emblem: {
    title: 'الرمز',
    where: 'علامة مربعة صغيرة: بجوار اسم الشركة في القوائم، وفي الإشعارات، وأعلى لوحة التحكم.',
    advice: 'يُفضّل PNG مربع 512×512 بكسل أو أكثر، والرمز في المنتصف بهامش بسيط. يُحفظ داخل مربع 512 بكسل دون قص أي جزء منه.',
    drop: 'اسحب صورة الرمز إلى هنا',
  },
};

const button = 'inline-flex items-center gap-1.5 rounded-xl px-3 py-2 text-sm font-bold disabled:opacity-50';

interface MarkFieldProps {
  kind: BrandKind;
  companyName: string;
  /** The saved picture's address, if there is one. */
  savedUrl: string | null;
  /** What shows when there is no picture of this kind: the fallback every screen uses. */
  fallback: React.ReactNode;
  change: BrandChange<File>;
  onChange: (change: BrandChange<File>) => void;
  disabled: boolean;
}

/** One mark: where it is used, what to upload, and how it looks on a light and on a dark background. */
const MarkField: React.FC<MarkFieldProps> = ({ kind, companyName, savedUrl, fallback, change, onChange, disabled }) => {
  const text = TEXT[kind];
  const [problem, setProblem] = useState('');
  const [note, setNote] = useState('');
  const [over, setOver] = useState(false);
  const [checking, setChecking] = useState(false);
  const fileUrl = useMemo(() => (change ? URL.createObjectURL(change) : null), [change]);
  useEffect(() => () => { if (fileUrl) URL.revokeObjectURL(fileUrl); }, [fileUrl]);
  // The choice was undone or saved from outside: its notes go with it.
  useEffect(() => { if (!change) setNote(''); }, [change]);

  const shown = fileUrl ?? (change === null ? null : savedUrl);
  const pick = async (file: File | undefined) => {
    if (!file || disabled) return;
    setNote('');
    const refused = checkBrandFile(file);
    if (refused) { setProblem(refused); return; }
    setChecking(true);
    try {
      const { width, height } = await imageSize(file);
      const unfit = checkBrandDimensions(kind, width, height);
      if (unfit) { setProblem(unfit); return; }
      setProblem('');
      if (kind === 'emblem' && !isSquarish(width, height)) setNote('الصورة ليست مربعة: ستوضع كاملة في منتصف مربع بهوامش شفافة. للحصول على أفضل شكل ارفع نسخة مربعة.');
      onChange(file);
    } catch (error) {
      setProblem(error instanceof Error ? error.message : 'تعذر قراءة الصورة.');
    } finally {
      setChecking(false);
    }
  };

  const tile = (dark: boolean) => (
    <div className={`flex h-24 flex-1 items-center justify-center rounded-xl border p-3 ${dark ? 'border-slate-800 bg-slate-900' : 'border-slate-200 bg-white'}`}>
      {shown
        ? <img src={shown} alt={dark ? `${text.title} على خلفية داكنة` : `${text.title} على خلفية فاتحة`} draggable={false}
            className={kind === 'emblem' ? 'h-16 w-16 rounded-2xl object-contain' : 'max-h-full max-w-full object-contain'} />
        : fallback}
    </div>
  );

  return (
    <section aria-label={text.title} className="space-y-3">
      <div>
        <h3 className="text-sm font-bold text-slate-700">
          {text.title}
          {change instanceof File && <span className="mr-2 rounded-full bg-amber-100 px-2 py-0.5 text-[10.5px] font-bold text-amber-800">لم يُحفظ بعد</span>}
          {change === null && <span className="mr-2 rounded-full bg-rose-50 px-2 py-0.5 text-[10.5px] font-bold text-rose-700">سيُزال عند الحفظ</span>}
        </h3>
        <p className="mt-0.5 text-xs leading-5 text-slate-500">{text.where}</p>
      </div>

      <div
        onDragOver={(event) => { if (disabled) return; event.preventDefault(); setOver(true); }}
        onDragLeave={() => setOver(false)}
        onDrop={(event) => { event.preventDefault(); setOver(false); void pick(event.dataTransfer.files?.[0]); }}
        className={`rounded-2xl border-2 border-dashed p-3 transition ${over ? 'border-[#3E8FBF] bg-[#EAF7FD]' : 'border-slate-200 bg-slate-50/60'}`}
      >
        <div className="flex gap-3">{tile(false)}{tile(true)}</div>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <label className={`${button} cursor-pointer border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 ${disabled ? 'pointer-events-none opacity-50' : ''}`}>
            <ImagePlus className="h-4 w-4" /> {shown ? 'تغيير الصورة' : 'اختيار صورة'}
            <input type="file" accept={ACCEPT} className="sr-only" disabled={disabled} aria-label={`اختيار صورة ${text.title} لشركة ${companyName}`}
              onChange={(event) => { const file = event.target.files?.[0]; event.target.value = ''; void pick(file); }} />
          </label>
          {change !== undefined ? (
            <button type="button" disabled={disabled} onClick={() => { setProblem(''); onChange(undefined); }} className={`${button} text-slate-600 hover:bg-slate-100`}>
              <RotateCcw className="h-4 w-4" /> {change === null ? 'إبقاء الحالي' : 'تراجع عن الاختيار'}
            </button>
          ) : savedUrl && (
            <button type="button" disabled={disabled} onClick={() => { setProblem(''); onChange(null); }} className={`${button} text-rose-600 hover:bg-rose-50`}>
              <Trash2 className="h-4 w-4" /> إزالة
            </button>
          )}
          <span className="text-xs text-slate-400">{checking ? 'جاري قراءة الصورة…' : text.drop}</span>
        </div>
      </div>

      {problem && <p role="alert" className="rounded-xl bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700">{problem}</p>}
      {!problem && note && <p role="status" className="rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-800">{note}</p>}
      <p className="text-[11.5px] leading-5 text-slate-400">{text.advice}</p>
    </section>
  );
};

/**
 * The company's identity: its logo and its emblem. Each is uploaded, replaced
 * or removed here and then shown wherever the company is named: this
 * dashboard, the students' app, receipts and the Wallet card.
 */
export const CompanyIdentityCard: React.FC<{ companyId: string; companyName: string }> = ({ companyId, companyName }) => {
  // The overview the workspace frame already keeps: the card asks for nothing of its own.
  const overview = useCompanyOverview(companyId);
  const company = overview.data?.company ?? null;
  const [logo, setLogo] = useState<BrandChange<File>>(undefined);
  const [emblem, setEmblem] = useState<BrandChange<File>>(undefined);
  const [stage, setStage] = useState<'upload' | 'save' | null>(null);
  const guard = useGuard();

  if (!company) {
    return overview.error
      ? <div role="alert" className="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل هوية الشركة: {overview.error}</div>
      : <SkeletonForm fields={2} />;
  }
  // An older database answers without the two fields: saving from here would wipe a logo this page cannot see.
  const known = 'emblem_path' in company && 'logo_path' in company;
  const busy = stage !== null;
  const dirty = logo !== undefined || emblem !== undefined;

  // Uploads what was chosen, saves both paths in one call and shows the server's answer: one run at a time.
  const save = () => guard('save', async () => {
    if (!known || !dirty) return;
    const uploaded: string[] = [];
    try {
      setStage('upload');
      const newLogo = logo instanceof File ? await uploadWalletArtwork(companyId, 'logo', logo) : logo;
      if (typeof newLogo === 'string') uploaded.push(newLogo);
      const newEmblem = emblem instanceof File ? await uploadWalletArtwork(companyId, 'emblem', emblem) : emblem;
      if (typeof newEmblem === 'string') uploaded.push(newEmblem);
      setStage('save');
      const { data, error } = await supabase.rpc('set_company_branding', {
        p_company_id: companyId, p_logo_path: nextPath(company.logo_path, newLogo), p_emblem_path: nextPath(company.emblem_path, newEmblem),
      });
      if (error) {
        throw new Error(error.code === MISSING_FUNCTION ? 'قاعدة البيانات لم تُحدَّث بعد لهذه الخاصية. حاول لاحقاً.' : error.message);
      }
      const saved = data as SavedBranding;
      const logoChanged = saved.logo_path !== (company.logo_path ?? null);
      // The company row's announcement would otherwise read again what is put on screen right here.
      rememberApplied([companyId], SHOWN_ALREADY);
      applySavedBranding(saved);
      setLogo(undefined);
      setEmblem(undefined);
      notifyDone('تم حفظ هوية الشركة', logoChanged
        ? 'الشعار الجديد يظهر على الإيصالات التي تصدر من الآن، وتُحدَّث به بطاقات المحفظة المثبّتة (تُتابَع من صفحة «بطاقة المحفظة»)؛ الإيصالات السابقة تحتفظ بشعارها.'
        : 'تظهر الآن في لوحة التحكم وفي تطبيق الطلاب.');
      // What nothing shows any more is removed; a folder still in use is refused by the database.
      void removeArtworkFolders(saved.stale);
    } catch (error) {
      void removeArtworkFolders(uploaded);
      notifyError('تعذر حفظ هوية الشركة', error instanceof Error ? error.message : undefined);
    } finally {
      setStage(null);
    }
  });

  const logoAfter = logo === null ? null : company.logo_path;
  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm" aria-busy={busy}>
      <div className="flex flex-wrap items-center gap-3">
        <CompanyMark name={companyName} brand={company} size="lg" />
        <div className="min-w-0">
          <h2 className="text-base font-bold text-slate-700">هوية الشركة</h2>
          <p className="mt-0.5 text-xs leading-5 text-slate-500">
            شعار {companyName} ورمزها كما يراهما الطلاب والمشرفون. تُحفظ الصور بصيغة PNG بعد تصغيرها هنا في المتصفح.
          </p>
        </div>
      </div>

      {!known && (
        <p role="status" className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
          رفع الشعار والرمز من هنا يحتاج إلى تحديث قاعدة البيانات أولاً. حتى ذلك الحين يُرفع الشعار من صفحة «بطاقة المحفظة».
        </p>
      )}

      <div className="mt-5 grid gap-6 lg:grid-cols-2">
        <MarkField kind="logo" companyName={companyName} savedUrl={logoUrl(company)} change={logo} onChange={setLogo} disabled={busy || !known}
          fallback={<span className="text-xs text-slate-400">لا يوجد شعار: يظهر اسم الشركة نصاً</span>} />
        <MarkField kind="emblem" companyName={companyName} savedUrl={brandFileUrl(company.emblem_path, 'master.png')} change={emblem} onChange={setEmblem}
          disabled={busy || !known}
          fallback={<CompanyMark name={companyName} brand={{ logo_path: logoAfter }} size="lg" />} />
      </div>
      <p className="mt-3 text-[11.5px] leading-5 text-slate-400">
        بدون رمز يُستخدم الشعار داخل مربع، وبدون شعار يظهر أول حرف مميِّز من اسم الشركة. ملفات SVG غير مقبولة.
      </p>

      <div className="mt-4 flex flex-wrap items-center justify-end gap-2 border-t border-slate-100 pt-4">
        {dirty && !busy && (
          <button type="button" onClick={() => { setLogo(undefined); setEmblem(undefined); }} className={`${button} border border-slate-200 text-slate-600 hover:bg-slate-50`}>
            تراجع عن التغييرات
          </button>
        )}
        <button type="button" disabled={!dirty || busy || !known} onClick={() => void save()}
          className="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-50">
          <Save className="h-4 w-4" /> {stage === 'upload' ? 'جاري رفع الصور…' : stage === 'save' ? 'جاري الحفظ…' : 'حفظ الهوية'}
        </button>
      </div>
    </div>
  );
};
