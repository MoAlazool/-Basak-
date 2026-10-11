import React, { useEffect, useState } from 'react';
import { Button, Checkbox, Note, SkeletonText, errorText } from '../ui';
import { governorateNames, sameCodes, useCompanyGovernorates, useGovernorates, useSaveCompanyGovernorates } from '../lib/governorates';
import { useGuard } from '../lib/guard';
import { notifyDone, notifyError } from '../lib/toasts';

/**
 * The governorates a company serves, chosen from the fixed list (never typed):
 * in the app a student picks their governorate first and sees only the
 * companies that serve it; one that has chosen none is shown under none. For
 * the company's admins (page «المحافظات») and the platform admin.
 * `compact`: two columns and its own explanation, for the platform's side panel.
 */
export const CompanyGovernoratesCard: React.FC<{ companyId: string; compact?: boolean }> = ({ companyId, compact = false }) => {
  const guard = useGuard();
  const list = useGovernorates();
  const saved = useCompanyGovernorates(companyId);
  const save = useSaveCompanyGovernorates(companyId);
  const [draft, setDraft] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  // The choice follows what is saved, whenever that changes.
  useEffect(() => { setDraft(saved.data ?? []); }, [saved.data]);

  const governorates = list.data ?? [];
  const dirty = !!saved.data && !sameCodes(draft, saved.data);
  const toggle = (code: string, on: boolean) =>
    setDraft((cur) => (on ? [...cur.filter((c) => c !== code), code] : cur.filter((c) => c !== code)));

  const onSave = () => guard('governorates', async () => {
    setSaving(true);
    try {
      await save(draft);
      notifyDone(draft.length ? `تم حفظ المحافظات: ${governorateNames(governorates, draft)}` : 'تم مسح المحافظات');
    } catch (error) {
      notifyError('تعذر حفظ المحافظات', (error as Error).message);
    } finally {
      setSaving(false);
    }
  });

  if (list.isLoading || saved.isLoading) return <SkeletonText rows={4} />;
  if (list.error || saved.error) {
    return <Note tone="danger" title="تعذّر تحميل المحافظات">{errorText(list.error ?? saved.error)}</Note>;
  }
  return (
    <div className="flex flex-col gap-3">
      {compact && (
        <p className="m-0 text-label text-ink-2">
          يختار الطالب محافظته أولاً عند الاشتراك، ثم تظهر له الشركات التي تخدمها فقط. اختر كل المحافظات التي تخدمها الشركة.
        </p>
      )}
      {draft.length === 0 && (
        <Note tone="warning">لم تُحدَّد محافظات بعد: لن تظهر الشركة للطلاب عند اختيار محافظتهم.</Note>
      )}
      <div className={`grid gap-x-4 ${compact ? 'grid-cols-2' : 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4'}`} role="group" aria-label="المحافظات التي تخدمها الشركة">
        {governorates.map((g) => (
          <Checkbox key={g.code} label={g.name} checked={draft.includes(g.code)} disabled={saving} onChange={(on) => toggle(g.code, on)} />
        ))}
      </div>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-label text-ink-2 tabular">اخترت {draft.length.toLocaleString('ar-EG')} من {governorates.length.toLocaleString('ar-EG')}</span>
        <span className="flex gap-2">
          {dirty && <Button kind="secondary" sm disabled={saving} onClick={() => setDraft(saved.data ?? [])}>تراجع</Button>}
          <Button sm loading={saving} disabled={!dirty} onClick={() => void onSave()}>حفظ المحافظات</Button>
        </span>
      </div>
    </div>
  );
};
