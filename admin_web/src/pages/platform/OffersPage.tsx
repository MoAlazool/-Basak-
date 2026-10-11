import React, { useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import { Badge, Button, Cell2, Chips, DataTable, Dialog, EmptyState, ErrorState, Menu, Page, PageHeader, Pager, PhoneBar, SearchBox, SkeletonTable, Toolbar, countText, errorText, num, NOUN, useOnline, type Column } from '../../ui';
import { Select } from '../../ui/Select';
import { ExportButton } from '../../ui/Transfer';
import { exportSheet } from '../../lib/excel';
import { excelMoment, MOMENT_FORMAT } from '../../lib/excelCells';
import { useGuard } from '../../lib/guard';
import { notifyDone, notifyError } from '../../lib/toasts';
import { matches } from '../../lib/platform';
import {
  audienceSummary, deleteOffer, kindLabel, offerActions, offerState, offersKey, periodText, rateText, removePictures, setOfferStatus, specialNotice, useOffersOverview,
  type Offer, type OfferState, type OfferStatus,
} from '../../lib/offers';
import { OfferForm } from '../../components/platform/OfferForm';
import { OfferStatePill, OfferStatsPanel } from '../../components/platform/OfferStats';
import { useAudienceNames } from '../../components/platform/OfferAudience';

const PAGE = 25;
const HERE = '/platform/offers';
type Filter = 'all' | OfferStatus;
type Asking = { kind: 'end' | 'delete' | 'publish'; offer: Offer };
const TITLE = 'العروض';
const SUB = '«عروض باصك»: عروض التجّار التي تظهر في التطبيق للطلاب الذين تختارهم. العرض يُحفظ مسودةً، ولا يراه أحد حتى تنشره.';

/**
 * «العروض» — every offer with what happened to it (seen, opened, used), the
 * buttons that publish, pause, end or delete one, its details and numbers in a
 * panel, and — on «عرض جديد» or «تعديل» — the form with the audience builder.
 */
export const OffersPage: React.FC = () => {
  const page = useOffersOverview();
  const data = page.data;
  const offers = useMemo(() => data?.offers ?? [], [data]);
  const merchants = useMemo(() => data?.merchants ?? [], [data]);
  const names = useAudienceNames();
  const online = useOnline();
  const client = useQueryClient();
  const guard = useGuard();
  const [params, setParams] = useSearchParams();

  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [merchantId, setMerchantId] = useState('');
  const [pageNo, setPageNo] = useState(1);
  const [asking, setAsking] = useState<Asking | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const go = (next: Record<string, string>, replace = false) => setParams(next, { replace });
  const openId = params.get('offer');
  const editId = params.get('edit');
  const creating = params.get('new') === '1';
  const open = offers.find((o) => o.id === openId) ?? null;
  const editing = offers.find((o) => o.id === editId) ?? null;

  const merchantActive = (o: Offer) => merchants.find((m) => m.id === o.merchant_id)?.is_active;
  const stateFor = (o: Offer): OfferState => offerState(o, merchantActive(o));
  const shown = useMemo(
    () => offers.filter((o) => (filter === 'all' || o.status === filter) && (!merchantId || o.merchant_id === merchantId) && matches(search, o.title, o.merchant_name, o.value_label)),
    [offers, filter, merchantId, search]);
  const pageRows = shown.slice((pageNo - 1) * PAGE, pageNo * PAGE);

  // ── Writes: the server's own sentence is shown when it refuses ───────────────
  const refresh = () => client.invalidateQueries({ queryKey: offersKey });
  const setStatus = (o: Offer, status: OfferStatus) => void guard(`status:${o.id}`, async () => {
    setBusy(o.id);
    try {
      const out = await setOfferStatus(o.id, status);
      await refresh();
      setAsking(null);
      if (status === 'live') {
        const later = new Date(o.starts_at).getTime() > Date.now();
        notifyDone(`نُشر «${o.title}».`, out.notified > 0 ? `وصل إشعار العرض الخاص إلى ${countText(out.notified, NOUN.student)}.`
          : later ? `يظهر للطلاب عند موعد بدايته${o.special ? '، ويصلهم إشعاره حينها' : ''}.` : 'يراه جمهوره في التطبيق من الآن.');
      } else if (status === 'paused') notifyDone(`أُوقف «${o.title}» مؤقتاً.`, 'اختفى عند الطلاب. انشره من جديد متى شئت.');
      else notifyDone(`أُنهي «${o.title}».`, 'اختفى عند الطلاب، وأرقامه باقية هنا.');
    } catch (e) {
      setAsking(null);
      notifyError(status === 'live' ? 'لم يُنشر العرض' : status === 'paused' ? 'لم يُوقف العرض' : 'لم يُنهَ العرض', errorText(e));
    }
    setBusy(null);
  });
  const remove = (o: Offer) => void guard(`delete:${o.id}`, async () => {
    setBusy(o.id);
    try {
      await deleteOffer(o.id);
      void removePictures([o.image_path]);
      if (openId === o.id) go({}, true);
      await refresh();
      setAsking(null);
      notifyDone(`حُذف «${o.title}».`);
    } catch (e) {
      setAsking(null);
      notifyError('لم يُحذف العرض', errorText(e));
    }
    setBusy(null);
  });
  /** Publishing a special offer tells its audience (now, or at its start), so it asks first; any other publish just happens. */
  const publish = (o: Offer) => (specialNotice(o) === 'no' ? setStatus(o, 'live') : setAsking({ kind: 'publish', offer: o }));

  const header = (actions?: React.ReactNode) => <PageHeader title={TITLE} sub={SUB} actions={actions} phoneActions={false} />;
  if (page.loading) return <Page>{header()}<SkeletonTable rows={6} cols={7} /></Page>;
  if (page.error && !data) return <Page>{header()}<ErrorState card title="تعذّر تحميل العروض" text="تأكد من اتصالك ثم حاول مرة أخرى. لم يتغيّر شيء عند الطلاب." onRetry={() => void page.reload()} /></Page>;
  if (!data) return <Page>{header()}<EmptyState card icon="receipt" title="العروض غير متاحة بعد" text="تعمل «عروض باصك» بعد تحديث الخادم. لا شيء مطلوب منك الآن." /></Page>;

  if (creating || editing) {
    return <Page><OfferForm key={editing?.id ?? 'new'} offer={editing} merchants={merchants} backTo={HERE} onDone={() => go(editing ? { offer: editing.id } : {})} /></Page>;
  }

  const addButton = <Button icon="plus" onClick={() => go({ new: '1' })}>عرض جديد</Button>;
  if (merchants.length === 0) {
    return <Page>{header()}<EmptyState card icon="pin" title="أضف تاجراً أولاً" text="كل عرض يأتي من تاجر. أضف التاجر ثم عُد لتنشئ عرضه." action={<Button icon="pin" to="/platform/merchants">افتح التجّار</Button>} /></Page>;
  }
  if (offers.length === 0) {
    return (
      <Page>{header()}
        <EmptyState card icon="receipt" title="لا عروض بعد" text="أنشئ أول عرض: ما هو، متى يعمل، ومن يراه. يُحفظ مسودةً حتى تنشره." action={addButton} />
      </Page>
    );
  }

  const exportRows = (list: Offer[]) => exportSheet<Offer>({
    name: 'العروض', rows: list,
    columns: [
      { label: 'العرض', value: (o) => o.title, width: 32 },
      { label: 'التاجر', value: (o) => o.merchant_name, width: 26 },
      { label: 'النوع', value: (o) => kindLabel(o.kind), width: 14 },
      { label: 'القيمة', value: (o) => o.value_label, width: 16 },
      { label: 'الحالة', value: (o) => stateFor(o).label, width: 14 },
      { label: 'عرض خاص', value: (o) => o.special },
      { label: 'يبدأ', value: (o) => excelMoment(o.starts_at), format: MOMENT_FORMAT, width: 18 },
      { label: 'ينتهي', value: (o) => excelMoment(o.ends_at), format: MOMENT_FORMAT, width: 18 },
      { label: 'الجمهور', value: (o) => audienceSummary(o.audience, names), width: 44 },
      { label: 'شاهدوه', value: (o) => o.seen, format: '#,##0' },
      { label: 'فتحوه', value: (o) => o.opened, format: '#,##0' },
      { label: 'مرات الاستخدام', value: (o) => o.redeemed, format: '#,##0', width: 16 },
      { label: 'سعر الاتفاق (داخلي)', value: (o) => o.price, format: '#,##0.00', width: 20 },
      { label: 'ملاحظة داخلية', value: (o) => o.internal_note, width: 36 },
    ],
  });

  const count = (n: number, of?: number) => <span className={`tabular ${n === 0 ? 'text-ink-3' : ''}`} title={of !== undefined ? `${rateText(n, of)} ممن شاهدوه` : undefined}>{num(n)}</span>;
  const menuOf = (o: Offer) => {
    const can = offerActions(o.status);
    return [
      { label: 'التفاصيل والأرقام', icon: 'chart' as const, onClick: () => go({ offer: o.id }) },
      { label: 'تعديل', icon: 'pencil' as const, onClick: () => go({ edit: o.id }) },
      { label: o.published_at ? 'أعد نشره' : 'انشر العرض', icon: 'megaphone' as const, hidden: !can.publish || !online, onClick: () => publish(o), divider: true },
      { label: 'أوقفه مؤقتاً', icon: 'clock' as const, hidden: !can.pause || !online, onClick: () => setStatus(o, 'paused'), divider: true },
      { label: 'أنهِ العرض', icon: 'power' as const, hidden: !can.end || !online, onClick: () => setAsking({ kind: 'end', offer: o }) },
      { label: 'احذف', icon: 'trash' as const, danger: true, hidden: !online, onClick: () => setAsking({ kind: 'delete', offer: o }), divider: true },
    ];
  };
  const columns: Column<Offer>[] = [
    { key: 'offer', label: 'العرض', render: (o) => <Cell2 main={<span className="inline-flex max-w-full items-center gap-2"><span className="truncate">{o.title}</span>{o.special && <Badge tone="teal">خاص</Badge>}</span>} sub={audienceSummary(o.audience, names)} /> },
    { key: 'merchant', label: 'التاجر', w: 180, render: (o) => <span className="truncate">{o.merchant_name}</span> },
    { key: 'value', label: 'القيمة', w: 130, render: (o) => (o.kind === 'info' ? <span className="text-ink-3">إعلان</span> : o.value_label ? <span className="font-medium">{o.value_label}</span> : <span className="text-ink-3">—</span>) },
    { key: 'period', label: 'المدة', w: 220, hideTablet: true, render: (o) => <span className="truncate text-label">{periodText(o.starts_at, o.ends_at)}</span> },
    { key: 'state', label: 'الحالة', w: 136, render: (o) => <OfferStatePill state={stateFor(o)} /> },
    { key: 'seen', label: 'شاهدوه', w: 88, render: (o) => count(o.seen) },
    { key: 'opened', label: 'فتحوه', w: 84, hideTablet: true, render: (o) => count(o.opened, o.seen) },
    { key: 'redeemed', label: 'استُخدم', w: 88, render: (o) => (o.kind === 'info' ? <span className="text-ink-3">—</span> : count(o.redeemed)) },
    { key: 'act', label: <span className="sr-only">إجراءات</span>, w: 64, align: 'end', render: (o) => <span onClick={(e) => e.stopPropagation()} className="inline-flex"><Menu label={`إجراءات ${o.title}`} items={menuOf(o)} /></span> },
  ];
  const counted = (s: OfferStatus) => offers.filter((o) => o.status === s).length;
  const toolbar = (
    <Toolbar
      search={<SearchBox value={search} onChange={(v) => { setSearch(v); setPageNo(1); }} placeholder="ابحث بعنوان العرض أو التاجر" />}
      filters={<Chips value={filter} onChange={(v) => { setFilter(v); setPageNo(1); }} options={[
        { value: 'all', label: 'الكل', count: offers.length }, { value: 'live', label: 'منشور', count: counted('live') }, { value: 'draft', label: 'مسودة', count: counted('draft') },
        { value: 'paused', label: 'موقوف', count: counted('paused') }, { value: 'ended', label: 'منتهٍ', count: counted('ended') },
      ]} />}
      actions={(
        <>
          <ExportButton className="hidden sm:inline-flex" count={shown.length} onExport={() => exportRows(shown)} />
          <Select value={merchantId} onChange={(v) => { setMerchantId(v); setPageNo(1); }} ariaLabel="التاجر" icon="pin" minListWidth={240}
            options={[{ value: '', label: 'كل التجّار' }, ...merchants.map((m) => ({ value: m.id, label: m.name }))]}
            className="inline-flex h-10 max-w-[220px] flex-none items-center gap-1.5 rounded-control px-2.5 text-label font-semibold shadow-ring hover:bg-ground sm:h-9" />
        </>
      )}
    />
  );
  const noMatch = shown.length === 0
    ? <EmptyState icon="search" title="لا عروض بهذا الوصف" text="جرّب كلمة أخرى، أو اعرض كل العروض." action={<Button kind="secondary" onClick={() => { setSearch(''); setFilter('all'); setMerchantId(''); }}>اعرض الكل</Button>} />
    : undefined;

  const a = asking;
  const notice = a?.kind === 'publish' ? specialNotice(a.offer) : 'no';
  return (
    <Page>
      {header(addButton)}
      <DataTable caption="العروض" columns={columns} rows={pageRows} rowKey={(o) => o.id} onOpen={(o) => go({ offer: o.id })} openKey={openId} toolbar={toolbar} empty={noMatch}
        pager={<Pager page={pageNo} total={shown.length} onPage={setPageNo} />} muted={(o) => o.status === 'ended'}
        card={(o) => ({
          title: o.title, sub: [o.merchant_name, o.kind === 'info' ? 'إعلان' : o.value_label].filter(Boolean).join(' · '), end: <OfferStatePill state={stateFor(o)} />,
          stats: [['شاهدوه', num(o.seen)], ['فتحوه', num(o.opened)], ['استُخدم', o.kind === 'info' ? '—' : num(o.redeemed)]],
          fields: [['المدة', periodText(o.starts_at, o.ends_at)], ['الجمهور', audienceSummary(o.audience, names)]],
          actions: <Menu label={`إجراءات ${o.title}`} items={menuOf(o)} />,
        })} />
      <PhoneBar>{React.cloneElement(addButton, { full: true })}</PhoneBar>

      <OfferStatsPanel offer={open} state={open ? stateFor(open) : null} names={names} online={online} busy={!!open && busy === open.id}
        onClose={() => go({}, true)} onEdit={() => open && go({ edit: open.id })} onPublish={() => open && publish(open)}
        onPause={() => open && setStatus(open, 'paused')} onEnd={() => open && setAsking({ kind: 'end', offer: open })} onDelete={() => open && setAsking({ kind: 'delete', offer: open })} />

      <Dialog open={a?.kind === 'publish'} onClose={() => setAsking(null)} icon="megaphone" title={`نشر «${a?.offer.title ?? ''}»؟`}
        actions={[<Button key="b" kind="secondary" onClick={() => setAsking(null)}>رجوع</Button>,
          <Button key="g" loading={!!a && busy === a.offer.id} disabled={!online} onClick={() => a && setStatus(a.offer, 'live')}>انشر العرض</Button>]}>
        <p className="m-0"><b className="text-ink">{notice === 'atStart'
          ? 'هذا عرض خاص لم يبدأ بعد: يصل جمهورَه الإشعار من نفسه حين يحين موعد بدايته.'
          : 'هذا عرض خاص وقد بدأ: يصل جمهورَه الإشعار الآن.'}</b></p>
        <p className="m-0">الجمهور: {a ? audienceSummary(a.offer.audience, names) : ''}.</p>
        <p className="m-0">الإشعار مرة واحدة لكل عرض: إن كان أُرسل من قبل فلن يُرسل ثانية، ولا يُسترجع بعد إرساله. ومن وصله إشعار عرض خاص آخر خلال آخر 7 أيام لا يصله هذا، ويرى العرض في التطبيق فقط.</p>
      </Dialog>
      <Dialog open={a?.kind === 'end'} onClose={() => setAsking(null)} icon="power" tone="danger" title={`إنهاء «${a?.offer.title ?? ''}»؟`}
        actions={[<Button key="b" kind="secondary" onClick={() => setAsking(null)}>رجوع</Button>,
          <Button key="g" kind="danger" loading={!!a && busy === a.offer.id} disabled={!online} onClick={() => a && setStatus(a.offer, 'ended')}>أنهِ العرض</Button>]}>
        <p className="m-0">يختفي العرض عند كل الطلاب، ولا يُفتح له كوبون جديد. كوبون مفتوح الآن يبقى حتى تنتهي دقائقه.</p>
        <p className="m-0">أرقامه تبقى هنا، وتستطيع نشره من جديد لاحقاً.</p>
      </Dialog>
      <Dialog open={a?.kind === 'delete'} onClose={() => setAsking(null)} icon="trash" tone="danger" title={`حذف «${a?.offer.title ?? ''}»؟`}
        actions={[<Button key="b" kind="secondary" onClick={() => setAsking(null)}>رجوع</Button>,
          <Button key="g" kind="danger" loading={!!a && busy === a.offer.id} disabled={!online} onClick={() => a && remove(a.offer)}>احذف العرض</Button>]}>
        <p className="m-0">يُحذف العرض وأرقام مشاهدته نهائياً، ولا يمكن استرجاعه.</p>
        <p className="m-0">العرض الذي استخدمه طالب لا يُحذف: أنهِه بدلاً من ذلك.</p>
      </Dialog>
    </Page>
  );
};
