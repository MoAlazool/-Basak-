import React, { useState } from 'react';
import { KeyRound, Phone, RefreshCw, X, Copy } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useQueryClient } from '@tanstack/react-query';
import { keys, unwrap, usePageData } from '../lib/query';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { notifyError } from '../lib/toasts';
import { isOpenReset as isOpen } from '../lib/resetRequests';

interface ResetRequest {
  id: string;
  student_id: string;
  student_name: string;
  student_phone: string;
  status: 'pending' | 'code_issued' | 'completed' | 'cancelled' | 'expired';
  requested_at: string;
  code_issued_at: string | null;
  code_expires_at: string | null;
  failed_attempts: number;
}

const statusLabels: Record<ResetRequest['status'], string> = {
  pending: 'بانتظار التحقق',
  code_issued: 'تم إصدار رمز',
  completed: 'تم تغيير كلمة المرور',
  cancelled: 'ملغي',
  expired: 'انتهت صلاحية الرمز',
};

const fmt = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString('ar-EG', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—';

/**
 * Student "Forgot password" requests. In a workspace: those of that company's
 * members. Without a company (platform admin): everyone's, including students
 * who ride with no company. The admin verifies the student by phone, then issues
 * a one-time code that the student types into the app with a new password.
 */
export const PasswordResetRequests: React.FC<{ companyId: string | null }> = ({ companyId }) => {
  const [issued, setIssued] = useState<{ request: ResetRequest; code: string; expiresAt: string } | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  // New requests arrive through the live topic of the workspace or the platform.
  const listKey = companyId ? keys.company(companyId, 'resetRequests') : keys.platform('resetRequests');
  const page = usePageData(listKey, () =>
    unwrap<ResetRequest[]>(supabase.rpc('admin_list_password_reset_requests', { p_company_id: companyId })));
  const requests = page.data ?? [];
  const error = page.error;
  const load = page.reload;
  const client = useQueryClient();
  const guard = useGuard();

  // What the admin just did to a request is shown from the server's answer; its
  // announcement on the live topic then re-reads neither the list nor the badge's count.
  const applyChange = (request: ResetRequest, change: Partial<ResetRequest>) => {
    rememberApplied([request.id], ['resetRequests']);
    client.setQueryData<ResetRequest[]>(listKey, (rows) => rows?.map((row) => (row.id === request.id ? { ...row, ...change } : row)));
    const closes = isOpen(request) && change.status !== undefined && !isOpen({ status: change.status });
    if (closes) client.setQueryData<number>([...listKey, 'count'], (count) => (count === undefined ? count : Math.max(0, count - 1)));
  };

  const issueCode = (request: ResetRequest) => guard(request.id, async () => {
    if (!confirm(`تأكد أولاً من هوية الطالب "${request.student_name}" بالاتصال على ${request.student_phone}. إصدار الرمز الآن؟`)) return;
    setBusyId(request.id);
    const { data, error: issueError } = await supabase.rpc('admin_issue_password_reset_code', { p_request_id: request.id });
    setBusyId(null);
    if (issueError || !data) return notifyError('تعذر إصدار الرمز', issueError?.message);
    setIssued({ request, code: data.code, expiresAt: data.expires_at });
    applyChange(request, { status: 'code_issued', code_issued_at: new Date().toISOString(), code_expires_at: data.expires_at });
  });

  const cancel = (request: ResetRequest) => guard(request.id, async () => {
    if (!confirm('إلغاء طلب الاستعادة؟')) return;
    setBusyId(request.id);
    const { error: cancelError } = await supabase.rpc('admin_cancel_password_reset', { p_request_id: request.id });
    setBusyId(null);
    if (cancelError) {
      notifyError('تعذر الإلغاء', cancelError.message);
      // It may have been completed or cancelled meanwhile: show what it is now.
      return load();
    }
    applyChange(request, { status: 'cancelled' });
  });

  const open = requests.filter(isOpen);
  if (!error && requests.length === 0) return null;

  return (
    <div className="rounded-2xl border border-amber-100 bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between">
        <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
          <KeyRound className="h-5 w-5 text-amber-600" />
          طلبات استعادة كلمة مرور الطلاب
          {open.length > 0 && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-800">{open.length}</span>}
        </h2>
        <button onClick={() => void load()} className="text-slate-400 hover:text-slate-600" title="تحديث">
          <RefreshCw className="h-4 w-4" />
        </button>
      </div>
      <p className="mt-1 text-xs text-slate-500">
        تحقق من هوية الطالب هاتفياً ثم أصدر رمزاً لمرة واحدة (صالح 30 دقيقة). يكتب الطالب الرمز وكلمة مرور جديدة في التطبيق. لا تظهر كلمات المرور هنا أبداً.
      </p>
      {error && <p role="alert" className="mt-3 text-sm text-rose-700">تعذر تحميل الطلبات: {error}</p>}

      {issued && (
        <div className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-4">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-sm font-bold text-emerald-800">رمز الاستعادة للطالب {issued.request.student_name}</p>
              <p className="mt-1 font-mono text-3xl font-extrabold tracking-[0.3em] text-emerald-900" dir="ltr">{issued.code}</p>
              <p className="mt-1 text-xs text-emerald-700">
                أبلغه للطالب على <span dir="ltr">{issued.request.student_phone}</span>. صالح حتى {fmt(issued.expiresAt)}. لن يظهر الرمز مرة أخرى.
              </p>
            </div>
            <div className="flex gap-2">
              <button title="نسخ" onClick={() => void navigator.clipboard?.writeText(issued.code)} className="text-emerald-700"><Copy className="h-4 w-4" /></button>
              <button title="إغلاق" onClick={() => setIssued(null)} className="text-emerald-700"><X className="h-4 w-4" /></button>
            </div>
          </div>
        </div>
      )}

      {requests.length > 0 && (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full min-w-[640px] text-right text-sm">
            <thead className="text-xs text-slate-500">
              <tr>
                <th className="p-2">الطالب</th>
                <th className="p-2">وقت الطلب</th>
                <th className="p-2">الحالة</th>
                <th className="p-2">إجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {requests.map((r) => {
                const stillOpen = isOpen(r);
                return (
                  <tr key={r.id}>
                    <td className="p-2">
                      <p className="font-semibold text-slate-800">{r.student_name}</p>
                      <p className="flex items-center gap-1 text-xs text-slate-500"><Phone className="h-3 w-3" /><span dir="ltr">{r.student_phone}</span></p>
                    </td>
                    <td className="p-2 text-xs text-slate-500">{fmt(r.requested_at)}</td>
                    <td className="p-2 text-xs">
                      <span className={`rounded-full px-2 py-0.5 font-bold ${stillOpen ? 'bg-amber-50 text-amber-700' : 'bg-slate-100 text-slate-500'}`}>
                        {statusLabels[r.status]}
                      </span>
                      {r.status === 'code_issued' && <span className="mr-2 text-slate-400">حتى {fmt(r.code_expires_at)}</span>}
                    </td>
                    <td className="p-2">
                      {stillOpen && (
                        <div className="flex gap-2">
                          <button disabled={busyId === r.id} onClick={() => void issueCode(r)}
                            className="rounded-lg bg-amber-600 px-3 py-1 text-xs font-bold text-white disabled:opacity-50">
                            {r.status === 'code_issued' ? 'إصدار رمز جديد' : 'إصدار رمز'}
                          </button>
                          <button disabled={busyId === r.id} onClick={() => void cancel(r)}
                            className="rounded-lg border border-slate-200 px-3 py-1 text-xs text-slate-600">إلغاء</button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};
