import React from 'react';
import {
  CAIRO_LABEL, formatCairo, percent, pushStatParts, senderLabel, statusClass, statusLabel, typeLabel, type HistoryRow,
} from '../../lib/notifications';
import { Dialog } from './parts';

const Fact: React.FC<{ label: string; children: React.ReactNode }> = ({ label, children }) => (
  <div className="flex items-baseline justify-between gap-4 border-b border-slate-50 py-1.5 text-sm last:border-0">
    <span className="shrink-0 text-xs font-semibold text-slate-500">{label}</span>
    <span className="text-left text-slate-800">{children}</span>
  </div>
);

const Count: React.FC<{ label: string; value: number; note?: string }> = ({ label, value, note }) => (
  <div className="rounded-xl bg-slate-50 p-3">
    <p className="text-lg font-extrabold text-slate-800">{value}</p>
    <p className="text-[11px] leading-4 text-slate-500">{label}</p>
    {note && <p className="text-[11px] font-bold text-emerald-700">{note}</p>}
  </div>
);

/** Everything known about one notification, with numbers that only say what was measured. */
export const NotificationDetails: React.FC<{ row: HistoryRow; pushConfigured: boolean | null; onClose: () => void }> = ({ row, pushConfigured, onClose }) => {
  const sent = row.status === 'sent';
  return (
    <Dialog wide onClose={onClose} title={(
      <div className="flex flex-wrap items-center gap-2">
        <span>{row.title}</span>
        <span className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${statusClass(row.status)}`}>{statusLabel(row.status)}</span>
      </div>
    )}>
      <p className="whitespace-pre-line rounded-2xl bg-slate-50 p-4 text-sm leading-relaxed text-slate-700">{row.body}</p>

      <div className="mt-4">
        <Fact label="النوع">{typeLabel(row.type, row.category)}{row.priority === 'high' ? ' · أولوية عالية' : ''}</Fact>
        <Fact label="المرسل">{senderLabel(row.sender_role, row.sender_name)}</Fact>
        <Fact label="المستلمون">{row.audience || '—'}</Fact>
        <Fact label="أُنشئ">{formatCairo(row.created_at, true)}</Fact>
        {row.scheduled_at && <Fact label="موعد الإرسال المجدول">{formatCairo(row.scheduled_at, true)}</Fact>}
        {row.sent_at && <Fact label="أُرسل">{formatCairo(row.sent_at, true)}</Fact>}
        {row.status_note && <Fact label="ملاحظة">{row.status_note}</Fact>}
      </div>
      <p className="mt-1 text-[11px] text-slate-400">كل الأوقات {CAIRO_LABEL}.</p>

      {sent && (
        <>
          <h3 className="mt-5 text-sm font-bold text-slate-700">داخل التطبيق</h3>
          <div className="mt-2 grid grid-cols-3 gap-2">
            <Count label="طالب أُضيف الإشعار إلى صندوقه" value={row.students} />
            <Count label="قرؤوه" value={row.read} note={row.students ? `${percent(row.read, row.students)}٪` : undefined} />
            <Count label="فتحوه من الإشعار الفوري" value={row.opened} />
          </div>

          <h3 className="mt-5 text-sm font-bold text-slate-700">الإشعارات الفورية (Push)</h3>
          {pushConfigured !== true && (
            <p className="mt-1 text-xs text-slate-500">الإشعارات الفورية غير مربوطة بعد، فلم يُرسل شيء إلى الهواتف خارج التطبيق.</p>
          )}
          <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-5">
            {pushStatParts(row.push).map((part) => <Count key={part.key} label={part.label} value={part.value} />)}
          </div>
          <p className="mt-2 text-[11px] leading-5 text-slate-400">
            «قبِلها مزوّد الإشعارات» تعني أن مزوّد الخدمة استلم الرسالة ليوصلها، ولا تعني أنها ظهرت على الهاتف.
          </p>
        </>
      )}

      <div className="mt-5 flex justify-end">
        <button type="button" onClick={onClose}
          className="rounded-xl bg-slate-100 px-4 py-2 text-sm font-bold text-slate-600 transition hover:bg-slate-200">
          إغلاق
        </button>
      </div>
    </Dialog>
  );
};
