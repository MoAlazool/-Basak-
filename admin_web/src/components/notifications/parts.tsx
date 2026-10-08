import React from 'react';
import { Smartphone, UserCheck, Users } from 'lucide-react';
import { Skeleton } from '../Skeleton';
import type { AudiencePreviewState } from '../../lib/notificationsData';

export const fieldClass = 'mt-1 w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none disabled:bg-slate-50';
export const labelClass = 'text-xs font-semibold text-slate-500';

/** A centred dialog over the page, like the other dialogs of the dashboard. */
export const Dialog: React.FC<{ title: React.ReactNode; onClose: () => void; wide?: boolean; children: React.ReactNode }> = ({ title, onClose, wide, children }) => (
  <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4" dir="rtl" role="dialog" aria-modal="true"
    onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}>
    <div className={`max-h-[92vh] w-full overflow-y-auto rounded-3xl bg-white p-6 shadow-2xl ${wide ? 'max-w-3xl' : 'max-w-lg'}`}>
      <div className="mb-4 text-lg font-bold text-slate-800">{title}</div>
      {children}
    </div>
  </div>
);

interface ConfirmProps {
  title: string;
  confirmLabel: string;
  busy?: boolean;
  danger?: boolean;
  error?: string;
  onConfirm: () => void;
  onClose: () => void;
  children: React.ReactNode;
}

/** One question with its consequence spelled out, before anything is sent or removed. */
export const ConfirmDialog: React.FC<ConfirmProps> = ({ title, confirmLabel, busy, danger, error, onConfirm, onClose, children }) => (
  <Dialog title={title} onClose={() => { if (!busy) onClose(); }}>
    <div className="space-y-3 text-sm leading-relaxed text-slate-700">{children}</div>
    {error && <p role="alert" className="mt-3 rounded-xl bg-rose-50 p-3 text-sm text-rose-700">{error}</p>}
    <div className="mt-5 flex justify-end gap-2">
      <button type="button" onClick={onClose} disabled={busy}
        className="rounded-xl bg-slate-100 px-4 py-2 text-sm font-bold text-slate-600 transition hover:bg-slate-200 disabled:opacity-50">
        رجوع
      </button>
      <button type="button" onClick={onConfirm} disabled={busy}
        className={`rounded-xl px-5 py-2 text-sm font-bold text-white transition disabled:opacity-50 ${
          danger ? 'bg-rose-600 hover:bg-rose-700' : 'bg-blue-600 hover:bg-blue-700'}`}>
        {busy ? 'لحظة…' : confirmLabel}
      </button>
    </div>
  </Dialog>
);

/** Who would receive the notification, as the server counts them right now. */
export const AudiencePreviewCard: React.FC<{ preview: AudiencePreviewState; hint?: string }> = ({ preview, hint }) => (
  <div className="rounded-2xl border border-slate-100 bg-slate-50/70 p-4" aria-live="polite">
    <p className={labelClass}>من سيصله الإشعار</p>
    {preview.status === 'incomplete' && <p className="mt-2 text-sm text-slate-500">{hint || 'أكمل اختيار المستلمين.'}</p>}
    {preview.status === 'loading' && (
      <div className="mt-2 space-y-2" aria-busy="true" aria-label="جاري التحميل">
        <Skeleton className="h-4 w-3/5" /><Skeleton className="h-3.5 w-4/5" />
      </div>
    )}
    {preview.status === 'error' && (
      <p role="alert" className="mt-2 text-sm text-rose-700">{preview.error || 'تعذر حساب المستلمين.'}</p>
    )}
    {preview.status === 'ready' && preview.data && (
      <>
        <p className="mt-1.5 text-sm font-bold text-slate-800">{preview.data.label}</p>
        <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600">
          <span className="flex items-center gap-1"><Users className="h-3.5 w-3.5 text-blue-600" />{preview.data.students} طالب</span>
          <span className="flex items-center gap-1"><UserCheck className="h-3.5 w-3.5 text-emerald-600" />{preview.data.supervisors} مشرف</span>
          <span className="flex items-center gap-1"><Smartphone className="h-3.5 w-3.5 text-slate-500" />{preview.data.devices} جهاز مسجّل</span>
        </div>
        {preview.data.students === 0 && (
          <p className="mt-2 text-xs font-bold text-amber-700">لا يوجد طلاب في هذا الاختيار، فلن يصل الإشعار إلى أحد.</p>
        )}
      </>
    )}
  </div>
);
