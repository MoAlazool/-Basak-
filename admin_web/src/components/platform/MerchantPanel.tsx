import React, { useEffect, useState } from 'react';
import { Button, FieldRow, Note, SelectField, SidePanel, StatePill, TextArea, TextField, Toggle, countText } from '../../ui';
import {
  MERCHANT_CATEGORIES, NAME_MAX, emptyMerchant, hasProblems, merchantDraftOf, merchantProblems,
  type Merchant, type MerchantCategory, type MerchantDraft, type PictureChange,
} from '../../lib/offers';
import type { UniversityRow } from '../../lib/reference';
import { PictureField } from './OfferPicture';

const OFFER: [string, string, string, string] = ['عرض واحد', 'عرضان', 'عروض', 'عرضاً'];
export const offersText = (n: number) => (n === 0 ? 'لا عروض' : countText(n, OFFER));
export const MerchantState: React.FC<{ on: boolean }> = ({ on }) => <StatePill state={on ? 'on' : 'off'} label={on ? 'يعمل' : 'موقوف'} />;

/**
 * A merchant, added or changed: who the offers are from and how a student
 * reaches them. `merchant` null with `open` = a new one. Nothing is written
 * until «حفظ»; the picture is uploaded with it.
 */
export const MerchantPanel: React.FC<{
  open: boolean; merchant: Merchant | null; universities: UniversityRow[]; busy: boolean; online: boolean; serverError?: string;
  onClose: () => void; onSave: (draft: MerchantDraft, logo: PictureChange) => void; onDelete: () => void;
}> = ({ open, merchant, universities, busy, online, serverError, onClose, onSave, onDelete }) => {
  const [draft, setDraft] = useState<MerchantDraft>(() => emptyMerchant(crypto.randomUUID()));
  const [logo, setLogo] = useState<PictureChange>(undefined);
  const [tried, setTried] = useState(false);
  // A new record each time the panel opens, or the saved one when it is another merchant.
  useEffect(() => {
    if (!open) return;
    setDraft(merchant ? merchantDraftOf(merchant) : emptyMerchant(crypto.randomUUID()));
    setLogo(undefined); setTried(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, merchant?.id]);
  if (!open) return null;

  const set = (patch: Partial<MerchantDraft>) => setDraft((d) => ({ ...d, ...patch }));
  const problems = merchantProblems(draft);
  const show = <K extends keyof typeof problems>(k: K) => (tried ? problems[k] : undefined);
  const submit = () => { setTried(true); if (!hasProblems(problems)) onSave(draft, logo); };
  // A university hidden since it was chosen stays in the list instead of silently changing.
  const options = universities.filter((u) => u.is_active || u.id === draft.universityId).map((u) => ({ value: u.id, label: u.name }));
  const stopping = !!merchant && merchant.is_active && !draft.isActive;

  return (
    <SidePanel open onClose={onClose} w={560} backLabel="التجّار"
      title={merchant ? merchant.name : 'إضافة تاجر'} meta={merchant ? <MerchantState on={merchant.is_active} /> : undefined}
      sub={merchant ? offersText(merchant.offers) : 'من تأتي منه العروض: مطعم، مكتبة، محل قرب الجامعة'}
      footer={<>{merchant && <Button kind="dangerQuiet" icon="trash" disabled={!online || busy} onClick={onDelete}>احذف التاجر</Button>}<Button kind="secondary" onClick={onClose}>إلغاء</Button><span className="hidden flex-1 sm:block" /><Button icon={merchant ? 'check' : 'plus'} loading={busy} disabled={!online} onClick={submit}>{merchant ? 'حفظ التاجر' : 'أضف التاجر'}</Button></>}>
      <form className="flex flex-col gap-4" onSubmit={(e) => { e.preventDefault(); submit(); }}>
        <FieldRow cols="minmax(0,3fr) minmax(0,2fr)">
          <TextField label="اسم التاجر" value={draft.name} onChange={(e) => set({ name: e.target.value })} maxLength={NAME_MAX} data-autofocus={merchant ? undefined : true}
            error={show('name')} help="كما يعرفه الطلاب. يظهر على كل عرض منه." />
          <SelectField label="النوع" value={draft.category} onChange={(e) => set({ category: e.target.value as MerchantCategory })} options={MERCHANT_CATEGORIES} />
        </FieldRow>
        <PictureField folder="merchants" title="الشعار" where="يظهر بجوار اسم التاجر في التطبيق." savedPath={draft.logoPath} change={logo} onChange={setLogo} disabled={busy} />
        <FieldRow>
          <TextField label="الهاتف" optional ltr inputMode="tel" value={draft.phone} onChange={(e) => set({ phone: e.target.value })} maxLength={20} error={show('phone')} />
          <TextField label="واتساب" optional ltr inputMode="tel" value={draft.whatsapp} onChange={(e) => set({ whatsapp: e.target.value })} maxLength={20} error={show('whatsapp')} />
        </FieldRow>
        <TextField label="رابط" optional ltr inputMode="url" placeholder="https://" value={draft.linkUrl} onChange={(e) => set({ linkUrl: e.target.value })} maxLength={300}
          error={show('linkUrl')} help="صفحة التاجر أو قائمته. يبدأ بـ https://" />
        <TextField label="العنوان" optional value={draft.address} onChange={(e) => set({ address: e.target.value })} maxLength={200} />
        <SelectField label="الجامعة القريبة" optional placeholder="بلا جامعة محددة" value={draft.universityId} onChange={(e) => set({ universityId: e.target.value })} options={options}
          help="للتنظيم فقط. من يرى العرض يحدده جمهور العرض نفسه." />
        <TextArea label="ملاحظات" optional rows={3} value={draft.notes} onChange={(e) => set({ notes: e.target.value })} maxLength={600} help="داخلية: لا تظهر للطلاب." />
        <Toggle label="التاجر يعمل" help="إيقافه يخفي كل عروضه عن الطلاب حتى تفعّله من جديد." checked={draft.isActive} onChange={(on) => set({ isActive: on })} />
        <button type="submit" hidden aria-hidden="true" tabIndex={-1} />
      </form>
      {stopping && merchant.offers > 0 && <Note tone="warning" title="عروضه تختفي عند الحفظ">{merchant.offers === 1 ? 'عرضه لن يظهر' : 'عروضه لن تظهر'} للطلاب ما دام موقوفاً، ولا يُنشر له عرض جديد.</Note>}
      {serverError && <Note tone="danger" title="لم يُحفظ التاجر">{serverError}</Note>}
    </SidePanel>
  );
};
