import React from 'react';
import { Ban } from 'lucide-react';
import { useBlockActions, type BlockedPhone } from '../lib/blockedPhones';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';

/**
 * Every blocked number, with who it belonged to and why, and a way to unblock
 * it: also the numbers whose account was deleted, which no students list shows.
 * Not shown while nothing is blocked.
 */
export const BlockedPhonesPanel: React.FC<{ list: BlockedPhone[] }> = ({ list }) => {
  const guard = useGuard();
  const { unblock } = useBlockActions();
  if (list.length === 0) return null;

  const onUnblock = (entry: BlockedPhone) => guard(`unblock:${entry.phone}`, async () => {
    if (!confirm(`إلغاء حظر الرقم ${entry.phone}؟\nيصبح متاحاً للتسجيل${entry.has_account ? '، ويستطيع صاحب الحساب الدخول مرة أخرى' : ''}.`)) return;
    try {
      await unblock(entry.phone);
      notifyDone(`تم إلغاء حظر ${entry.phone}`);
    } catch (error) {
      notifyError('تعذر إلغاء الحظر', (error as Error).message);
    }
  });

  return (
    <div className="glass-panel overflow-hidden">
      <div className="border-b border-slate-100 p-4">
        <h2 className="flex items-center gap-2 text-[15px] font-bold text-[#1F2937]">
          <Ban className="h-4 w-4 text-rose-500" /> الأرقام المحظورة ({list.length.toLocaleString('ar-EG')})
        </h2>
        <p className="text-[12px] text-[#5B6B7A]">لا يمكن التسجيل بها، ولا يستطيع أصحابها الدخول إلى التطبيق. يبقى الرقم محظوراً حتى لو حُذف حسابه.</p>
      </div>
      <ul className="divide-y divide-slate-100">
        {list.map((entry) => (
          <li key={entry.phone} className="flex flex-wrap items-center justify-between gap-3 p-4 text-sm">
            <div>
              <p className="font-bold text-slate-800">
                {entry.full_name ?? '—'} <span className="font-mono text-xs font-normal text-slate-500" dir="ltr">{entry.phone}</span>
                {!entry.has_account && <span className="mr-2 rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-500">الحساب محذوف</span>}
              </p>
              <p className="text-xs text-slate-500">
                حُظر في {new Date(entry.blocked_at).toLocaleDateString('ar-EG')}{entry.reason ? ` • ${entry.reason}` : ''}
              </p>
            </div>
            <button onClick={() => void onUnblock(entry)}
              className="rounded-lg border border-emerald-200 px-3 py-1.5 text-xs font-bold text-emerald-700 hover:bg-emerald-50">
              إلغاء الحظر
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
};
