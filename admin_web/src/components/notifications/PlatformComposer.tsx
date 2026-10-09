import React, { useRef, useState } from 'react';
import { CalendarClock, Megaphone, Send } from 'lucide-react';
import { notify } from '../../lib/toasts';
import {
  draftProblem, emptyDraft, idempotencyKeyFor, isDirty, platformAudience, platformCompanyIds, type NotificationDraft,
  type PlatformPreview,
} from '../../lib/notifications';
import { CAIRO_LABEL, cairoLocalToIso, cairoToday, formatCairo } from '../../lib/time';
import { awaitPlatformHistory, platformComposeNotification, usePlatformPreview } from '../../lib/notificationsData';
import { usePlatformCompanies, type CompanyOption } from '../../lib/reference';
import { NotificationForm } from './NotificationForm';
import { PhonePreview } from './PhonePreview';
import { AudiencePreviewCard, ConfirmDialog, labelClass } from './parts';

const pill = (on: boolean) => `rounded-full px-3 py-1.5 text-xs font-bold transition disabled:opacity-50 ${
  on ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`;

interface PickerProps {
  all: boolean;
  selected: string[];
  onChange: (all: boolean, selected: string[]) => void;
  companies: CompanyOption[];
  loading: boolean;
  disabled: boolean;
}

/** Every active company, or the ones ticked. Only the choice leaves the page; the server works out the people. */
const CompanyPicker: React.FC<PickerProps> = ({ all, selected, onChange, companies, loading, disabled }) => {
  const toggle = (id: string) => onChange(false, selected.includes(id) ? selected.filter((item) => item !== id) : [...selected, id]);
  return (
    <div>
      <span className={labelClass}>يصل إلى</span>
      <div className="mt-1 flex flex-wrap gap-2">
        <button type="button" disabled={disabled} aria-pressed={all} onClick={() => onChange(true, selected)} className={pill(all)}>
          كل الشركات المفعّلة
        </button>
        <button type="button" disabled={disabled} aria-pressed={!all} onClick={() => onChange(false, selected)} className={pill(!all)}>
          شركات محددة{!all && selected.length ? ` (${selected.length})` : ''}
        </button>
      </div>
      {!all && (
        <div className="mt-3 rounded-xl border border-slate-200">
          <div className="flex items-center justify-between gap-2 border-b border-slate-100 px-3 py-1.5 text-[11px] font-bold">
            <span className="text-slate-500">{selected.length} من {companies.length} شركة</span>
            <span className="flex gap-3">
              <button type="button" disabled={disabled} className="text-blue-700 disabled:opacity-50"
                onClick={() => onChange(false, companies.map((company) => company.id))}>تحديد الكل</button>
              <button type="button" disabled={disabled || !selected.length} className="text-slate-500 disabled:opacity-50"
                onClick={() => onChange(false, [])}>مسح</button>
            </span>
          </div>
          <div className="grid max-h-44 grid-cols-1 gap-x-4 overflow-y-auto p-2 sm:grid-cols-2">
            {companies.map((company) => (
              <label key={company.id} className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm text-slate-700 hover:bg-slate-50">
                <input type="checkbox" checked={selected.includes(company.id)} disabled={disabled} onChange={() => toggle(company.id)} />
                <span className="truncate">{company.name}</span>
              </label>
            ))}
            {companies.length === 0 && (
              <p className="p-2 text-xs text-slate-500">{loading ? 'جاري التحميل…' : 'لا توجد شركات مفعّلة.'}</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
};

/**
 * A notification from the platform to the students of every active company, or
 * of the chosen ones. The server counts who would get it before anything is
 * sent, and creates one notification per company.
 */
export const PlatformComposer: React.FC = () => {
  const [today] = useState(() => cairoToday());
  const [draft, setDraft] = useState<NotificationDraft>(() => emptyDraft(today));
  const [all, setAll] = useState(true);
  const [selected, setSelected] = useState<string[]>([]);
  // The audience as it was counted when the admin pressed send: what the confirmation restates.
  const [confirming, setConfirming] = useState<PlatformPreview | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const inFlight = useRef(false);

  // One key per notification being written: a retry or a double click repeats
  // it, so the server sends once. A clean form (after a success) has none.
  const idempotencyKey = useRef<string | null>(null);
  idempotencyKey.current = idempotencyKeyFor(idempotencyKey.current, isDirty(draft));

  const lookup = usePlatformCompanies();
  // Before the lookup says which are active, none is hidden; the server refuses the ones it will not send to.
  const companies = (lookup.data ?? []).filter((company) => (company.status ?? 'active') === 'active');
  const preview = usePlatformPreview(all, selected);

  const problem = draftProblem(draft) || (!all && selected.length === 0 ? 'اختر شركة واحدة على الأقل.' : '');
  const students = preview.status === 'ready' ? preview.data?.students ?? 0 : 0;
  const canSend = !problem && preview.status === 'ready' && students > 0;
  const scheduled = draft.when === 'later';
  const scheduledIso = scheduled ? cairoLocalToIso(draft.scheduledLocal) : null;

  const change = (next: NotificationDraft) => { setDraft(next); setError(''); };

  const send = async () => {
    if (inFlight.current) return;
    // The minutes spent on the confirmation may have carried a scheduled time into the past.
    const late = draftProblem(draft);
    if (late || !idempotencyKey.current) { setError(late || 'أكمل بيانات الإشعار.'); return; }
    inFlight.current = true;
    setBusy(true);
    setError('');
    try {
      const result = await platformComposeNotification({
        title: draft.title.trim(), body: draft.body.trim(), companyIds: platformCompanyIds(all, selected),
        scheduledAt: scheduledIso, idempotencyKey: idempotencyKey.current, priority: draft.priority,
      });
      // `duplicate` means an earlier attempt with this key already went through: the same success, said once.
      notify(result.status === 'scheduled'
        ? { title: 'تمت جدولة الإشعار', body: `يُرسل إلى طلاب ${result.companies} شركة في موعده.` }
        : { title: 'تم إرسال الإشعار', body: `أُضيف إلى إشعارات ${result.students} طالب في ${result.companies} شركة داخل التطبيق.` });
      idempotencyKey.current = null;
      setDraft(emptyDraft(today));
      setConfirming(null);
      awaitPlatformHistory();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'تعذر إرسال الإشعار.');
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  };

  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
      <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
        <Megaphone className="h-4 w-4 text-blue-600" />
        إشعار جديد من المنصة
      </h2>
      <form className="mt-4 grid grid-cols-1 gap-6 lg:grid-cols-3"
        onSubmit={(e) => { e.preventDefault(); if (canSend && preview.data) { setError(''); setConfirming(preview.data); } }}>
        <div className="space-y-4 lg:col-span-2">
          <NotificationForm draft={draft} onChange={change} today={today} disabled={busy}
            audience={(
              <CompanyPicker all={all} selected={selected} companies={companies} loading={lookup.loading} disabled={busy}
                onChange={(nextAll, nextSelected) => { setAll(nextAll); setSelected(nextSelected); setError(''); }} />
            )} />
          {lookup.error && <p role="alert" className="text-xs text-rose-600">تعذر تحميل الشركات: {lookup.error}</p>}
          {error && !confirming && <p role="alert" className="rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
        </div>

        <div className="space-y-4">
          <PhonePreview title={draft.title} body={draft.body} high={draft.priority === 'high'} />
          <AudiencePreviewCard hint="اختر شركة واحدة على الأقل."
            preview={{ ...preview, data: preview.data && platformAudience(preview.data, all, selected.length) }} />
          <button type="submit" disabled={busy || !canSend}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50">
            {scheduled ? <CalendarClock className="h-4 w-4" /> : <Send className="h-4 w-4" />}
            {scheduled ? 'جدولة الإشعار' : 'إرسال الإشعار'}
          </button>
          {!canSend && isDirty(draft) && problem && <p className="text-center text-xs text-slate-500">{problem}</p>}
        </div>
      </form>

      {confirming && (
        <ConfirmDialog title={scheduled ? 'تأكيد جدولة الإشعار' : 'تأكيد إرسال الإشعار'} busy={busy} error={error}
          confirmLabel={scheduled ? 'جدولة' : `إرسال إلى ${confirming.students} طالب`}
          onConfirm={() => void send()} onClose={() => { setConfirming(null); setError(''); }}>
          <p>
            {scheduled ? 'سيُرسل هذا الإشعار إلى ' : 'سيُرسل هذا الإشعار الآن إلى '}
            <b>{confirming.students} طالب</b> في <b>{confirming.companies} شركة</b>
            {all ? ' (كل الشركات المفعّلة التي بها مستلمون)' : ` (من ${selected.length} شركة مختارة)`}
            {confirming.supervisors ? `، ومعهم ${confirming.supervisors} مشرف` : ''}.
            {' '}الأجهزة المسجّلة لديهم: {confirming.devices}.
          </p>
          <p className="text-xs text-slate-500">يُنشأ إشعار مستقل لكل شركة، والشركة التي لا يوجد بها من يستلمه تُتخطى.</p>
          {scheduled && scheduledIso && (
            <p>موعد الإرسال: <b>{formatCairo(scheduledIso, true)}</b> {CAIRO_LABEL}.</p>
          )}
          <div className="rounded-2xl bg-slate-50 p-3">
            <p className="font-bold text-slate-800">{draft.title.trim()}</p>
            <p className="mt-1 whitespace-pre-line text-slate-600">{draft.body.trim()}</p>
          </div>
          {draft.priority === 'high' && <p className="text-xs font-bold text-amber-700">أولوية عالية.</p>}
        </ConfirmDialog>
      )}
    </div>
  );
};
