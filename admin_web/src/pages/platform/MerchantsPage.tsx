import React, { useMemo, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import { Button, Cell2, Chips, DataTable, Dialog, EmptyState, ErrorState, Ltr, Page, PageHeader, Pager, PhoneBar, SearchBox, SkeletonTable, Toolbar, errorText, num, phoneText, useOnline, type Column } from '../../ui';
import { ExportButton } from '../../ui/Transfer';
import { exportSheet } from '../../lib/excel';
import { useGuard } from '../../lib/guard';
import { notifyDone, notifyError } from '../../lib/toasts';
import { matches } from '../../lib/platform';
import { useUniversities } from '../../lib/reference';
import { categoryLabel, deleteMerchant, merchantPayload, offersKey, removePictures, saveMerchant, saveWithPicture, useOffersOverview, type Merchant, type MerchantDraft, type PictureChange } from '../../lib/offers';
import { MerchantPanel, MerchantState, offersText } from '../../components/platform/MerchantPanel';
import { PictureThumb } from '../../components/platform/OfferPicture';

const PAGE = 25;
type Filter = 'all' | 'on' | 'off';
const TITLE = 'التجّار';
const SUB = 'من تأتي منهم «عروض باصك»: مطعم بجوار الجامعة، مكتبة، محل أدوات. أضف التاجر أولاً ثم أنشئ عروضه.';

/**
 * «التجّار» — the merchants offers come from: the list, and a panel that adds
 * one or changes it. Stopping a merchant hides its offers from students.
 */
export const MerchantsPage: React.FC = () => {
  const page = useOffersOverview();
  const unis = useUniversities();
  const universities = useMemo(() => unis.data ?? [], [unis.data]);
  const rows = useMemo(() => page.data?.merchants ?? [], [page.data]);
  const online = useOnline();
  const client = useQueryClient();
  const guard = useGuard();
  const [params, setParams] = useSearchParams();

  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [pageNo, setPageNo] = useState(1);
  const [adding, setAdding] = useState(false);
  const [busy, setBusy] = useState(false);
  const [saveError, setSaveError] = useState('');
  const [deleting, setDeleting] = useState<Merchant | null>(null);

  const openId = params.get('merchant');
  const setOpen = (id: string | null) => setParams((p) => { const n = new URLSearchParams(p); if (id) n.set('merchant', id); else n.delete('merchant'); return n; }, { replace: !id });
  const open = rows.find((m) => m.id === openId) ?? null;
  const close = () => { setAdding(false); setOpen(null); setSaveError(''); };
  const uniName = (id: string | null) => universities.find((u) => u.id === id)?.name ?? '';

  const shown = useMemo(
    () => rows.filter((m) => (filter === 'all' || (filter === 'on') === m.is_active) && matches(search, m.name, categoryLabel(m.category), m.phone, m.address, uniName(m.university_id))),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rows, filter, search, universities]);
  const pageRows = shown.slice((pageNo - 1) * PAGE, pageNo * PAGE);

  const save = (draft: MerchantDraft, logo: PictureChange) => void guard('save', async () => {
    setBusy(true); setSaveError('');
    try {
      await saveWithPicture('merchants', draft.id, draft.logoPath, logo, (path) => saveMerchant(merchantPayload(draft, path)));
      await client.invalidateQueries({ queryKey: offersKey });
      close();
      notifyDone(draft.isNew ? `أُضيف ${draft.name.trim()}. أنشئ عروضه من صفحة العروض.` : `حُفظت بيانات ${draft.name.trim()}.`,
        !draft.isNew && !draft.isActive ? 'التاجر موقوف: عروضه لا تظهر للطلاب.' : undefined);
    } catch (e) { setSaveError(errorText(e)); }
    setBusy(false);
  });

  /** Only a merchant without offers goes; the server says so in its own words otherwise. */
  const remove = (m: Merchant) => void guard(`delete:${m.id}`, async () => {
    setBusy(true);
    try {
      await deleteMerchant(m.id);
      void removePictures([m.logo_path]);
      setDeleting(null);
      close();
      await client.invalidateQueries({ queryKey: offersKey });
      notifyDone(`حُذف ${m.name}.`);
    } catch (e) {
      setDeleting(null);
      notifyError('لم يُحذف التاجر', errorText(e));
    }
    setBusy(false);
  });

  const exportRows = (list: Merchant[]) => exportSheet<Merchant>({
    name: 'التجّار', rows: list,
    columns: [
      { label: 'التاجر', value: (m) => m.name, width: 30 },
      { label: 'النوع', value: (m) => categoryLabel(m.category), width: 18 },
      { label: 'الجامعة القريبة', value: (m) => uniName(m.university_id), width: 28 },
      { label: 'الهاتف', value: (m) => m.phone, width: 16 },
      { label: 'واتساب', value: (m) => m.whatsapp, width: 16 },
      { label: 'الرابط', value: (m) => m.link_url, width: 30 },
      { label: 'العنوان', value: (m) => m.address, width: 30 },
      { label: 'العروض', value: (m) => m.offers },
      { label: 'الحالة', value: (m) => (m.is_active ? 'يعمل' : 'موقوف') },
      { label: 'ملاحظات', value: (m) => m.notes, width: 36 },
    ],
  });

  const addButton = <Button icon="plus" onClick={() => { setSaveError(''); setAdding(true); }}>إضافة تاجر</Button>;
  const header = <PageHeader title={TITLE} sub={SUB} actions={rows.length ? addButton : undefined} phoneActions={false} />;
  const panel = (
    <MerchantPanel open={adding || !!open} merchant={adding ? null : open} universities={universities} busy={busy} online={online}
      serverError={saveError || undefined} onClose={close} onSave={save} onDelete={() => open && setDeleting(open)} />
  );
  const confirm = (
    <Dialog open={!!deleting} onClose={() => setDeleting(null)} icon="trash" tone="danger" title={`حذف ${deleting?.name ?? ''}؟`}
      actions={[<Button key="b" kind="secondary" onClick={() => setDeleting(null)}>رجوع</Button>,
        <Button key="g" kind="danger" loading={busy} disabled={!online} onClick={() => deleting && remove(deleting)}>احذف التاجر</Button>]}>
      <p className="m-0">يُحذف التاجر وشعاره نهائياً، ولا يمكن استرجاعه.</p>
      <p className="m-0">التاجر الذي له عروض لا يُحذف: أوقفه بدلاً من ذلك، فتختفي عروضه عن الطلاب وتبقى أرقامها.</p>
    </Dialog>
  );

  if (page.loading) return <Page>{header}<SkeletonTable rows={6} cols={6} /></Page>;
  if (page.error && !page.data) return <Page>{header}<ErrorState card title="تعذّر تحميل التجّار" text="تأكد من اتصالك ثم حاول مرة أخرى." onRetry={() => void page.reload()} /></Page>;
  if (!page.data) return <Page>{header}<EmptyState card icon="pin" title="العروض غير متاحة بعد" text="تعمل «عروض باصك» بعد تحديث الخادم. لا شيء مطلوب منك الآن." /></Page>;
  if (rows.length === 0) {
    return (
      <Page>{header}
        <EmptyState card icon="pin" title="لا تجّار بعد" text="أضف أول تاجر: اسمه ونوعه وكيف يصل إليه الطالب. بعدها تنشئ عروضه وتختار من يراها."
          action={<Button icon="plus" onClick={() => setAdding(true)}>إضافة تاجر</Button>} />
        {panel}
      {confirm}
      </Page>
    );
  }

  const dash = <span className="text-ink-3">—</span>;
  const columns: Column<Merchant>[] = [
    { key: 'name', label: 'التاجر', render: (m) => <div className="flex min-w-0 items-center gap-3"><PictureThumb path={m.logo_path} folder="merchants" size={36} /><Cell2 main={m.name} sub={m.address ?? undefined} /></div> },
    { key: 'category', label: 'النوع', w: 150, render: (m) => categoryLabel(m.category) },
    { key: 'university', label: 'الجامعة القريبة', w: 200, hideTablet: true, render: (m) => (uniName(m.university_id) ? <span className="truncate">{uniName(m.university_id)}</span> : dash) },
    { key: 'phone', label: 'الهاتف', w: 150, render: (m) => (m.phone ? <Ltr className="tabular">{phoneText(m.phone)}</Ltr> : dash) },
    { key: 'offers', label: 'العروض', w: 96, render: (m) => <span className={`tabular ${m.offers === 0 ? 'text-ink-3' : ''}`}>{num(m.offers)}</span> },
    { key: 'state', label: 'الحالة', w: 112, render: (m) => <MerchantState on={m.is_active} /> },
    { key: 'open', label: <span className="sr-only">فتح</span>, w: 88, align: 'end', render: (m) => <span onClick={(e) => e.stopPropagation()} className="inline-flex"><Button sm kind="tonal" onClick={() => setOpen(m.id)}>افتح</Button></span> },
  ];
  const counted = { all: rows.length, on: rows.filter((m) => m.is_active).length, off: rows.filter((m) => !m.is_active).length };
  const toolbar = (
    <Toolbar
      search={<SearchBox value={search} onChange={(v) => { setSearch(v); setPageNo(1); }} placeholder="ابحث باسم التاجر أو نوعه أو جامعته" />}
      filters={<Chips value={filter} onChange={(v) => { setFilter(v); setPageNo(1); }} options={[
        { value: 'all', label: 'الكل', count: counted.all }, { value: 'on', label: 'يعمل', count: counted.on }, { value: 'off', label: 'موقوف', count: counted.off },
      ]} />}
      actions={<ExportButton className="hidden sm:inline-flex" count={shown.length} onExport={() => exportRows(shown)} />}
    />
  );
  const noMatch = shown.length === 0 ? (
    search.trim()
      ? <EmptyState icon="search" title={`لا تاجر باسم «${search.trim()}»`} text="تأكد من الاسم، أو أضفه إن كان جديداً." action={<Button kind="secondary" icon="plus" onClick={() => setAdding(true)}>إضافة تاجر</Button>} />
      : <EmptyState icon="pin" title={filter === 'off' ? 'لا تجّار موقوفون' : 'لا تجّار يعملون'} action={<Button kind="secondary" onClick={() => setFilter('all')}>اعرض الكل</Button>} />
  ) : undefined;

  return (
    <Page>
      {header}
      <DataTable caption="التجّار" columns={columns} rows={pageRows} rowKey={(m) => m.id} onOpen={(m) => setOpen(m.id)} openKey={openId} toolbar={toolbar} empty={noMatch}
        pager={<Pager page={pageNo} total={shown.length} onPage={setPageNo} />} muted={(m) => !m.is_active}
        card={(m) => ({
          title: m.name, sub: [categoryLabel(m.category), uniName(m.university_id)].filter(Boolean).join(' · '), end: <MerchantState on={m.is_active} />,
          fields: [['الهاتف', m.phone ? <Ltr>{phoneText(m.phone)}</Ltr> : '—'], ['العروض', offersText(m.offers)]],
        })} />
      <PhoneBar>{React.cloneElement(addButton, { full: true })}</PhoneBar>
      {panel}
      {confirm}
    </Page>
  );
};
