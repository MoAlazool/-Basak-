import React, { useState } from 'react';
import { Copy, KeyRound, ShieldCheck, X } from 'lucide-react';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { useGuard } from '../lib/guard';

interface Props {
  student: { id: string; full_name: string; phone: string; university: string; company?: string | null };
  onClose: () => void;
}

/**
 * Super Admin only: sets a temporary password on the student's Supabase Auth
 * account (Edge Function, service role) and forces a change at next sign-in.
 * The temporary password is shown once here and never stored or logged.
 */
export const ResetStudentPasswordDialog: React.FC<Props> = ({ student, onClose }) => {
  const [mode, setMode] = useState<'generate' | 'manual'>('generate');
  const [password, setPassword] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const guard = useGuard();
  // A second click must not set a second password while the first is being set.
  const submit = () => guard('reset', async () => {
    setError('');
    if (mode === 'manual' && password.length < 8) { setError('كلمة المرور المؤقتة يجب ألا تقل عن 8 أحرف.'); return; }
    setBusy(true);
    try {
      const response = await invokeEdgeFunction<{ temporaryPassword?: string }>('admin-reset-student-password', {
        studentId: student.id, ...(mode === 'manual' ? { password } : {}),
      });
      setResult(mode === 'manual' ? password : response.temporaryPassword ?? '');
      setPassword('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'تعذر إعادة تعيين كلمة المرور.');
    } finally {
      setBusy(false);
    }
  });

  const close = () => { setResult(null); onClose(); };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4" dir="rtl">
      <div className="w-full max-w-md space-y-4 rounded-3xl bg-white p-6 shadow-2xl">
        <div className="flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-bold text-slate-800"><KeyRound className="h-5 w-5 text-amber-500" />إعادة تعيين كلمة مرور طالب</h2>
          <button onClick={close} className="text-slate-400" aria-label="إغلاق"><X className="h-5 w-5" /></button>
        </div>
        <div className="space-y-1 rounded-2xl bg-slate-50 p-4 text-sm">
          <p className="font-bold text-slate-800">{student.full_name}</p>
          <p className="font-mono text-slate-500" dir="ltr">{student.phone}</p>
          <p className="text-slate-500">{student.university}{student.company ? ` · ${student.company}` : ''}</p>
        </div>

        {result !== null ? (
          <div className="space-y-3">
            <div className="rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">
              <p className="mb-2 flex items-center gap-1.5 font-bold"><ShieldCheck className="h-4 w-4" />تم تغيير كلمة المرور.</p>
              <p className="mb-2">سلّمها للطالب بنفسك (مقابلة أو مكالمة). ستظهر هنا مرة واحدة فقط، وسيُطلب منه تغييرها عند أول دخول.</p>
              <div className="flex items-center justify-between gap-2 rounded-xl bg-white px-3 py-2">
                <code className="text-lg font-bold tracking-wider text-slate-800" dir="ltr">{result}</code>
                <button onClick={() => { void navigator.clipboard.writeText(result); setCopied(true); }} className="flex items-center gap-1 text-xs font-bold text-blue-600"><Copy className="h-3.5 w-3.5" />{copied ? 'تم النسخ' : 'نسخ'}</button>
              </div>
            </div>
            <button onClick={close} className="w-full rounded-xl bg-slate-800 py-2.5 text-sm font-bold text-white">تم</button>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-2">
              <button onClick={() => setMode('generate')} className={`rounded-xl border px-3 py-2 text-xs font-bold ${mode === 'generate' ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-slate-200 text-slate-600'}`}>توليد كلمة مرور آمنة</button>
              <button onClick={() => setMode('manual')} className={`rounded-xl border px-3 py-2 text-xs font-bold ${mode === 'manual' ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-slate-200 text-slate-600'}`}>كتابة كلمة مؤقتة</button>
            </div>
            {mode === 'manual' && (
              <input type="text" dir="ltr" autoComplete="off" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="8 أحرف على الأقل"
                className="w-full rounded-xl border border-slate-200 px-3 py-2 font-mono text-sm" />
            )}
            <label className="flex items-start gap-2 text-sm text-slate-600">
              <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} className="mt-1" />
              أؤكد أنني تحققت من هوية الطالب وأن كلمة المرور الحالية ستتوقف عن العمل.
            </label>
            {error && <p role="alert" className="rounded-xl bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>}
            <div className="flex justify-end gap-2">
              <button onClick={close} className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-600">إلغاء</button>
              <button onClick={() => void submit()} disabled={busy || !confirmed}
                className="rounded-xl bg-amber-500 px-5 py-2 text-sm font-bold text-white disabled:opacity-40">{busy ? 'جاري التنفيذ...' : 'إعادة التعيين'}</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
};
