import React, { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Badge, Button, Card, FieldRow, Note, PageHeader, PhoneBar, RadioCards, SelectField, TextArea, TextField, Toggle, errorText, num, useOnline } from '../../ui';
import { useGuard } from '../../lib/guard';
import { notifyDone } from '../../lib/toasts';
import { CAIRO_LABEL, cairoLocalToIso } from '../../lib/time';
import {
  LIMITS, NAME_MAX, OFFER_KINDS, TEXT_MAX, VALUE_MAX, emptyOffer, hasProblems, offerDraftOf, offerPayload, offerProblems, offersKey, reachText,
  saveOffer, saveWithPicture, type Merchant, type Offer, type OfferDraft, type OfferKind, type PictureChange,
} from '../../lib/offers';
import { AudienceBuilder, AudienceReach, NumberField } from './OfferAudience';
import { PictureField } from './OfferPicture';

/** A card of the form: its title, one helping sentence, then the fields. */
const Block: React.FC<{ title: React.ReactNode; help?: React.ReactNode; meta?: React.ReactNode; children: React.ReactNode }> = ({ title, help, meta, children }) => (
  <Card as="section" className="flex flex-col gap-4 p-4 lg:p-6">
    <div>
      <div className="flex flex-wrap items-center gap-2"><h2 className="m-0 text-card">{title}</h2>{meta}</div>
      {help && <p className="m-0 mt-0.5 text-label text-ink-2">{help}</p>}
    </div>
    {children}
  </Card>
);

/** A Cairo day and hour as two boxes; `fallbackTime` is the hour a day chosen first starts with. */
const WhenFields: React.FC<{
  dayLabel: string; value: string; onChange: (local: string) => void; fallbackTime: string; error?: string; optional?: boolean; disabled?: boolean;
}> = ({ dayLabel, value, onChange, fallbackTime, error, optional, disabled }) => {
  const [day, time] = value ? value.split('T') : ['', ''];
  return (
    <FieldRow cols="minmax(0,3fr) minmax(0,2fr)">
      <TextField label={dayLabel} optional={optional} type="date" ltr value={day} disabled={disabled} error={error}
        onChange={(e) => onChange(e.target.value ? `${e.target.value}T${time || fallbackTime}` : '')} />
      <TextField label="الساعة" type="time" ltr value={time ?? ''} disabled={disabled || !day} help={CAIRO_LABEL}
        onChange={(e) => { if (day) onChange(`${day}T${e.target.value || fallbackTime}`); }} />
    </FieldRow>
  );
};

/**
 * An offer, created or changed: what it is, when it runs, its coupon, and who
 * sees it, with the audience counted live beside the form. Saving never
 * changes whether it is published: that is done from the list.
 */
export const OfferForm: React.FC<{ offer: Offer | null; merchants: Merchant[]; onDone: () => void; backTo: string }> = ({ offer, merchants, onDone, backTo }) => {
  const client = useQueryClient();
  const guard = useGuard();
  const online = useOnline();
  // The id is made here, before anything is saved, so the picture can be stored under it.
  const [draft, setDraft] = useState<OfferDraft>(() => (offer ? offerDraftOf(offer) : emptyOffer(crypto.randomUUID())));
  const [image, setImage] = useState<PictureChange>(undefined);
  const [tried, setTried] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const set = (patch: Partial<OfferDraft>) => { setDraft((d) => ({ ...d, ...patch })); setError(''); };
  const problems = offerProblems(draft);
  const bad = hasProblems(problems);
  const show = <K extends Exclude<keyof typeof problems, 'audience'>>(k: K) => (tried ? problems[k] : undefined);
  const coupon = draft.kind !== 'info';
  const kind = OFFER_KINDS.find((k) => k.value === draft.kind);
  const merchant = merchants.find((m) => m.id === draft.merchantId);
  const startsAt = cairoLocalToIso(draft.startsLocal);
  const startsLater = !!startsAt && new Date(startsAt).getTime() > Date.now();

  const save = () => {
    setTried(true);
    if (bad) { setError('راجع الحقول المعلَّمة ثم احفظ.'); return; }
    void guard('save', async () => {
      setBusy(true); setError('');
      try {
        const out = await saveWithPicture('offers', draft.id, draft.imagePath, image, (path) => saveOffer(offerPayload(draft, path)));
        await client.invalidateQueries({ queryKey: offersKey });
        notifyDone(draft.isNew ? 'حُفظ العرض مسودةً.' : 'حُفظ العرض.',
          `${reachText(out.students)}.${offer?.status === 'live' ? '' : ' انشره من قائمة العروض ليراه الطلاب.'}`);
        onDone();
      } catch (e) { setError(errorText(e)); }
      setBusy(false);
    });
  };

  const primary = <Button icon="check" loading={busy} disabled={!online} onClick={save}>{draft.isNew ? 'احفظ العرض مسودةً' : 'احفظ العرض'}</Button>;
  const cancel = <Button kind="secondary" disabled={busy} onClick={onDone}>إلغاء</Button>;

  return (
    <>
      <PageHeader title={offer ? 'تعديل العرض' : 'عرض جديد'} back={{ label: 'العروض', to: backTo }}
        sub={offer ? offer.title : 'عرض من تاجر يظهر للطلاب الذين تختارهم. يُحفظ مسودةً، وتنشره من القائمة حين يكون جاهزاً.'} />
      {offer?.status === 'live' && <Note tone="warning" title="هذا العرض منشور">ما تحفظه هنا يراه الطلاب فوراً، ومنه تغيير الجمهور.</Note>}
      <div className="grid grid-cols-1 items-start gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] lg:gap-6">
        <form className="flex min-w-0 flex-col gap-5 lg:gap-6" onSubmit={(e) => { e.preventDefault(); save(); }}>
          <Block title="العرض" help="ما يراه الطالب في بطاقة العرض وصفحته.">
            <SelectField label="التاجر" placeholder="اختر التاجر" value={draft.merchantId} onChange={(e) => set({ merchantId: e.target.value })} error={show('merchantId')}
              options={merchants.filter((m) => m.is_active || m.id === draft.merchantId).map((m) => ({ value: m.id, label: m.is_active ? m.name : `${m.name} (موقوف)` }))}
              help={merchant && !merchant.is_active ? 'هذا التاجر موقوف: لا يُنشر له عرض حتى تفعّله.' : merchants.length === 0 ? 'أضف التاجر أولاً من صفحة التجّار.' : undefined} />
            <TextField label="عنوان العرض" value={draft.title} onChange={(e) => set({ title: e.target.value })} maxLength={NAME_MAX} error={show('title')} placeholder="مثل: خصم على كل المشروبات" />
            <TextArea label="الوصف" optional rows={3} value={draft.description} onChange={(e) => set({ description: e.target.value })} maxLength={TEXT_MAX} error={show('description')} />
            <TextArea label="الشروط" optional rows={3} value={draft.terms} onChange={(e) => set({ terms: e.target.value })} maxLength={TEXT_MAX} error={show('terms')}
              help="ما يجب أن يعرفه الطالب قبل الذهاب: الأيام، الفروع، ما لا يشمله العرض." />
            <PictureField folder="offers" title="صورة العرض" where="تظهر أعلى بطاقة العرض. الصور العريضة أنسب." savedPath={draft.imagePath} change={image} onChange={setImage} disabled={busy} />
          </Block>

          <Block title="القيمة والمدة">
            <RadioCards<OfferKind> label="نوع العرض" cols={4} value={draft.kind} onChange={(k) => set({ kind: k })}
              options={OFFER_KINDS.map((k) => ({ value: k.value, label: k.label, sub: k.sub }))} />
            {coupon
              ? <TextField label="القيمة كما تظهر على البطاقة" value={draft.valueLabel} onChange={(e) => set({ valueLabel: e.target.value })} maxLength={VALUE_MAX} error={show('valueLabel')}
                  placeholder={kind?.example} help={`نص قصير، ${VALUE_MAX} حرفاً على الأكثر. مطلوب قبل النشر.`} className="sm:max-w-[320px]" />
              : <Note title="إعلان بلا كوبون">يرى الطالب العرض وطرق الوصول إلى التاجر فقط: لا كوبون ولا رمز ولا حدود استخدام.</Note>}
            <WhenFields dayLabel="يبدأ يوم" value={draft.startsLocal} onChange={(startsLocal) => set({ startsLocal })} fallbackTime="00:00" error={show('starts')} disabled={busy} />
            <WhenFields dayLabel="ينتهي يوم" optional value={draft.endsLocal} onChange={(endsLocal) => set({ endsLocal })} fallbackTime="23:59" error={show('ends')} disabled={busy} />
            <p className="m-0 text-label text-ink-2">{draft.endsLocal ? 'بعد موعد النهاية يختفي العرض عند الطلاب من نفسه.' : 'بلا يوم نهاية: يبقى ظاهراً حتى توقفه أو تنهيه.'}</p>
          </Block>

          {coupon && (
            <Block title="الكوبون" help="يفتح الطالب كوبوناً برمز يعرضه للتاجر، ويُحسب استخداماً عند تأكيده.">
              <FieldRow>
                <NumberField label="مرات لكل طالب" value={draft.perStudentLimit} onValue={(perStudentLimit) => set({ perStudentLimit })} digits={3} suffix="مرة" error={show('perStudentLimit')}
                  help={`من ${LIMITS.perStudent.min} إلى ${LIMITS.perStudent.max}.`} />
                <NumberField label="إجمالي مرات الاستخدام" optional value={draft.totalLimit} onValue={(totalLimit) => set({ totalLimit })} digits={7} suffix="مرة" error={show('totalLimit')}
                  help="فارغ = بلا حد. عند بلوغه يختفي العرض ممن لم يستخدمه." />
                <NumberField label="مدة الكوبون" value={draft.couponMinutes} onValue={(couponMinutes) => set({ couponMinutes })} digits={2} suffix="دقيقة" error={show('couponMinutes')}
                  help={`من ${LIMITS.coupon.min} إلى ${LIMITS.coupon.max} دقيقة.`} />
              </FieldRow>
              <div className="flex flex-col gap-3 border-t border-hair pt-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-label font-medium">رمز التاجر</span>
                  {draft.hasPin && !draft.removePin ? <Badge tone="success">مضبوط</Badge> : <Badge>{draft.removePin ? 'سيُزال عند الحفظ' : 'بلا رمز'}</Badge>}
                </div>
                {draft.removePin ? (
                  <Note tone="warning" title="سيُزال الرمز عند الحفظ" action={<Button sm kind="secondary" icon="undo" onClick={() => set({ removePin: false })}>أبقِ الرمز</Button>}>
                    بعدها يُحسب الكوبون مستخدماً فور فتحه، دون تأكيد من التاجر.
                  </Note>
                ) : (
                  <div className="flex flex-col gap-2 sm:flex-row sm:items-start">
                    <TextField aria-label={draft.hasPin ? 'رمز جديد للتاجر' : 'رمز التاجر'} ltr inputMode="numeric" autoComplete="off" value={draft.pin} maxLength={6} error={show('pin')}
                      placeholder={draft.hasPin ? 'رمز جديد' : '4 إلى 6 أرقام'} className="sm:w-[220px]"
                      onChange={(e) => set({ pin: e.target.value.replace(/\D/g, '').slice(0, 6) })} />
                    {draft.hasPin && <Button kind="dangerQuiet" icon="trash" onClick={() => set({ removePin: true, pin: '' })}>أزل الرمز</Button>}
                  </div>
                )}
                <p className="m-0 text-label text-ink-2">
                  {draft.hasPin
                    ? 'الرمز المحفوظ لا يُعرض هنا ولا في أي مكان. اترك الحقل فارغاً ليبقى كما هو، أو اكتب رمزاً جديداً يحلّ محلّه.'
                    : 'يكتبه التاجر على هاتف الطالب ليؤكد الاستخدام (خمس محاولات لكل كوبون). بلا رمز يُحسب الكوبون مستخدماً فور فتحه. بعد الحفظ لا يُعرض الرمز مرة أخرى، فأبلغه للتاجر الآن.'}
                </p>
              </div>
            </Block>
          )}

          <Block title="من يراه" help="كل شرط يضيّق الجمهور، ويجب أن تتحقق كلها معاً. القائمة التي لا تختار منها شيئاً لا تضيّق.">
            <AudienceBuilder value={draft.audience} onChange={(audience) => set({ audience })} problems={tried || hasProblems(problems.audience ?? {}) ? problems.audience : undefined} disabled={busy} />
          </Block>

          <Block title="الظهور">
            <Toggle label="عرض خاص" checked={draft.special} onChange={(special) => set({ special })}
              help="يظهر أولاً بعنوان «عرض خاص لك»، ويصل جمهورَه إشعار واحد: عند نشره إن كان قد بدأ، وإلا عند موعد بدايته. لا يصل الطالبَ أكثر من إشعار عرض خاص واحد كل أسبوع." />
            {draft.special && (
              <Note title="متى يصل الإشعار">
                {offer?.status === 'live'
                  ? 'العرض منشور: إن لم يكن أُعلن من قبل، يصل الإشعار خلال دقائق من الحفظ إذا كان قد بدأ، أو عند موعد بدايته.'
                  : startsLater ? 'عند نشره لا يصل شيء فوراً: يصل الإشعار من نفسه حين يحين موعد البداية.' : 'يصل الإشعار لحظة نشره.'}
                {' '}مرة واحدة لكل عرض.
              </Note>
            )}
            <NumberField label="الترتيب" value={draft.sort} onValue={(sort) => set({ sort })} digits={4} error={show('sort')} className="sm:max-w-[200px]"
              help="الرقم الأعلى يظهر أولاً بين العروض." />
          </Block>

          <Block title="للمنصة فقط" meta={<Badge tone="warning">داخلي · لا يظهر للطلاب ولا للتاجر</Badge>} help="حسابات المنصة مع التاجر. لا تُرسل إلى التطبيق أبداً.">
            <TextField label="سعر الاتفاق (داخلي)" optional ltr inputMode="decimal" suffix="ج.م" value={draft.price} error={show('price')} className="sm:max-w-[240px]"
              onChange={(e) => set({ price: e.target.value.replace(/[^\d.]/g, '').slice(0, 11) })} />
            <TextArea label="ملاحظة داخلية" optional rows={2} value={draft.internalNote} onChange={(e) => set({ internalNote: e.target.value })} maxLength={600} />
          </Block>

          {error && <Note tone="danger" title="لم يُحفظ العرض">{error}</Note>}
          <div className="hidden justify-end gap-2 sm:flex">{cancel}{primary}</div>
          <button type="submit" hidden aria-hidden="true" tabIndex={-1} />
        </form>
        <div className="flex min-w-0 flex-col gap-4 lg:sticky lg:top-6">
          <AudienceReach value={draft.audience} problems={problems.audience} />
          <Card className="flex flex-col gap-1 px-4 py-3.5 sm:px-5">
            <span className="text-label font-medium text-ink-2">ملخص</span>
            <span className="text-small font-semibold">{draft.title.trim() || 'عنوان العرض'}</span>
            <span className="text-label text-ink-2">{[merchant?.name, coupon ? draft.valueLabel.trim() : 'إعلان'].filter(Boolean).join(' · ') || '—'}</span>
            {coupon && <span className="text-label text-ink-3">{`${num(draft.perStudentLimit === '' ? null : draft.perStudentLimit)} لكل طالب · ${draft.totalLimit === '' ? 'بلا حد إجمالي' : `${num(draft.totalLimit)} إجمالاً`} · ${draft.hasPin && !draft.removePin || draft.pin ? 'برمز التاجر' : 'بلا رمز'}`}</span>}
          </Card>
        </div>
      </div>
      <PhoneBar>{React.cloneElement(primary, { full: true })}</PhoneBar>
    </>
  );
};
