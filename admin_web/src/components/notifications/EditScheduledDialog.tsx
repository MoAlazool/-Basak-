import React, { useState } from 'react';
import {
  audienceFromSpec, audienceToPayload, cairoLocalToIso, cairoToday, draftProblem, isoToCairoLocal,
  type HistoryRow, type NotificationDraft,
} from '../../lib/notifications';
import { updateScheduledNotification, useAudienceOptions, useAudiencePreview, useNotificationActions } from '../../lib/notificationsData';
import { notify } from '../../lib/toasts';
import { NotificationForm } from './NotificationForm';
import { AudiencePreviewCard, Dialog } from './parts';

/** A scheduled notification before it goes out: its words, its audience and its time can still change. */
export const EditScheduledDialog: React.FC<{ companyId: string; row: HistoryRow; onClose: () => void }> = ({ companyId, row, onClose }) => {
  const [today] = useState(() => cairoToday());
  const [draft, setDraft] = useState<NotificationDraft>(() => ({
    title: row.title, body: row.body, audience: audienceFromSpec(row.audience_spec, today),
    priority: row.priority === 'high' ? 'high' : 'normal', when: 'later',
    scheduledLocal: row.scheduled_at ? isoToCairoLocal(row.scheduled_at) : '',
  }));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const options = useAudienceOptions(companyId);
  const audience = audienceToPayload(draft.audience);
  const preview = useAudiencePreview(companyId, audience);
  const { refresh } = useNotificationActions(companyId);

  const problem = draftProblem(draft);
  const students = preview.status === 'ready' ? preview.data?.students ?? 0 : 0;
  const canSave = !problem && preview.status === 'ready' && students > 0;

  const save = async () => {
    const scheduledAt = cairoLocalToIso(draft.scheduledLocal);
    const late = draftProblem(draft);
    if (busy || late || !audience || !scheduledAt) { if (late) setError(late); return; }
    setBusy(true);
    setError('');
    try {
      await updateScheduledNotification({ id: row.id, title: draft.title.trim(), body: draft.body.trim(), audience, scheduledAt });
      notify({ title: 'تم حفظ تعديل الإشعار المجدول' });
      void refresh();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'تعذر حفظ التعديل.');
      setBusy(false);
    }
  };

  return (
    <Dialog wide title="تعديل إشعار مجدول" onClose={() => { if (!busy) onClose(); }}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); if (canSave) void save(); }}>
        {!row.audience_spec && (
          <p className="rounded-xl bg-amber-50 p-3 text-xs font-bold text-amber-700">
            تعذر قراءة المستلمين المحفوظين لهذا الإشعار ({row.audience || 'غير معروف'}). اخترهم من جديد قبل الحفظ.
          </p>
        )}
        <NotificationForm draft={draft} onChange={(next) => { setDraft(next); setError(''); }} lines={options.data?.lines ?? []}
          universities={options.data?.universities ?? []} optionsLoading={options.loading} today={today} scheduledOnly disabled={busy} />
        <AudiencePreviewCard preview={preview} />
        {(error || problem) && (
          <p role={error ? 'alert' : undefined} className={`text-sm ${error ? 'rounded-xl bg-rose-50 p-3 text-rose-700' : 'text-xs text-slate-500'}`}>
            {error || problem}
          </p>
        )}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} disabled={busy}
            className="rounded-xl bg-slate-100 px-4 py-2 text-sm font-bold text-slate-600 transition hover:bg-slate-200 disabled:opacity-50">
            رجوع
          </button>
          <button type="submit" disabled={busy || !canSave}
            className="rounded-xl bg-blue-600 px-5 py-2 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50">
            {busy ? 'جاري الحفظ…' : canSave ? `حفظ · ${students} طالب` : 'حفظ التعديل'}
          </button>
        </div>
      </form>
    </Dialog>
  );
};
