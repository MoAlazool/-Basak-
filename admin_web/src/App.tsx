import React, { useState, useEffect } from 'react';
import { Sidebar } from './components/Sidebar';
import { OverviewPage } from './pages/OverviewPage';
import { CompaniesPage } from './pages/CompaniesPage';
import { LinesPage } from './pages/LinesPage';
import { SupervisorsPage } from './pages/SupervisorsPage';
import { ReportsPage } from './pages/ReportsPage';
import { LoginPage } from './pages/LoginPage';
import { PendingReceiptsTable } from './components/PendingReceiptsTable';

export function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [activeTab, setActiveTab] = useState<string>('overview');

  // Restore session from localStorage
  useEffect(() => {
    const saved = localStorage.getItem('basak_admin_auth');
    if (saved === 'true') setIsLoggedIn(true);
  }, []);

  const handleLogout = () => {
    localStorage.removeItem('basak_admin_auth');
    setIsLoggedIn(false);
  };

  if (!isLoggedIn) {
    return <LoginPage onLogin={() => setIsLoggedIn(true)} />;
  }

  return (
    <div className="flex min-h-screen" dir="rtl">
      {/* ── Desktop Sidebar (hidden on mobile) ─────── */}
      <div className="hidden md:flex">
        <Sidebar activeTab={activeTab} onTabChange={setActiveTab} onLogout={handleLogout} />
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
          {activeTab === 'companies' && <CompaniesPage />}
          {activeTab === 'lines' && <LinesPage />}
          {activeTab === 'supervisors' && <SupervisorsPage />}
          {activeTab === 'receipts' && (
            <div className="space-y-6">
              <h1 className="text-2xl font-bold text-slate-800">فحص واعتماد الإيصالات</h1>
              <PendingReceiptsTable receipts={[]} loading={false} onReceiptReviewed={() => {}} />
            </div>
          )}
          {activeTab === 'reports' && <ReportsPage />}
        </div>
      </main>

      {/* ── Mobile Bottom Navigation Bar ───────────── */}
      <MobileNav activeTab={activeTab} onTabChange={setActiveTab} onLogout={handleLogout} />
    </div>
  );
}

// ── Mobile Bottom Nav ──────────────────────────────────────────────
import {
  LayoutDashboard, Building2, Bus, UserCheck,
  FileCheck2, BarChart3, LogOut,
} from 'lucide-react';

interface MobileNavProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  onLogout: () => void;
}

const MobileNav: React.FC<MobileNavProps> = ({ activeTab, onTabChange, onLogout }) => {
  const items = [
    { id: 'overview',    icon: LayoutDashboard, label: 'الرئيسية' },
    { id: 'companies',   icon: Building2,        label: 'الشركات'  },
    { id: 'lines',       icon: Bus,              label: 'الخطوط'   },
    { id: 'supervisors', icon: UserCheck,        label: 'المشرفون' },
    { id: 'receipts',   icon: FileCheck2,        label: 'الإيصالات'},
    { id: 'reports',     icon: BarChart3,        label: 'التقارير' },
  ];

  return (
    <nav
      className="md:hidden fixed bottom-0 left-0 right-0 z-40 flex items-center justify-around px-2 py-2"
      style={{
        background: 'rgba(255,255,255,0.85)',
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
            className="flex flex-col items-center gap-0.5 px-1.5 py-1 rounded-xl transition-all"
          >
            <Icon
              className={`h-5 w-5 transition-colors ${active ? 'text-[#3E8FBF]' : 'text-slate-400'}`}
            />
            <span
              className={`text-[9px] font-bold transition-colors ${active ? 'text-[#3E8FBF]' : 'text-slate-400'}`}
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
        className="flex flex-col items-center gap-0.5 px-1.5 py-1 rounded-xl"
      >
        <LogOut className="h-5 w-5 text-rose-400" />
        <span className="text-[9px] font-bold text-rose-400">خروج</span>
      </button>
    </nav>
  );
};

export default App;
