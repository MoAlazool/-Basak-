import React, { Suspense, lazy, useEffect } from 'react';
import { Navigate, Route, Routes, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { AppShell, type Who } from '../shell/AppShell';
import { CompanyMark } from '../components/CompanyMark';
import { SkeletonPage, SkeletonShell } from '../components/Skeleton';
import { Button } from '../ui/Button';
import { Icon } from '../ui/Icon';
import { supabase } from '../lib/supabase';
import { keys, queryClient, STALE, usePageData } from '../lib/query';
import type { CompanyOption } from '../lib/reference';
import { useCompanyOverview } from '../lib/overview';
import { useWorkspaceSync } from '../lib/sync';
import { OPEN_RESET_STATUSES } from '../lib/resetRequests';
import { COMPANY_NAV, MOVED_SLUGS } from '../lib/nav';
import { AdminProfile, CompanyScope, CompanyScopeProvider, companyAccountStatusLabel } from '../lib/adminScope';
import {
  AnalyticsPage, GovernoratesPage, LineNewPage, LinePage, LinesPage, NotificationsPage, PaymentMethodsPage, ReceiptDetailsPage,
  ReceiptsPage, ReportsPage, RideConfirmationPage, StudentsPage, SubscriptionPeriodsPage, SupervisorsPage, TeamPage,
  TodayPage, WalletCardPage,
} from '../lib/routes';

/** Only the platform admin ever sees the return bar: company admins never download it. */
const WorkspaceBar = lazy(() => import('../shell/WorkspaceBar').then((m) => ({ default: m.WorkspaceBar })));

type Loaded = { state: 'loading' } | { state: 'missing' } | { state: 'ready'; company: CompanyScope };

export const whoOf = (admin: AdminProfile): Who => ({
  name: admin.full_name || admin.email,
  roleLabel: admin.role === 'super_admin' ? 'مدير المنصة' : 'مدير الشركة',
  initial: (admin.full_name || admin.email || '؟').trim().charAt(0),
});

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
      <Notice title={companyQuery.error ? 'تعذّر فتح لوحة الشركة' : 'هذه الشركة غير موجودة'} onLogout={onLogout}
        action={companyQuery.error ? <Button kind="secondary" icon="refresh" onClick={() => void companyQuery.refetch()}>إعادة المحاولة</Button>
          : admin.role === 'super_admin' ? <Button kind="secondary" icon="arrowBack" to="/platform/companies">العودة إلى الشركات</Button> : undefined}>
        {companyQuery.error ? 'تأكد من الاتصال بالإنترنت وحاول مرة أخرى.' : 'ربما حُذفت أو تغيّر رابطها.'}
      </Notice>
    );
  }
  const { company } = loaded;
  if (admin.role === 'company_admin' && company.status !== 'active') {
    return (
      <Notice title={`حساب شركة «${company.name}» ${companyAccountStatusLabel[company.status]} حالياً`} onLogout={onLogout} icon="lock">
        لا يمكن استخدام اللوحة حتى يعيد مدير المنصة تفعيل الشركة. بياناتكم وبيانات طلابكم محفوظة كما هي، والطلاب لا يستطيعون الاشتراك حتى ذلك الحين.
      </Notice>
    );
  }

  // Keyed by company: moving to another company unmounts every page, so no list,
  // form, timer or live feed of the previous company survives the switch.
  return (
    <CompanyScopeProvider company={company} key={company.id}>
      <WorkspaceSync companyId={company.id} />
      <WorkspaceShell admin={admin} company={company} onLogout={onLogout}>
        {/* The frame stays; only the page area waits for a page's code the first time it is opened. */}
        <Suspense fallback={<SkeletonPage />}>
          <Routes>
            <Route index element={<TodayPage />} />
            <Route path="receipts" element={<ReceiptsPage />} />
            {/* Password requests are the platform's alone (/platform/password-requests). */}
            <Route path="password-requests" element={<Navigate to={admin.role === 'super_admin' ? '/platform/password-requests' : `/c/${company.id}`} replace />} />
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="students" element={<StudentsPage />} />
            <Route path="supervisors" element={<SupervisorsPage />} />
            <Route path="team" element={<TeamPage />} />
            <Route path="lines" element={<LinesPage />} />
            <Route path="lines/new" element={<LineNewPage />} />
            <Route path="lines/:lineId" element={<LinePage />} />
            <Route path="ride-confirmation" element={<RideConfirmationPage />} />
            <Route path="governorates" element={<GovernoratesPage />} />
            <Route path="subscription-periods" element={<SubscriptionPeriodsPage />} />
            <Route path="payment-methods" element={<PaymentMethodsPage />} />
            <Route path="reports" element={<ReportsPage />} />
            <Route path="analytics" element={<AnalyticsPage />} />
            <Route path="wallet-card" element={<WalletCardPage />} />
            <Route path="receipt-details" element={<ReceiptDetailsPage />} />
            {Object.entries(MOVED_SLUGS).map(([from, to]) => <Route key={from} path={from} element={<Navigate to={`/c/${company.id}/${to}`} replace />} />)}
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
async function countResetRequests(companyId: string | null): Promise<number> {
  const { count, error } = await supabase.rpc('admin_list_password_reset_requests', { p_company_id: companyId }, { head: true, count: 'exact' })
    .in('status', OPEN_RESET_STATUSES);
  if (error) throw new Error(error.message);
  return count ?? 0;
}
export const useResetRequestCount = (companyId: string | null) =>
  usePageData(companyId ? keys.company(companyId, 'resetRequests', 'count') : keys.platform('resetRequests', 'count'), () => countResetRequests(companyId)).data ?? 0;

/**
 * The workspace frame with what is waiting for the admin: receipts to review,
 * as a red count. The count is in the browser tab's title too, for when the tab
 * is in the back. Password-reset requests are the platform's (PlatformArea).
 */
const WorkspaceShell: React.FC<{ admin: AdminProfile; company: CompanyScope; onLogout: () => void; children: React.ReactNode }> = ({ admin, company, onLogout, children }) => {
  const overview = useCompanyOverview(company.id).data;
  const receipts = overview?.pending_receipts ?? 0;
  useTabCount(receipts);
  const isPlatform = admin.role === 'super_admin';
  return (
    <AppShell role={isPlatform ? 'workspace' : 'company'} groups={COMPANY_NAV} base={`/c/${company.id}`} scope="لوحة الشركة"
      companyName={company.name} companyId={company.id} who={whoOf(admin)} onLogout={onLogout}
      mark={overview?.company && (overview.company.emblem_path || overview.company.logo_path) ? <CompanyMark name={company.name} brand={overview.company} size="md" className="!h-9 !w-9 !rounded-control" /> : undefined}
      badges={{ receipts }} workspaceBar={isPlatform ? <Suspense fallback={<div className="h-12 flex-none bg-ink" />}><WorkspaceBar company={company} /></Suspense> : undefined}>
      {children}
    </AppShell>
  );
};

/** «(9) باصك · لوحة الإدارة» while something waits. */
export function useTabCount(total: number) {
  useEffect(() => {
    const base = document.title.replace(/^\(\d+\+?\)\s*/, '');
    document.title = total > 0 ? `(${total > 99 ? '99+' : total}) ${base}` : base;
    return () => { document.title = base; };
  }, [total]);
}

/** Listens to the open company's topic for as long as its workspace is mounted. */
const WorkspaceSync: React.FC<{ companyId: string }> = ({ companyId }) => {
  useWorkspaceSync(companyId);
  return null;
};

const Notice: React.FC<{ title: string; onLogout: () => void; children?: React.ReactNode; action?: React.ReactNode; icon?: 'lock' | 'alert' }> = ({ title, onLogout, children, action, icon = 'alert' }) => (
  <div className="grid min-h-screen place-items-center bg-ground p-4">
    <div className="flex w-full max-w-[480px] flex-col items-center gap-2 rounded-card bg-surface p-8 text-center shadow-card">
      <span aria-hidden="true" className={`mb-2 flex h-14 w-14 items-center justify-center rounded-full ${icon === 'lock' ? 'bg-warn-bg text-warn' : 'bg-bad-bg text-bad'}`}><Icon name={icon} size={26} /></span>
      <h1 className="m-0 text-section">{title}</h1>
      <p className="m-0 text-small text-ink-2">{children}</p>
      <div className="mt-4 flex w-full flex-col gap-2 sm:w-auto sm:flex-row">{action}<Button kind="outline" icon="logout" onClick={onLogout}>تسجيل الخروج</Button></div>
    </div>
  </div>
);
