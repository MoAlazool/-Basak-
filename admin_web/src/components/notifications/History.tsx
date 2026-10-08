import React, { useMemo, useState } from 'react';
import { Bell, Bus, CalendarClock, Cog, Eye, PencilLine, RefreshCw, Search, Trash2, Users, XCircle } from 'lucide-react';
import { Refreshing, SkeletonRows } from '../Skeleton';
import {
  CAIRO_LABEL, STATUS_FILTERS, formatCairo, percent, pushStatParts, senderLabel, statusClass, statusLabel, typeLabel,
  type HistoryRow, type StatusFilter,
} from '../../lib/notifications';
import { useNotificationActions, type useNotificationHistory } from '../../lib/notificationsData';
import { EditScheduledDialog } from './EditScheduledDialog';
import { NotificationDetails } from './NotificationDetails';
import { ConfirmDialog } from './parts';

const SENDER_STYLE: Record<string, { icon: typeof Bell; className: string; chip: string }> = {
  admin: { icon: Bell, className: 'bg-blue-50 text-blue-600', chip: 'bg-blue-50 text-blue-700' },
  supervisor: { icon: Bus, className: 'bg-emerald-50 text-emerald-600', chip: 'bg-emerald-50 text-emerald-700' },
  system: { icon: Cog, className: 'bg-slate-100 text-slate-500', chip: 'bg-slate-100 text-slate-600' },
};

const chipClass = 'rounded-full px-2 py-0.5';

interface RowProps {
  row: HistoryRow;
  onDetails: () => void;
  onEdit: () => void;
  onCancel: () => void;
  onDelete: () => void;
}

const Row: React.FC<RowProps> = ({ row, onDetails, onEdit, onCancel, onDelete }) => {
  const style = SENDER_STYLE[row.sender_role] ?? SENDER_STYLE.admin;
  const Icon = row.status === 'scheduled' ? CalendarClock : style.icon;
  // What the system sends by itself is shown as it happened, with nothing to edit.
  const manual = row.sender_role !== 'system';
  const share = percent(row.read, row.students);
  return (
    <li className="flex gap-4 p-4">
      <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${style.className}`}>
        <Icon className="h-5 w-5" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h3 className="font-bold text-slate-800">{row.title}</h3>
          <span className="text-xs text-slate-400">{formatCairo(row.sent_at || row.created_at)}</span>
        </div>
        <p className="mt-1 line-clamp-2 whitespace-pre-line text-sm text-slate-600">{row.body}</p>
        <div className="mt-2 flex flex-wrap items-center gap-2 text-[11px] font-bold">
          {row.status !== 'sent' && <span className={`${chipClass} ${statusClass(row.status)}`}>{statusLabel(row.status)}</span>}
          <span className={`${chipClass} bg-indigo-50 text-indigo-700`}>{typeLabel(row.type, row.category)}</span>
          <span className={`${chipClass} ${style.chip}`}>{senderLabel(row.sender_role, row.sender_name)}</span>
          {row.audience && (
            <span className={`${chipClass} flex items-center gap-1 bg-slate-100 text-slate-600`}><Users className="h-3 w-3" />{row.audience}</span>
          )}
          {row.priority === 'high' && <span className={`${chipClass} bg-amber-50 text-amber-700`}>أولوية عالية</span>}
        </div>

        {row.status === 'scheduled' && row.scheduled_at && (
          <p className="mt-2 text-xs text-slate-600">يُرسل {formatCairo(row.scheduled_at, true)} {CAIRO_LABEL}</p>
        )}
        {(row.status === 'failed' || row.status === 'cancelled') && row.status_note && (
          <p className="mt-2 text-xs text-slate-500">{row.status_note}</p>
        )}
        {row.status === 'sent' && (
          <div className="mt-2 space-y-1 text-[11px] text-slate-500">
            <div className="flex flex-wrap items-center gap-2">
              <div className="h-1.5 w-24 overflow-hidden rounded-full bg-slate-100">
                <div className="h-full rounded-full bg-emerald-500" style={{ width: `${share}%` }} />
              </div>
              <span>المستلمون {row.students} · قرأه {row.read} · فتحه من الإشعار الفوري {row.opened}</span>
            </div>
            <p>
              <span className="font-bold text-slate-600">الإشعارات الفورية: </span>
              {pushStatParts(row.push).map((part) => `${part.value} ${part.key === 'skipped' ? 'لم تُرسل' : part.label}`).join(' · ')}
            </p>
          </div>
        )}
      </div>

      <div className="flex shrink-0 items-start gap-1 self-start">
        <button type="button" onClick={onDetails} title="التفاصيل" aria-label="التفاصيل"
          className="rounded-lg p-1.5 text-slate-400 transition hover:bg-slate-50 hover:text-blue-600"><Eye className="h-4 w-4" /></button>
        {manual && row.status === 'scheduled' && (
          <>
            <button type="button" onClick={onEdit} title="تعديل" aria-label="تعديل"
              className="rounded-lg p-1.5 text-slate-400 transition hover:bg-slate-50 hover:text-blue-600"><PencilLine className="h-4 w-4" /></button>
            <button type="button" onClick={onCancel} title="إلغاء الإرسال" aria-label="إلغاء الإرسال"
              className="rounded-lg p-1.5 text-rose-400 transition hover:bg-rose-50 hover:text-rose-600"><XCircle className="h-4 w-4" /></button>
          </>
        )}
        {manual && row.status !== 'scheduled' && (
          <button type="button" onClick={onDelete} title="حذف الإشعار" aria-label="حذف الإشعار"
            className="rounded-lg p-1.5 text-rose-400 transition hover:bg-rose-50 hover:text-rose-600"><Trash2 className="h-4 w-4" /></button>
        )}
      </div>
    </li>
  );
};

interface Props {
  companyId: string;
  filter: StatusFilter;
  onFilter: (filter: StatusFilter) => void;
  history: ReturnType<typeof useNotificationHistory>;
}

type Open = { kind: 'details' | 'edit' | 'cancel' | 'delete'; row: HistoryRow };

/**
 * What was sent, what waits for its time, and what was cancelled or failed,
 * a page at a time. The numbers are the server's; a live change refreshes them.
 */
export const History: React.FC<Props> = ({ companyId, filter, onFilter, history }) => {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState<Open | null>(null);
  const [error, setError] = useState('');
  const actions = useNotificationActions(companyId);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return history.rows;
    return history.rows.filter((row) => [row.title, row.body, row.sender_name, row.audience]
      .some((field) => (field || '').toLowerCase().includes(q)));
  }, [history.rows, query]);

  // The row leaves (or changes) at once; a refusal puts it back and says why, in the server's words.
  const act = (run: (id: string) => Promise<void>) => {
    if (!open) return;
    const { row } = open;
    setOpen(null);
    setError('');
    run(row.id).catch((err: unknown) => setError(err instanceof Error ? err.message : 'تعذر تنفيذ الطلب.'));
  };

  // The details follow the live row, so a refresh updates the numbers on screen.
  const openRow = open ? history.rows.find((row) => row.id === open.row.id) ?? open.row : null;

  return (
    <div className="rounded-2xl border border-slate-100 bg-white shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 p-4">
        <div className="flex flex-wrap items-center gap-2">
          {STATUS_FILTERS.map((item) => (
            <button key={item.key} type="button" onClick={() => onFilter(item.key)} aria-pressed={filter === item.key}
              className={`rounded-full px-3 py-1 text-xs font-bold transition ${
                filter === item.key ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
              {item.label}
            </button>
          ))}
          <Refreshing active={history.refreshing} />
        </div>
        <div className="flex w-full items-center gap-2 sm:w-auto">
          <div className="relative flex-1 sm:w-64">
            <Search className="absolute right-3 top-2.5 h-4 w-4 text-slate-400" />
            <input type="search" placeholder="ابحث في الإشعارات المعروضة" value={query} onChange={(e) => setQuery(e.target.value)}
              className="w-full rounded-xl border border-slate-200 py-2 pl-3 pr-9 text-sm focus:border-blue-500 focus:outline-none" />
          </div>
          <button type="button" onClick={history.reload} title="تحديث" aria-label="تحديث"
            className="rounded-xl border border-slate-200 p-2 text-slate-500 transition hover:bg-slate-50">
            <RefreshCw className="h-4 w-4" />
          </button>
        </div>
      </div>

      {error && (
        <div role="alert" className="flex items-start justify-between gap-3 border-b border-rose-100 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          <span>{error}</span>
          <button type="button" className="font-bold underline" onClick={() => setError('')}>إخفاء</button>
        </div>
      )}
      {history.error && (
        <div role="alert" className="border-b border-rose-100 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          تعذر تحميل الإشعارات: {history.error}
          <button type="button" className="mr-3 font-bold underline" onClick={history.reload}>إعادة المحاولة</button>
        </div>
      )}

      {history.loading ? (
        <SkeletonRows rows={5} />
      ) : shown.length === 0 ? (
        !history.error && (
          <div className="p-8 text-center text-slate-500">
            {history.rows.length > 0 ? 'لا يوجد إشعار يطابق البحث فيما عُرض.'
              : filter === 'all' ? 'لم يُرسل أي إشعار بعد.' : 'لا توجد إشعارات بهذه الحالة.'}
          </div>
        )
      ) : (
        <ul className="divide-y divide-slate-100">
          {shown.map((row) => (
            <Row key={row.id} row={row}
              onDetails={() => setOpen({ kind: 'details', row })} onEdit={() => setOpen({ kind: 'edit', row })}
              onCancel={() => setOpen({ kind: 'cancel', row })} onDelete={() => setOpen({ kind: 'delete', row })} />
          ))}
        </ul>
      )}

      {history.hasMore && !history.loading && (
        <div className="border-t border-slate-100 p-3 text-center">
          <button type="button" onClick={history.loadMore} disabled={history.loadingMore}
            className="rounded-xl bg-slate-100 px-5 py-2 text-sm font-bold text-slate-600 transition hover:bg-slate-200 disabled:opacity-50">
            {history.loadingMore ? 'جاري التحميل…' : 'عرض المزيد'}
          </button>
        </div>
      )}

      {open?.kind === 'details' && openRow && (
        <NotificationDetails row={openRow} pushConfigured={history.pushConfigured} onClose={() => setOpen(null)} />
      )}
      {open?.kind === 'edit' && <EditScheduledDialog companyId={companyId} row={open.row} onClose={() => setOpen(null)} />}
      {open?.kind === 'cancel' && (
        <ConfirmDialog danger title="إلغاء الإشعار المجدول" confirmLabel="إلغاء الإرسال"
          onConfirm={() => act(actions.cancel)} onClose={() => setOpen(null)}>
          <p>
            لن يُرسل الإشعار «<b>{open.row.title}</b>»{open.row.audience ? <> إلى {open.row.audience}</> : null}
            {open.row.scheduled_at ? <> في موعده ({formatCairo(open.row.scheduled_at, true)} {CAIRO_LABEL})</> : null}. يبقى في السجل كإشعار ملغى.
          </p>
        </ConfirmDialog>
      )}
      {open?.kind === 'delete' && (
        <ConfirmDialog danger title="حذف الإشعار" confirmLabel="حذف"
          onConfirm={() => act(actions.remove)} onClose={() => setOpen(null)}>
          <p>حذف الإشعار «<b>{open.row.title}</b>»؟ سيختفي من عند كل الطلاب والمشرفين.</p>
        </ConfirmDialog>
      )}
    </div>
  );
};
