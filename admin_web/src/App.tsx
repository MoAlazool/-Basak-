import React, { useState, useEffect } from 'react';
import { Sidebar } from './components/Sidebar';
import { OverviewPage } from './pages/OverviewPage';
import { CompaniesPage } from './pages/CompaniesPage';
import { CompanyAdminsPage } from './pages/CompanyAdminsPage';
import { UniversitiesPage } from './pages/UniversitiesPage';
import { LinesPage } from './pages/LinesPage';
import { SupervisorsPage } from './pages/SupervisorsPage';
import { StudentsPage } from './pages/StudentsPage';
import { ReportsPage } from './pages/ReportsPage';
import { LoginPage } from './pages/LoginPage';
import { ResetPasswordPage } from './pages/ResetPasswordPage';
import { PendingReceiptsTable } from './components/PendingReceiptsTable';
import { supabase } from './lib/supabase';
import { usePendingReceipts } from './lib/pendingReceipts';
import { AdminProfile, AdminScopeProvider } from './lib/adminScope';

export function App() {
  const [admin, setAdmin] = useState<AdminProfile | null>(null);
  const [activeTab, setActiveTab] = useState<string>('overview');
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
        if (mounted) setAdmin(null);
        return;
      }
      const profile = await loadAdminProfile(userId);
      if (!mounted || current !== generation) return;
      const { data: { session } } = await supabase.auth.getSession();
      if (!mounted || current !== generation) return;
      if (profile && session?.user.id === userId) {
        setAdmin(profile);
      } else {
        setAdmin(null);
        if (session) await supabase.auth.signOut();
      }
    };

    const restore = async () => {
      if (/type=(recovery|invite)/.test(window.location.hash)) setRecoveryMode(true);
      const { data: { session } } = await supabase.auth.getSession();
      await applySession(session?.user.id ?? null);
      if (mounted) setAuthLoading(false);
    };
    void restore();
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY') setRecoveryMode(true);
      if (event === 'TOKEN_REFRESHED') return;
      // Supabase calls must not run inside this callback (auth lock), so defer.
      setTimeout(() => { void applySession(session?.user.id ?? null); }, 0);
    });
    return () => { mounted = false; subscription.unsubscribe(); };
  }, []);

  useEffect(() => {
    if (admin?.role === 'company_admin' && ['companies', 'company-admins', 'universities'].includes(activeTab)) {
      setActiveTab('overview');
    }
  }, [admin, activeTab]);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    setAdmin(null);
  };

  if (authLoading) return <div className="min-h-screen grid place-items-center" dir="rtl">جاري التحقق من الجلسة...</div>;
  if (recoveryMode) return <ResetPasswordPage onComplete={() => setRecoveryMode(false)} />;
  if (!admin) {
    return <LoginPage onLogin={setAdmin} />;
  }

  return (
    <AdminScopeProvider admin={admin}>
    <div className="flex min-h-screen" dir="rtl">
      {/* ── Desktop Sidebar (hidden on mobile) ─────── */}
      <div className="hidden md:flex">
        <Sidebar activeTab={activeTab} onTabChange={setActiveTab} onLogout={handleLogout} role={admin.role} />
      </div>

      {/* ── Main Content ────────────────────────────── */}
      <main
        className="flex-1 min-w-0 overflow-x-hidden pb-24 md:pb-8"
        style={{
          background: 'radial-gradient(ellipse 80% 60% at 20% 10%, #EAF7FD 0%, #F3FAFD 50%, #ffffff 100%)',
          minHeight: '100vh',
        }}
      >
        <div className="mx-auto max-w-[1400px] p-4 sm:p-6 space-y-0">
          {activeTab === 'overview' && <OverviewPage />}
          {activeTab === 'companies' && admin.role === 'super_admin' && <CompaniesPage />}
          {activeTab === 'company-admins' && admin.role === 'super_admin' && <CompanyAdminsPage />}
          {activeTab === 'universities' && admin.role === 'super_admin' && <UniversitiesPage />}
          {activeTab === 'lines' && <LinesPage />}
          {activeTab === 'supervisors' && <SupervisorsPage />}
          {activeTab === 'students' && <StudentsPage />}
          {activeTab === 'receipts' && (
            <div className="space-y-6">
              <h1 className="text-2xl font-bold text-slate-800">فحص واعتماد الإيصالات</h1>
              <AdminReceiptsQueue />
            </div>
          )}
          {activeTab === 'reports' && <ReportsPage />}
        </div>
      </main>

      {/* ── Mobile Bottom Navigation Bar ───────────── */}
      <MobileNav activeTab={activeTab} onTabChange={setActiveTab} onLogout={handleLogout} role={admin.role} />
    </div>
    </AdminScopeProvider>
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

const AdminReceiptsQueue: React.FC = () => {
  const { receipts, loading, error, refresh } = usePendingReceipts();

  if (error) return <div role="alert" className="mb-4 rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل الإيصالات: {error} <button className="mr-3 font-bold underline" onClick={() => void refresh()}>إعادة المحاولة</button></div>;
  return <PendingReceiptsTable receipts={receipts} loading={loading} onReceiptReviewed={() => void refresh()} />;
};

// ── Mobile Bottom Nav ──────────────────────────────────────────────
import {
  LayoutDashboard, Building2, Bus, UserCheck,
  FileCheck2, BarChart3, LogOut, GraduationCap, Users,
} from 'lucide-react';

interface MobileNavProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  onLogout: () => void;
  role: 'super_admin' | 'company_admin';
}

const MobileNav: React.FC<MobileNavProps> = ({ activeTab, onTabChange, onLogout, role }) => {
  const items = [
    { id: 'overview',     icon: LayoutDashboard, label: 'الرئيسية' },
    ...(role === 'super_admin' ? [
      { id: 'companies', icon: Building2, label: 'الشركات' },
      { id: 'company-admins', icon: GraduationCap, label: 'مديرو الشركات' },
      { id: 'universities', icon: GraduationCap, label: 'الجامعات' },
    ] : []),
    { id: 'lines',        icon: Bus,             label: 'الخطوط'   },
    { id: 'supervisors',  icon: UserCheck,       label: 'المشرفون' },
    { id: 'students',     icon: Users,           label: 'الطلاب'   },
    { id: 'receipts',     icon: FileCheck2,       label: 'الإيصالات'},
    { id: 'reports',      icon: BarChart3,       label: 'التقارير' },
  ];

  return (
    <nav
      className="md:hidden fixed bottom-0 left-0 right-0 z-40 flex items-center justify-between overflow-x-auto px-2 py-2"
      style={{
        background: 'rgba(255,255,255,0.92)',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        borderTop: '1px solid rgba(255,255,255,0.7)',
        boxShadow: '0 -4px 24px rgba(126,200,227,0.15)',
      }}
    >
      {items.map(({ id, icon: Icon, label }) => {
        const active = activeTab === id;
        return (
          <button
            key={id}
            onClick={() => onTabChange(id)}
            className="flex flex-col items-center gap-0.5 px-2 py-1 rounded-xl transition-all flex-shrink-0"
          >
            <Icon
              className={`h-5 w-5 transition-colors ${active ? 'text-[#3E8FBF]' : 'text-slate-400'}`}
            />
            <span
              className={`text-[9.5px] font-bold transition-colors ${active ? 'text-[#3E8FBF]' : 'text-slate-400'}`}
            >
              {label}
            </span>
            {active && (
              <div className="h-1 w-4 rounded-full bg-[#7EC8E3] mt-0.5" />
            )}
          </button>
        );
      })}

      {/* Logout button */}
      <button
        onClick={onLogout}
        className="flex flex-col items-center gap-0.5 px-2 py-1 rounded-xl flex-shrink-0"
      >
        <LogOut className="h-5 w-5 text-rose-400" />
        <span className="text-[9.5px] font-bold text-rose-400">خروج</span>
      </button>
    </nav>
  );
};

export default App;
