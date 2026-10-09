import React from 'react';
import { CalendarClock, Send } from 'lucide-react';
import type { LineOption, UniversityOption } from '../../lib/lineOptions';
import { BODY_MAX, TITLE_MAX, scheduleProblem, type NotificationDraft } from '../../lib/notifications';
import { CAIRO_LABEL, CAIRO_ZONE, cairoLocalToIso, formatCairo, isoToCairoLocal } from '../../lib/time';
import { AudiencePicker } from './AudiencePicker';
import { fieldClass, labelClass } from './parts';

interface Props {
  draft: NotificationDraft;
  onChange: (next: NotificationDraft) => void;
  lines?: LineOption[];
  universities?: UniversityOption[];
  optionsLoading?: boolean;
  /** Another way to choose who gets it (the platform's companies), in place of the company's own audience picker. */
  audience?: React.ReactNode;
  today: string;
  /** Editing a scheduled notification: it stays scheduled, and its priority is not part of the edit. */
  scheduledOnly?: boolean;
  disabled?: boolean;
}

/** The fields of a notification, shared by the composer and by the edit of a scheduled one. */
export const NotificationForm: React.FC<Props> = ({ draft, onChange, lines = [], universities = [], optionsLoading, audience, today, scheduledOnly, disabled }) => {
  const set = (patch: Partial<NotificationDraft>) => onChange({ ...draft, ...patch });
  const later = scheduledOnly || draft.when === 'later';
  const nowLocal = isoToCairoLocal(new Date());
  const timeProblem = later && draft.scheduledLocal ? scheduleProblem(draft.scheduledLocal) : '';
  const scheduledIso = later && draft.scheduledLocal ? cairoLocalToIso(draft.scheduledLocal) : null;

  return (
    <div className="space-y-4">
      {audience ?? (
        <AudiencePicker value={draft.audience} onChange={(next) => set({ audience: next })} lines={lines} universities={universities}
          today={today} loading={optionsLoading} disabled={disabled} />
      )}

      <label className="block">
        <span className={labelClass}>العنوان ({draft.title.length}/{TITLE_MAX})</span>
        <input type="text" maxLength={TITLE_MAX} placeholder="مثال: إجازة رسمية" value={draft.title} disabled={disabled}
          onChange={(e) => set({ title: e.target.value })} className={fieldClass} />
      </label>

      <label className="block">
        <span className={labelClass}>نص الإشعار ({draft.body.length}/{BODY_MAX})</span>
        <textarea maxLength={BODY_MAX} rows={4} placeholder="اكتب ما تريد أن يعرفه الطلاب" value={draft.body} disabled={disabled}
          onChange={(e) => set({ body: e.target.value })} className={fieldClass} />
      </label>

      {!scheduledOnly && (
        <label className="flex items-start gap-2 text-sm text-slate-700">
          <input type="checkbox" className="mt-1" checked={draft.priority === 'high'} disabled={disabled}
            onChange={(e) => set({ priority: e.target.checked ? 'high' : 'normal' })} />
          <span>
            <b>أولوية عالية</b>
            <span className="block text-xs text-slate-500">للأمور العاجلة فقط، مثل تغيير يخص رحلة اليوم.</span>
          </span>
        </label>
      )}

      <div>
        <span className={labelClass}>موعد الإرسال</span>
        {!scheduledOnly && (
          <div className="mt-1 flex flex-wrap gap-2">
            {([['now', 'الآن', Send], ['later', 'في موعد لاحق', CalendarClock]] as const).map(([key, label, Icon]) => (
              <button key={key} type="button" disabled={disabled} aria-pressed={draft.when === key}
                onClick={() => set({
                  when: key,
                  // A sensible start for the picker: an hour from now, Cairo time.
                  scheduledLocal: key === 'later' && !draft.scheduledLocal
                    ? isoToCairoLocal(new Date(Date.now() + 3_600_000)) : draft.scheduledLocal,
                })}
                className={`flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-bold transition disabled:opacity-50 ${
                  draft.when === key ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                <Icon className="h-3.5 w-3.5" />{label}
              </button>
            ))}
          </div>
        )}
        {later && (
          <div className="mt-2">
            <div className="flex flex-wrap items-center gap-2">
              <input type="datetime-local" dir="ltr" value={draft.scheduledLocal} min={nowLocal} disabled={disabled}
                onChange={(e) => set({ scheduledLocal: e.target.value })}
                className={`${fieldClass} mt-0 w-auto`} aria-label={`موعد الإرسال ${CAIRO_LABEL}`} />
              <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-bold text-slate-600">
                {CAIRO_LABEL} <span dir="ltr">({CAIRO_ZONE})</span>
              </span>
            </div>
            {timeProblem
              ? <p className="mt-1.5 text-xs font-bold text-rose-600">{timeProblem}</p>
              : scheduledIso && <p className="mt-1.5 text-xs text-slate-500">يُرسل {formatCairo(scheduledIso, true)} {CAIRO_LABEL}.</p>}
          </div>
        )}
      </div>
    </div>
  );
};
