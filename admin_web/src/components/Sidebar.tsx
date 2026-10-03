import React from 'react';
import {
  LayoutDashboard,
  Building2,
  Bus,
  UserCheck,
  FileCheck2,
  BarChart3,
  ShieldCheck,
  LogOut,
  GraduationCap,
  Users,
  CalendarRange,
} from 'lucide-react';

interface SidebarProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  onLogout: () => void;
  role: 'super_admin' | 'company_admin';
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange, onLogout, role }) => {
  const navItems = [
    { id: 'overview',     name: 'نظرة عامة',        icon: LayoutDashboard },
    ...(role === 'super_admin' ? [
      { id: 'companies',    name: 'الشركات',           icon: Building2 },
      { id: 'company-admins', name: 'مديرو الشركات',    icon: ShieldCheck },
      { id: 'universities', name: 'الجامعات والوجهات', icon: GraduationCap },
    ] : []),
    { id: 'lines',        name: 'الخطوط والمحطات',  icon: Bus },
    { id: 'supervisors',  name: 'المشرفون',          icon: UserCheck },
    { id: 'students',     name: 'إدارة الطلاب',      icon: Users },
    { id: 'receipts',     name: 'فحص الإيصالات',     icon: FileCheck2 },
    { id: 'reports',      name: 'التقارير المالية',  icon: BarChart3 },
    { id: 'settings',     name: 'إعدادات الاشتراكات', icon: CalendarRange },
  ];

  return (
    <aside
      className="sticky top-0 h-screen w-[72px] lg:w-[230px] flex flex-col justify-between py-5 px-3 z-30 flex-shrink-0"
      style={{
        background: 'rgba(255,255,255,0.72)',
        backdropFilter: 'blur(18px)',
        WebkitBackdropFilter: 'blur(18px)',
        borderLeft: '1px solid rgba(255,255,255,0.7)',
        boxShadow: '4px 0 24px rgba(126,200,227,0.12)',
      }}
    >
      <div>
        {/* Brand */}
        <div className="flex items-center gap-3 px-2 py-3 mb-6 border-b border-white/40">
          <div className="h-10 w-10 min-w-[40px] rounded-xl bg-gradient-to-tr from-[#3E8FBF] to-[#7EC8E3] flex items-center justify-center text-white shadow-md shadow-[#7EC8E3]/30">
            <Bus className="h-5 w-5" />
          </div>
          <div className="hidden lg:block">
            <h1 className="text-base font-extrabold text-[#1F2937] leading-tight">باصك</h1>
            <p className="text-[11px] font-medium text-[#5B6B7A]">لوحة تحكم الإدارة</p>
          </div>
        </div>

        {/* Nav Items */}
        <nav className="space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeTab === item.id;
            return (
              <button
                key={item.id}
                onClick={() => onTabChange(item.id)}
                title={item.name}
                className={`flex w-full items-center gap-3 px-3 py-2.5 rounded-2xl text-[13px] font-semibold transition-all duration-150 ${
                  isActive
                    ? 'bg-[#D6EEF9]/80 text-[#3E8FBF] shadow-sm'
                    : 'text-[#5B6B7A] hover:bg-white/60 hover:text-[#1F2937]'
                }`}
              >
                <Icon className={`h-5 w-5 min-w-[20px] ${isActive ? 'text-[#3E8FBF]' : 'text-[#5B6B7A]'}`} />
                <span className="hidden lg:inline">{item.name}</span>
              </button>
            );
          })}
        </nav>
      </div>

      {/* Bottom: security badge + logout */}
      <div className="space-y-2">
        <div className="hidden lg:flex items-center gap-2 p-3 rounded-2xl bg-white/50 border border-white/60 text-[11px] text-[#5B6B7A]">
          <ShieldCheck className="h-4 w-4 text-[#3E8FBF] flex-shrink-0" />
          <span>نظام محمي ومشفر بالكامل</span>
        </div>
        <button
          onClick={onLogout}
          title="تسجيل الخروج"
          className="flex w-full items-center gap-3 px-3 py-2.5 rounded-2xl text-[13px] font-semibold text-rose-500 hover:bg-rose-50 transition"
        >
          <LogOut className="h-5 w-5 min-w-[20px]" />
          <span className="hidden lg:inline">تسجيل الخروج</span>
        </button>
      </div>
    </aside>
  );
};
