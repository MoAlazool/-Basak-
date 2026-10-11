import React, { useMemo, useState } from 'react';
import {
  PLATFORM_ANNOUNCEMENT, STATUS_FILTERS, senderShort, studentsText, whenLabel, type HistoryRow, type StatusFilter,
} from '../../lib/notifications';
import { CAIRO_LABEL } from '../../lib/time';
import type { HistoryActions, HistoryState } from '../../lib/notificationsData';
import { useGuard } from '../../lib/guard';
import type { CompanyBrand } from '../../lib/branding';
import { Badge, Button, Chips, DataTable, EmptyState, ErrorState, IconButton, Menu, SearchBox, SkeletonTable, STATE, StatePill, Toolbar, errorText, type Column } from '../../ui';
import { ExportButton } from '../../ui/Transfer';
import { exportSheet } from '../../lib/excel';
import { excelMoment, MOMENT_FORMAT } from '../../lib/excelCells';
import { notifyError } from '../../lib/toasts';
import { CompanyMark } from '../CompanyMark';
import { EditScheduledDialog } from './EditScheduledDialog';
import { NotificationDetails } from './NotificationDetails';
import { ConfirmDialog } from './parts';

interface Props {
  /** The company whose scheduled notifications can be edited here; absent in the platform's history. */
  companyId?: string;
  filter: StatusFilter;
  onFilter: (filter: StatusFilter) => void;
  history: HistoryState;
  actions: HistoryActions;
  /** More filters, beside the status ones. */
  filters?: React.ReactNode;
  /** Every company's marks by id: the platform's history shows who sent each notification. */
  brands?: Record<string, CompanyBrand>;
  /** The admin reading (their own notifications say «أنت»). */
  me?: string | null;
  /** The empty list's button: «اكتب أول إشعار». */
  onNew?: () => void;
  /** Every notification of the current status filter (all pages), for «تصدير Excel». */
  loadAll?: () => Promise<HistoryRow[]>;
}

type Open = { kind: 'details' | 'edit' | 'cancel' | 'delete'; row: HistoryRow };

const at = (r: HistoryRow) => r.sent_at ?? r.scheduled_at ?? r.created_at;
const EMPTY: Record<StatusFilter, [string, string]> = {
  all: ['لم يُرسل أي إشعار بعد', 'أخبر طلابك بإجازة، أو بتعديل في المواعيد، أو ذكّرهم بالدفع. تختار من يصله، وترى كم طالباً قرأه.'],
  sent: ['لا إشعارات مُرسلة', 'ما ترسله يظهر هنا مع عدد من قرأه.'],
  scheduled: ['لا إشعارات مجدولة', 'الإشعار الذي تختار له موعداً لاحقاً يظهر هنا حتى يُرسل.'],
  cancelled: ['لا إشعارات ملغاة', 'الإشعار المجدول الذي تلغيه قبل موعده يظهر هنا.'],
  failed: ['لا إشعارات فاشلة', 'إن تعذّر إرسال إشعار يظهر هنا مع السبب.'],
};

const ReadCell: React.FC<{ r: HistoryRow }> = ({ r }) => (r.status !== 'sent' ? <span className="text-ink-3">—</span> : (
  <div className="flex flex-col gap-1">
    <span className="whitespace-nowrap text-small"><b className="font-semibold tabular">{r.read.toLocaleString('en-US')}</b> <span className="text-label text-ink-2">من {r.students.toLocaleString('en-US')}</span></span>
    <span aria-hidden="true" className="block h-1 w-[96px] overflow-hidden rounded bg-sunken"><span className="block h-1 rounded bg-ok" style={{ width: `${r.students ? Math.min(100, Math.round((r.read / r.students) * 100)) : 0}%` }} /></span>
  </div>
));
const statePill = (r: HistoryRow) => <StatePill state={r.status} />;

/**
 * «سجل الإشعارات»: what was sent, what waits for its time, and what was cancelled
 * or failed, 25 at a time. Numbers say who received and who read; the delivery
 * machinery behind the phone alerts is not shown to a company.
 */
const matchesQuery = (row: HistoryRow, query: string) => {
  const q = query.trim().toLowerCase();
  return !q || [row.title, row.body, row.sender_name, row.audience, row.company_name].some((f) => (f || '').toLowerCase().includes(q));
};

export const History: React.FC<Props> = ({ companyId, filter, onFilter, history, actions, filters, brands, me, onNew, loadAll }) => {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState<Open | null>(null);
  const shown = useMemo(() => history.rows.filter((row) => matchesQuery(row, query)), [history.rows, query]);

  // All of the filter's notifications, not only the pages read so far; the search applies to them too.
  const exportAll = async () => {
    const rows = (loadAll ? await loadAll() : history.rows).filter((row) => matchesQuery(row, query));
    await exportSheet<HistoryRow>({
      name: 'سجل الإشعارات', rows,
      columns: [
        { label: 'الإشعار', value: (r) => r.title, width: 30 },
        { label: 'النص', value: (r) => r.body, width: 50 },
        { label: 'عاجل', value: (r) => (r.priority === 'high' ? 'عاجل' : null), width: 8 },
        ...(companyId ? [] : [{ label: 'الشركة', value: (r: HistoryRow) => r.company_name, width: 22 }]),
        { label: 'إلى', value: (r) => r.audience, width: 30 },
        { label: 'المرسل', value: (r) => senderShort(r, me), width: 20 },
        { label: 'الموعد', value: (r) => excelMoment(at(r)), format: MOMENT_FORMAT, width: 18 },
        { label: 'الحالة', value: (r) => STATE[r.status][0], width: 14 },
        { label: 'وصل إلى (طالب)', value: (r) => (r.status === 'sent' ? r.students : null), width: 14 },
        { label: 'قرأه', value: (r) => (r.status === 'sent' ? r.read : null), width: 10 },
        { label: 'ملاحظة', value: (r) => r.status_note, width: 30 },
      ],
    });
  };

  // The row changes at once; a refusal puts it back and says why.
  const guard = useGuard();
  const act = (run: (id: string) => Promise<void>, row: HistoryRow) => {
    setOpen(null);
    void guard(row.id, () => run(row.id).catch((err: unknown) => notifyError('لم يتم', errorText(err))));
  };
  const openRow = open ? history.rows.find((row) => row.id === open.row.id) ?? open.row : null;
  const platform = !companyId;
  const editable = (r: HistoryRow) => r.sender_role !== 'system' && r.status === 'scheduled';
  const canEdit = (r: HistoryRow) => !!companyId && editable(r) && r.type !== PLATFORM_ANNOUNCEMENT;

  const columns: Column<HistoryRow>[] = [
    { key: 'title', label: 'الإشعار', render: (r) => (
      <div className="min-w-0">
        <div className="flex items-center gap-2"><span className="truncate font-semibold">{r.title}</span>{r.priority === 'high' && <Badge tone="danger">عاجل</Badge>}</div>
        <div className={`truncate text-cap ${r.status === 'failed' && r.status_note ? 'text-bad' : 'text-ink-3'}`}>{(r.status === 'failed' || r.status === 'cancelled') && r.status_note ? r.status_note : r.body}</div>
      </div>
    ) },
    ...(platform ? [{ key: 'company', label: 'الشركة', w: 160, render: (r: HistoryRow) => (r.company_name
      ? <span className="flex min-w-0 items-center gap-2"><CompanyMark name={r.company_name} brand={r.company_id ? brands?.[r.company_id] : undefined} size="xs" /><span className="truncate">{r.company_name}</span></span> : '—') }] : []),
    { key: 'to', label: 'إلى', w: 170, hideTablet: true, render: (r) => <span className="line-clamp-2">{r.audience ?? '—'}</span> },
    { key: 'from', label: 'المرسل', w: 130, hideTablet: true, render: (r) => <span className="line-clamp-2">{senderShort(r, me)}</span> },
    { key: 'at', label: 'الموعد', w: 170, render: (r) => <span className={`whitespace-nowrap ${r.status === 'cancelled' ? 'text-ink-3' : ''}`}>{whenLabel(at(r))}</span> },
    { key: 'read', label: 'قرأه', w: 120, render: (r) => <ReadCell r={r} /> },
    { key: 'state', label: 'الحالة', w: 120, render: statePill },
    { key: 'act', label: <span className="sr-only">إجراءات</span>, w: 128, align: 'end', render: (r) => (
      <div className="flex items-center justify-end gap-1" onClick={(e) => e.stopPropagation()}>
        {canEdit(r) && <Button sm kind="outline" onClick={() => setOpen({ kind: 'edit', row: r })}>تعديل</Button>}
        <Menu label={`إجراءات «${r.title}»`} items={[
          { label: 'التفاصيل', icon: 'eye', onClick: () => setOpen({ kind: 'details', row: r }) },
          { label: 'إلغاء الإرسال', icon: 'x', danger: true, hidden: !editable(r), onClick: () => setOpen({ kind: 'cancel', row: r }) },
          { label: 'حذف الإشعار', icon: 'trash', danger: true, hidden: r.sender_role === 'system' || r.status === 'scheduled', onClick: () => setOpen({ kind: 'delete', row: r }) },
        ]} />
      </div>
    ) },
  ];
  const card = (r: HistoryRow) => ({
    title: <span className="flex items-center gap-2">{r.title}{r.priority === 'high' && <Badge tone="danger">عاجل</Badge>}</span>,
    sub: <span className={`line-clamp-2 ${r.status === 'failed' && r.status_note ? 'text-bad' : ''}`}>{(r.status === 'failed' || r.status === 'cancelled') && r.status_note ? r.status_note : r.body}</span>,
    end: statePill(r),
    fields: [['إلى', r.audience ?? '—'], ['المرسل', senderShort(r, me)], ['الموعد', whenLabel(at(r))],
      ...(r.status === 'sent' ? [['قرأه', <span key="r"><b className="font-semibold">{r.read}</b> من {r.students}</span>]] : [])] as [React.ReactNode, React.ReactNode][],
    actions: canEdit(r) ? <><Button kind="secondary" className="!h-11" onClick={() => setOpen({ kind: 'edit', row: r })}>تعديل</Button><Button kind="outline" className="!h-11" onClick={() => setOpen({ kind: 'cancel', row: r })}>إلغاء الإرسال</Button></> : undefined,
  });
  const toolbar = (
    <Toolbar search={<SearchBox value={query} onChange={setQuery} placeholder="ابحث في الإشعارات" />}
      filters={<div className="flex items-center gap-2"><Chips<StatusFilter> value={filter} onChange={onFilter} options={STATUS_FILTERS.map((f) => ({ value: f.key, label: f.label }))} />{filters}</div>}
      actions={<>
        {history.rows.length > 0 && <ExportButton className="hidden sm:inline-flex" onExport={exportAll} />}
        <IconButton icon="refresh" label="تحديث" sm className={`hidden shadow-ring sm:inline-flex ${history.refreshing ? 'animate-spin' : ''}`} onClick={history.reload} />
      </>} />
  );
  const [eTitle, eText] = EMPTY[filter];
  const empty = history.loading ? undefined : history.error && history.rows.length === 0 ? (
    <ErrorState title="تعذّر تحميل الإشعارات" text="لم نستطع جلب السجل. تأكد من اتصالك ثم حاول مرة أخرى." onRetry={history.reload} />
  ) : shown.length === 0 ? (
    history.rows.length > 0
      ? <EmptyState icon="search" title="لا إشعار يطابق بحثك" text="البحث فيما عُرض فقط. اعرض الأقدم أو غيّر الكلمة." />
      : <EmptyState icon="megaphone" title={eTitle} text={eText} action={filter === 'all' && onNew && <Button icon="plus" onClick={onNew}>اكتب أول إشعار</Button>} />
  ) : undefined;

  if (history.loading) return <SkeletonTable rows={8} cols={6} />;
  return (
    <>
      <DataTable<HistoryRow> rows={shown} rowKey={(r) => r.id} caption="سجل الإشعارات" columns={columns} card={card} toolbar={toolbar} empty={empty}
        rowH={58} onOpen={(r) => setOpen({ kind: 'details', row: r })} openKey={open?.kind === 'details' ? open.row.id : null}
        pager={shown.length > 0 && (
          <div className="flex min-h-14 flex-col items-stretch gap-3 px-0 sm:flex-row sm:items-center sm:border-t sm:border-hair sm:px-4">
            <span className="hidden flex-1 text-label text-ink-2 sm:block">يُعرض {history.rows.length <= 25 ? `أحدث ${history.rows.length.toLocaleString('en-US')} ${history.rows.length > 10 ? 'إشعاراً' : 'إشعارات'}` : `${history.rows.length.toLocaleString('en-US')} إشعاراً`}</span>
            {history.hasMore && <Button kind="outline" sm icon="adown" className="max-sm:!h-12" loading={history.loadingMore} onClick={history.loadMore}>اعرض 25 أقدم</Button>}
          </div>
        )} />
      {/* notifications_purge (20261122000001): nothing sent is kept longer. */}
      <p className="mt-3 text-cap text-ink-3">تُحذف الإشعارات المرسلة تلقائياً بعد 7 أيام من إرسالها، وإشعارات الاشتراك التلقائية بعد 30 يوماً.</p>

      {open?.kind === 'details' && openRow && (
        <NotificationDetails row={openRow} pushConfigured={history.pushConfigured} onClose={() => setOpen(null)} showPush={platform} me={me}
          onDelete={openRow.sender_role !== 'system' && openRow.status !== 'scheduled' ? () => setOpen({ kind: 'delete', row: openRow }) : undefined}
          onCancel={editable(openRow) ? () => setOpen({ kind: 'cancel', row: openRow }) : undefined}
          onEdit={canEdit(openRow) ? () => setOpen({ kind: 'edit', row: openRow }) : undefined} />
      )}
      {open?.kind === 'edit' && companyId && (
        <EditScheduledDialog companyId={companyId} row={open.row} onClose={() => setOpen(null)} onCancelSend={() => setOpen({ kind: 'cancel', row: open.row })} />
      )}
      {open?.kind === 'cancel' && (
        <ConfirmDialog danger icon="x" title={`إلغاء إرسال «${open.row.title}»؟`} confirmLabel="إلغاء الإرسال"
          onConfirm={() => act(actions.cancel, open.row)} onClose={() => setOpen(null)}>
          <p className="m-0">لن يُرسل إلى {open.row.audience ?? 'المستلمين'}{open.row.company_name ? ` في «${open.row.company_name}»` : ''}
            {open.row.scheduled_at ? ` في موعده (${whenLabel(open.row.scheduled_at).replace(' · ', '، ')} ${CAIRO_LABEL})` : ''}. يبقى في السجل كإشعار ملغى.</p>
        </ConfirmDialog>
      )}
      {open?.kind === 'delete' && (
        <ConfirmDialog danger title={`حذف إشعار «${open.row.title}»؟`} confirmLabel="حذف الإشعار"
          onConfirm={() => act(actions.remove, open.row)} onClose={() => setOpen(null)}>
          <p className="m-0">يختفي من عند كل الطلاب والمشرفين الذين وصلهم{open.row.students ? ` (${studentsText(open.row.students)})` : ''}{open.row.company_name ? ` في «${open.row.company_name}»` : ''}، ومن هذا السجل. من قرأه لا يُمحى من ذاكرته، ولا يمكن استرجاع الإشعار.</p>
        </ConfirmDialog>
      )}
    </>
  );
};

