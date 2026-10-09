import React, { useState } from 'react';
import { Clock, Mail, X } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useQueryClient } from '@tanstack/react-query';
import { keys, unwrap, usePageData } from '../lib/query';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { notifyError } from '../lib/toasts';

interface Invite { id: string; phone: string; status: string; created_at: string; expires_at: string; lines: { name: string } | null; }
interface Correction { id: string; field: 'full_name' | 'university'; old_value: string | null; new_value: string; status: string; created_at: string; decision_note: string | null; }

const inviteStatus: Record<string, string> = { pending: 'بانتظار موافقة الطالب', accepted: 'قُبلت', declined: 'رفضها الطالب', cancelled: 'أُلغيت', expired: 'انتهت' };
const correctionStatus: Record<string, string> = { pending: 'بانتظار إدارة المنصة', approved: 'اعتُمد', rejected: 'رُفض' };

/**
 * What this company is waiting on from others: students it invited (they decide
 * in the app) and profile corrections it proposed (the platform admin decides).
 */
export const MembershipRequests: React.FC<{ companyId: string }> = ({ companyId }) => {
  const [busy, setBusy] = useState<string | null>(null);
  const client = useQueryClient();
  const guard = useGuard();
  const invitesKey = keys.company(companyId, 'invites');
  const invites = usePageData(invitesKey, () =>
    unwrap<Invite[]>(supabase.from('company_invites').select('id, phone, status, created_at, expires_at, lines(name)')
      .eq('company_id', companyId).order('created_at', { ascending: false }).limit(10) as unknown as PromiseLike<{ data: Invite[] | null; error: { message: string } | null }>));
  const corrections = usePageData(keys.company(companyId, 'corrections'), () =>
    unwrap<Correction[]>(supabase.from('student_correction_requests').select('id, field, old_value, new_value, status, created_at, decision_note')
      .eq('company_id', companyId).order('created_at', { ascending: false }).limit(10)));

  const cancel = (invite: Invite) => guard(invite.id, async () => {
    if (!window.confirm(`إلغاء الدعوة المرسلة إلى ${invite.phone}؟`)) return;
    setBusy(invite.id);
    const { error } = await supabase.rpc('company_cancel_invite', { p_invite_id: invite.id });
    setBusy(null);
    if (error) {
      notifyError('تعذر إلغاء الدعوة', error.message);
      // The student may have answered it meanwhile: show what it is now.
      return invites.reload();
    }
    // Shown as cancelled at once; its announcement re-reads neither the invitations nor the students.
    rememberApplied([invite.id], ['invites', 'students']);
    client.setQueryData<Invite[]>(invitesKey, (rows) => rows?.map((row) => (row.id === invite.id ? { ...row, status: 'cancelled' } : row)));
  });

  if (!(invites.data?.length || corrections.data?.length)) return null;
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {(invites.data?.length ?? 0) > 0 && (
        <div className="rounded-2xl border border-slate-100 bg-white p-4 shadow-sm">
          <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-slate-700"><Mail className="h-4 w-4 text-sky-600" /> دعوات لحسابات موجودة</h3>
          <p className="mb-3 text-[11.5px] text-slate-500">رقم الهاتف له حساب في باصك. يظهر الطالب في قائمتك بعد أن يوافق على الدعوة من التطبيق.</p>
          <ul className="space-y-1.5 text-xs">
            {invites.data!.map((invite) => (
              <li key={invite.id} className="flex items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2">
                <span><b dir="ltr" className="font-mono">{invite.phone}</b> • {invite.lines?.name ?? '—'} • {inviteStatus[invite.status] ?? invite.status}</span>
                {invite.status === 'pending' && (
                  <button disabled={busy === invite.id} onClick={() => void cancel(invite)} className="inline-flex items-center gap-1 font-bold text-rose-600 disabled:opacity-50"><X className="h-3 w-3" /> إلغاء</button>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
      {(corrections.data?.length ?? 0) > 0 && (
        <div className="rounded-2xl border border-slate-100 bg-white p-4 shadow-sm">
          <h3 className="mb-2 flex items-center gap-2 text-sm font-bold text-slate-700"><Clock className="h-4 w-4 text-amber-600" /> طلبات تصحيح البيانات</h3>
          <ul className="space-y-1.5 text-xs">
            {corrections.data!.map((request) => (
              <li key={request.id} className="rounded-lg bg-slate-50 px-3 py-2">
                {request.field === 'full_name' ? 'الاسم' : 'الجامعة'}: <span className="text-slate-400 line-through">{request.old_value ?? '—'}</span> ← <b>{request.new_value}</b>
                {' • '}{correctionStatus[request.status] ?? request.status}{request.decision_note ? ` (${request.decision_note})` : ''}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
};
