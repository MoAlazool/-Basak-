import React from 'react';
import { Badge, Button, ErrorState, InfoRows, Note, Pill, SidePanel, SkeletonList, SkeletonStat, StatCard, dayText, moneyText, momentText, num } from '../../ui';
import { ExportButton } from '../../ui/Transfer';
import { exportSheets } from '../../lib/excel';
import {
  FOLD_UNDER, FOLDED, audienceSummary, kindLabel, offerActions, periodText, rate, rateText, statsRates, statsSheets, useOfferStats,
  type AudienceNames, type Offer, type OfferState, type OfferStats, type StatsGroup,
} from '../../lib/offers';
import { PictureThumb } from './OfferPicture';

export const OfferStatePill: React.FC<{ state: OfferState }> = ({ state }) => <Pill tone={state.tone}>{state.label}</Pill>;

const pct = (r: number | null) => (r === null ? '—' : `${num(r)}%`);

/** One breakdown: who saw the offer and how often it was used, group by group. */
const Groups: React.FC<{ title: string; head: string; rows: StatsGroup[] }> = ({ title, head, rows }) => (
  <section className="flex flex-col gap-2">
    <h3 className="m-0 text-card">{title}</h3>
    {rows.length === 0 ? <p className="m-0 text-label text-ink-2">لم يشاهده أحد بعد.</p> : (
      <div className="overflow-hidden rounded-inner shadow-ring">
        <table className="w-full table-fixed border-collapse text-small">
          <caption className="sr-only">{title}</caption>
          <thead>
            <tr className="h-10 bg-ground text-label font-semibold text-ink-2">
              <th scope="col" className="px-3 text-start">{head}</th>
              <th scope="col" className="w-20 px-3 text-start">شاهدوه</th>
              <th scope="col" className="w-24 px-3 text-start">استُخدم</th>
              <th scope="col" className="w-20 px-3 text-start">النسبة</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.name} className="h-11 border-t border-hair">
                <th scope="row" className={`truncate px-3 text-start font-medium ${r.name === FOLDED ? 'text-ink-2' : ''}`}>{r.name}</th>
                <td className="px-3 tabular">{num(r.seen)}</td>
                <td className="px-3 tabular">{num(r.redeemed)}</td>
                <td className="px-3 tabular text-ink-2">{rateText(r.redeemed, r.seen)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    )}
  </section>
);

/** Uses day by day, each day's bar a share of the busiest one. */
const Days: React.FC<{ rows: OfferStats['by_day'] }> = ({ rows }) => {
  const top = Math.max(0, ...rows.map((r) => r.redeemed));
  return (
    <section className="flex flex-col gap-2">
      <h3 className="m-0 text-card">الاستخدام باليوم</h3>
      {rows.length === 0 ? <p className="m-0 text-label text-ink-2">لم يُستخدم بعد.</p> : (
        <ol className="m-0 flex list-none flex-col p-0">
          {rows.map((r, i) => (
            <li key={r.day} className={`flex items-center gap-3 py-2 ${i ? 'border-t border-hair' : ''}`}>
              <span className="w-32 flex-none text-label">{dayText(r.day, { year: false, weekday: true })}</span>
              <span aria-hidden="true" className="h-1.5 min-w-0 flex-1 overflow-hidden rounded bg-sunken"><span className="block h-1.5 rounded bg-teal" style={{ width: `${top > 0 ? Math.max(2, Math.round((r.redeemed / top) * 100)) : 0}%` }} /></span>
              <span className="w-12 flex-none text-end text-label font-medium tabular">{num(r.redeemed)}</span>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
};

/**
 * One offer in full: what it is, and its numbers from `platform_offer_stats` —
 * how many it reaches, saw it, opened it and used it, by university, by college
 * and by day. Counts only; nobody is named.
 */
export const OfferStatsPanel: React.FC<{
  offer: Offer | null; state: OfferState | null; names: AudienceNames; online: boolean; busy: boolean;
  onClose: () => void; onEdit: () => void; onPublish: () => void; onPause: () => void; onEnd: () => void; onDelete: () => void;
}> = ({ offer, state, names, online, busy, onClose, onEdit, onPublish, onPause, onEnd, onDelete }) => {
  const stats = useOfferStats(offer?.id ?? null);
  if (!offer || !state) return null;
  const s = stats.data;
  const can = offerActions(offer.status);
  const coupon = offer.kind !== 'info';
  const rates = s ? statsRates(s) : null;
  return (
    <SidePanel open onClose={onClose} w={640} backLabel="العروض" title={offer.title} meta={<><OfferStatePill state={state} />{offer.special && <Badge tone="teal">عرض خاص</Badge>}</>}
      sub={[offer.merchant_name, coupon ? offer.value_label : 'إعلان'].filter(Boolean).join(' · ')}
      footer={<>
        <Button kind="dangerQuiet" icon="trash" disabled={!online || busy} onClick={onDelete}>احذف</Button>
        {can.end && <Button kind="secondary" disabled={!online || busy} onClick={onEnd}>أنهِ العرض</Button>}
        <span className="hidden flex-1 sm:block" />
        <Button kind="secondary" icon="pencil" onClick={onEdit}>تعديل</Button>
        {can.pause && <Button kind="tonal" disabled={!online || busy} onClick={onPause}>أوقفه مؤقتاً</Button>}
        {can.publish && <Button icon="megaphone" disabled={!online || busy} onClick={onPublish}>{offer.published_at ? 'أعد نشره' : 'انشر العرض'}</Button>}
      </>}>
      <section className="flex flex-col gap-3">
        <div className="flex items-center gap-2"><h3 className="m-0 flex-1 text-card">الأرقام</h3>
          {s && <ExportButton onExport={() => exportSheets(`أرقام عرض ${offer.title}`, statsSheets(offer, s))} />}</div>
        <Note icon="shield" title="أعداد فقط، بلا أسماء">
          لا يظهر هنا أي طالب باسمه. والجامعة أو الكلية التي شاهد العرضَ منها أقل من {num(FOLD_UNDER)} طلاب تُضم إلى «{FOLDED}»، حتى لا يُعرف أحد من عدد صغير.
        </Note>
        {stats.loading ? <div className="grid grid-cols-2 gap-3"><SkeletonStat /><SkeletonStat /><SkeletonStat /><SkeletonStat /></div>
          : !s ? <ErrorState title="تعذّر تحميل أرقام العرض" text="تأكد من اتصالك ثم حاول مرة أخرى." onRetry={() => void stats.reload()} />
            : (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <StatCard label="يصل إليهم الآن" value={num(s.reach)} hint="جمهور العرض كما هو اليوم" />
                  <StatCard label="شاهدوه" value={num(s.seen)} hint={rates?.seen == null ? 'ظهر على شاشتهم' : `${pct(rates.seen)} من جمهوره اليوم`} />
                  <StatCard label="فتحوه" value={num(s.opened)} hint={`${pct(rates?.opened ?? null)} ممن شاهدوه`} />
                  {coupon
                    ? <StatCard label="استخدموه" value={num(s.students_redeemed)} hint={`${pct(rates?.redeemed ?? null)} ممن شاهدوه · ${num(s.redeemed)} مرة`} />
                    : <StatCard label="استخدموه" value="—" hint="إعلان بلا كوبون" />}
                </div>
                {coupon && (
                  <InfoRows labelW={170} rows={[
                    ['كوبونات صدرت', num(s.coupons)],
                    ['منها مؤكَّدة (استخدام)', `${num(s.redeemed)} · ${pct(rate(s.redeemed, s.coupons))} من الكوبونات`],
                    ['الباقي من الإجمالي', offer.total_limit == null ? 'بلا حد' : `${num(Math.max(0, offer.total_limit - s.redeemed))} من ${num(offer.total_limit)}`],
                  ]} />
                )}
              </>
            )}
      </section>
      {s && <Groups title="بالجامعة" head="الجامعة" rows={s.by_university} />}
      {s && <Groups title="بالكلية" head="الكلية" rows={s.by_college} />}
      {s && coupon && <Days rows={s.by_day} />}
      {stats.loading && <SkeletonList rows={4} />}

      <section className="flex flex-col gap-1">
        <h3 className="m-0 text-card">العرض</h3>
        <div className="flex items-start gap-3 py-2">
          <PictureThumb path={offer.image_path} folder="offers" size={72} />
          <div className="min-w-0 flex-1 text-label text-ink-2">
            <p className="m-0 whitespace-pre-line">{offer.description || 'بلا وصف.'}</p>
            {offer.terms && <p className="m-0 mt-1 whitespace-pre-line text-ink-3">الشروط: {offer.terms}</p>}
          </div>
        </div>
        <InfoRows labelW={150} rows={[
          ['النوع', kindLabel(offer.kind)],
          ['الجمهور', audienceSummary(offer.audience, names)],
          ['المدة', periodText(offer.starts_at, offer.ends_at)],
          ['أول نشر', offer.published_at ? momentText(offer.published_at) : 'لم يُنشر بعد'],
          ...(coupon ? [
            ['لكل طالب', `${num(offer.per_student_limit)} ${offer.per_student_limit === 1 ? 'مرة' : 'مرات'}`],
            ['مدة الكوبون', `${num(offer.coupon_minutes)} دقيقة`],
            ['رمز التاجر', offer.has_pin ? 'مضبوط (لا يُعرض)' : 'بلا رمز: يُحسب الاستخدام فور فتح الكوبون'],
          ] as [React.ReactNode, React.ReactNode][] : []),
        ]} />
      </section>
      {(offer.price != null || offer.internal_note) && (
        <section className="flex flex-col gap-1">
          <div className="flex flex-wrap items-center gap-2"><h3 className="m-0 text-card">للمنصة فقط</h3><Badge tone="warning">داخلي · لا يظهر للطلاب</Badge></div>
          <InfoRows labelW={150} rows={[
            ['سعر الاتفاق', offer.price == null ? '—' : moneyText(offer.price)],
            ['ملاحظة داخلية', offer.internal_note || '—'],
          ]} />
        </section>
      )}
    </SidePanel>
  );
};
