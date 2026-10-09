import React, { useRef, useState } from 'react';
import { CalendarClock, Megaphone, Send } from 'lucide-react';
import { notify } from '../../lib/toasts';
import {
  audienceToPayload, draftProblem, emptyDraft, idempotencyKeyFor, isDirty, type AudiencePreview, type NotificationDraft,
} from '../../lib/notifications';
import { CAIRO_LABEL, cairoLocalToIso, cairoToday, formatCairo } from '../../lib/time';
import { composeNotification, useAudiencePreview, useNotificationActions } from '../../lib/notificationsData';
import { useLineOptions } from '../../lib/reference';
import { NotificationForm } from './NotificationForm';
import { PhonePreview } from './PhonePreview';
import { AudiencePreviewCard, ConfirmDialog } from './parts';

/** Ready-made messages: [button, title, text]. */
const TEMPLATES: [string, string, string][] = [
  ['إجازة رسمية', 'إجازة رسمية', 'غداً إجازة رسمية ولا توجد رحلات. تعود الرحلات في مواعيدها بعد الإجازة.'],
  ['تعديل المواعيد', 'تعديل مواعيد الرحلات', 'تم تعديل مواعيد بعض الرحلات، راجع مواعيدك في التطبيق قبل التصويت.'],
  ['تذكير بالدفع', 'تذكير بسداد الاشتراك', 'اقترب موعد سداد الاشتراك. ادفع من صفحة الاشتراك في التطبيق لتستمر رحلاتك.'],
];

/**
 * A new notification: what it says, who gets it (counted by the server before
 * anything is sent), and whether it goes now or at a set Cairo time.
 */
export const Composer: React.FC<{ companyId: string }> = ({ companyId }) => {
  const [today] = useState(() => cairoToday());
  const [draft, setDraft] = useState<NotificationDraft>(() => emptyDraft(today));
  // The audience as it was counted when the admin pressed send: what the confirmation restates.
  const [confirming, setConfirming] = useState<AudiencePreview | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const inFlight = useRef(false);

  // One key per notification being written: a retry or a double click repeats
  // it, so the server sends once. A clean form (after a success) has none.
  const idempotencyKey = useRef<string | null>(null);
  idempotencyKey.current = idempotencyKeyFor(idempotencyKey.current, isDirty(draft));

  // The lines (with their trips) and universities the audience is chosen from: the cache other pages already fill.
  const options = useLineOptions(companyId);
  const audience = audienceToPayload(draft.audience);
  const preview = useAudiencePreview(companyId, audience);
  const { refresh } = useNotificationActions(companyId);

  const problem = draftProblem(draft);
  const students = preview.status === 'ready' ? preview.data?.students ?? 0 : 0;
  const canSend = !problem && preview.status === 'ready' && students > 0;
  const scheduled = draft.when === 'later';
  const scheduledIso = scheduled ? cairoLocalToIso(draft.scheduledLocal) : null;

  const change = (next: NotificationDraft) => { setDraft(next); setError(''); };

  const send = async () => {
    if (inFlight.current) return;
    // The minutes spent on the confirmation may have carried a scheduled time into the past.
    const late = draftProblem(draft);
    if (late || !audience || !idempotencyKey.current) { setError(late || 'أكمل بيانات الإشعار.'); return; }
    inFlight.current = true;
    setBusy(true);
    setError('');
    try {
      const result = await composeNotification(companyId, {
        title: draft.title.trim(), body: draft.body.trim(), audience,
        scheduledAt: scheduledIso, idempotencyKey: idempotencyKey.current, priority: draft.priority,
      });
      // `duplicate` means an earlier attempt with this key already went through: the same success, said once.
      notify(result.status === 'scheduled'
        ? { title: 'تمت جدولة الإشعار', body: `يُرسل إلى ${confirming?.label ?? 'المستلمين'} في موعده.` }
        : { title: 'تم إرسال الإشعار', body: `أُضيف إلى إشعارات ${result.students} طالب داخل التطبيق.` });
      idempotencyKey.current = null;
      setDraft(emptyDraft(today));
      setConfirming(null);
      void refresh(result.id);
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
        إشعار جديد
      </h2>
      <form className="mt-4 grid grid-cols-1 gap-6 lg:grid-cols-3"
        onSubmit={(e) => { e.preventDefault(); if (canSend && preview.data) { setError(''); setConfirming(preview.data); } }}>
        <div className="space-y-4 lg:col-span-2">
          <NotificationForm draft={draft} onChange={change} lines={options.data?.lines ?? []}
            universities={options.data?.universities ?? []} optionsLoading={options.loading} today={today} disabled={busy} />
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold text-slate-500">رسائل جاهزة:</span>
            {TEMPLATES.map(([label, title, body]) => (
              <button key={label} type="button" disabled={busy} onClick={() => change({ ...draft, title, body })}
                className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700 transition hover:bg-blue-100 disabled:opacity-50">
                {label}
              </button>
            ))}
          </div>
          {options.error && <p role="alert" className="text-xs text-rose-600">تعذر تحميل الخطوط والجامعات: {options.error}</p>}
          {error && !confirming && <p role="alert" className="rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
        </div>

        <div className="space-y-4">
          <PhonePreview title={draft.title} body={draft.body} high={draft.priority === 'high'} />
          <AudiencePreviewCard preview={preview} />
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
            <b>{confirming.label}</b> ({confirming.students} طالب{confirming.supervisors ? ` و${confirming.supervisors} مشرف` : ''}).
          </p>
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
