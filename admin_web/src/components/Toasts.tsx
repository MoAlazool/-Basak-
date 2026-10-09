import React from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertCircle, BellRing, CheckCircle2, X } from 'lucide-react';
import { dismiss, useToasts } from '../lib/toasts';

const TONE = {
  info: { border: 'border-blue-100', badge: 'bg-blue-50 text-blue-600', icon: BellRing },
  success: { border: 'border-emerald-200', badge: 'bg-emerald-50 text-emerald-600', icon: CheckCircle2 },
  error: { border: 'border-rose-200', badge: 'bg-rose-50 text-rose-600', icon: AlertCircle },
};

/** Notices over every page: what just arrived (a new receipt, a new request) and how the admin's own actions went. */
export const Toasts: React.FC = () => {
  const toasts = useToasts();
  const navigate = useNavigate();
  if (toasts.length === 0) return null;
  return (
    <div className="pointer-events-none fixed left-4 top-4 z-[60] flex w-[min(92vw,340px)] flex-col gap-2" dir="rtl" aria-live="polite">
      {toasts.map((toast) => {
        const tone = TONE[toast.tone ?? 'info'];
        const Icon = tone.icon;
        return (
        <div key={toast.id} role={toast.tone === 'error' ? 'alert' : 'status'}
          className={`pointer-events-auto flex items-start gap-3 rounded-2xl border bg-white p-3.5 shadow-xl shadow-blue-900/10 ${tone.border}`}>
          <span className={`mt-0.5 flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full ${tone.badge}`}>
            <Icon className="h-4 w-4" />
          </span>
          <button type="button" className="min-w-0 flex-1 text-right"
            onClick={() => { if (toast.to) navigate(toast.to); dismiss(toast.id); }}>
            <p className="text-sm font-bold text-slate-800">{toast.title}</p>
            {toast.body && <p className="mt-0.5 text-xs leading-5 text-slate-500">{toast.body}</p>}
            {toast.to && <p className="mt-1 text-xs font-bold text-blue-600">عرض الآن</p>}
          </button>
          <button type="button" aria-label="إغلاق" onClick={() => dismiss(toast.id)}
            className="rounded-lg p-1 text-slate-300 hover:bg-slate-50 hover:text-slate-500">
            <X className="h-4 w-4" />
          </button>
        </div>
        );
      })}
    </div>
  );
};
