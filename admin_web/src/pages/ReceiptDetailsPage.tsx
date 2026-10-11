import React, { Suspense, lazy, useEffect, useMemo, useState } from 'react';

/** The logo and emblem editor, downloaded when it is opened. */
const CompanyIdentityCard = lazy(() => import('../components/CompanyIdentityCard').then((m) => ({ default: m.CompanyIdentityCard })));
import { useQueryClient } from '@tanstack/react-query';
import {
  Button, Card, ErrorState, Sheet, Icon, Ltr, Money, Note, Page, PageHeader, PhoneBar, SkeletonForm, SkeletonText, TextField, dayText, useOnline,
} from '../ui';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import { useCompanyOverview } from '../lib/overview';
import { STALE, unwrap, usePageData } from '../lib/query';
import { settingsKey } from '../lib/reference';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';
import { cairoToday } from '../lib/time';
import { CompanyMark } from '../components/CompanyMark';
import { errorText } from '../ui/format';

/** What is printed about the company at the top of every receipt (companies: contact_phone, address, commercial_register, tax_number). */
interface ReceiptInfo { phone: string | null; address: string | null; commercial_register: string | null; tax_number: string | null }
interface SettingsAnswer { receipt_info?: ReceiptInfo | null; [key: string]: unknown }
type Draft = { phone: string; address: string; commercial_register: string; tax_number: string };

const LIMITS = { phone: 30, address: 200, commercial_register: 40, tax_number: 40 } as const;
const toDraft = (info: ReceiptInfo | null | undefined): Draft => ({
  phone: info?.phone ?? '', address: info?.address ?? '', commercial_register: info?.commercial_register ?? '', tax_number: info?.tax_number ?? '',
});
/** The company row's announcement would otherwise read again what this page already shows; the wallet card reads the same phone, so it is read again. */
const SHOWN_HERE = ['company', 'overview', 'settings', 'switches', 'vote'];

/**
 * «بيانات الإيصال»: the company's phone and address on the subscription receipt the
 * student downloads after the payment is accepted, with a live picture of the receipt's top.
 * The name is the platform's to change; the logo is the student card's.
 */
export const ReceiptDetailsPage: React.FC = () => {
  const company = useCompany();
  const client = useQueryClient();
  const guard = useGuard();
  const online = useOnline();
  const key = settingsKey(company.id);
  const page = usePageData(key, () => unwrap<SettingsAnswer>(supabase.rpc('get_subscription_settings', { p_company_id: company.id })), { staleTime: STALE.reference });
  const brand = useCompanyOverview(company.id).data?.company ?? null;
  const saved = useMemo(() => toDraft(page.data?.receipt_info), [page.data]);
  const [draft, setDraft] = useState<Draft>(saved);
  const [touched, setTouched] = useState(false);
  const [saving, setSaving] = useState(false);
  const [identityOpen, setIdentityOpen] = useState(false);
  // What is saved shows until the admin starts typing; a background refresh never overwrites typing.
  useEffect(() => { if (!touched) setDraft(saved); }, [saved, touched]);

  const set = (field: keyof Draft) => (e: React.ChangeEvent<HTMLInputElement>) => { setTouched(true); setDraft((d) => ({ ...d, [field]: e.target.value })); };
  const dirty = (Object.keys(draft) as (keyof Draft)[]).some((k) => draft[k].trim() !== saved[k].trim());
  const phoneError = draft.phone && !/^[0-9+\s()-]*$/.test(draft.phone) ? 'اكتب رقم الهاتف بالأرقام فقط.' : undefined;
  // The register and tax numbers are printed only when written; they are shown here when the company has them.
  const hasLegal = !!(saved.commercial_register || saved.tax_number);

  const save = () => guard('receipt-info', async () => {
    if (!dirty || phoneError) return;
    setSaving(true);
    try {
      const { data, error } = await supabase.rpc('set_company_receipt_info', {
        p_company_id: company.id, p_phone: draft.phone.trim(), p_address: draft.address.trim(),
        p_commercial_register: draft.commercial_register.trim(), p_tax_number: draft.tax_number.trim(),
      });
      if (error) throw new Error(error.message);
      rememberApplied([company.id], SHOWN_HERE);
      if (data) client.setQueryData<SettingsAnswer>(key, (current) => (current ? { ...current, receipt_info: data as ReceiptInfo } : current));
      else void page.reload();
      setTouched(false);
      notifyDone('حُفظت بيانات الإيصال', 'تظهر على الإيصالات التي تصدر من الآن. الإيصالات السابقة لا تتغيّر.');
    } catch (error) {
      notifyError('لم تُحفظ بيانات الإيصال', errorText(error));
    } finally { setSaving(false); }
  });
  const revert = () => { setDraft(saved); setTouched(false); };

  const header = <PageHeader title="بيانات الإيصال" sub="ما يُطبع عن شركتك أعلى إيصال الاشتراك الذي يحمّله الطالب بعد قبول الدفع." />;
  if (page.loading) {
    return (
      <Page>{header}
        <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_452px]">
          <SkeletonForm rows={3} />
          <Card className="hidden p-6 lg:block"><SkeletonText rows={5} /></Card>
        </div>
      </Page>
    );
  }
  if (page.error && !page.data) {
    return <Page>{header}<ErrorState card title="تعذّر تحميل بيانات الإيصال" text="لم نستطع جلب البيانات المحفوظة. تأكد من اتصالك ثم حاول مرة أخرى." onRetry={() => void page.reload()} /></Page>;
  }

  const hasLogo = !!brand?.logo_path;
  const canSave = dirty && !phoneError && online;
  return (
    <Page className="flex-1">
      {header}
      <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_452px]">
        <Card as="section" className="flex flex-col">
          <div className="flex flex-col gap-5 p-4 lg:p-6">
            <div>
              <h2 className="m-0 text-card">بيانات الشركة على الإيصال</h2>
              <p className="m-0 text-label text-ink-2">كلها اختيارية. ما تتركه فارغاً لا يُطبع.</p>
            </div>
            <TextField label="اسم الشركة" value={company.name} disabled readOnly help="يغيّره مدير المنصة. تواصل معه إن تغيّر اسم شركتك." />
            <div className="flex items-center gap-3 rounded-inner bg-ground px-4 py-3">
              {hasLogo
                ? <CompanyMark name={company.name} brand={brand} size="md" className="!h-10 !w-10 flex-none" />
                : <span aria-hidden="true" className="flex h-10 w-10 flex-none items-center justify-center rounded-control bg-sunken text-ink-2"><Icon name="image" size={20} /></span>}
              <div className="min-w-0 flex-1">
                <div className="text-small font-semibold">الشعار</div>
                <div className="text-label text-ink-2">{hasLogo ? 'يُطبع أعلى الإيصال، ويظهر للطلاب في التطبيق.' : 'لا شعار بعد. بلا شعار يُطبع اسم الشركة وحده.'}</div>
              </div>
              <Button kind="link" sm iconEnd="fwd" onClick={() => setIdentityOpen(true)}>{hasLogo ? 'تغيير الشعار' : 'أضف الشعار'}</Button>
            </div>
            <TextField label="هاتف الشركة" optional ltr inputMode="tel" autoComplete="tel" maxLength={LIMITS.phone} value={draft.phone} onChange={set('phone')} error={phoneError} />
            <div className="relative">
              <span className="absolute end-0 top-0 text-cap leading-5 text-ink-2 tabular" aria-hidden="true"><span dir="ltr">{draft.address.length} / {LIMITS.address}</span></span>
              <TextField label="العنوان" optional maxLength={LIMITS.address} value={draft.address} onChange={set('address')} placeholder="مثال: 12 شارع الجلاء، دمياط" />
            </div>
            {hasLegal && (
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <TextField label="رقم السجل التجاري" optional ltr maxLength={LIMITS.commercial_register} value={draft.commercial_register} onChange={set('commercial_register')} />
                <TextField label="رقم التسجيل الضريبي" optional ltr maxLength={LIMITS.tax_number} value={draft.tax_number} onChange={set('tax_number')} />
              </div>
            )}
            <Note tone="teal">تظهر على الإيصالات التي تصدر من الآن. الإيصالات السابقة لا تتغيّر.</Note>
          </div>
          <div className="hidden justify-end gap-2 border-t border-hair px-4 py-4 sm:flex lg:mx-6 lg:px-0 lg:pb-6 lg:pt-4">
            <Button kind="secondary" disabled={!dirty || saving} onClick={revert}>تراجع عن التغييرات</Button>
            <Button loading={saving} disabled={!canSave} onClick={() => void save()}>حفظ بيانات الإيصال</Button>
          </div>
        </Card>

        <Card as="section" className="flex flex-col gap-4 p-4 lg:p-6">
          <div>
            <h2 className="m-0 text-card">هكذا يراها الطالب</h2>
            <p className="m-0 text-label text-ink-2">أعلى الإيصال. باقي الإيصال يملؤه النظام.</p>
          </div>
          <ReceiptPreview name={company.name} brand={hasLogo ? brand : null} phone={draft.phone.trim()} address={draft.address.trim()}
            register={draft.commercial_register.trim()} tax={draft.tax_number.trim()} />
        </Card>
      </div>
      <PhoneBar><Button full loading={saving} disabled={!canSave} onClick={() => void save()}>حفظ بيانات الإيصال</Button></PhoneBar>
      {/* The company's logo and emblem (receipts, the app, the dashboard) — saved on their own, as before. */}
      <Sheet open={identityOpen} onClose={() => setIdentityOpen(false)} title="شعار الشركة" w={720}>
        <Suspense fallback={<SkeletonForm />}><CompanyIdentityCard companyId={company.id} companyName={company.name} /></Suspense>
      </Sheet>
    </Page>
  );
};

/** The top of the receipt as the student's PDF prints it, with an example below it. */
const ReceiptPreview: React.FC<{ name: string; brand: React.ComponentProps<typeof CompanyMark>['brand'] | null; phone: string; address: string; register: string; tax: string }> = ({ name, brand, phone, address, register, tax }) => (
  <div className="rounded-inner bg-[#D5E0E7] p-4 sm:p-6">
    <div className="flex flex-col gap-3 rounded-[6px] bg-surface p-5 shadow-[0_8px_24px_-8px_rgba(23,56,74,.25)]" aria-label="معاينة أعلى الإيصال">
      <div className="flex items-start gap-3">
        {brand && <CompanyMark name={name} brand={brand} size="md" className="!h-10 !w-10 flex-none" />}
        <div className="flex min-w-0 flex-1 flex-col">
          <span className="text-card">{name}</span>
          {phone && <Ltr className="self-start text-label text-ink-2">{phone}</Ltr>}
          {address && <span className="text-label text-ink-2">{address}</span>}
          {register && <span className="text-cap text-ink-2">سجل تجاري <Ltr>{register}</Ltr></span>}
          {tax && <span className="text-cap text-ink-2">رقم ضريبي <Ltr>{tax}</Ltr></span>}
        </div>
        <div className="flex flex-none flex-col items-start text-label">
          <span className="text-ink-2">إيصال رقم</span>
          <span className="font-semibold tabular">1642</span>
        </div>
      </div>
      <hr className="m-0 border-0 border-t border-dashed border-disabled" />
      <dl className="m-0 grid grid-cols-[auto_minmax(0,1fr)] gap-x-6 gap-y-1.5 text-label">
        <dt className="text-ink-2">الطالب</dt><dd className="m-0">منة الله إبراهيم عبد الرازق</dd>
        <dt className="text-ink-2">الاشتراك</dt><dd className="m-0">الفصل الأول · خط دمياط الجديدة</dd>
        <dt className="text-ink-2">تاريخ الدفع</dt><dd className="m-0">{dayText(cairoToday())}</dd>
      </dl>
      <div className="flex items-baseline justify-between border-t border-hair pt-3">
        <span className="text-small font-semibold">المبلغ</span>
        <span className="text-small font-semibold"><Money value={4500} /></span>
      </div>
    </div>
  </div>
);
