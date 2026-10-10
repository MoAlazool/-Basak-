import React from 'react';
import { Ban, ShieldCheck } from 'lucide-react';
import { BLOCK_REASON_MAX, useBlockActions } from '../lib/blockedPhones';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';

/**
 * Block a student (the platform admin's call): their number can no longer be
 * registered and their account can no longer sign in. Nothing is deleted.
 * On a blocked student it unblocks instead.
 */
export const BlockStudentButton: React.FC<{
  student: { id: string; full_name: string; phone: string };
  blocked: boolean;
  className?: string;
}> = ({ student, blocked, className = '' }) => {
  const guard = useGuard();
  const { block, unblock } = useBlockActions();

  const onBlock = () => guard(`block:${student.id}`, async () => {
    const reason = prompt(
      `حظر الطالب "${student.full_name}" (${student.phone})؟\n`
      + 'لن يستطيع الدخول إلى التطبيق، ولا التسجيل مرة أخرى بهذا الرقم حتى لو حُذف حسابه. لا يُحذف شيء من بياناته، ويمكن إلغاء الحظر لاحقاً.\n\n'
      + 'سبب الحظر (اختياري، يظهر لإدارة المنصة فقط):',
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

  return blocked ? (
    <button onClick={() => void onUnblock()} className={`text-emerald-500 transition hover:text-emerald-700 ${className}`}
      title="إلغاء الحظر" aria-label={`إلغاء حظر ${student.full_name}`}>
      <ShieldCheck className="h-4 w-4" />
    </button>
  ) : (
    <button onClick={() => void onBlock()} className={`text-slate-400 transition hover:text-rose-600 ${className}`}
      title="حظر الطالب (يمنع الدخول والتسجيل بنفس الرقم)" aria-label={`حظر ${student.full_name}`}>
      <Ban className="h-4 w-4" />
    </button>
  );
};

/** "محظور" beside a blocked student's name. */
export const BlockedBadge: React.FC = () => (
  <span className="mr-2 inline-flex items-center gap-1 rounded-full bg-rose-50 px-2 py-0.5 align-middle text-[11px] font-bold text-rose-600">
    <Ban className="h-3 w-3" /> محظور
  </span>
);
