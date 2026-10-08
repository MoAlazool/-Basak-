import React, { useEffect, useState } from 'react';
import { SkeletonShell } from './components/Skeleton';
import { BrowserRouter, Link, Navigate, Route, Routes, useParams } from 'react-router-dom';
import { Shell } from './components/Shell';
import { WorkspaceBar } from './components/WorkspaceBar';
import { PendingReceiptsTable } from './components/PendingReceiptsTable';
import { Topbar } from './components/Topbar';
import { OverviewPage } from './pages/OverviewPage';
import { PlatformOverviewPage } from './pages/PlatformOverviewPage';
import { AllCompaniesPage } from './pages/AllCompaniesPage';
import { AllStudentsPage } from './pages/AllStudentsPage';
import { PlatformNotificationsPage } from './pages/PlatformNotificationsPage';
import { CompanyAdminsPage } from './pages/CompanyAdminsPage';
import { UniversitiesPage } from './pages/UniversitiesPage';
import { LinesPage } from './pages/LinesPage';
import { SupervisorsPage } from './pages/SupervisorsPage';
import { NotificationsPage } from './pages/NotificationsPage';
import { StudentsPage } from './pages/StudentsPage';
import { ReportsPage } from './pages/ReportsPage';
import { CompanySettingsPage, PlatformDefaultsPage } from './pages/SubscriptionSettingsPage';
import { PaymentMethodsPage } from './pages/PaymentMethodsPage';
import { WalletCardDesignPage } from './pages/WalletCardDesignPage';
import { TeamPage } from './pages/TeamPage';
import { LoginPage } from './pages/LoginPage';
import { ResetPasswordPage } from './pages/ResetPasswordPage';
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client';
import { supabase } from './lib/supabase';
import { useQuery } from '@tanstack/react-query';
import { clearCache, keys, persistOptions, queryClient, unwrap, usePageData } from './lib/query';
import { useCompanyOverview } from './lib/overview';
import { usePlatformSync, useWorkspaceSync } from './lib/sync';
import { usePendingReceipts } from './lib/pendingReceipts';
import { platformNav, workspaceNav } from './lib/nav';
import {
  AdminProfile, AdminScopeProvider, CompanyScope, CompanyScopeProvider, companyStatusLabel, useCompany,
} from './lib/adminScope';

export function App() {
  const [admin, setAdmin] = useState<AdminProfile | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [recoveryMode, setRecoveryMode] = useState(() => /type=(recovery|invite)/.test(window.location.hash));

  // Restore only a real Supabase session whose user is listed as an admin.
  useEffect(() => {
    let mounted = true;
    // Every auth change bumps the generation. A profile lookup that resolves after
    // a newer change (e.g. sign-out) is discarded, otherwise the dashboard would
    // render without a session and every RLS query would silently return [].
    let generation = 0;

    const applySession = async (userId: string | null) => {
      const current = ++generation;
      if (!userId) {
        clearCache();
        if (mounted) { setAdmin(null); setAuthLoading(false); }
        return;
      }
      const profile = await loadAdminProfile(userId);
      if (!mounted || current !== generation) return;
      const { data: { session } } = await supabase.auth.getSession();
      if (!mounted || current !== generation) return;
      if (profile && session?.user.id === userId) {
        setAdmin(profile);
      } else {
        clearCache();
        setAdmin(null);
        if (session) await supabase.auth.signOut();
      }
      // Only the check that is still the latest decides what to show. On a page
      // reload two checks start almost together (the stored session and the
      // library's own first event); the first is discarded above, and ending
      // the wait there would show the sign-in page for a moment.
      if (mounted) setAuthLoading(false);
    };

    const restore = async () => {
      if (/type=(recovery|invite)/.test(window.location.hash)) setRecoveryMode(true);
      const { data: { session } } = await supabase.auth.getSession();
      await applySession(session?.user.id ?? null);
    };
    void restore();
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY') setRecoveryMode(true);
      if (event === 'TOKEN_REFRESHED') return;
      // Supabase calls must not run inside this callback (auth lock), so defer.
      setTimeout(() => { void applySession(session?.user.id ?? null); }, 0);
    });
    // The session is shared by every tab of this browser: signing in with another
    // account in one tab replaces it everywhere. Re-check when it changes so a tab
    // never keeps acting with an account that is no longer the signed-in one.
    const onStorage = (event: StorageEvent) => {
      if (!event.key || !/^sb-.*-auth-token$/.test(event.key)) return;
      void supabase.auth.getSession().then(({ data: { session } }) => applySession(session?.user.id ?? null));
    };
    window.addEventListener('storage', onStorage);
    return () => { mounted = false; subscription.unsubscribe(); window.removeEventListener('storage', onStorage); };
  }, []);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    clearCache();
    setAdmin(null);
  };

  // While the session is checked, the frame of the dashboard, not a blank page.
  if (authLoading) return <SkeletonShell />;
  if (recoveryMode) return <ResetPasswordPage onComplete={() => setRecoveryMode(false)} />;
  if (!admin) {
    return <LoginPage onLogin={setAdmin} />;
  }

  // A platform admin starts in the platform area; a company admin lives in their
  // own workspace and has no other address to go to.
  const home = admin.role === 'super_admin' ? '/platform' : `/c/${admin.company_id}`;
  return (
    <PersistQueryClientProvider client={queryClient} persistOptions={persistOptions(admin.id)}>
    <AdminScopeProvider admin={admin}>
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <Routes>
          {admin.role === 'super_admin' && (
            <Route path="/platform/*" element={<PlatformArea onLogout={handleLogout} />} />
          )}
          <Route path="/c/:companyId/*" element={<Workspace admin={admin} onLogout={handleLogout} />} />
          <Route path="*" element={<Navigate to={home} replace />} />
        </Routes>
      </BrowserRouter>
    </AdminScopeProvider>
    </PersistQueryClientProvider>
  );
}

async function loadAdminProfile(userId: string): Promise<AdminProfile | null> {
  const { data, error } = await supabase.from('admins')
    .select('id,email,full_name,role,company_id').eq('id', userId).maybeSingle();
  if (error || !data) return null;
  let companyName: string | null = null;
  if (data.company_id) {
    const { data: company } = await supabase.from('companies').select('name').eq('id', data.company_id).maybeSingle();
    companyName = company?.name ?? null;
  }
  return { ...data, role: data.role, companyName } as AdminProfile;
}

const PlatformArea: React.FC<{ onLogout: () => void }> = ({ onLogout }) => {
  usePlatformSync();
  return (
  <Shell items={platformNav} areaLabel="إدارة المنصة" onLogout={onLogout}>
    <Routes>
      <Route index element={<PlatformOverviewPage />} />
      <Route path="companies" element={<AllCompaniesPage />} />
      <Route path="students" element={<AllStudentsPage />} />
      <Route path="notifications" element={<PlatformNotificationsPage />} />
      <Route path="admins" element={<CompanyAdminsPage />} />
      <Route path="universities" element={<UniversitiesPage />} />
      <Route path="defaults" element={<PlatformDefaultsPage />} />
      <Route path="*" element={<Navigate to="/platform" replace />} />
    </Routes>
  </Shell>
  );
};

type Loaded = { state: 'loading' } | { state: 'missing' } | { state: 'ready'; company: CompanyScope };

/** Opens one company. Everything rendered inside reads and writes that company only. */
const Workspace: React.FC<{ admin: AdminProfile; onLogout: () => void }> = ({ admin, onLogout }) => {
  const { companyId = '' } = useParams();
  const allowed = admin.role === 'super_admin' || companyId === admin.company_id;
  // The company row itself is cached too, so reopening a workspace does not wait for it.
  const companyQuery = useQuery({
    queryKey: keys.company(companyId, 'company'),
    enabled: allowed,
    queryFn: async () => (await supabase.from('companies').select('id, name, status').eq('id', companyId).maybeSingle()).data as CompanyScope | null,
  });
  const loaded: Loaded = companyQuery.isPending ? { state: 'loading' }
    : companyQuery.data ? { state: 'ready', company: companyQuery.data } : { state: 'missing' };

  if (!allowed) return <Navigate to={`/c/${admin.company_id}`} replace />;
  if (loaded.state === 'loading') return <SkeletonShell />;
  if (loaded.state === 'missing') {
    return (
      <Notice title="الشركة غير موجودة" onLogout={onLogout}>
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
      </WorkspaceShell>
    </CompanyScopeProvider>
  );
};

/**
 * The workspace frame with what is waiting for the admin: receipts to review
 * on "فحص الإيصالات" and password-reset requests on "الطلاب", as red badges.
 * The total is in the browser tab's title too, for when the tab is in the back.
 */
const WorkspaceShell: React.FC<{ companyId: string; companyName: string; onLogout: () => void; children: React.ReactNode }> =
  ({ companyId, companyName, onLogout, children }) => {
    const receipts = useCompanyOverview(companyId).data?.pending_receipts ?? 0;
    const requests = usePageData(keys.company(companyId, 'resetRequests'), () =>
      unwrap<unknown[]>(supabase.rpc('admin_list_password_reset_requests', { p_company_id: companyId }))).data?.length ?? 0;
    useEffect(() => {
      const base = document.title.replace(/^\(\d+\+?\)\s*/, '');
      const total = receipts + requests;
      document.title = total > 0 ? `(${total > 99 ? '99+' : total}) ${base}` : base;
      return () => { document.title = base; };
    }, [receipts, requests]);
    return (
      <Shell items={workspaceNav(companyId)} areaLabel={companyName} onLogout={onLogout} banner={<WorkspaceBar />}
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

const ReceiptsPage: React.FC = () => {
  const company = useCompany();
  const { receipts, loading, error, refresh, review } = usePendingReceipts(company.id);
  return (
    <div className="space-y-6">
      <Topbar title="فحص واعتماد الإيصالات" subtitle="تصل الإيصالات الجديدة هنا فور رفعها" />
      {error
        ? <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل الإيصالات: {error} <button className="mr-3 font-bold underline" onClick={() => void refresh()}>إعادة المحاولة</button></div>
        : <PendingReceiptsTable receipts={receipts} loading={loading} onReview={review} />}
    </div>
  );
};

export default App;
