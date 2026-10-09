import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Check, Search, X } from 'lucide-react';
import { Topbar } from '../components/Topbar';
import { SkeletonTable } from '../components/Skeleton';
import { supabase } from '../lib/supabase';
import { useQueryClient } from '@tanstack/react-query';
import { keys, refreshIfNotUpdated, unwrap, usePageData, VARIANT_GC } from '../lib/query';
import { usePlatformCompanies } from '../lib/reference';
import { rememberApplied } from '../lib/recentChanges';
import { useGuard } from '../lib/guard';
import { notifyError } from '../lib/toasts';

interface Membership { company_id: string; company: string; status: 'active' | 'removed'; joined_at: string; }
interface PlatformStudent {
  id: string; full_name: string; phone: string; university: string; created_at: string;
  memberships: Membership[]; active_subscriptions: number;
}
interface Correction {
  id: string; student_id: string; company_id: string; field: 'full_name' | 'university';
  old_value: string | null; new_value: string; note: string | null; created_at: string;
  companies: { name: string } | null;
}

const PAGE_SIZE = 25;
const select = 'rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs';
const fieldLabel = { full_name: 'الاسم', university: 'الجامعة' };

/**
 * Every account on the platform with the companies it belongs to. Only the
 * platform admin has this view; a company only ever sees its own active members.
 */
export const AllStudentsPage: React.FC = () => {
  const [typed, setTyped] = useState('');
  const [filters, setFilters] = useState({ search: '', companyId: '', membership: '' });
  const [pageIndex, setPageIndex] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => { setFilters((f) => ({ ...f, search: typed.trim() })); setPageIndex(0); }, 300);
    return () => window.clearTimeout(timer);
  }, [typed]);

  const companies = usePlatformCompanies().data ?? [];

  const client = useQueryClient();
  const guard = useGuard();
  const variant = !!(filters.search || filters.companyId || filters.membership || pageIndex);
  const page = usePageData(keys.platform('students', { ...filters, pageIndex }), () =>
    unwrap<{ total: number; rows: PlatformStudent[] }>(supabase.rpc('platform_students', {
      p_search: filters.search || null, p_company_id: filters.companyId || null, p_membership: filters.membership || null,
      p_limit: PAGE_SIZE, p_offset: pageIndex * PAGE_SIZE,
    })), { keepPrevious: true, gcTime: variant ? VARIANT_GC : undefined });
  const rows = page.data?.rows ?? [];
  const total = page.data?.total ?? 0;
  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const corrections = usePageData(keys.platform('corrections'), () =>
    unwrap<Correction[]>(supabase.from('student_correction_requests')
      .select('id, student_id, company_id, field, old_value, new_value, note, created_at, companies(name)')
      .eq('status', 'pending').order('created_at') as unknown as PromiseLike<{ data: Correction[] | null; error: { message: string } | null }>));

  const decide = (request: Correction, approve: boolean) => guard(request.id, async () => {
    const question = approve
      ? `اعتماد تغيير ${fieldLabel[request.field]} من «${request.old_value ?? '—'}» إلى «${request.new_value}»؟ يتغير لدى كل الشركات التي ينتمي إليها الطالب.`
      : 'رفض طلب التصحيح؟';
    if (!window.confirm(question)) return;
    setBusy(request.id);
    const { error } = await supabase.rpc('decide_student_correction', { p_request_id: request.id, p_approve: approve });
    setBusy(null);
    if (error) {
      notifyError('تعذر حفظ القرار', error.message);
      return corrections.reload();
    }
    // The request leaves the waiting list at once. An approval changes the account, so its
    // announcement reads the accounts again (once); a refusal changes nothing else.
    rememberApplied([request.id], approve ? ['corrections'] : ['corrections', 'students']);
    client.setQueryData<Correction[]>(keys.platform('corrections'), (rows) => rows?.filter((row) => row.id !== request.id));
    if (approve) refreshIfNotUpdated(keys.platform('students'));
  });

  const set = (patch: Partial<typeof filters>) => { setFilters((f) => ({ ...f, ...patch })); setPageIndex(0); };

  return (
    <div className="space-y-6">
      <Topbar title="كل الطلاب" subtitle="كل الحسابات على المنصة وعضوياتها في الشركات" />

      {(corrections.data?.length ?? 0) > 0 && (
        <div className="glass-panel overflow-hidden">
          <div className="border-b border-slate-100 p-4">
            <h2 className="text-[15px] font-bold text-[#1F2937]">طلبات تصحيح بيانات بانتظار قرارك</h2>
            <p className="text-[12px] text-[#5B6B7A]">تقترحها الشركات. الاعتماد يغيّر بيانات الحساب لدى كل الشركات.</p>
          </div>
          <ul className="divide-y divide-slate-100">
            {corrections.data!.map((request) => (
              <li key={request.id} className="flex flex-wrap items-center justify-between gap-3 p-4 text-sm">
                <div>
                  <p className="font-bold text-slate-800">
                    {fieldLabel[request.field]}: <span className="text-slate-500 line-through">{request.old_value ?? '—'}</span> ← {request.new_value}
                  </p>
                  <p className="text-xs text-slate-500">
                    من {request.companies?.name ?? '—'} • {new Date(request.created_at).toLocaleDateString('ar-EG')}{request.note ? ` • ${request.note}` : ''}
                  </p>
                </div>
                <div className="flex gap-2">
                  <button disabled={busy === request.id} onClick={() => void decide(request, false)} className="inline-flex items-center gap-1 rounded-lg border border-rose-200 px-3 py-1.5 text-xs font-bold text-rose-600 hover:bg-rose-50 disabled:opacity-50"><X className="h-3.5 w-3.5" /> رفض</button>
                  <button disabled={busy === request.id} onClick={() => void decide(request, true)} className="inline-flex items-center gap-1 rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-bold text-white hover:bg-emerald-700 disabled:opacity-50"><Check className="h-3.5 w-3.5" /> اعتماد</button>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="glass-panel overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b border-slate-100 p-4">
          <div className="relative min-w-[220px] flex-1">
            <Search className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="بحث بالاسم، الهاتف أو الجامعة..."
              className="w-full rounded-xl border border-slate-200 bg-white py-2 pl-3 pr-9 text-xs focus:border-[#7EC8E3] focus:outline-none" />
          </div>
          <select value={filters.companyId} onChange={(e) => set({ companyId: e.target.value })} className={select} aria-label="الشركة">
            <option value="">كل الشركات</option>
            {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <select value={filters.membership} onChange={(e) => set({ membership: e.target.value })} className={select} aria-label="العضوية">
            <option value="">كل الحسابات</option>
            <option value="none">بدون شركة</option>
            <option value="multiple">في أكثر من شركة</option>
          </select>
          <span className="text-xs font-semibold text-slate-400">
            {total.toLocaleString('ar-EG')} حساب{page.refreshing ? ' • جاري التحديث…' : ''}
          </span>
        </div>

        {page.loading ? <SkeletonTable rows={6} columns={5} /> : page.error ? (
          <div role="alert" className="p-8 text-center text-rose-700">تعذر تحميل الطلاب: {page.error}</div>
        ) : rows.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا توجد حسابات مطابقة.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-right text-sm">
              <thead className="bg-slate-50/60 text-[12px] text-slate-500">
                <tr><th className="p-3 font-bold">الطالب</th><th className="p-3 font-bold">الهاتف</th><th className="p-3 font-bold">الجامعة</th><th className="p-3 font-bold">الشركات</th><th className="p-3 font-bold">اشتراكات سارية</th><th className="p-3 font-bold">تاريخ التسجيل</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {rows.map((student) => (
                  <tr key={student.id} className="hover:bg-slate-50/70">
                    <td className="p-3 font-bold text-slate-800">{student.full_name}</td>
                    <td className="p-3 font-mono text-xs text-slate-600" dir="ltr">{student.phone}</td>
                    <td className="p-3 text-slate-600">{student.university}</td>
                    <td className="p-3">
                      <div className="flex flex-wrap gap-1.5">
                        {student.memberships.length === 0 && <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-semibold text-slate-500">بدون شركة</span>}
                        {student.memberships.map((m) => (
                          <Link key={m.company_id} to={`/c/${m.company_id}/students`}
                            className={`rounded-full px-2 py-0.5 text-[11px] font-bold ${m.status === 'active' ? 'bg-[#D6EEF9] text-[#3E8FBF]' : 'bg-slate-100 text-slate-400 line-through'}`}
                            title={m.status === 'active' ? 'عضو حالي' : 'أُزيل من الشركة'}>
                            {m.company}
                          </Link>
                        ))}
                      </div>
                    </td>
                    <td className="p-3">{student.active_subscriptions.toLocaleString('ar-EG')}</td>
                    <td className="p-3 text-xs text-slate-400">{new Date(student.created_at).toLocaleDateString('ar-EG')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {pageCount > 1 && (
          <div className="flex items-center justify-between border-t border-slate-100 p-3 text-xs text-slate-500">
            <button disabled={pageIndex === 0} onClick={() => setPageIndex(pageIndex - 1)} className="rounded-lg border border-slate-200 px-3 py-1.5 font-bold disabled:opacity-40">السابق</button>
            <span>صفحة {(pageIndex + 1).toLocaleString('ar-EG')} من {pageCount.toLocaleString('ar-EG')}</span>
            <button disabled={pageIndex >= pageCount - 1} onClick={() => setPageIndex(pageIndex + 1)} className="rounded-lg border border-slate-200 px-3 py-1.5 font-bold disabled:opacity-40">التالي</button>
          </div>
        )}
      </div>
    </div>
  );
};
