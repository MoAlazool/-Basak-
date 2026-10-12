import React, { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Button } from '../../ui/Button';
import { Icon } from '../../ui/Icon';
import { SidePanel } from '../../ui/Overlay';
import { Badge, Ltr } from '../../ui/Status';
import { agoText, phoneText } from '../../ui/format';
import { supabase } from '../../lib/supabase';
import { invokeEdgeFunction } from '../../lib/edgeFunctions';
import { keys, refreshIfNotUpdated } from '../../lib/query';
import { forgetApplied, rememberApplied } from '../../lib/recentChanges';
import { notifyDone } from '../../lib/toasts';
import { useGuard } from '../../lib/guard';
import { requestCorrection, type CorrectionField } from '../../lib/corrections';
import type { BlockedPhone } from '../../lib/blockedPhones';
import {
  openSubscriptions, pastSubscriptions, runSubscriptionAction, shortName, studentShown, studyLine, subscriptionPatch,
  withoutStudent, withStudent, withSubscription, type StudentRow, type StudentSubscription, type SubscriptionAction,
} from '../../lib/students';
import { ResetStudentPasswordDialog } from '../ResetStudentPasswordDialog';
import { BlockStudentButton } from '../BlockStudentButton';
import { Avatar, fullDay, PanelHead, ShownPill } from './parts';
import { PastSubscriptionRow, SubscriptionActionDialog, SubscriptionCard } from './SubscriptionCard';
import { CorrectionDialog, DeleteAccountDialog, RemoveDialog } from './StudentDialogs';

const DONE: Record<SubscriptionAction, (who: string) => string> = {
  activate: (w) => `فُعّل اشتراك ${w}`, cancel: (w) => `أُلغي اشتراك ${w}`, end: (w) => `أُنهي اشتراك ${w}`,
  revert: (w) => `عاد اشتراك ${w} إلى «بانتظار الدفع»`, reactivate: (w) => `أُعيد تفعيل اشتراك ${w}`,
};

/** Every students list on screen: the page's lists, and the single row opened from the top bar. */
const isList = (data: unknown): data is { rows: StudentRow[] } => !!data && typeof data === 'object' && Array.isArray((data as { rows?: unknown }).rows);

/**
 * One student of the company (docs/canvas/AdmStudentPanel, AdmStudentPanelActive,
 * AdmStudentPhone, AdmStudentWorkspace): who they are, their subscriptions with the
 * moves each status allows, the password request, and the actions on the account.
 */
export const StudentPanel: React.FC<{
  student: StudentRow; company: { id: string; name: string }; base: string; isSuper: boolean; today: string; online: boolean;
  avatarUrl?: string; universities: { id: string; name: string }[]; block?: BlockedPhone; blockAs: string | null;
  onClose: () => void;
}> = ({ student, company, base, isSuper, today, online, avatarUrl, universities, block, blockAs, onClose }) => {
  const client = useQueryClient();
  const guard = useGuard();
  const [target, setTarget] = useState<{ sub: StudentSubscription; action: SubscriptionAction } | null>(null);
  const [dialog, setDialog] = useState<'remove' | 'delete' | 'reset' | CorrectionField | null>(null);
  const studentsKey = keys.company(company.id, 'students');
  const edit = (change: <P extends { rows: StudentRow[] }>(page: P | undefined) => P | undefined) =>
    client.setQueriesData({ queryKey: studentsKey, predicate: (q) => isList(q.state.data) }, (data: unknown) => (isList(data) ? change(data) : data));

  const open = openSubscriptions(student, today);
  const past = pastSubscriptions(student, today);
  const shown = studentShown(student, today);
  const pending = student.corrections ?? [];
  const pendingName = pending.find((c) => c.field === 'full_name');
  const pendingUniversity = pending.find((c) => c.field === 'university');
  const who = shortName(student.full_name);

  const act = async () => {
    if (!target) return;
    const { sub, action } = target;
    await guard(`sub:${sub.id}`, async () => {
      rememberApplied([sub.id], ['students']);
      try {
        const answer = await runSubscriptionAction(sub.id, action);
        edit((page) => withSubscription(page, sub.id, subscriptionPatch(answer, today)));
        // The chips' numbers and the row's place follow from the server once.
        refreshIfNotUpdated(studentsKey);
        notifyDone(DONE[action](who));
      } catch (e) { forgetApplied([sub.id]); throw e; }
    });
  };
  const remove = async () => {
    await guard('remove', async () => {
      const { error } = await supabase.rpc('company_remove_student', { p_company_id: company.id, p_student_id: student.id });
      if (error) throw new Error(error.message);
      onClose();
      edit((page) => withoutStudent(page, student.id));
      refreshIfNotUpdated(studentsKey);
      notifyDone(`أُزيل ${who} من ${company.name}`, 'بقي حسابه في التطبيق كما هو.');
    });
  };
  const deleteAccount = async () => {
    await guard('delete', async () => {
      await invokeEdgeFunction('admin-delete-student', { studentId: student.id });
      onClose();
      edit((page) => withoutStudent(page, student.id));
      refreshIfNotUpdated(studentsKey);
      notifyDone(`حُذف حساب ${who} من المنصة`);
    });
  };
  const sendCorrection = (field: CorrectionField) => async (value: string) => {
    await guard(`fix:${field}`, async () => {
      const id = await requestCorrection(company.id, student.id, field, value);
      const row = { id: id ?? `local-${Date.now()}`, field, old_value: field === 'full_name' ? student.full_name : student.university, new_value: value.trim().replace(/\s+/g, ' '), created_at: new Date().toISOString() };
      edit((page) => withStudent(page, student.id, (s) => ({ ...s, corrections: [...(s.corrections ?? []), row] })));
      if (id) rememberApplied([id], ['students']);
      refreshIfNotUpdated(keys.company(company.id, 'corrections'));
      notifyDone('أُرسل طلب التصحيح إلى إدارة المنصة', 'تراه في تبويب «طلبات تصحيح الاسم» حتى تقرر.');
    });
  };

  return (
    <SidePanel open onClose={onClose} title={student.full_name} meta={<ShownPill shown={shown} />} backLabel="الطلاب"
      sub={<a href={`tel:${student.phone}`} className="inline-flex items-center gap-1.5 text-label text-ink-2 hover:text-teal"><Ltr>{phoneText(student.phone)}</Ltr></a>}
      footer={<>
        <Button kind="dangerQuiet" icon="trash" disabled={!online} onClick={() => setDialog('remove')}>إزالة من الشركة</Button>
        <span className="hidden flex-1 sm:block" />
        <Button kind="outline" icon="pencil" disabled={!online || !!pendingName} title={pendingName ? 'طلبك السابق ما زال عند إدارة المنصة.' : undefined} onClick={() => setDialog('full_name')}>طلب تصحيح الاسم</Button>
      </>}>
      {/* Who */}
      <div className="flex items-center gap-4">
        <Avatar name={student.full_name} id={student.id} url={avatarUrl} size={64} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-baseline gap-x-2 text-small font-semibold">
            <span>{student.university || 'الجامعة غير محددة'}</span>
            {!pendingUniversity && <button type="button" disabled={!online} onClick={() => setDialog('university')} className="text-label font-medium text-teal hover:underline disabled:text-disabled">تصحيح الجامعة</button>}
          </div>
          {studyLine(student.college, student.specialisation, '', ' · ') && <div className="text-label text-ink-2">{studyLine(student.college, student.specialisation, '', ' · ')}</div>}
          <div className="text-label text-ink-2">سُجّل {fullDay(student.joined_at ?? student.created_at)}</div>
        </div>
      </div>

      {pending.map((c) => (
        <div key={c.id} className="flex items-start gap-3 rounded-inner bg-teal-tint px-4 py-3">
          <Icon name="pencil" size={18} className="mt-0.5 text-teal" />
          <div className="min-w-0 flex-1">
            <div className="text-small font-semibold">{c.field === 'full_name' ? 'طلب تصحيح الاسم عند إدارة المنصة' : 'طلب تصحيح الجامعة عند إدارة المنصة'}</div>
            <div className="text-label text-ink-2">{c.field === 'full_name'
              ? <>الاسم المقترح: «{c.new_value}». يتغيّر الاسم بعد أن تعتمده.</>
              : <>الجامعة المقترحة: «{c.new_value}». تتغيّر بعد أن تعتمدها.</>}</div>
          </div>
        </div>
      ))}

      {open.length > 0 && (
        <section className="flex flex-col gap-3">
          <PanelHead>{open.length > 1 ? 'الاشتراكات الحالية' : 'الاشتراك الحالي'}</PanelHead>
          {open.map((sub) => (
            <SubscriptionCard key={sub.id} sub={sub} today={today} studentName={student.full_name} receiptsTo={`${base}/receipts`} online={online}
              onAction={(s, action) => setTarget({ sub: s, action })} />
          ))}
        </section>
      )}
      {open.length === 0 && (
        <section className="flex flex-col gap-3">
          <PanelHead>الاشتراك الحالي</PanelHead>
          <p className="m-0 rounded-inner bg-ground px-4 py-3 text-small text-ink-2 sm:bg-sunken/50">لا اشتراك مفتوحاً له الآن. يشترك من التطبيق متى أراد.</p>
        </section>
      )}
      {past.length > 0 && (
        <section className="flex flex-col gap-3">
          <PanelHead>اشتراكات سابقة</PanelHead>
          <div className="overflow-hidden rounded-inner bg-surface shadow-ring [&>*+*]:border-t [&>*+*]:border-hair">
            {past.map((sub) => <PastSubscriptionRow key={sub.id} sub={sub} today={today} online={online} onAction={(s, action) => setTarget({ sub: s, action })} />)}
          </div>
        </section>
      )}

      <section className="flex flex-col gap-3">
        <PanelHead>كلمة المرور</PanelHead>
        {isSuper && student.open_reset && (
          <div className="flex items-start gap-3 rounded-inner bg-warn-bg px-4 py-3">
            <Icon name="key" size={18} className="mt-0.5 text-warn" />
            <div className="min-w-0 flex-1">
              <div className="text-small font-semibold">طلب المساعدة في كلمة المرور {agoText(student.open_reset.requested_at)}</div>
              <div className="text-label text-ink-2">اتصل به لتتأكد أنه هو ثم أعطه رمزاً.</div>
            </div>
            <Button sm kind="tonal" to={`/platform/password-requests?request=${student.open_reset.id}`} className="!bg-surface">افتح الطلب</Button>
          </div>
        )}
        {isSuper ? (
          <div className="flex flex-col gap-2 rounded-inner bg-surface px-4 py-3 shadow-ring">
            <div className="flex items-center gap-2"><span className="flex-1 text-small font-semibold">تعيين كلمة مرور مؤقتة</span><Badge>لمدير المنصة فقط</Badge></div>
            <p className="m-0 text-label text-ink-2">تتوقف كلمته الحالية، ويُطلب منه تغيير المؤقتة عند أول دخول.</p>
            <Button sm kind="secondary" icon="key" disabled={!online} className="self-start max-sm:!h-12 max-sm:self-stretch" onClick={() => setDialog('reset')}>إعادة تعيين كلمة المرور</Button>
          </div>
        ) : (
          <p className="m-0 text-label text-ink-2">لا تظهر كلمة المرور لأحد. إن نسيها يضغط «نسيت كلمة المرور» في التطبيق، ويتولّى فريق باصك طلبه.</p>
        )}
      </section>

      {isSuper && (
        <section className="flex flex-col gap-3">
          <PanelHead>حذف الحساب</PanelHead>
          <div className="flex flex-col gap-2 rounded-inner bg-surface px-4 py-3 shadow-ring">
            <div className="flex items-center gap-2"><span className="flex-1 text-small font-semibold">حذف الحساب نهائياً من المنصة</span><Badge>لمدير المنصة فقط</Badge></div>
            <p className="m-0 text-label text-ink-2">يُحذف حسابه واشتراكاته لدى كل الشركات. غير الإزالة من هذه الشركة.</p>
            <Button sm kind="dangerQuiet" icon="trash" disabled={!online} className="self-start max-sm:!h-12 max-sm:self-stretch" onClick={() => setDialog('delete')}>حذف الحساب</Button>
          </div>
        </section>
      )}

      <BlockStudentButton student={student} entry={block} companyId={blockAs} disabled={!online} />

      <SubscriptionActionDialog target={target} studentName={student.full_name} onClose={() => setTarget(null)} onConfirm={act} />
      <RemoveDialog open={dialog === 'remove'} onClose={() => setDialog(null)} name={student.full_name} company={company.name} onConfirm={remove} />
      <DeleteAccountDialog open={dialog === 'delete'} onClose={() => setDialog(null)} name={student.full_name} company={company.name} onConfirm={deleteAccount} />
      <CorrectionDialog open={dialog === 'full_name'} onClose={() => setDialog(null)} field="full_name" name={student.full_name} current={student.full_name} onSend={sendCorrection('full_name')} />
      <CorrectionDialog open={dialog === 'university'} onClose={() => setDialog(null)} field="university" name={student.full_name} current={student.university} universities={universities} onSend={sendCorrection('university')} />
      {dialog === 'reset' && (
        <ResetStudentPasswordDialog student={{ id: student.id, full_name: student.full_name, phone: student.phone, university: student.university, company: company.name }} onClose={() => setDialog(null)} />
      )}
    </SidePanel>
  );
};
