import React, { Suspense, useEffect } from 'react';
import { Link, Navigate, Route, Routes, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Shell } from '../components/Shell';
import { SkeletonPage, SkeletonShell } from '../components/Skeleton';
import { WorkspaceBar } from '../components/WorkspaceBar';
import { CompanyMark } from '../components/CompanyMark';
import { supabase } from '../lib/supabase';
import { keys, queryClient, STALE, usePageData } from '../lib/query';
import type { CompanyOption } from '../lib/reference';
import { useCompanyOverview } from '../lib/overview';
import { useWorkspaceSync } from '../lib/sync';
import { OPEN_RESET_STATUSES } from '../lib/resetRequests';
import { workspaceNav } from '../lib/nav';
import { AdminProfile, CompanyScope, CompanyScopeProvider, companyStatusLabel } from '../lib/adminScope';
import {
  CompanySettingsPage, LinesPage, NotificationsPage, OverviewPage, PaymentMethodsPage, ReceiptsPage, ReportsPage,
  StudentsPage, SupervisorsPage, TeamPage, WalletCardDesignPage,
} from '../lib/routes';

type Loaded = { state: 'loading' } | { state: 'missing' } | { state: 'ready'; company: CompanyScope };

/** Opens one company. Everything rendered inside reads and writes that company only. */
export const Workspace: React.FC<{ admin: AdminProfile; onLogout: () => void }> = ({ admin, onLogout }) => {
  const { companyId = '' } = useParams();
  const allowed = admin.role === 'super_admin' || companyId === admin.company_id;
  // The company row is cached: a company admin's own row arrives with their
  // profile at sign-in (lib/adminProfile.ts), so their workspace never waits for it.
  const companyQuery = useQuery({
    queryKey: keys.company(companyId, 'company'),
    enabled: allowed,
    staleTime: STALE.reference,
    // A platform admin coming from the companies list already has the row in that lookup.
    initialData: () => {
      const known = queryClient.getQueryData<CompanyOption[]>(keys.platform('companyNames'))?.find((c) => c.id === companyId);
      return known?.status ? ({ id: known.id, name: known.name, status: known.status } as CompanyScope) : undefined;
    },
    initialDataUpdatedAt: () => queryClient.getQueryState(keys.platform('companyNames'))?.dataUpdatedAt,
    queryFn: async () => {
      const { data, error } = await supabase.from('companies').select('id, name, status').eq('id', companyId).maybeSingle();
      if (error) throw new Error(error.message);
      return data as CompanyScope | null;
    },
  });
  const loaded: Loaded = companyQuery.isPending ? { state: 'loading' }
    : companyQuery.data ? { state: 'ready', company: companyQuery.data } : { state: 'missing' };

  if (!allowed) return <Navigate to={`/c/${admin.company_id}`} replace />;
  if (loaded.state === 'loading') return <SkeletonShell />;
  if (loaded.state === 'missing') {
    return (
      <Notice title={companyQuery.error ? 'تعذر فتح مساحة الشركة' : 'الشركة غير موجودة'} onLogout={onLogout}>
        {companyQuery.error && <p role="alert">{companyQuery.error.message} <button className="font-bold underline" onClick={() => void companyQuery.refetch()}>إعادة المحاولة</button></p>}
        {admin.role === 'super_admin' && <Link to="/platform/companies" className="font-bold text-[#3E8FBF] underline">العودة إلى كل الشركات</Link>}
      </Notice>
    );
  }
  const { company } = loaded;
  if (admin.role === 'company_admin' && company.status !== 'active') {
    return (
      <Notice title={`حساب شركة «${company.name}» ${companyStatusLabel[company.status]} حالياً`} onLogout={onLogout}>
        لا يمكن استخدام لوحة التحكم حتى تعيد إدارة المنصة تفعيل الشركة. بياناتكم محفوظة كما هي.
      </Notice>
    );
  }

  // Keyed by company: moving to another company unmounts every page, so no list,
  // form, timer or live feed of the previous company survives the switch.
  return (
    <CompanyScopeProvider company={company} key={company.id}>
      <WorkspaceSync companyId={company.id} />
      <WorkspaceShell companyId={company.id} companyName={company.name} onLogout={onLogout}>
        {/* The frame stays; only the page area waits for a page's code the first time it is opened. */}
        <Suspense fallback={<SkeletonPage />}>
          <Routes>
            <Route index element={<OverviewPage />} />
            <Route path="students" element={<StudentsPage />} />
            <Route path="receipts" element={<ReceiptsPage />} />
            <Route path="lines" element={<LinesPage />} />
            <Route path="supervisors" element={<SupervisorsPage />} />
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="reports" element={<ReportsPage />} />
            <Route path="payment-methods" element={<PaymentMethodsPage />} />
            <Route path="wallet-card" element={<WalletCardDesignPage />} />
            <Route path="team" element={<TeamPage />} />
            <Route path="settings" element={<CompanySettingsPage />} />
            <Route path="*" element={<Navigate to={`/c/${company.id}`} replace />} />
          </Routes>
        </Suspense>
      </WorkspaceShell>
    </CompanyScopeProvider>
  );
};

/**
 * How many reset requests are waiting, without downloading them: the same function and
 * checks as the list, counted by the server, the handled ones left out.
 */
async function countResetRequests(companyId: string): Promise<number> {
  const { count, error } = await supabase.rpc('admin_list_password_reset_requests', { p_company_id: companyId }, { head: true, count: 'exact' })
    .in('status', OPEN_RESET_STATUSES);
  if (error) throw new Error(error.message);
  return count ?? 0;
}

/**
 * The workspace frame with what is waiting for the admin: receipts to review
 * on "فحص الإيصالات" and password-reset requests on "الطلاب", as red badges.
 * The total is in the browser tab's title too, for when the tab is in the back.
 */
const WorkspaceShell: React.FC<{ companyId: string; companyName: string; onLogout: () => void; children: React.ReactNode }> =
  ({ companyId, companyName, onLogout, children }) => {
    const overview = useCompanyOverview(companyId).data;
    const receipts = overview?.pending_receipts ?? 0;
    // Under the list's own key prefix, so the live topic refreshes both together.
    const requests = usePageData(keys.company(companyId, 'resetRequests', 'count'), () => countResetRequests(companyId)).data ?? 0;
    useEffect(() => {
      const base = document.title.replace(/^\(\d+\+?\)\s*/, '');
      const total = receipts + requests;
      document.title = total > 0 ? `(${total > 99 ? '99+' : total}) ${base}` : base;
      return () => { document.title = base; };
    }, [receipts, requests]);
    return (
      <Shell items={workspaceNav(companyId)} areaLabel={companyName} onLogout={onLogout} banner={<WorkspaceBar />}
        mark={<CompanyMark name={companyName} brand={overview?.company} />}
        badges={{ receipts, requests }}>
        {children}
      </Shell>
    );
  };

/** Listens to the open company's topic for as long as its workspace is mounted. */
const WorkspaceSync: React.FC<{ companyId: string }> = ({ companyId }) => {
  useWorkspaceSync(companyId);
  return null;
};

const Notice: React.FC<{ title: string; onLogout: () => void; children?: React.ReactNode }> = ({ title, onLogout, children }) => (
  <div className="min-h-screen grid place-items-center p-6" dir="rtl">
    <div className="glass-panel max-w-md p-8 text-center space-y-4">
      <h1 className="text-xl font-extrabold text-[#1F2937]">{title}</h1>
      <div className="text-sm leading-7 text-[#5B6B7A]">{children}</div>
      <button onClick={onLogout} className="rounded-xl bg-slate-100 px-4 py-2 text-sm font-bold text-slate-700 hover:bg-slate-200">تسجيل الخروج</button>
    </div>
  </div>
);
