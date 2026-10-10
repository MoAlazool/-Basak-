import React from 'react';
import { Ban, ShieldCheck } from 'lucide-react';
import { BLOCK_REASON_MAX, blockedBy, useBlockActions, type BlockedPhone } from '../lib/blockedPhones';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';

/**
 * Block a student: their number can no longer be registered and their account
 * can no longer sign in. Nothing is deleted. On a blocked student it unblocks
 * instead, when the one asking may (a company lifts only its own blocks).
 * companyId: act as that company; null: as the platform.
 */
export const BlockStudentButton: React.FC<{
  student: { id: string; full_name: string; phone: string };
  entry: BlockedPhone | undefined;
  companyId: string | null;
  className?: string;
}> = ({ student, entry, companyId, className = '' }) => {
  const guard = useGuard();
  const { block, unblock } = useBlockActions(companyId);

  const onBlock = () => guard(`block:${student.id}`, async () => {
    const reason = prompt(
      `حظر الطالب "${student.full_name}" (${student.phone})؟\n`
      + 'لن يستطيع الدخول إلى التطبيق، ولا التسجيل مرة أخرى بهذا الرقم حتى لو حُذف حسابه. لا يُحذف شيء من بياناته، ويمكن إلغاء الحظر لاحقاً. '
      + 'عند مسح بطاقته يظهر للمشرف أنه محظور.\n\n'
      + `سبب الحظر (اختياري، يظهر ${companyId ? 'لإدارة شركتك ولإدارة المنصة' : 'لإدارة المنصة'} فقط):`,
      '',
    );
    if (reason === null) return;
    try {
      await block(student.id, reason.trim().slice(0, BLOCK_REASON_MAX) || null);
      notifyDone(`تم حظر ${student.full_name}`);
    } catch (error) {
      notifyError('تعذر حظر الطالب', (error as Error).message);
    }
  });

  const onUnblock = () => guard(`block:${student.id}`, async () => {
    if (!confirm(`إلغاء حظر "${student.full_name}"؟\nيستطيع الدخول إلى التطبيق مرة أخرى، ويصبح رقمه متاحاً للتسجيل.`)) return;
    try {
      await unblock(student.phone);
      notifyDone(`تم إلغاء حظر ${student.full_name}`);
    } catch (error) {
      notifyError('تعذر إلغاء الحظر', (error as Error).message);
    }
  });

  if (entry) {
    // Blocked by the platform or another company: only the platform lifts it.
    if (entry.can_unblock === false) return null;
    return (
      <button onClick={() => void onUnblock()} className={`text-emerald-500 transition hover:text-emerald-700 ${className}`}
        title="إلغاء الحظر" aria-label={`إلغاء حظر ${student.full_name}`}>
        <ShieldCheck className="h-4 w-4" />
      </button>
    );
  }
  return (
    <button onClick={() => void onBlock()} className={`text-slate-400 transition hover:text-rose-600 ${className}`}
      title="حظر الطالب (يمنع الدخول والتسجيل بنفس الرقم)" aria-label={`حظر ${student.full_name}`}>
      <Ban className="h-4 w-4" />
    </button>
  );
};

/** "محظور" beside a blocked student's name; who blocked, and why when known, on hover. */
export const BlockedBadge: React.FC<{ entry: BlockedPhone }> = ({ entry }) => (
  <span className="mr-2 inline-flex items-center gap-1 rounded-full bg-rose-50 px-2 py-0.5 align-middle text-[11px] font-bold text-rose-600"
    title={`حظره: ${blockedBy(entry)}${entry.reason ? ` • ${entry.reason}` : ''}`}>
    <Ban className="h-3 w-3" /> محظور
  </span>
);
